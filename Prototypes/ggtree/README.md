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

## Checked: does ete4 change this comparison? (2026-10-22)

No. Installed ete4 4.4.0 fresh into a throwaway venv (no Qt extra needed)
and inspected its actual source rather than relying on the older
[[project_ete4_migration_deferred]] investigation from 2026-08-04:

- Static PDF/PNG export (`ete4.treeview`) is confirmed still
  `from .qt import *` - a near-verbatim Qt port of ete3's renderer,
  including the same circular-layout machinery
  (`qt_circular_render.py`) ete3 already has via `TreeStyle(mode='c')`.
  Nothing new for the batch/headless rendering this pipeline needs.
- `ete4.smartview`'s declarative layout system (`Layout`,
  `'shape': 'circular'`, `PropFace` driven directly off a node
  property, `is-leaf-fn`) genuinely *is* a cleaner way to express
  "color every leaf by its own taxon property" than ete3's imperative
  `colorNodes()`/`NodeStyle` propagation-from-reference approach - but
  its SVG/PNG export (`static/js/download.js`'s `download_svg()`/
  `download_image()`) is client-side JavaScript that serializes
  whatever is currently drawn in the browser's on-screen canvas. It
  needs a running server plus a manual browser click, and only
  captures the current viewport, not the whole tree. No headless/CLI/
  server-side export path exists anywhere in `smartview` or `tools`
  (grepped the installed package, nothing).

So ete4 doesn't open a new route to an automatic, whole-tree, headless
static render - the ggtree-vs-ete3 comparison above stands unchanged.

## Checked: can ggtree load the pipeline's own phyloXML export? (2026-10-22)

Yes for correctness of the tree/topology/cladeName, but treeio's phyloXML
reader is too slow to use at this pipeline's real scale - this is a dead
end, not a viable path to "one export feeds both Archaeopteryx and
ggtree", at least not via `treeio::read.phyloxml()` as-is.

**What works:** `treeio::read.phyloxml()` loads the real, already-working
production file (`PRRs/.../pmsf.treefile.TaxaClades.fullTree.xml`, 1101
leaves, confirmed working in Archaeopteryx) correctly - all tips, all
1101 `cladeName` properties, each attached to the right leaf. ggtree
renders a correct circular cladogram straight from it.

**What's broken - color:** confirmed a real bug in `treeio`'s own parser,
not a mistake in this prototype's R code. `treeio:::extract_another()`
does `res <- res[!duplicated(res)]`, deduplicating a `<color>` element's
`red`/`green`/`blue` children **by value, not by name** - any color where
two of the three channels numerically coincide silently loses the later
one. Confirmed on the real PRRs file: 665 of 2200 colored nodes affected
(cyan, pure red/green/blue, darkgreen, limegreen, brown, ... - any color
with a repeated digit). Cyan (0,255,255) reads back as green (0,255,0) -
exactly the bug the user caught by eye in a rendered tree.

Fix for the *correctness* bug: `12_ConvertTreesToFigures.py`'s
`buildPhyloXMLClade()` (as of 2026-10-22) also writes a
`PhylogenyPipeline:cladeColor` property (a hex string) alongside the
existing `cladeName` one, in the SAME single `<property>` element
(pipe-delimited `"cladeName|#hexcolor"`), not a second `<property>`
sibling - see next finding for why.

**What's broken - speed, the real blocker:** a second `<property>`
sibling per node (tried first, the "obvious" fix) made
`read.phyloxml()` hang - confirmed via instrumented timing, it never
even finished on a 722-leaf test tree after 100+ seconds. Root cause:
`treeio:::parser_clade()` calls `dplyr::bind_rows()` on the ENTIRE
accumulated node list so far at EVERY recursion level (the return value
of each inner call is discarded - pure wasted work), already an O(n^2)
pattern before any further overhead. With two property elements sharing
the same tag name, EVERY one of those n intermediate bind_rows() calls
also triggers tibble's duplicate-column-name repair (prints a "New
names" message each time) - turning an already-bad O(n^2) into something
far worse in practice.

Switching to a single combined property (not two) avoided the repair-
message overhead, but didn't fix the underlying O(n^2) - timing the
**original, unmodified, single-cladeName-only design** directly
confirmed this is inherent to `read.phyloxml()` itself, nothing to do
with this prototype's changes: the real PRRs file (1101 leaves) took
**60 seconds** just to parse. A clean scaling test (synthetic balanced
trees, 200/400/800/1600 leaves, single property per node, same design as
the real pipeline) gave a log-log regression slope of **2.0055** -
genuinely quadratic, not just "slow" - and the fit (`t = 4.469e-5 * n^2`)
predicts 60s at PRRs' real 1101 leaves (measured: 60.1s, a very close
match) and extrapolates to **~3.1 hours at PeptideReceptors' 15871
leaves and ~7.2 hours at Mas1's 24156 leaves**.

**Verdict:** don't route per-leaf color/taxon data for ggtree through
`treeio::read.phyloxml()` on a real pipeline-scale tree - it will not
finish in practical time. The `cladeColor`/`cladeName` properties are
still useful for Archaeopteryx and for testing on small trees, but for
ggtree at real scale, re-derive per-leaf taxonomy directly
(`classify_tips_by_taxon.py`'s existing approach, no phyloXML/treeio
involved at all) rather than reading it back out of the exported file.

**Not a dead end for good, though - the O(n^2) is a fixable bug, not an
inherent cost.** Re-reading `parser_clade()`'s source: the one line
`dat <- dplyr::bind_rows(as.list(id[["data"]]))` runs at EVERY recursive
call, rebuilding a data frame from the ENTIRE accumulated node list so
far - and every intermediate result except the outermost call's is
immediately discarded (`lapply()`'s return value is never used, only its
side effect of mutating the shared `id` environment is). Move that one
line out of the recursion, call it once after the full traversal
finishes, and parsing drops to genuinely O(n). So a from-scratch, minimal
phyloXML-to-tibble reader (fixed schema: name/branch_length/color/
properties, written directly against `xml2`, not `treeio`) could plausibly
parse at real pipeline scale in practical time.

That would also remove the reason for this session's pipe-delimited
single-property workaround: treeio's column-collision problem (bug 1's
original "obvious fix," a second `<property>` sibling, made bug 2 far
worse) only happens because treeio names columns generically after the
XML tag ("property", "ref", ...), not after each property's own `ref`
attribute value. A custom reader we control can key each `<property>` by
its own `ref` directly into a distinctly-named column, so arbitrarily
many separate properties per node (cladeName, cladeColor, whatever else
comes up later) are fine - no packing/splitting hack needed.

## Built: a fast hybrid reader, bypassing treeio entirely (2026-10-23)

Rather than reimplementing `ape`'s tip/node-numbering from scratch (the
hard part of building a `phylo` object by hand), split the problem:

- **Topology** comes from the companion Newick `*.treefile`, via
  `ape::read.tree()` - already fast, never affected by treeio's
  phyloXML-specific O(n^2) bug, and it's the exact same tree object the
  phyloXML was serialized from (same source ete3 `Tree`, written twice).
- **Per-leaf annotations** (`cladeName`) come from a single linear
  `xml2` pass over the phyloXML: `.//d1:clade[not(d1:clade)]` selects
  every leaf `<clade>` element (no nested `<clade>` child) in one
  document-order XPath query - pure libxml2 C-side traversal, nothing
  like `parser_clade()`'s per-recursion-level `bind_rows()`.
- These join by leaf **label** - safe, since real accession-based tip
  names are unique. Internal node labels are NOT safe to join by:
  confirmed on the real PRRs file that the single support-value string
  "100/1/100" appears 170 times, so internal-node data can't be
  correlated this way. Not a problem in practice - the same
  monophyletic-propagation trick `render_colored_tree.R` already used
  (`groupOTU()`, coloring a whole subtree from its member leaves' group
  membership) reconstructs correct internal-branch coloring from
  leaf-level data alone, with no need to read per-internal-node color
  from the XML at all.

`render_from_phyloxml_fast.R` implements this. Benchmarked against real
production phyloXML files (not synthetic):

| Tree | Leaves | Newick parse | XML leaf extraction | Render | Total |
|---|---|---|---|---|---|
| PRRs | 1101 | 0.01s | 0.06s | 3.1s | ~3.2s |
| Renins | 9566 | 0.09s | 0.47s | 24.4s | ~25s |
| PeptideReceptors | 13814 | 0.15s | 0.68s | 38.9s | ~40s |

Compare to `treeio::read.phyloxml()` alone (the O(n^2) fit from
`project_treeio_phyloxml_quadratic_scaling`): ~60s at 1101 leaves,
~2.4 HOURS estimated at 13814. This isn't a marginal improvement, it's
the difference between impractical and instant - parsing is no longer
the bottleneck at all; total time is now dominated by ggtree/ggplot2's
own rendering, which scales roughly linearly and stays practical even
at the pipeline's largest real trees.

**Verdict updated**: the pipeline's own phyloXML export IS now a
practical shared data source for ggtree at real scale - just not via
`treeio::read.phyloxml()`. "One export feeds both Archaeopteryx and
ggtree" is viable after all, using this hybrid reader.

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
