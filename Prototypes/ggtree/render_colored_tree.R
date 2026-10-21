#!/usr/bin/env Rscript

# Renders a real pipeline tree as a circular cladogram with every branch
# colored by its leaves' actual NCBI taxonomy (via groupOTU), not by
# tree-topology propagation from a single reference sequence the way
# 12_ConvertTreesToFigures.py's colorNodes() does it - see this directory's
# README.md for why that distinction matters and what ete3 can/can't
# already do natively.
#
# Usage:
#   Rscript render_colored_tree.R <tree.newick> <classification.tsv> <out.pdf>
#
# <classification.tsv> is classify_tips_by_taxon.py's own output
# (columns: label, clade). Requires ggtree, ape, ggrepel, tidytree -
# install via BiocManager::install(c("ggtree","ggrepel")) if missing
# (ape/tidytree come along as ggtree's own dependencies). Needs a
# current ggtree (>= ~4.x) - the version Bioconductor's default
# BiocManager::install() resolves to on an old R install can be years
# out of date and silently incompatible with a current dplyr/rlang
# (confirmed 2026-10-21); if so, first run
# BiocManager::install(version = "3.23") (or whatever your R version's
# own current Bioconductor release is) before installing ggtree.

suppressMessages({
  library(ggtree)
  library(ape)
  library(ggrepel)
  library(tidytree)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: Rscript render_colored_tree.R <tree.newick> <classification.tsv> <out.pdf>")
}
treeFile <- args[1]
classFile <- args[2]
outFile <- args[3]

# Same taxon -> color map as classify_tips_by_taxon.py's TAXON_BUCKETS -
# kept in sync by hand (two small self-contained files beat a shared
# config dependency for a prototype this size).
colorMap <- c(
  Cyclostomata = "Turquoise", Chondrichthyes = "HotPink", Actinopterygii = "LimeGreen",
  Coelacanthimorpha = "Red", Dipnomorpha = "Peru", Amphibia = "Blue",
  Mammalia = "Orange", Lepidosauria = "YellowGreen", Testudinata = "Navy",
  Crocodylia = "Firebrick", Aves = "Cyan", Cephalochordata = "DarkGreen",
  Tunicata = "LightSeaGreen", Echinodermata = "Green", Hemichordata = "OliveDrab",
  Annelida = "Pink", Bryozoa = "DodgerBlue", Arthropoda = "DarkBlue",
  Brachiopoda = "DarkViolet", Rotifera = "CadetBlue", Tardigrada = "Tomato",
  Onychophora = "RosyBrown", Mollusca = "SteelBlue", Nematoda = "Brown",
  Platyhelminthes = "DarkGoldenrod", Cnidaria = "MediumOrchid", Ctenophora = "DarkOrange",
  Choanoflagellata = "Indigo", Porifera = "Gold", Placozoa = "DarkKhaki",
  Viridiplantae = "Green", Fungi = "DeepPink", Discoba = "Chocolate",
  Amoebozoa = "SlateBlue", Rhizaria = "Magenta"
)

t0 <- Sys.time()
tree <- read.tree(treeFile)
cat("Loaded tree with", length(tree$tip.label), "tips in",
    round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")

classification <- read.table(classFile, sep = "\t", header = TRUE,
                              stringsAsFactors = FALSE, quote = "")
groupList <- split(classification$label, classification$clade)

t0 <- Sys.time()
treeGrouped <- groupOTU(tree, groupList, group_name = "Clade")
cat("groupOTU done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")

p <- ggtree(treeGrouped, layout = "circular", branch.length = "none",
            aes(color = Clade), linewidth = 0.12) +
  scale_color_manual(values = colorMap, na.value = "grey70", guide = "none") +
  theme(plot.margin = margin(10, 10, 10, 10))

# Label each group at its MRCA's own plotted position, not an arbitrary
# member leaf (the quick prototype's "first tip in the list" placement
# could land visibly off-center from the clade's actual colored mass -
# the MRCA is always inside/at the root of that clade's real extent).
treeData <- p$data
mrcaRows <- lapply(names(groupList), function(g) {
  tips <- groupList[[g]]
  nodeId <- if (length(tips) == 1) {
    treeData$node[treeData$label == tips[1]]
  } else {
    tidytree::MRCA(treeGrouped, tips)
  }
  row <- treeData[treeData$node == nodeId, c("x", "y")]
  if (nrow(row) == 1) data.frame(Clade = g, x = row$x, y = row$y) else NULL
})
labelPoints <- do.call(rbind, mrcaRows)

p <- p + geom_text_repel(
  data = labelPoints,
  aes(x = x, y = y, label = Clade), color = "black", inherit.aes = FALSE,
  size = 2.2, fontface = "bold", max.overlaps = Inf,
  segment.size = 0.25, segment.alpha = 0.5,
  min.segment.length = 0, box.padding = 0.3
)

t0 <- Sys.time()
ggsave(outFile, plot = p, width = 16, height = 16, limitsize = FALSE)
cat("ggsave done in", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
cat("Wrote", outFile, "\n")
