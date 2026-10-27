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

## Wired in cladeColor + tested at Mas1's full scale (2026-10-23)

`cladeColor` (added to `buildPhyloXMLClade()` the same day, as a second
`<property>` alongside `cladeName` - safe for this directory's own xml2
reader even though a second `<property>` is exactly what made treeio's
reader hang, see above) is now read the same way as `cladeName` and
used directly via `scale_color_identity()` - the render uses the
pipeline's own already-chosen curated colors, not a separately
re-derived ggplot palette, matching the real production PDF's own
palette exactly.

Mas1 had no phyloXML export yet (predates the feature) - generated a
real one locally by importing `12_ConvertTreesToFigures.py` and calling
its actual pre-render functions directly (`loadTaxa`, `loadCladeInfo`,
`initialReroot`, `cladifyNodes`, `nameCladeRoots`, `colorAndNameClades`,
`saveFullTreeAsPhyloXML`), skipping only the Qt-dependent PDF rendering
and alignment-sorting steps - same technique used for earlier synthetic
test files, just now against Mas1's real 24156-leaf tree and real
61-clade `Clades.csv`, not synthetic data.

**Full Mas1 scale (24156 leaves, the largest real completed tree in
this pipeline): 0.28s Newick parse + 1.7s XML extraction + 113.7s
render = ~116s total.** Matches the very first ggtree prototype's
original "well under 2 minutes" benchmark from before any of the
treeio complications - now achieved reading the pipeline's own real
exported data, not a separate taxonomy-reclassification step. Visual
result confirmed correct: real curated clade colors from Mas1's own
`Clades.csv`, with large black regions being the pipeline's own genuine
"no clade defined yet" background color (not a fallback artifact) -
exactly the diagnostic view useful for deciding where to carve out new
clades.

**Clade labels added same day, placed to match
`assignCladeNameToCenterLeaf()` exactly** (confirmed by reading its
source, not guessed): that function labels the leaf at position
floor(n/2) in ete3's `iter_leaves()` order, not the clade's MRCA/root.
First version used `tidytree::MRCA()` (an internal node) - user caught
that this didn't match the pipeline's own convention. Fixed by sorting
each clade's member tips by their plotted `y` position (ggtree's tip
order follows the same left-to-right traversal as ete3's, same source
topology) and picking the middle one - a real leaf, not an internal
node. Also turned out faster: 108.8s vs 195s at full Mas1 scale (61
labels) - `MRCA()` was apparently the slow part, not
`geom_text_repel()`.

**Labels moved outside the tree entirely, same day** - user feedback:
labels anchored right at the center leaf's own position still
overlapped tree branches. In this circular layout `x` is literally the
radial distance from center and `y` is the angular/tip-index position -
not Cartesian coordinates (confirmed directly: a test tree's `p$data$x`
ranged 0-42, i.e. tree depth, and `y` ranged 1-Ntip; the depth->radius /
index->angle transform happens at render time via ggtree's own
coordinate system, shared by every layer on the plot). So pushing a
label outward is just a larger `x` at the same `y` - no trigonometry
needed. Each label now sits at a fixed outer radius
(`max(x) * 1.1`), connected back to its real center-leaf anchor by a
straight radial `geom_segment`. Confirmed clean at full Mas1 scale (61
labels, ~112s total) - no overlap with the tree, only minor leader-line
crossing in the single densest region (the MRGPRX cluster).

**Still crossed into the tree in some spots - fixed properly, same day.**
User kept catching real remaining cases. Root causes, found by actually
checking the data rather than guessing twice more:

1. First attempt added `xlim = c(outerX, NA)` to `geom_text_repel()`
   alone - verified numerically (via `ggplot_build()`) that this
   correctly clamps the label's data-space x (radius) to never go below
   `outerX`, so the ANCHOR point is always genuinely outside the tree.
   But `geom_text_repel` renders text horizontally regardless of where
   around the circle it sits - on the left half of the circle, text
   growing rightward from a correctly-outside anchor still grows back
   toward the center. ggtree's own `geom_tiplab_circular()` (read its
   source directly) already solves exactly this: flip `hjust` to 1
   whenever `angle` (a column ggtree already computes in `p$data`, 0-360
   degrees) is in `[90, 270]`.
2. hjust-only still weren't enough - confirmed on real labels sitting at
   ~220-245 degrees (diagonal, not purely leftward/rightward): even
   correctly-leftward-growing horizontal text still has a vertical
   extent that crosses into the tree at angles far from exactly 180.
   `geom_tiplab_circular()`'s full convention also rotates the text
   itself to the local radial angle (`angle` as-is on the right half,
   `angle + 180` on the left half, so it stays upright) - confirmed
   `geom_text_repel` actually supports a rotated `angle` aesthetic via
   an isolated test first, then applied the same full rotation + hjust
   combination here.

Confirmed clean at full Mas1 scale after both fixes: every one of the
61 labels reads radially outward, correctly oriented, with no crossing
into the tree anywhere around the full circle - residual overlap is
now only label-vs-label text crowding in the single densest cluster
(a much smaller, separate problem from labels entering the tree).

**Still one label visibly wrong (Somatostatin receptor 1/SSTR1) - fixed
for real this time, with the actual root cause identified precisely by
the user rather than more guessing.** Isolated testing of SSTR1's exact
real data (angle, hjust, rotation - all directly from the production
pipeline) confirmed the rotation FORMULA itself was correct even for
this specific clade; the bug was elsewhere. User's own diagnosis,
verified directly against the code, was exactly right: "There is a kink
in the connecting line inward... The rotation would be right if it were
at its intended place. One other thing is that the connecting line goes
to the top of the label box, instead to the front or to the back
depending on rotation." Root cause: `geom_text_repel()`'s own
auto-drawn connector always reaches a fixed point on the text's
UNROTATED bounding box - it ignores the `angle` aesthetic entirely, so
once text is rotated that auto-segment reaches the wrong corner,
producing a visible kink. The same rotation-blindness also affects
ggrepel's internal collision/placement math, letting a label's anchor
drift inward from `outerX` even under `xlim = c(outerX, NA)` (a
constraint, not an exact value). Fixed two ways: `segment.color = NA`
suppresses ggrepel's own broken connector entirely (the `geom_segment()`
drawn separately, a plain point-to-point line, is immune to this since
it never needs to find a "side" of a box), and `xlim = c(outerX,
outerX)` (both bounds the same exact value, not just a minimum) removes
any room for radial drift - only the tangential/angular position is
ever adjusted to declutter now. Confirmed clean on the real SSTR1 clade
and the full Mas1 render afterward.

**One more real issue found after that, with the connector itself, not
the label position.** User's own precise diagnosis: "the connecting
line goes to the top of the label box, instead to the front or to the
back depending on rotation" - and read `ggrepel::makeTextRepelGrobs()`'s
actual source directly to understand it precisely rather than guessing
a third time. Confirmed: the text's own position/rotation (`x_adj`/
`y_adj` in that function) DOES correctly account for hjust/vjust/angle
- that part was never broken. The connector is separate: it picks the
nearest point on the text's AXIS-ALIGNED bounding box (`grobX`/`grobY`
"west"/"east"/"south"/"north" - literal compass directions, not "front"/
"back" of the reading direction) to the label's ORIGINAL, pre-repel
anchor - no public parameter lets you override which side gets chosen.
Tried letting ggrepel's own connector draw anyway (removing
`segment.color = NA`): confirmed worse, not better - a heavily-repelled
label's connector could pick a far corner and draw a long diagonal line
straight across several unrelated labels' text (seen on the real Mas1
render, "Kappa opioid receptor" cutting across "Somatostatin receptor
1" and others).

Fixed properly with a two-pass build: suppress ggrepel's own connector
(`segment.color = NA`) and manually draw a clean point-to-point
`geom_segment()` instead - but using each label's REAL final (post-
repel) position, not its original pre-repel anchor (a plain manually-
drawn segment at the original position was the earlier, previously-
reported "not connected... quite off" symptom, since repel is still
free to move labels tangentially to declutter and a static segment
doesn't track that). Extracted the real final positions via one extra
`ggplot_build()` call before adding that segment layer and saving -
confirmed row order stays stable against `geom_text_repel()`'s own
position adjustment (checked a known label's row against its expected
values). Surprisingly cheap in practice: ~113s total at full Mas1
scale, barely more than the single-pass version, not the roughly-double
time a second full build might suggest. Confirmed clean on the real
SSTR1 region and the full circle: every connector is now a straight
line from the real leaf to its label, correctly tracking repel's
tangential adjustments, with no kinks and no stray diagonals crossing
through unrelated labels anywhere.

**That still wasn't the end of it - user caught "half inside the tree"
on the same label, a real bug in a different layer entirely.** Traced
to `ggplot_build()` only reporting `geom_text_repel()`'s position/repel
ALGORITHM output (confirmed unchanged, exactly `outerX`) - the actual
RENDERED glyphs get shifted again, later, inside
`makeTextRepelGrobs()`'s own grob-building step, by roughly half the
string's rendered width (implementing hjust). That later shift never
goes through `ggplot_build()`, so the two-pass connector fix above never
saw it and never respected the locked radius. First attempt: calibrate
real native-units-per-point empirically (render two tiny reference
labels at known radii on the bare tree, read back their true printed
position via `pdftotext -bbox`), then compute each label's own
`grid::stringWidth()`-based half-width and shift its anchor outward to
compensate - technically sound, but overly complex. A direct side-by-side
test (same string, same `x`/`y`/`hjust`/`angle`/locked radius) isolated
the real cause more precisely: plain `geom_text()` rendered entirely
outside the tree with NO compensation needed at all; `geom_text_repel()`
visibly bled into it. So the width-offset is not a general hjust/rotation
property to correct for - it's specific to `geom_text_repel()`'s own
drawing step.

**Final, much simpler architecture**: stop asking `geom_text_repel()` to
draw anything at all (`color = NA`). Only use it for what it's genuinely
good at - finding good angular (y) spacing to declutter dense clusters,
with the radius locked via `xlim = c(outerX, outerX)` as before. Extract
the repelled y via one `ggplot_build()` call, then draw the actual
visible text with plain `geom_text()` at a fixed radius/hjust/angle - no
per-label width compensation needed, deterministic, immune to whatever
`geom_text_repel()`'s internal grob-drawing math does. Confirmed clean
on the real SSTR1 clade and the full Mas1 render: no labels crossing
into the tree anywhere around the full circle. Remaining text-on-text
crowding in the one or two densest clusters (e.g. "Complement C3a
receptor" overlapping its neighbor) is the separate, already-accepted
label-density limitation from earlier in this section - not the same
bug.

**That remaining crowding turned out fixable too - confirmed
geom_text_repel's own collision DETECTION is unreliable here, not just
its drawing.** Direct test on the real worst case (two adjacent
single-leaf clades, "C5AR1-like" and "Complement C3a receptor", y 1
apart out of 24156 total): `geom_text_repel()` left their y completely
unchanged (converged in 0.18s, having concluded - wrongly - that
nothing needed to move). Consistent with the same axis-aligned,
rotation-blind bounding-box math found everywhere else in this
investigation, now confirmed to affect overlap detection too, not just
drawing and raw positioning.

Replaced with a direct, deterministic calculation instead of trying to
tune `geom_text_repel()` further. Labels are rotated to read radially,
so the dimension that matters for two ADJACENT labels not overlapping
is each one's own font HEIGHT in the angular/y direction (not string
length, which only matters radially and is already handled by the
fixed outerX radius) - the same constant for every label here, since
they all share one font size. That reduces the whole problem to: sort
labels by y, and whenever two consecutive ones are closer than one
font-height's worth of arc length, push the later one out by the
shortfall. Needed two real calibrated quantities, not assumed values:
the true physical radius of outerX in points (two tiny reference labels
at known radii on the bare tree, read back via `pdftotext -bbox` - same
technique as the earlier width investigation) and degrees-per-y-unit
computed directly from the tree's own real angle/y data (in case of any
"open angle" gap in the circular layout, rather than assuming a clean
360/Ntip). Confirmed clean on the real worst cases at full Mas1 scale:
the previously-overlapping pair, and the three tightly-packed
MAS-related GPR X1/X3/X4 labels, are all now cleanly separated and
legible. Costs one extra full tree render for the calibration step
(~160s total at Mas1 scale now, up from ~110s), a real but bounded
trade-off for getting this right rather than leaving it as an accepted
limitation.

**Two more real issues found after that, both confirmed and fixed at
full Mas1 scale.**

1. Several labels were genuinely clipped at the real PDF page edge
   (confirmed directly, not a crop artifact) - `ggsave()`'s automatic
   panel sizing only accounts for each label's DATA point (`x = outerX`,
   a single value), not the rendered text extending beyond it via
   `hjust`. Fixed with `expand_limits(x = outerX + maxLabelWidthNative *
   1.1)`, using the same `stringWidth()`-based technique as elsewhere in
   this section to find the single longest label's own width.
2. That fix reintroduced the exact overlaps just fixed above - a real
   circular dependency: widening the data range via `expand_limits()`
   shrinks the rendered circle to fit the same fixed page size, which
   changes the true points-per-native-unit scale the declutter spacing
   was computed from. Fixed with two calibration passes instead of one:
   a rough pass (no expansion) sizes how much expansion is needed: a
   second pass re-measures the actual resulting scale with that same
   expansion already applied, so the declutter spacing uses the scale
   the final render actually produces, not a stale pre-expansion one.

Separately, a still-real but different-feeling case (CMKLR1/MRGPRD,
touching at their far ends despite the declutter sweep applying its
*exact* intended spacing - confirmed directly, not a sweep bug) showed
the font-height margin itself was just too tight in practice; raised
from +40% to +120% and confirmed clean afterward, including every
previously-flagged cluster (C3AR1/C5AR2, CMKLR1/MRGPRD, FMLP I/II,
MRGPRX1/X3/X4, GPER1/Apelin/GPR15, the P2RY12/GPR18/CLTR1/CLTR2 run)
plus no page-edge clipping. No known remaining issues as of this
writing. Now three full tree renders total (~210s at Mas1 scale).

**Minor polish, same day:** the connector line ran right up to a
label's first/last glyph with no visual gap - `segmentGapNative` (a few
points, converted via the same `pointsPerNativeUnit` calibration) pulls
the line's end back slightly short of `outerX` while the text itself
still anchors exactly at `outerX`, same for every label regardless of
`hjust` direction. Confirmed at full Mas1 scale: a clear, modest gap
everywhere, no regressions elsewhere.

## By-taxon coloring (no labels)

`12_ConvertTreesToFigures.py`'s `buildPhyloXMLClade()` now also writes each
leaf's real per-leaf NCBI-taxonomy classification (`addHigherTaxaOfInterest()`,
the same mechanism behind the existing PDF's own taxon-of-interest faces) as
two more `<property>` elements, `PhylogenyPipeline:taxonOfInterest` and
`PhylogenyPipeline:taxonColor` - independent of, and alongside, the curated
`cladeName`/`cladeColor` pair above. Same reasoning as that pair for keeping
them as separate sibling `<property>` elements rather than packed into one
(no column-collision risk for this project's own `xml2`-based reader, unlike
treeio's).

`render_from_phyloxml_fast.R` takes a 3rd, optional CLI argument, `colorBy`,
to pick which property pair to color/group by:

```
Rscript render_from_phyloxml_fast.R <fullTree.xml> <out.pdf> [clade|taxon]
```

- `clade` (default, unchanged behavior) - curated `Clades.csv` assignment,
  with the full outside-tree label-placement machinery (calibration,
  declutter, connectors) described above.
- `taxon` - real NCBI taxonomy instead, with the entire label block skipped
  (user feedback 2026-10-23: "I just don't think that this tree needs lables,
  at least not for now" - real taxonomy isn't a small curated list the way
  Clades.csv's ~61 clades are, so there's no natural small label set here
  the way there is for `clade` mode). Confirmed working at full Mas1 scale:
  ~106s (vs ~209s for `clade` mode, which does three full tree renders for
  its two calibration passes - `taxon` mode only ever renders once), no
  clipping, no stray label artifacts.

## Topology now read from the phyloXML itself, not a companion Newick file

The original design (above) read tree topology from the companion Newick
`*.treefile` and used the phyloXML only for per-leaf properties, reasoning
that both files serialize "the same tree." That turned out to be wrong in
one real, confirmed case (2026-10-26, found while reviewing a fresh Renins
render): `12_ConvertTreesToFigures.py`'s `initialReroot()`/
`rerootToOutgroup()` (rooting on whichever `Clades.csv` clade is listed
last) run on ete's own in-memory copy of the tree *after* it's loaded from
the `*.treefile`, and that reroot is baked into both ete's own PDF and the
phyloXML export - but the `*.treefile` on disk is never rewritten, so it
keeps IQ-Tree's own original root (frequently an arbitrary, biologically
meaningless trifurcation for a round with no outgroup). Confirmed directly
on Renins' `FAMSA.BigTree5/RogueIter_5` (a real no-outgroup round): the
`*.treefile`'s root has 3 children (`ape::is.rooted() == FALSE`), while
that same tree's phyloXML root has 2. Reading topology from the
`*.treefile` meant this script's own circular layout showed a different,
arbitrary root than ete's rendering of "the same" tree.

No existing R package reads phyloXML faster than `treeio` either (checked
2026-10-26 - `RNeXML` is a different format, NeXML; nothing else current
turned up), so `readPhyloXMLTopology()` is a second from-scratch linear
reader, parallel to the existing leaf-property one: `xml_find_all(doc,
".//d1:clade")` gets every `<clade>` in one linear pre-order pass, then
each node's parent is resolved individually via `xml_parent()` on that one
node (confirmed `xml_parent()` does NOT vectorize 1:1 over a whole
nodeset - called on a 2-element nodeset sharing one parent, it returned a
nodeset of length 1, i.e. it deduplicates rather than mapping
element-by-element). A single-node `xml_parent()` call is backed by
libxml2's native parent pointer (true O(1), not a search), so resolving
all n parents individually is still genuinely O(n) - confirmed via direct
benchmark on real data: ~0.5s for the parent-resolution loop alone at
Mas1's 48311-clade scale (vs treeio's own ~7.2h estimate for parsing that
file). A synthetic `data-idx` attribute, written once per clade in the
same pass, turns "which clade is this node's parent" into an O(1)
attribute lookup. Confirmed working end-to-end: Renins' real
`FAMSA.BigTree5/RogueIter_5` now renders with `is.rooted() == TRUE` and a
2-child root, matching ete's phyloXML exactly; full Mas1-scale regression
(24156 leaves) confirmed clean (~3s topology+property read, same visual
output as before, no timing regression vs. the old Newick-based read).

The companion Newick `*.treefile` is no longer read by this script at
all - the CLI dropped its first argument accordingly.

## Support-value coloring (2026-10-27)

A third `colorBy` mode, `support`, colors each internal branch by whether
it passes the strict acceptance criterion from
`feedback_support_value_acceptance_criterion` memory: all three of
SH-aLRT>=80, aBayes>=0.95, UFBoot>=95 individually, not an average or
majority vote. Black = passes (or is a leaf branch, which the criterion
doesn't apply to), red = fails, grey = no parseable composite label at
all (e.g. the root). No leaf grouping/coloring and no labels - this mode
ignores `cladeName`/`cladeColor`/`taxonOfInterest`/`taxonColor` entirely
and only reads each internal `<clade>`'s own `<name>`.

This surfaced a real, easy-to-miss gotcha: a round's phyloXML only
carries genuine composite support values if it was built from the
source tree's `*.treefile` (IQ-Tree's own ML best tree). `*.contree`
(the consensus tree) only carries plain consensus-percentage integers at
internal nodes (e.g. `34`, `100`) - no SH-aLRT/aBayes/UFBoot at all.
`buildPhyloXMLClade()` just writes whatever `eteNode.name` the fed-in
tree happened to have, so this isn't a bug in the exporter - it's
entirely about which extension gets passed to step 12's `-m` master
render. Renins' `FAMSA.BigTree5/RogueIter_5` had to be rebuilt with
`-e treefile -E treefile` (previously built with `-e contree`, matching
`Config.sh`'s `extension="contree"` - which is step 16's extraction
setting, not step 12's) before this mode had real data to show -
confirmed directly: the old contree-based phyloXML's internal names were
all plain integers, the treefile-based rebuild's were all genuine
`SH-aLRT/aBayes/UFBoot` strings. See
`project_renins_support_value_tree_source` memory for the full
investigation.

Implementation: `readPhyloXMLTopology()` now also returns every clade's
own `<name>` text (not just leaves'), indexed by the same ape node
numbering as `phy` itself, from the same single linear pass (no second
XML traversal). Support mode parses each internal node's `/`-delimited
label into its three numbers and joins the resulting pass/fail color
onto the tree via `%<+%` (ggtree's own node-indexed data join) -
`groupOTU()`'s leaf-group propagation (used for `clade`/`taxon` mode)
doesn't apply here, since this is a direct per-node property, not
something to propagate down from leaf membership.

Confirmed on Renins' real tree (`FAMSA.BigTree5/RogueIter_5`, rebuilt
with `.treefile`): 4882 pass, 4363 fail, 4 unparseable out of 9249
internal nodes - visually a believable scattered mix of red/black
throughout the circular layout, not concentrated in one obviously-wrong
region. Regression-tested at full Mas1 scale (24156 leaves, whose test
fixture's phyloXML was already treefile-based): 13166 pass, 10985 fail,
4 unparseable, ~87s total, no errors.

**Per-metric gradients, same day.** User follow-up after seeing the
combined view: checking just Renin/Cathepsin D/Napsin A (the three
clades already confirmed solid by E-value and topology, see the main
session's investigation) still showed ~50% "fail" each (391/405/488
internal nodes, 51.4%/42.7%/50.2% pass) - but inspecting the actual
failing labels showed many are a near-miss on just ONE of the three
metrics (e.g. `87.6/0.997/85` fails only because UFBoot is 85 vs the 95
threshold), not uniformly weak. A 4th CLI argument, `supportMetric`,
was added to see this directly: `"shalrt"`/`"abayes"`/`"ufboot"` render
a continuous red (low) to black (high) gradient of that one metric's
own raw value (0-100 for SH-aLRT/UFBoot, 0-1 for aBayes - each kept on
its own natural scale rather than normalized), instead of the combined
pass/fail view (still the default, `"combined"`). Confirmed working on
Renins at full scale, visually a sensible, legend-labeled gradient (not
just binary red/black).

**SH-aLRT threshold correction, same day.** This script (and the memory
this whole criterion came from) briefly used 85 as the SH-aLRT cutoff.
That was wrong - confirmed 80 from two independent sources: the actual
published methods section (Gühmann, Porter & Bok 2022, *Cells* 11:2441,
Section 2.4) and, independently, the production pipeline's own
`12_ConvertTreesToFigures.py` (`SHaLRTThresholds[0] = 80.0`, checked
against in `getSupportOverThresholdColor()`). All numbers in this
section were recomputed with the corrected 80 after this surfaced - see
`feedback_support_value_acceptance_criterion` memory for the full story
of how the wrong number got there in the first place (a concrete
instance of a number getting corrupted across a compaction boundary,
not an independent error).

**"2of3" criterion, same day.** After the threshold correction still
left the combined view looking about as red as before (expected - the
correction only moved a narrow band of nodes, not the overall picture),
user conclusion: the combined criterion's strictness itself, not any
specific number, is what mainly drives the ~50% fail rate - deliberate
per the paper's own stated reasoning (the three metrics "compensate for
each other's failures"), but a genuinely different point on the
sensitivity/specificity tradeoff than "how many splits pass at least 2
of 3". Added `supportMetric = "2of3"`: same black/red/grey coloring as
"combined", but passes if at least two of the three clear their own
threshold rather than requiring all three. Uses a pairwise OR-of-AND
construction (`(shPass&aPass)|(shPass&uPass)|(aPass&uPass)`) rather than
`rowSums(...)>=2`, so NA (unparseable) propagates exactly as
principled as plain `&` already does for "combined" - two known passes
make a node pass regardless of whether the third metric was even
parseable, while a single known pass plus two unparseable stays
correctly NA (genuinely ambiguous) rather than guessing.

Confirmed on Renins: 6622 pass, 2623 fail, 4 unparseable (71.6% pass,
vs. 52.8% for "combined" on the same tree) - visually a substantially
less-red circle, as expected. Regression-tested at full Mas1 scale:
17414 pass, 6737 fail, 4 unparseable (72.1%), no errors.

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
