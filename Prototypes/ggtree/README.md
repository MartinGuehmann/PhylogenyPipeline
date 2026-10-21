Prototype: rendering a real pipeline tree with ggtree (R/Bioconductor),
colored by each leaf's **actual NCBI taxonomy** rather than by tree
topology. Not wired into the pipeline - a standalone exploration, kept
here so it doesn't get lost (2026-10-21 session).

## Why this exists

`12_ConvertTreesToFigures.py`'s own `colorNodes()` colors a whole subtree
one color by propagating down from wherever a single reference sequence
sits in the tree - fast, topology-based, but it can't tell a real member
of a clade apart from an unrelated sequence that a tree-reconstruction
error (long-branch attraction, weak signal in a small chunk) happened to
place nearby. This prototype instead classifies every leaf independently
by its own species' NCBI lineage (same approach used throughout this
session's manual investigations, e.g. the Angiotensinogens arthropod/
Chelicerata tree inspection), so a misplaced sequence shows up as a
visibly different-colored branch instead of being silently painted the
same color as its neighbors.

**Important finding from building this**: this isn't actually a new
*capability* ete3 lacks - see "What ete3 already does" below. The real
gap is narrower than it first looked.

## Files

- `classify_tips_by_taxon.py` - takes a real tree (Newick), classifies
  every leaf by NCBI taxonomy into this pipeline's own standard taxon
  vocabulary (same names/colors as every repo's `InterestingTaxa.csv` -
  copied from `Mas1/InterestingTaxa.csv`, the most complete version
  found). Writes a `label\tclade` TSV.
- `render_colored_tree.R` - takes that TSV + the same tree, renders a
  circular cladogram (`branch.length="none"`, so one real long branch
  can't blow out the whole plot's bounding box - confirmed necessary)
  with every branch colored via `groupOTU`, and one label per clade
  placed at that clade's own MRCA position (not an arbitrary member
  leaf - an earlier version of this script did that and some labels
  landed visibly off from their clade's actual colored mass).

Usage:
```
python3 classify_tips_by_taxon.py --tree <real.treefile> --out classification.tsv
Rscript render_colored_tree.R <real.treefile> classification.tsv out.pdf
```

## Environment note

This machine's R had a broken `ggtree` (2.4.2, from a stale default
Bioconductor pin) incompatible with its current `dplyr`/`rlang` - even
`ggtree(tree)` with zero extra arguments failed. Fixed via
`BiocManager::install(version = "3.23")` (matching R 4.6) before
`BiocManager::install("ggtree")`; also needed `install.packages("ggrepel")`
separately (not a Bioconductor package). If this is run somewhere ggtree
was never installed before, that whole dance isn't needed - just install
normally.

## What's been tested

- **PRRs** (1101 tips, real `PASTA.BigTree0/RogueIter_5` PMSF tree):
  works cleanly, ~1090/1101 leaves classified. Found genuine non-animal
  homologs (Fungi, Amoebozoa, Rhizaria, Viridiplantae) that really are
  in this tree - ATP6AP2 is an ancient, broadly-conserved eukaryotic
  gene, so this is correct, not a classification bug.
- **Mas1** (24156 tips, real `FAMSA.BigTree0/RogueIter_0` tree, the
  largest real completed tree in this pipeline as of 2026-10-21): full
  pipeline (classify + render) completes in well under 2 minutes
  (classification is the slow part at this scale; `groupOTU` 15s,
  `ggtree` build 37s, `ggsave` 47s), output PDF ~1.1MB. No sign of a
  scaling problem for anything in this pipeline's actual size range.
  ~84% of leaves classified (20366/24156) - the rest presumably fall
  outside the 34-bucket vocabulary (deep-sea/environmental samples,
  synthetic constructs, etc.) or have species names ete3's name
  translator doesn't resolve.

## What ete3 already does (don't assume this needs R)

Checked directly in `12_ConvertTreesToFigures.py` and ete3 itself:

- `TreeStyle(mode='c')` - ete3 already supports circular layout natively,
  same library the pipeline already uses. The pipeline's own
  `getFullTreeStyle()`/`getCollapsedTreeStyle()` just don't set it
  (default to rectangular `'r'`).
- Every leaf already gets a real `taxonOfInterest` attribute from
  `InterestingTaxa.csv` (genus-level mapping), used today for
  **per-leaf colored text labels** in the full-detail tree layout and
  for **`PieChartFace` composition pie charts** on collapsed nodes
  (`getColorsAndPercents(node, taxonColorMap, 'taxonOfInterest')`) -
  i.e. the "is this collapsed clade secretly impure" diagnostic this
  prototype's branch-coloring also gives you, ete3 already has, just in
  pie-chart form for collapsed views rather than branch color for full
  ones.

So the one genuinely missing piece is: color every leaf's own branch
(not just its text label) by `taxonOfInterest` across the *whole*
uncollapsed tree - a targeted addition to `colorNodes()`'s call sites in
the existing Python script, reusing data it already computes, rather
than a reason to add ggtree/R to this pipeline's toolchain.

## Known rough edges

- `na.value = NA` (as opposed to a real color like `"grey70"`) crashes
  `ggsave` with a confusing `Unknown colour name` error from `farver` -
  not immediately obvious this was the `na.value` setting and not the
  actual color map.
- Label density: when many small clades sit close together
  topologically (e.g. the basal-metazoan cluster: Porifera/Cnidaria/
  Placozoa/Hemichordata), `ggrepel` still can't fully avoid crowding -
  would need either smaller font, fewer labeled clades, or an
  interactive viewer instead of a static one for that region.
- Classification coverage isn't 100% (see per-tree numbers above) -
  unresolved leaves render as unclassified `grey70`, not wrong, but not
  informative either.
