#!/usr/bin/env python3

# Renders a real pipeline tree as a circular, depth-based ete3 tree with
# every branch (leaf AND internal, where monophyletic) colored by real
# per-leaf NCBI taxonomy - the ete3 counterpart to
# ../ggtree/render_colored_tree.R, built to compare the two. See this
# directory's README.md for the full writeup and verdict (ggtree wins).
#
# Usage:
#   python3 render_colored_tree_depth.py <tree.newick> <classification.tsv> <out.pdf>
#
# <classification.tsv> is ../ggtree/classify_tips_by_taxon.py's own
# output (columns: label, clade) - reused as-is, same classification
# logic and taxon vocabulary for a fair comparison.
#
# "Depth" because every edge is unit-length regardless of real branch
# length (ts.force_topology=True), so each leaf's distance from the
# root reflects its own topological depth (number of ancestor edges),
# NOT real evolutionary distance and NOT tip-alignment - this is
# ete3's closest built-in equivalent to a cladogram, but it is a
# genuinely different thing from ggtree's branch.length="none", which
# *does* align every tip at a common radius. See render_colored_tree_tip_aligned.py
# for the (rejected) attempt to get true tip alignment out of ete3 too.

import sys
import time
from ete3 import Tree, TreeStyle, NodeStyle

tree_file, class_file, out_file = sys.argv[1], sys.argv[2], sys.argv[3]

t0 = time.time()
tree = Tree(tree_file, format=1)
print(f"Loaded tree with {len(tree.get_leaves())} tips in {time.time()-t0:.1f}s")

# Same taxon -> color map as ../ggtree/render_colored_tree.R - kept in
# sync by hand (see that file's own comment for why).
COLOR_MAP = {
    "Cyclostomata": "turquoise", "Chondrichthyes": "hotpink", "Actinopterygii": "limegreen",
    "Coelacanthimorpha": "red", "Dipnomorpha": "peru", "Amphibia": "blue",
    "Mammalia": "orange", "Lepidosauria": "yellowgreen", "Testudinata": "navy",
    "Crocodylia": "firebrick", "Aves": "cyan", "Cephalochordata": "darkgreen",
    "Tunicata": "lightseagreen", "Echinodermata": "green", "Hemichordata": "olivedrab",
    "Annelida": "pink", "Bryozoa": "dodgerblue", "Arthropoda": "darkblue",
    "Brachiopoda": "darkviolet", "Rotifera": "cadetblue", "Tardigrada": "tomato",
    "Onychophora": "rosybrown", "Mollusca": "steelblue", "Nematoda": "brown",
    "Platyhelminthes": "darkgoldenrod", "Cnidaria": "mediumorchid", "Ctenophora": "darkorange",
    "Choanoflagellata": "indigo", "Porifera": "gold", "Placozoa": "darkkhaki",
    "Viridiplantae": "green", "Fungi": "deeppink", "Discoba": "chocolate",
    "Amoebozoa": "slateblue", "Rhizaria": "magenta",
}
DEFAULT_COLOR = "grey"

classification = {}
with open(class_file) as f:
    next(f)
    for line in f:
        label, clade = line.rstrip("\n").split("\t")
        classification[label] = clade

# Bottom-up, single pass with memoization: a node's "uniform clade" is its
# own clade if it's a classified leaf, or its children's shared clade if
# every child already agrees (same idea as ggtree's groupOTU - a mixed-
# ancestor node gets no color, same as that falls back to its own
# grey/na.value there). Each node's clade is computed once (postorder
# guarantees children are visited, and cached, before their parent) -
# not recomputed per ancestor, which would be O(n^2) and too slow for
# this pipeline's real tree sizes (tried first, confirmed too slow).
t0 = time.time()
nodeClade = {}
classified_count = 0
styled_count = 0
for node in tree.traverse("postorder"):
    if node.is_leaf():
        clade = classification.get(node.name)
    else:
        childClades = set(nodeClade[child] for child in node.children)
        clade = next(iter(childClades)) if len(childClades) == 1 else None
    nodeClade[node] = clade
    color = COLOR_MAP.get(clade, DEFAULT_COLOR)
    if clade:
        classified_count += (1 if node.is_leaf() else 0)
    nstyle = NodeStyle()
    nstyle["fgcolor"] = color
    nstyle["hz_line_color"] = color
    nstyle["vt_line_color"] = color
    # size=0 on EVERY node (not just leaves) matters for two reasons,
    # not just cosmetics - confirmed 2026-10-22: leaving ete3's default
    # node markers on produced a PDF with ~1 "Syntax Error: No current
    # point in closepath" per leaf (per poppler/pdftoppm) - a genuinely
    # invalid PDF, not just visual clutter. Okular still opened it, but
    # a stricter reader might not.
    nstyle["size"] = 0
    nstyle["hz_line_width"] = 1
    nstyle["vt_line_width"] = 1
    node.set_style(nstyle)
    styled_count += 1
print(f"Styled {styled_count} nodes ({classified_count} classified leaves) in {time.time()-t0:.1f}s")


def layout(node):
    pass  # no per-leaf text labels - illegible at these sizes regardless of tool


ts = TreeStyle()
ts.mode = "c"
ts.show_leaf_name = False
ts.show_scale = False
ts.force_topology = True
ts.layout_fn = layout

t0 = time.time()
tree.render(out_file, tree_style=ts, dpi=150, w=4000)
print(f"render() done in {time.time()-t0:.1f}s")
print(f"Wrote {out_file}")
