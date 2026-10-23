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
# Usage: Rscript render_from_phyloxml_fast.R <treefile> <fullTree.xml> <out.pdf> [colorBy]
#
# colorBy selects which pair of per-leaf phyloXML <property> elements to
# color/group by (both pairs are written by buildPhyloXMLClade(), see
# 12_ConvertTreesToFigures.py):
#   "clade" (default) - PhylogenyPipeline:cladeName/cladeColor, the curated
#       clade assignment - and draws the full clade-label-placement machinery
#       below (outside-tree labels, declutter, connectors).
#   "taxon" - PhylogenyPipeline:taxonOfInterest/taxonColor, the real per-leaf
#       NCBI taxonomy classification - no labels (2026-10-23 user feedback:
#       "I just don't think that this tree needs lables, at least not for
#       now"), just the colored tree, since there isn't a small curated list
#       of named groups to label the way Clades.csv's ~61 clades are.

library(xml2)
library(ape)
library(ggtree)
library(ggplot2)
library(dplyr)

args <- commandArgs(trailingOnly = TRUE)
treefilePath <- args[1]
xmlPath <- args[2]
outFile <- args[3]
colorBy <- ifelse(length(args) >= 4, args[4], "clade")
stopifnot(colorBy %in% c("clade", "taxon"))
addLabels <- colorBy == "clade"
nameRef <- if (colorBy == "clade") "PhylogenyPipeline:cladeName" else "PhylogenyPipeline:taxonOfInterest"
colorRef <- if (colorBy == "clade") "PhylogenyPipeline:cladeColor" else "PhylogenyPipeline:taxonColor"

cat("reading topology from Newick...\n"); t0 <- Sys.time()
phy <- read.tree(treefilePath)
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s -", Ntip(phy), "tips\n")

cat("extracting leaf", nameRef, "+", colorRef, "from phyloXML (xml2, single pass)...\n"); t0 <- Sys.time()
doc <- read_xml(xmlPath)
ns <- xml_ns(doc)
leafClades <- xml_find_all(doc, ".//d1:clade[not(d1:clade)]", ns)
leafNames <- xml_text(xml_find_first(leafClades, "./d1:name", ns))
cladeNames <- xml_text(xml_find_first(leafClades, paste0("./d1:property[@ref='", nameRef, "']"), ns))
# Separate <property> element from cladeName's, not pipe-delimited - fine
# for our own xml2-based reader (each <property> parsed independently),
# unlike treeio's tibble pivot, which is what made two properties blow up
# there (see this directory's README).
cladeColors <- xml_text(xml_find_first(leafClades, paste0("./d1:property[@ref='", colorRef, "']"), ns))
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

if (addLabels) {

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
#
# Only meaningful for colorBy="clade" (Clades.csv's ~61 named, curated
# groups) - skipped entirely for colorBy="taxon" (2026-10-23 user
# feedback: "I just don't think that this tree needs lables, at least not
# for now" - the by-taxon view is for a quick visual taxonomic-composition
# check, not a labeled publication figure, and real NCBI taxonomy doesn't
# come in a small curated list the way Clades.csv's clades do).
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
# geom_text_repel's own COLLISION DETECTION also turned out unreliable
# here, not just its drawing: confirmed directly on a real pair of
# single-leaf clades (adjacent tips, y 1 apart out of 24156 total) that
# were still fully overlapping after this fix - geom_text_repel left
# their y completely unchanged (converged in 0.18s, having apparently
# decided - wrongly - that nothing needed to move). Root cause is
# consistent with everything else found in this section: its
# axis-aligned, rotation-blind bounding-box math, applied inside this
# extreme-aspect-ratio (radius ~0-110 vs angle ~1-24156) coordinate
# system, doesn't reliably detect true overlap of rotated text either.
#
# Fix: stop relying on geom_text_repel for y-spacing too - compute it
# directly instead. Labels are rotated to read radially, so the
# dimension that matters for two ADJACENT labels (different y, same
# radius) not overlapping is each label's own FONT HEIGHT in the
# angular/y direction, not its string length (which only matters
# radially, already handled by pushing every label to the same fixed
# outerX). Font height is the same constant for every label here (one
# fixed font size), so the fix is a simple, deterministic sweep: sort by
# y, and whenever two consecutive labels are closer than one
# font-height's worth of arc length, push the later one out by the
# shortfall - a standard, reliable technique for circular label
# placement, not dependent on force-simulation convergence at all.
#
# "One font-height's worth of arc length", in y-units, needs: (a) the
# true physical radius of outerX in points - calibrated empirically via
# two tiny reference labels at known radii on the bare tree, read back
# via pdftotext -bbox (confirmed thrown off if any oversized/overflowing
# text is in the SAME calibration plot, so this stays a separate render
# each time, not reused from the real one); and (b) degrees-per-y-unit,
# computed directly from this tree's own real angle/y data rather than
# assumed, in case of any "open angle" gap in the circular layout.
calibTip <- treeData[!is.na(treeData$label) & !is.na(treeData$angle), ]
calibTip <- calibTip[which.min(abs(calibTip$angle - 0)), ]
calibData <- data.frame(x = c(1, max(treeData$x, na.rm = TRUE)), y = calibTip$y, label = c("A", "B"))
degreesPerYUnit <- diff(range(treeData$angle, na.rm = TRUE)) / diff(range(treeData$y, na.rm = TRUE))
fontSizePoints <- 2.2 * (72.27 / 25.4) # ggplot2's own mm-to-points "size" convention

measurePointsPerNativeUnit <- function(plot) {
	calibPlot <- plot + geom_text(data = calibData, aes(x = x, y = y, label = label), hjust = 0.5, angle = 0, size = 2.2, fontface = "bold", inherit.aes = FALSE)
	calibFile <- tempfile(fileext = ".pdf")
	ggsave(calibFile, calibPlot, width = 25, height = 25, units = "cm")
	calibText <- system2("pdftotext", c("-bbox", calibFile, "-"), stdout = TRUE)
	calibRows <- grep(">A<|>B<", calibText, value = TRUE)
	extractCenter <- function(row) {
		nums <- as.numeric(regmatches(row, gregexpr("[0-9.]+", row))[[1]])
		mean(c(nums[1], nums[3]))
	}
	unlink(calibFile)
	(extractCenter(calibRows[2]) - extractCenter(calibRows[1])) / (max(treeData$x, na.rm = TRUE) - 1)
}

maxLabelWidthPoints <- max(sapply(labelPoints$cladeName, function(lbl) {
	grid::convertWidth(grid::stringWidth(lbl), "points", valueOnly = TRUE) * fontSizePoints / 12
}))

# Two calibration passes, not one: expand_limits() below (needed so the
# longest label doesn't get clipped at the real page edge - user
# feedback 2026-10-23, confirmed genuine clipping at the actual PDF
# boundary, not a crop artifact) widens the plot's own data range, which
# SHRINKS the rendered circle to fit the same fixed page size - changing
# the true points-per-native-unit scale. Computing declutter spacing
# from a calibration done BEFORE that expansion was applied used a
# stale, too-generous scale, so the same overlaps that were just fixed
# came right back once the margin was added. First pass gets a rough
# scale to size the expansion; second pass re-measures with that same
# expansion already applied, so the scale used for real is the one the
# final render will actually use.
pointsPerNativeUnitRough <- measurePointsPerNativeUnit(p)
maxLabelWidthNativeRough <- maxLabelWidthPoints / pointsPerNativeUnitRough
expandedXLimit <- outerX + maxLabelWidthNativeRough * 1.1
pointsPerNativeUnit <- measurePointsPerNativeUnit(p + expand_limits(x = expandedXLimit))
cat("calibration: points per native-x-unit (rough, final) =", pointsPerNativeUnitRough, pointsPerNativeUnit, "\n")

physicalRadiusPoints <- outerX * pointsPerNativeUnit
fontHeightPoints <- grid::convertHeight(grid::stringHeight("Mg"), "points", valueOnly = TRUE) * fontSizePoints / 12 * 2.2 # margin - 1.4x still left a confirmed real touching case (CMKLR1/MRGPRD) at full Mas1 scale
neededYSeparation <- (fontHeightPoints / physicalRadiusPoints) * (180 / pi) / degreesPerYUnit
cat("calibration: needed y-separation between labels =", neededYSeparation, "\n")

labelPoints <- labelPoints[order(labelPoints$y), ]
labelPoints$yFinal <- labelPoints$y
for (i in seq_len(nrow(labelPoints))[-1]) {
	if (labelPoints$yFinal[i] - labelPoints$yFinal[i - 1] < neededYSeparation) {
		labelPoints$yFinal[i] <- labelPoints$yFinal[i - 1] + neededYSeparation
	}
}

# A few points of visual gap between the connector's end and the text's
# own start/end - without this the line runs right up to the first/last
# glyph (user feedback 2026-10-23). Native-unit equivalent of a few
# points, using the already-calibrated pointsPerNativeUnit - the segment
# stops this much short of outerX; the text itself still anchors exactly
# at outerX, same for every label regardless of hjust direction.
segmentGapNative <- 3 / pointsPerNativeUnit

p <- p +
	geom_segment(
		data = labelPoints,
		aes(x = xAnchor, y = y, xend = x - segmentGapNative, yend = yFinal), color = "grey50",
		linewidth = 0.2, inherit.aes = FALSE
	) +
	geom_text(
		data = labelPoints,
		aes(x = x, y = yFinal, label = cladeName, hjust = hjust, angle = textAngle),
		color = "black", size = 2.2, fontface = "bold", inherit.aes = FALSE
	)

# ggsave()'s automatic panel sizing only accounts for the DATA point
# itself (x=outerX, a single value per label) - not the rendered text
# extending beyond it via hjust, since ggplot2's default scale expansion
# only looks at numeric data values, not a geom's visual footprint. User
# feedback 2026-10-23: several labels were genuinely cut off at the real
# page edge (confirmed directly - not a crop artifact, the real PDF's
# own boundary). expandedXLimit (computed above, before the declutter
# calibration, since it has to exist before that second calibration pass
# can measure the scale it actually produces) reserves room for the
# single longest label on both sides (right-half labels extend further
# right past outerX; left-half labels extend further left - same margin
# covers both by symmetry).
p <- p + expand_limits(x = expandedXLimit)

}

ggsave(outFile, p, width = 25, height = 25, units = "cm", limitsize = FALSE)
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s\n")
cat("Wrote", outFile, "\n")
