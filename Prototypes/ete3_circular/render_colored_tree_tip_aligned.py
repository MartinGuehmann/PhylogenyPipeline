#!/usr/bin/env python3

# Variant of render_colored_tree_depth.py that forces true tip alignment
# (every leaf at the same radius, matching ggtree's branch.length="none"
# cladogram) by manually stretching each leaf's own final branch - ete3
# has no built-in equivalent of ggtree's cladogram mode, so this is the
# standard workaround. Mechanically it works (confirmed 2026-10-22: every
# tip genuinely lands at the same radius). The verdict was still to
# prefer ggtree, though: for a real tree with uneven leaf depths (normal,
# not a special case), leaves that start much closer to the root need
# their single final edge stretched dramatically to reach the common
# boundary - this produces a few huge solid color wedges that dominate
# the figure and bury the real internal topology, rather than a clean
# branching structure. The unaligned depth-based version
# (render_colored_tree_depth.py) reads better despite not being a strict
# cladogram. Kept here as a documented dead end, not deleted - the
# technique itself may still be useful for a tree with more even leaf
# depths.
#
# Usage:
#   python3 render_colored_tree_tip_aligned.py <tree.newick> <classification.tsv> <out.pdf>

import sys
import time
from ete3 import Tree, TreeStyle, NodeStyle

tree_file, class_file, out_file = sys.argv[1], sys.argv[2], sys.argv[3]

t0 = time.time()
tree = Tree(tree_file, format=1)
print(f"Loaded tree with {len(tree.get_leaves())} tips in {time.time()-t0:.1f}s")

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

# True tip alignment: every edge gets unit length (1) except each leaf's
# own final edge, which gets stretched by however much it's short of the
# deepest leaf's topological depth - every root-to-tip path then sums to
# the same constant (maxDepth), while internal nodes still sit at their
# own true topological depth (unit length per edge, same as the "depth"
# variant) - only the final leaf-owning edges get individually stretched.
depth = {tree: 0}
for node in tree.traverse("preorder"):
    for child in node.children:
        depth[child] = depth[node] + 1
maxDepth = max(depth[leaf] for leaf in tree.get_leaves())

for node in tree.traverse("postorder"):
    if node.up is None:
        continue
    node.dist = (1 + (maxDepth - depth[node])) if node.is_leaf() else 1

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
    nstyle["size"] = 0
    nstyle["hz_line_width"] = 1
    nstyle["vt_line_width"] = 1
    node.set_style(nstyle)
    styled_count += 1
print(f"Styled {styled_count} nodes ({classified_count} classified leaves) in {time.time()-t0:.1f}s")


def layout(node):
    pass


ts = TreeStyle()
ts.mode = "c"
ts.show_leaf_name = False
ts.show_scale = False
ts.force_topology = False  # use the hand-crafted dist values above, not a fixed unit length
ts.layout_fn = layout

t0 = time.time()
tree.render(out_file, tree_style=ts, dpi=150, w=4000)
print(f"render() done in {time.time()-t0:.1f}s")
print(f"Wrote {out_file}")
