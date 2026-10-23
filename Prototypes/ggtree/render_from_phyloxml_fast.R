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

ggsave(outFile, p, width = 25, height = 25, units = "cm", limitsize = FALSE)
cat("  ", as.numeric(Sys.time() - t0, units = "secs"), "s\n")
cat("Wrote", outFile, "\n")
