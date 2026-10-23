# Fast alternative to render_from_phyloxml.R - avoids
# treeio::read.phyloxml() entirely (confirmed O(n^2), see
# project_treeio_phyloxml_quadratic_scaling memory / this directory's
# README) instead of trying to patch around it.
#
# Key realization (2026-10-23): we don't actually need treeio to parse the
# tree TOPOLOGY out of the phyloXML at all - the phyloXML's topology is
# identical to its companion Newick *.treefile (same source ete3 Tree
# object, serialized twice), and Newick parsing was never the slow part -
# only treeio's phyloxml-specific parser (parser_clade()) is O(n^2).
# ape/treeio's Newick reader is already fast and already trusted elsewhere
# in this pipeline.
#
# Also: internal node labels (support-value strings like "100/1/100") are
# NOT unique - confirmed on the real PRRs file, that exact string alone
# appears 170 times - so a label-based join only works for LEAVES (real
# accession IDs, guaranteed unique), not internal nodes. That's fine: we
# don't need per-internal-node color from the XML at all. The same
# monophyletic-propagation trick the original ggtree prototype
# (render_colored_tree.R) already used - groupOTU() coloring a whole
# subtree from its member leaves' group membership - handles internal
# branches correctly from leaf-level data alone, and was already proven
# fast at full Mas1 scale (24156 leaves, well under 2 minutes total).
#
# So this script only needs the phyloXML for one thing: each LEAF's
# cladeName property. That's a single XPath selecting leaf <clade>
# elements (no nested <clade> child) in one linear pass - pure libxml2
# C-side traversal, no R-level recursion, nothing like treeio's
# bind_rows-at-every-recursion-level pattern.
#
# Usage: Rscript render_from_phyloxml_fast.R <treefile> <fullTree.xml> <out.pdf>

library(xml2)
library(ape)
library(ggtree)
library(ggplot2)
library(dplyr)
library(ggrepel)
library(tidytree)

args <- commandArgs(trailingOnly = TRUE)
treefilePath <- args[1]
xmlPath <- args[2]
outFile <- args[3]

cat("reading topology from Newick...\n"); t0 <- Sys.time()
phy <- read.tree(treefilePath)
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s -", Ntip(phy), "tips\n")

cat("extracting leaf cladeName + cladeColor from phyloXML (xml2, single pass)...\n"); t0 <- Sys.time()
doc <- read_xml(xmlPath)
ns <- xml_ns(doc)
leafClades <- xml_find_all(doc, ".//d1:clade[not(d1:clade)]", ns)
leafNames <- xml_text(xml_find_first(leafClades, "./d1:name", ns))
cladeNames <- xml_text(xml_find_first(leafClades, "./d1:property[@ref='PhylogenyPipeline:cladeName']", ns))
# Separate <property> element from cladeName's, not pipe-delimited - fine
# for our own xml2-based reader (each <property> parsed independently),
# unlike treeio's tibble pivot, which is what made two properties blow up
# there (see this directory's README).
cladeColors <- xml_text(xml_find_first(leafClades, "./d1:property[@ref='PhylogenyPipeline:cladeColor']", ns))
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s -", length(leafNames), "leaf clades found\n")

leafData <- tibble(
	label = leafNames,
	cladeName = ifelse(is.na(cladeNames) | cladeNames == "", "Unclassified", cladeNames),
	# grey70 for leaves outside any curated clade - same fallback color
	# this directory's earlier prototypes used.
	cladeColor = ifelse(is.na(cladeColors) | cladeColors == "", "#B3B3B3", cladeColors)
)

cat("rendering...\n"); t0 <- Sys.time()
# Group by the clade's own curated hex color (not cladeName) so the
# render uses the pipeline's real, already-chosen colors directly via
# scale_color_identity() - the same palette the production PDF already
# uses, not a separately re-derived ggplot palette. groupOTU's MRCA-based
# subtree propagation still reconstructs internal-branch coloring
# correctly from this leaf-level grouping, same mechanism as before.
groups <- split(leafData$label, leafData$cladeColor)
phyGrouped <- groupOTU(phy, groups)

p <- ggtree(phyGrouped, layout = "circular", branch.length = "none", size = 0.3, aes(color = group)) +
	scale_color_identity()

# Label each curated clade at its CENTER LEAF's plotted position, matching
# 12_ConvertTreesToFigures.py's own assignCladeNameToCenterLeaf() exactly
# (confirmed by reading its source, not guessed): that function places the
# label on the leaf at position floor(n/2) in ete3's iter_leaves() order,
# not the clade's MRCA/root. ggtree's plotted tip "y" position follows the
# same left-to-right leaf order as ete3's traversal (same source topology),
# so sorting a clade's member tips by "y" and picking the middle one is the
# exact R equivalent - not an MRCA (an internal node, which for a
# non-monophyletic or lopsided clade can land visually off-center from
# where the clade's own leaves actually sit, unlike a real member leaf).
cladeNameGroups <- split(leafData$label, leafData$cladeName)
cladeNameGroups[["Unclassified"]] <- NULL

treeData <- p$data
centerLeafRows <- lapply(names(cladeNameGroups), function(g) {
	tips <- cladeNameGroups[[g]]
	tipRows <- treeData[treeData$label %in% tips, c("y", "x", "angle")]
	tipRows <- tipRows[order(tipRows$y), ]
	centerRow <- tipRows[floor(nrow(tipRows) / 2) + 1, ]
	if (nrow(centerRow) == 1) data.frame(cladeName = g, xAnchor = centerRow$x, y = centerRow$y, angle = centerRow$angle) else NULL
})
labelPoints <- do.call(rbind, centerLeafRows)

# geom_text_repel draws text horizontally by default, so on the LEFT
# half of the circle text growing rightward from its anchor grows back
# toward the center, straight into the tree, even though the anchor
# itself is safely outside it (user feedback 2026-10-23). hjust alone
# (flipping growth direction left/right) isn't enough either - confirmed
# on real labels at ~220-245 degrees (diagonal, not purely leftward):
# horizontal text still has a vertical extent that crosses into the tree
# at angles far from exactly 180. The real fix needs actual rotation too
# - same full convention ggtree:::geom_tiplab_circular() uses internally
# for its own circular tip labels (confirmed by reading its source, and
# confirmed geom_text_repel does support a rotated "angle" aesthetic via
# an isolated test): rotate text to the local radial angle (+180 on the
# left half, so it stays upright and readable instead of upside-down),
# combined with the same hjust flip.
labelPoints$textAngle <- ifelse(labelPoints$angle >= 90 & labelPoints$angle <= 270, labelPoints$angle + 180, labelPoints$angle)
labelPoints$hjust <- ifelse(labelPoints$angle >= 90 & labelPoints$angle <= 270, 1, 0)

# Push labels to a fixed radius outside the tree entirely, rather than
# right at the center leaf's own position (user feedback 2026-10-23:
# labels were overlapping tree branches). In this circular layout "x" IS
# the radial distance from center and "y" IS the angular/tip-index
# position - not literal Cartesian coordinates (confirmed by checking
# p$data directly: x ranges 0-42 for a tree with ~42 depth units, y
# ranges 1-Ntip; the depth->radius / index->angle transform happens at
# render time via ggtree's own coordinate system, shared by every layer
# on this plot) - so moving a label outward is just a larger x at the
# SAME y, no trigonometry needed. A straight radial segment (same y,
# different x) connects each label back to its real center-leaf anchor.
outerX <- max(treeData$x, na.rm = TRUE) * 1.1
labelPoints$x <- outerX

# geom_text_repel's OWN drawing step (not its position/repel algorithm,
# which is fine) applies an internal hjust/angle-based offset that
# shifts the ACTUAL rendered glyphs away from the point ggplot_build()
# reports - confirmed directly 2026-10-23 with a side-by-side test:
# plain geom_text() and geom_text_repel(), same string, same (x,y),
# same hjust/angle, same xlim-locked radius - geom_text() rendered
# entirely outside the tree, geom_text_repel() visibly bled into it
# ("half inside the tree" per direct user report). This isn't a
# per-label width problem to compensate for (an earlier, more
# complicated attempt computed each label's own half-width via
# grid::stringWidth() and a calibrated native-units-per-point factor -
# unnecessary once this was isolated directly to geom_text_repel()
# itself, not a general hjust/rotation property).
#
# Fix: stop using geom_text_repel() to draw anything at all. Only use
# it to find good ANGULAR (y) spacing between labels - genuinely useful
# for that - then draw the actual VISIBLE text with plain geom_text()
# at a fixed radius, hjust, and angle: deterministic, and immune to
# whatever geom_text_repel()'s own drawing step does internally.
repelLayer <- geom_text_repel(
	data = labelPoints,
	aes(x = x, y = y, label = cladeName, hjust = hjust, angle = textAngle),
	color = NA, size = 2.2, fontface = "bold", max.overlaps = Inf,
	segment.color = NA, min.segment.length = 0, box.padding = 0.5,
	# Defaults (force=1, force_pull=1, max.time=0.5s) left some real
	# overlap unresolved in the densest cluster - stronger push-apart
	# force, weaker pull back toward the original anchor, and more
	# time/iterations to actually converge.
	force = 4, force_pull = 0.5, max.iter = 10000, max.time = 10,
	# Locks the radius exactly (not just a minimum) so repel's only
	# remaining freedom is the angular/y position - the one thing it's
	# actually needed for here.
	xlim = c(outerX, outerX)
)
builtForY <- ggplot_build(p + repelLayer)
labelPoints$yFinal <- builtForY$data[[length(builtForY$data)]]$y

p <- p +
	geom_segment(
		data = labelPoints,
		aes(x = xAnchor, y = y, xend = x, yend = yFinal), color = "grey50",
		linewidth = 0.2, inherit.aes = FALSE
	) +
	geom_text(
		data = labelPoints,
		aes(x = x, y = yFinal, label = cladeName, hjust = hjust, angle = textAngle),
		color = "black", size = 2.2, fontface = "bold", inherit.aes = FALSE
	)

ggsave(outFile, p, width = 25, height = 25, units = "cm", limitsize = FALSE)
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s\n")
cat("Wrote", outFile, "\n")
