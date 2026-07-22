#!/usr/bin/env python3

# Finds every sequence in a FASTA file whose header matches a species in a
# priority list, and prints their IDs, one per line. Used to build an
# exclude/exceptions file so RogueNaRok/TreeShrink never consider these
# taxa for pruning, regardless of how unstable they look in the tree - the
# same species list already used in step 4 (PickSequenceRepresentatives.py)
# to prefer a well-annotated representative during clustering. Stdlib
# only, same reason as PickSequenceRepresentatives.py: no dependency on
# whatever Python happens to have Biopython/pandas/etc. available.

import argparse


def parse_fasta_headers(path):
    # Returns list of (id, header_rest)
    headers = []
    with open(path) as f:
        for line in f:
            if line.startswith(">"):
                header = line[1:].rstrip("\n")
                parts = header.split(None, 1)
                seq_id = parts[0]
                header_rest = parts[1] if len(parts) > 1 else ""
                headers.append((seq_id, header_rest))
    return headers


def load_species_list(path):
    # Tab-separated, species scientific name in column 2. Order does not
    # matter here (unlike PickSequenceRepresentatives.py's priority order),
    # since every match is protected regardless of which species it is.
    species = []
    with open(path) as f:
        for line in f:
            fields = [field for field in line.rstrip("\n").split("\t") if field != ""]
            if len(fields) >= 2:
                species.append(fields[1].strip())
    return species


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                         help="FASTA file with full original headers")
    parser.add_argument("--species-list", required=True,
                         help="tab-separated species list, species name in column 2")
    args = parser.parse_args()

    headers = parse_fasta_headers(args.input)
    species_list = load_species_list(args.species_list)

    for seq_id, header_rest in headers:
        for species in species_list:
            if species in header_rest:
                print(seq_id)
                break


if __name__ == "__main__":
    main()
