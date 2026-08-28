#!/usr/bin/env python3

# Takes the already-extracted bait clade (nw_clade's MRCA-of-bait subtree)
# from stdin and, for every outgroup/anchor leaf (see AnchorSequences/
# README.md) still present in it, carves out and removes the largest
# sub-clade around that outgroup leaf that contains no bait leaf.
#
# This replaced discarding the whole chunk on any outgroup leak (see
# PhylogenyPipeline commit 8006be6): found 2026-08-28 on PeptideReceptors
# that leakage looked all-or-nothing (57/131 chunks lost every one of 9
# anchors together) purely because that check treated the shared anchor set
# as one block. The bait/outgroup split should instead come only from
# BaitSequences and the outgroup markers themselves, not from whether they
# happen to land together in one tree - so each outgroup leaf now defines
# its own exclusion clade independently. Distinct outgroup leaves' exclusion
# clades need not share a common superclade; unrelated content elsewhere in
# the bait MRCA that isn't nested with any leaked outgroup leaf survives.
#
# Prints the surviving leaf labels, one per line, to stdout. With no
# outgroup leaves given (or none present in the tree), this is equivalent
# to `nw_labels -I -` on the input subtree.

import argparse
import sys

from ete3 import Tree


def exclusion_clade(leaf, baitNames):
    # Walk up from `leaf` while the parent clade still contains no bait
    # leaf; return the highest such node (or the leaf itself if even its
    # immediate parent already has a bait leaf in it).
    node = leaf
    parent = node.up
    while parent is not None and not (set(parent.get_leaf_names()) & baitNames):
        node = parent
        parent = node.up
    return node


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bait", nargs="+", required=True,
                         help="Bait leaf labels seeding the ingroup")
    parser.add_argument("--outgroup", nargs="*", default=[],
                         help="Outgroup/anchor leaf labels, each defining its own exclusion clade")
    args = parser.parse_args()

    newick = sys.stdin.read().strip()
    if not newick:
        return

    tree = Tree(newick, format=1)
    baitNames = set(args.bait)
    outgroupNames = set(args.outgroup)

    leaves = tree.get_leaves()
    allNames = set(leaf.name for leaf in leaves)

    leakedOutgroup = [leaf for leaf in leaves if leaf.name in outgroupNames]

    excludedNames = set()
    for outgroupLeaf in leakedOutgroup:
        excludedNames.update(exclusion_clade(outgroupLeaf, baitNames).get_leaf_names())

    for name in allNames - excludedNames:
        print(name)


if __name__ == "__main__":
    main()
