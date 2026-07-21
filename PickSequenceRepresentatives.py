#!/usr/bin/env python3

# Swaps cd-hit's chosen cluster representative for a higher-priority one by
# species, wherever a cluster contains a member matching an entry in a
# priority-ordered species list. Falls back to cd-hit's own choice for any
# cluster where no member matches any listed species. Stdlib only, on
# purpose - no dependency on whatever Python environment happens to have
# Biopython/pandas/etc. available.

import argparse
import re
import sys


def parse_fasta(path):
    # Returns dict: id -> (header_rest, sequence_lines_joined)
    records = {}
    seq_id = None
    header_rest = None
    seq_lines = []

    def flush():
        if seq_id is not None:
            records[seq_id] = (header_rest, "".join(seq_lines))

    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith(">"):
                flush()
                header = line[1:]
                parts = header.split(None, 1)
                seq_id = parts[0]
                header_rest = parts[1] if len(parts) > 1 else ""
                seq_lines = []
            else:
                seq_lines.append(line + "\n")
        flush()
    return records


# cd-hit always renders a cluster member line as ">ID... *" (representative)
# or ">ID... at XX.XX%" (everyone else), regardless of whether ID was
# actually long enough to need truncating.
CLUSTER_MEMBER_RE = re.compile(r">(.+)\.\.\. (\*|at )")


def parse_clstr(path):
    # Returns a list of (member_ids_in_file_order, representative_index)
    clusters = []
    members = []
    rep_index = None

    def flush():
        if members:
            clusters.append((members, rep_index))

    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith(">Cluster"):
                flush()
                members = []
                rep_index = None
            else:
                m = CLUSTER_MEMBER_RE.search(line)
                if not m:
                    continue
                if m.group(2) == "*":
                    rep_index = len(members)
                members.append(m.group(1))
        flush()
    return clusters


def load_species_priority(path):
    # Tab-separated, species scientific name in column 2, row order is
    # priority order (earlier rows win).
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
                         help="cd-hit's own input FASTA (full original headers)")
    parser.add_argument("--cdhit-output", required=True,
                         help="cd-hit's -o output FASTA, rewritten in place")
    parser.add_argument("--clstr", required=True, help="cd-hit's .clstr file")
    parser.add_argument("--species-list", required=True,
                         help="tab-separated priority list, species name in column 2")
    args = parser.parse_args()

    input_records = parse_fasta(args.input)
    clusters = parse_clstr(args.clstr)
    species_priority = load_species_priority(args.species_list)

    swaps = {}  # current representative id -> replacement id

    for members, rep_index in clusters:
        if len(members) < 2 or rep_index is None:
            continue
        current_rep = members[rep_index]

        chosen = None
        chosen_species = None
        for species in species_priority:
            for member_id in members:
                header_rest = input_records.get(member_id, ("", ""))[0]
                if species in header_rest:
                    chosen = member_id
                    chosen_species = species
                    break
            if chosen is not None:
                break

        if chosen is not None and chosen != current_rep:
            swaps[current_rep] = chosen
            print(f"Replacing representative {current_rep} with {chosen} "
                  f"(matched '{chosen_species}')", file=sys.stderr)

    if not swaps:
        print("No representative swaps needed.", file=sys.stderr)
        return

    output_ids = []
    with open(args.cdhit_output) as f:
        for line in f:
            if line.startswith(">"):
                output_ids.append(line[1:].split(None, 1)[0])

    with open(args.cdhit_output, "w") as out:
        for output_id in output_ids:
            final_id = swaps.get(output_id, output_id)
            header_rest, seq = input_records[final_id]
            header_line = f">{final_id}"
            if header_rest:
                header_line += f" {header_rest}"
            out.write(header_line + "\n")
            out.write(seq)

    print(f"Swapped {len(swaps)} cluster representative(s).", file=sys.stderr)


if __name__ == "__main__":
    main()
