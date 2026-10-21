#!/usr/bin/env python3

# Classifies every leaf of a real pipeline tree (Newick) into one of this
# pipeline's own standard taxon buckets (the same vocabulary/colors every
# repo's InterestingTaxa.csv already uses - see Mas1/InterestingTaxa.csv
# for the canonical list this was copied from), using each leaf's own
# NCBI taxonomy lineage - not tree topology, not a single reference
# sequence. This is the ground-truth classification step the ggtree
# prototype (../render_colored_tree.R) needs to color every branch by
# what a leaf actually is, rather than by which pre-defined clade's
# reference sequence happens to be nearest in the tree.
#
# Usage:
#   python3 classify_tips_by_taxon.py --tree path/to/real.treefile --out classification.tsv
#
# Prints a 2-column TSV (label, clade) to --out; leaves whose species
# name can't be resolved or whose lineage matches none of the buckets
# below are simply omitted (render_colored_tree.R treats missing leaves
# as unclassified/grey).

import argparse
from ete3 import NCBITaxa, Tree

# The standard taxon vocabulary + NCBI taxids, matching every repo's own
# InterestingTaxa.csv (colors copied from Mas1/InterestingTaxa.csv,
# 2026-10-21 - the most complete "Regular" row set found in this
# pipeline). First match in iteration order wins, so more specific taxa
# must be checked before broader ones that would also contain them
# (e.g. Amphibia before Tetrapoda would need to exist only if Tetrapoda
# itself were a bucket here - it isn't, so plain dict order is fine).
TAXON_BUCKETS = {
    "Cyclostomata":      (1476529, "Turquoise"),
    "Chondrichthyes":    (7777,    "HotPink"),
    "Actinopterygii":    (7898,    "LimeGreen"),
    "Coelacanthimorpha": (118072,  "Red"),
    "Dipnomorpha":       (7878,    "Peru"),
    "Amphibia":          (8292,    "Blue"),
    "Mammalia":          (40674,   "Orange"),
    "Lepidosauria":      (8504,    "YellowGreen"),
    "Testudinata":       (157842,  "Navy"),
    "Crocodylia":        (1294634, "Firebrick"),
    "Aves":              (8782,    "Cyan"),
    "Cephalochordata":   (7735,    "DarkGreen"),
    "Tunicata":          (7712,    "LightSeaGreen"),
    "Echinodermata":     (7586,    "Green"),
    "Hemichordata":      (10219,   "OliveDrab"),
    "Annelida":          (6340,    "Pink"),
    "Bryozoa":           (10205,   "DodgerBlue"),
    "Arthropoda":        (6656,    "DarkBlue"),
    "Brachiopoda":       (7568,    "DarkViolet"),
    "Rotifera":          (10190,   "CadetBlue"),
    "Tardigrada":        (42241,   "Tomato"),
    "Onychophora":       (27563,   "RosyBrown"),
    "Mollusca":          (6447,    "SteelBlue"),
    "Nematoda":          (6231,    "Brown"),
    "Platyhelminthes":   (6157,    "DarkGoldenrod"),
    "Cnidaria":          (6073,    "MediumOrchid"),
    "Ctenophora":        (10197,   "DarkOrange"),
    "Choanoflagellata":  (28009,   "Indigo"),
    "Porifera":          (6040,    "Gold"),
    "Placozoa":          (10226,   "DarkKhaki"),
    "Viridiplantae":     (33090,   "Green"),
    "Fungi":             (4751,    "DeepPink"),
    "Discoba":           (2611352, "Chocolate"),
    "Amoebozoa":         (554915,  "SlateBlue"),
    "Rhizaria":          (543769,  "Magenta"),
}


def build_resolver():
    ncbi = NCBITaxa()
    name_cache = {}
    lineage_cache = {}

    def resolve(species_name):
        if species_name not in name_cache:
            hits = ncbi.get_name_translator([species_name]).get(species_name)
            name_cache[species_name] = hits[0] if hits else None
        return name_cache[species_name]

    def lineage(taxid):
        if taxid not in lineage_cache:
            try:
                lineage_cache[taxid] = set(ncbi.get_lineage(taxid))
            except Exception:
                lineage_cache[taxid] = None
        return lineage_cache[taxid]

    return resolve, lineage


def classify_label(label, resolve, lineage):
    # Tip labels are this pipeline's own sanitized
    # "ACCESSION_description_Genus_species" form - try the last 2 then
    # 3 underscore-joined tokens as "Genus species"/"Genus species ssp".
    parts = label.split("_")
    for n in (2, 3):
        if len(parts) >= n:
            candidate = " ".join(parts[-n:])
            taxid = resolve(candidate)
            if taxid:
                lin = lineage(taxid)
                if lin is None:
                    return None
                for bucket, (bucket_taxid, _color) in TAXON_BUCKETS.items():
                    if bucket_taxid in lin:
                        return bucket
                return None
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", required=True, help="Newick tree file")
    parser.add_argument("--out", required=True, help="Output TSV path (label, clade)")
    args = parser.parse_args()

    tree = Tree(args.tree, format=1)
    leaves = tree.get_leaves()
    resolve, lineage = build_resolver()

    classified = 0
    with open(args.out, "w") as f:
        f.write("label\tclade\n")
        for leaf in leaves:
            clade = classify_label(leaf.name, resolve, lineage)
            if clade is not None:
                f.write(f"{leaf.name}\t{clade}\n")
                classified += 1

    print(f"{classified} of {len(leaves)} leaves classified -> {args.out}")


if __name__ == "__main__":
    main()
