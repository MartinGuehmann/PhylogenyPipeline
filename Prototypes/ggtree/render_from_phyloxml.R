# Renders a circular cladogram directly from the pipeline's own phyloXML
# export (saveFullTreeAsPhyloXML() in 12_ConvertTreesToFigures.py) - the
# exact same *.fullTree.xml file already confirmed working in Archaeopteryx,
# no separate taxonomy classification step needed.
#
# Colors are read from the "PhylogenyPipeline:cladeColor" property, NOT
# from the native phyloXML <color> element - treeio::read.phyloxml()'s
# color parsing has a confirmed bug (its internal extract_another()
# deduplicates a <color> element's red/green/blue children BY VALUE, not
# by name, silently dropping any channel whose number matches an earlier
# one on the same node - e.g. cyan (0,255,255) loses blue and reads back as
# green). The cladeColor property is a single text value per node, added
# specifically to sidestep this (see buildPhyloXMLClade()'s own comment in
# 12_ConvertTreesToFigures.py for the full writeup and the real numbers:
# 665/2200 colored nodes affected in a real tree).
#
# Because every clade also carries a "PhylogenyPipeline:cladeName" property
# alongside cladeColor, treeio parses two <property> elements per node -
# each is independent (no value-collision risk, unlike <color>), but
# tidytree's as_tibble() auto-renames the resulting duplicate "ref"/
# "property" columns positionally (ref...3, ref...7, property...6,
# property...10, ...) rather than by content. So this script finds the
# right columns by checking which ref...N column actually holds
# "PhylogenyPipeline:cladeColor"/"PhylogenyPipeline:cladeName", instead of
# hardcoding a column name or position.
#
# Usage: Rscript render_from_phyloxml.R <fullTree.xml> <out.pdf>

library(treeio)
library(ggtree)
library(dplyr)

args <- commandArgs(trailingOnly = TRUE)
inFile <- args[1]
outFile <- args[2]

x <- read.phyloxml(inFile)
tb <- as_tibble(x)

findPropertyColumn <- function(tb, refValue) {
	refCols <- grep("^ref(\\.\\.\\.[0-9]+)?$", colnames(tb), value = TRUE)
	for (refCol in refCols) {
		if (any(tb[[refCol]] == refValue, na.rm = TRUE)) {
			propCol <- sub("^ref", "property", refCol)
			return(list(ref = refCol, property = propCol))
		}
	}
	stop(paste0("No column found with ref == '", refValue, "'"))
}

colorCols <- findPropertyColumn(tb, "PhylogenyPipeline:cladeColor")
nameCols <- findPropertyColumn(tb, "PhylogenyPipeline:cladeName")

tb2 <- tb %>%
	mutate(
		hexColor = ifelse(.data[[colorCols$ref]] == "PhylogenyPipeline:cladeColor", .data[[colorCols$property]], NA),
		cladeName = ifelse(.data[[nameCols$ref]] == "PhylogenyPipeline:cladeName", .data[[nameCols$property]], NA)
	)

x2 <- full_join(x, tb2 %>% select(node, hexColor, cladeName), by = "node")

p <- ggtree(x2, layout = "circular", branch.length = "none", size = 0.3) +
	aes(color = I(ifelse(is.na(hexColor), "grey70", hexColor)))

ggsave(outFile, p, width = 20, height = 20, units = "cm", limitsize = FALSE)
cat("Wrote", outFile, "\n")
