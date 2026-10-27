# Fast alternative to render_from_phyloxml.R - avoids
# treeio::read.phyloxml() entirely (confirmed O(n^2), see
# project_treeio_phyloxml_quadratic_scaling memory / this directory's
# README) instead of trying to patch around it.
#
# Topology now comes from the phyloXML itself, not a companion Newick
# *.treefile (changed 2026-10-26 - see "Why not just read the companion
# Newick file?" below for why that was abandoned). Internal node labels
# (support-value strings like "100/1/100") are NOT unique - confirmed on
# the real PRRs file, that exact string alone appears 170 times - so a
# label-based join only works for LEAVES (real accession IDs, guaranteed
# unique), not internal nodes. That's fine: we don't need per-internal-node
# color from the XML at all. The same monophyletic-propagation trick the
# original ggtree prototype (render_colored_tree.R) already used -
# groupOTU() coloring a whole subtree from its member leaves' group
# membership - handles internal branches correctly from leaf-level data
# alone, and was already proven fast at full Mas1 scale (24156 leaves,
# well under 2 minutes total).
#
# Why not just read the companion Newick file? (the original 2026-10-23
# design, abandoned 2026-10-26) Initially this script read topology from
# the companion Newick *.treefile instead, reasoning that phyloXML's
# topology is "the same tree, serialized twice" so the much simpler/faster
# ape::read.tree() could stand in for it. That reasoning turned out to be
# wrong in one important case: 12_ConvertTreesToFigures.py's own
# initialReroot()/rerootToOutgroup() (rooting on whichever Clades.csv
# clade is listed last) run on ETE'S OWN IN-MEMORY COPY of the tree, AFTER
# it was already loaded from the *.treefile - so this reroot is baked into
# both ete's PDF render and the phyloXML export (confirmed 2026-10-26: the
# phyloXML's own root <clade> has exactly 2 children), but the *.treefile
# on disk is never rewritten and keeps IQ-Tree's own original, typically
# unrooted/trifurcating root. Confirmed concretely on Renins'
# FAMSA.BigTree5/RogueIter_5 (a real, no-outgroup round): the *.treefile's
# root has 3 children (ape::is.rooted() == FALSE), while the very same
# tree's phyloXML root has 2. Reading topology from the *.treefile meant
# this script's circular layout showed a different, biologically-arbitrary
# root than ete's own rendering of "the same" tree - a real discrepancy,
# not a cosmetic one. No faster existing R package than treeio turned up
# for reading phyloXML directly either (checked 2026-10-26 - RNeXML is a
# different format, NeXML, and nothing else current turned up), so
# readPhyloXMLTopology() below is a second from-scratch linear reader,
# alongside the existing leaf-property one, rather than a web find.
#
# readPhyloXMLTopology()'s approach: xml_find_all(doc, ".//d1:clade")
# returns every <clade> element in a single linear, pre-order, libxml2
# C-side traversal (document order) - this part costs the same as the
# leaf-only XPath already used elsewhere in this script (benchmarked:
# 0.03-0.08s even at Mas1's 48311 total clades). Resolving each clade's
# PARENT needs more care: xml_parent() on an entire nodeset does NOT
# vectorize 1:1 (confirmed directly 2026-10-26 - called on a 2-element
# nodeset sharing one parent, it returned a nodeset of length 1, i.e. it
# deduplicates rather than mapping element-by-element), so each node's
# parent has to be resolved individually via xml_parent() on that one
# node. A single-node xml_parent() call is backed by libxml2's native
# parent pointer (a true O(1) dereference, not a search), so doing this
# once per clade is still genuinely O(n) overall - confirmed via direct
# benchmark on real data: ~0.5s for the parent-resolution loop alone at
# Mas1's 48311-clade scale (vs treeio's own ~7.2h estimate for parsing
# that same file). A synthetic "data-idx" attribute, written once per
# clade in the same single pass, turns "which clade is this node's
# parent" into an O(1) attribute lookup instead of a second tree search.
#
# Usage: Rscript render_from_phyloxml_fast.R <fullTree.xml> <out.pdf> [colorBy]
#
# colorBy selects what the circular layout actually shows:
#   "clade" (default) - colors/groups by the curated PhylogenyPipeline:
#       cladeName/cladeColor leaf properties, and draws the full
#       clade-label-placement machinery below (outside-tree labels,
#       declutter, connectors).
#   "taxon" - colors/groups by the real per-leaf NCBI taxonomy
#       (PhylogenyPipeline:taxonOfInterest/taxonColor) instead - no labels
#       (2026-10-23 user feedback: "I just don't think that this tree needs
#       lables, at least not for now"), just the colored tree, since there
#       isn't a small curated list of named groups to label the way
#       Clades.csv's ~61 clades are.
#   "support" - ignores leaf properties entirely and colors each internal
#       BRANCH by whether it passes the strict support criterion (all
#       three of SH-aLRT>=85, aBayes>=0.95, UFBoot>=95 individually - see
#       feedback_support_value_acceptance_criterion memory): black if it
#       passes (or is a leaf branch, which this criterion doesn't apply
#       to), red if it fails, grey if no parseable support label exists
#       (e.g. the root). Needs the phyloXML's internal <clade> <name>
#       values to actually be IQ-Tree's own composite support string,
#       which only happens if the phyloXML's source tree was the real
#       *.treefile - *.contree (IQ-Tree's consensus tree) only carries
#       plain consensus-percentage integers, no SH-aLRT/aBayes/UFBoot at
#       all (confirmed 2026-10-27 on Renins' real fullTree.xml - see
#       project_renins_support_value_tree_source memory for the full
#       writeup and how to rebuild a round's phyloXML with the right
#       source if it's still contree-based). No labels, same reasoning as
#       "taxon".

library(xml2)
library(ape)
library(ggtree)
library(ggplot2)
library(dplyr)

# Builds an ape `phylo` object directly from the phyloXML's own nested
# <clade> structure - see this file's header comment for why (topology
# must match ete's own reroot, which a companion Newick *.treefile does
# not always reflect) and for the linear-time approach used here. Returns
# the tree plus the leaf <clade> nodeset (document order, aligned with
# tip 1..Ntip) so callers can pull per-leaf properties without a second
# full-document XPath pass.
readPhyloXMLTopology <- function(doc, ns) {
	allClades <- xml_find_all(doc, ".//d1:clade", ns)
	n <- length(allClades)

	for (i in seq_len(n)) xml_set_attr(allClades[[i]], "data-idx", i)

	parentIdx <- integer(n)
	for (i in seq_len(n)) {
		p <- xml_parent(allClades[[i]])
		pidx <- xml_attr(p, "data-idx")
		parentIdx[i] <- if (is.na(pidx)) NA_integer_ else as.integer(pidx)
	}

	# A clade is a leaf iff no other clade lists it as a parent - avoids a
	# second, separate "no nested <clade> child" XPath pass.
	isLeaf <- !(seq_len(n) %in% parentIdx)
	nTip <- sum(isLeaf)
	nNode <- n - nTip

	# ape-convention numbering (tips 1..nTip, internal (nTip+1)..(nTip+nNode)),
	# assigned in the same pre-order the clades were found in - the root
	# (the first clade found, parentIdx NA) is therefore the first internal
	# node encountered and lands on nTip+1, matching ape's own root
	# convention, with no separate special-casing needed.
	newId <- integer(n)
	newId[isLeaf] <- seq_len(nTip)
	newId[!isLeaf] <- nTip + seq_len(nNode)

	hasParent <- !is.na(parentIdx)
	edge <- cbind(newId[parentIdx[hasParent]], newId[which(hasParent)])

	leafClades <- allClades[isLeaf]
	# tip.label's order already matches newId's tip assignment above (both
	# walk isLeaf's TRUE positions in the same pre-order), so no separate
	# reordering is needed here.
	tipLabel <- xml_text(xml_find_first(leafClades, "./d1:name", ns))

	# Every clade's own <name> - for leaves this duplicates tipLabel; for
	# internal nodes this is whatever IQ-Tree wrote as that node's own
	# label in the source tree the phyloXML was built from (the composite
	# "SH-aLRT/aBayes/UFBoot" string when that source was *.treefile - see
	# the "support" colorBy mode above). Indexed by NEW ape node id
	# (1..nTip+nNode), same numbering as phy's own nodes, so callers can
	# use it directly without redoing the newId remapping.
	nodeName <- character(n)
	nodeName[newId] <- xml_text(xml_find_first(allClades, "./d1:name", ns))

	phy <- structure(list(edge = edge, tip.label = tipLabel, Nnode = nNode), class = "phylo")
	list(phy = reorder(phy, "cladewise"), leafClades = leafClades, nodeName = nodeName)
}

args <- commandArgs(trailingOnly = TRUE)
xmlPath <- args[1]
outFile <- args[2]
colorBy <- ifelse(length(args) >= 3, args[3], "clade")
stopifnot(colorBy %in% c("clade", "taxon", "support"))
addLabels <- colorBy == "clade"

cat("reading topology from phyloXML (xml2, single linear pass)...\n"); t0 <- Sys.time()
doc <- read_xml(xmlPath)
ns <- xml_ns(doc)
topo <- readPhyloXMLTopology(doc, ns)
phy <- topo$phy
leafClades <- topo$leafClades
leafNames <- phy$tip.label
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s -", length(leafNames), "tips\n")

cat("rendering...\n"); t0 <- Sys.time()

if (colorBy %in% c("clade", "taxon")) {

nameRef <- if (colorBy == "clade") "PhylogenyPipeline:cladeName" else "PhylogenyPipeline:taxonOfInterest"
colorRef <- if (colorBy == "clade") "PhylogenyPipeline:cladeColor" else "PhylogenyPipeline:taxonColor"

cladeNames <- xml_text(xml_find_first(leafClades, paste0("./d1:property[@ref='", nameRef, "']"), ns))
# Separate <property> element from cladeName's, not pipe-delimited - fine
# for our own xml2-based reader (each <property> parsed independently),
# unlike treeio's tibble pivot, which is what made two properties blow up
# there (see this directory's README).
cladeColors <- xml_text(xml_find_first(leafClades, paste0("./d1:property[@ref='", colorRef, "']"), ns))

leafData <- tibble(
	label = leafNames,
	cladeName = ifelse(is.na(cladeNames) | cladeNames == "", "Unclassified", cladeNames),
	# grey70 for leaves outside any curated clade - same fallback color
	# this directory's earlier prototypes used.
	cladeColor = ifelse(is.na(cladeColors) | cladeColors == "", "#B3B3B3", cladeColors)
)

# Group by the clade's own curated hex color (not cladeName) so the
# render uses the pipeline's real, already-chosen colors directly via
# scale_color_identity() - the same palette the production PDF already
# uses, not a separately re-derived ggplot palette. groupOTU's MRCA-based
# subtree propagation still reconstructs internal-branch coloring
# correctly from this leaf-level grouping, same mechanism as before.
groups <- split(leafData$label, leafData$cladeColor)
phyGrouped <- groupOTU(phy, groups)

# groupOTU() assigns its own reserved "0" level (a literal string, not a
# hex color) to any branch whose descendant leaves span more than one
# input group - e.g. the tree's own "spine" branches connecting separate
# curated clades together. scale_color_identity() can't resolve "0" as a
# color, so those branches rendered completely invisible/white - confirmed
# 2026-10-26 (user noticed the Renin clade's own connecting branch to the
# rest of the tree was missing). Recode that level to a real color before
# plotting; black matches how the rest of this pipeline already renders
# unresolved/connecting branches (e.g. ete3's own fullTree.pdf).
levels(attr(phyGrouped, "group"))[levels(attr(phyGrouped, "group")) == "0"] <- "#000000"

p <- ggtree(phyGrouped, layout = "circular", branch.length = "none", size = 0.3, aes(color = group)) +
	scale_color_identity()

} else {

# "support" mode: no leaf grouping at all - color each internal branch by
# whether ITS OWN node passes the strict support criterion. A node's
# composite label describes the branch leading to it (standard
# convention), so this is a per-node, not per-leaf-group, coloring -
# ggtree's %<+% (join extra data onto the tree by node id) is the right
# tool, not groupOTU (which is about propagating LEAF group membership
# down through monophyletic subtrees, a different problem).
nTip <- Ntip(phy)
nNode <- phy$Nnode
internalIds <- seq(nTip + 1, nTip + nNode)
supportParts <- strsplit(topo$nodeName[internalIds], "/")
getPart <- function(i) suppressWarnings(as.numeric(vapply(supportParts, function(p) if (length(p) == 3) p[i] else NA_character_, character(1))))
shALRT <- getPart(1)
aBayes <- getPart(2)
ufBoot <- getPart(3)

# All three thresholds individually, not an average or a majority vote -
# see feedback_support_value_acceptance_criterion memory for why (and
# why ete3's own .support attribute can't be trusted for this - it
# silently defaults to 1.0 for composite labels like these; reading the
# raw text ourselves, like here, is the only reliable way).
passes <- shALRT >= 85 & aBayes >= 0.95 & ufBoot >= 95

branchColor <- character(nTip + nNode)
branchColor[seq_len(nTip)] <- "#000000" # leaf branches - the criterion doesn't apply to these at all
branchColor[internalIds] <- ifelse(is.na(passes), "#B3B3B3", ifelse(passes, "#000000", "#FF0000"))

cat("support check (SH-aLRT>=85, aBayes>=0.95, UFBoot>=95, all three): ",
	sum(passes, na.rm = TRUE), "pass,", sum(!passes, na.rm = TRUE), "fail,",
	sum(is.na(passes)), "no parseable label (out of", nNode, "internal nodes)\n")

nodeColorDf <- data.frame(node = seq_len(nTip + nNode), branchColor = branchColor)
p <- ggtree(phy, layout = "circular", branch.length = "none", size = 0.3) %<+% nodeColorDf +
	aes(color = branchColor) + scale_color_identity()

}

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
