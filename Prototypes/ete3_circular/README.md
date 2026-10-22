Prototype: can ete3 (already the pipeline's own rendering library, used
by `12_ConvertTreesToFigures.py`) do the same thing `../ggtree/` does -
a circular tree with every branch colored by real per-leaf NCBI
taxonomy? Shelved here next to `../ggtree/` (2026-10-22 session).

## Verdict: ggtree wins

ete3 *can* do circular mode and per-leaf/per-subtree branch coloring by
real taxonomy - confirmed working, not just theoretically possible. But
it has no built-in equivalent of ggtree's `branch.length="none"`
cladogram (true tip alignment), and the manual workaround for that
(`render_colored_tree_tip_aligned.py`) produces a visibly worse figure
than ggtree's native version for a real tree with uneven leaf depths
(see "What was tried" below). Keep using ggtree
(`../ggtree/render_colored_tree.R`) for this kind of overview figure.

This doesn't mean ete3 is a dead end generally - see "What this doesn't
rule out" at the bottom.

## What was tried, in order

1. **First attempt** (not kept, see git history if curious): leaf-only
   coloring, default `TreeStyle(mode='c')`, real branch lengths (a true
   phylogram), default node markers left on. Rendered, but:
   - poppler/pdftoppm reported ~1 `Syntax Error: No current point in
     closepath` per leaf - a genuinely invalid PDF, not just a cosmetic
     issue. **Okular still opened it fine** (confirmed by hand), so this
     doesn't block every viewer, but it's not a clean, valid PDF either
     - a stricter reader might not be as forgiving.
   - Visually lopsided/rough: real branch-length scaling meant long
     branches dominated and short ones crowded together - expected
     phylogram behavior, not a bug, but not what was being compared
     against (ggtree's version uses `branch.length="none"`, a cladogram,
     not a phylogram - different thing, not an apples-to-apples
     comparison).

2. **`render_colored_tree_depth.py`** (kept, works well): switched to
   `ts.force_topology=True` (ete3's built-in "fixed branch length"
   option) and `size=0` on every node, not just leaves. This fixed
   *both* problems at once - zero PDF syntax errors, and a clean,
   reasonably-proportioned circular tree with full internal+leaf branch
   coloring (bottom-up monophyletic propagation, same idea as ggtree's
   `groupOTU`). Renders in ~1.2s for PRRs' 1101 tips.
   
   Caveat found by actually inspecting the rendered tips closely: this
   is **not** a true cladogram - `force_topology` gives every edge the
   same *fixed* length, so a leaf's distance from the root is
   `unit_length × its own topological depth`. Leaves at different
   depths end up at different radii, same as a real phylogram just
   using unit lengths instead of real branch lengths - genuinely
   different from ggtree's tip-aligned cladogram, not just a labeling
   nitpick (confirmed visually: e.g. the Arthropoda sector reaches much
   further out than others in the same tree).

3. **`render_colored_tree_tip_aligned.py`** (kept, documented dead end):
   attempted true tip alignment by manually rewriting branch lengths -
   unit length per internal edge, then stretching only each leaf's own
   final edge by however much it's short of the deepest leaf's depth, so
   every root-to-tip path sums to the same constant. This **does**
   achieve real tip alignment (confirmed). But for a real tree with
   uneven leaf depths, leaves that start much closer to the root need
   their one final edge stretched dramatically - this produces a few
   huge solid color wedges dominating the figure, burying the real
   internal branching structure that the depth-based version showed
   cleanly. Visibly worse than both the depth-based ete3 version and
   ggtree's native tip-aligned cladogram.

## What this doesn't rule out

- ete3 rendering is noticeably *faster* than ggtree for the same tree
  (~1.2s vs ggtree's ~2.6s for PRRs' 1101 tips) - speed was never the
  problem here, legibility/correctness of the circular-cladogram
  geometry was.
- `12_ConvertTreesToFigures.py` already has real per-leaf taxonomy data
  (`taxonOfInterest`, from `InterestingTaxa.csv`) computed for every
  tree it builds - see `../ggtree/README.md`'s own "What ete3 already
  does" section. Adding per-leaf branch coloring to the *existing*
  rectangular full-detail layout (not circular) would sidestep this
  whole tip-alignment problem entirely, since a rectangular layout's
  leaves are naturally aligned on one axis regardless of depth - that
  remains a reasonable, still-unexplored path if the goal is just
  "color every leaf's own branch by ground truth," without needing
  circular mode at all.
