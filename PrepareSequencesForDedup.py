#!/usr/bin/env python3

# NCBI's own efetch output represents groups of accessions that share a
# byte-identical protein sequence as a single FASTA record: one header
# line with multiple ">accession description [organism]" segments
# concatenated (no newline between them), followed by just one copy of
# the sequence. Every standard FASTA parser (seqkit, BioPython, cd-hit,
# ...) only treats a line *starting* with ">" as a record boundary, so
# every accession after the first one in such a line is invisible to
# every downstream tool - not deduplicated on purpose, just silently
# absorbed as text into the first accession's description. Confirmed
# 2026-08-10: 631 such merged lines in a single PRRs part file alone.
#
# This splits every merged record back into one real FASTA record per
# accession (each getting its own copy of the shared sequence), then
# reorders the whole set so that seqkit rmdup -s's own "only the first
# record is saved for duplicates" rule (it has no other way to control
# which duplicate survives - checked its own --help) actually picks a
# species-list priority match when one exists among a group of
# identical sequences, same priority list/file already used to override
# cd-hit's own representative choice (see PickSequenceRepresentatives.py).
# Meant to run right before seqkit rmdup -s in 04_MakeNonRedundant.sh -
# without this, rmdup never even sees the split-out accessions, let
# alone has any way to prefer one of them.

import argparse
import re
import sys


SEGMENT_SPLIT_RE = re.compile(r'\s+>(?=\S)')


def parse_fasta_records(paths):
    # Returns (records, merged_line_count): records is a list of
    # (id, description, sequence_lines_joined) in file order, already
    # split wherever a header line held more than one accession.
    # merged_line_count is how many original header lines actually
    # split into more than one record (not just the total record count).
    records = []
    merged_line_count = 0

    def flush(header_rest, seq_lines):
        nonlocal merged_line_count
        if header_rest is None:
            return
        segments = SEGMENT_SPLIT_RE.split(header_rest)
        if len(segments) > 1:
            merged_line_count += 1
        for segment in segments:
            parts = segment.split(None, 1)
            seq_id = parts[0]
            desc = parts[1] if len(parts) > 1 else ""
            records.append((seq_id, desc, "".join(seq_lines)))

    for path in paths:
        header_rest = None
        seq_lines = []
        with open(path) as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith(">"):
                    flush(header_rest, seq_lines)
                    header_rest = line[1:]
                    seq_lines = []
                elif header_rest is not None:
                    seq_lines.append(line + "\n")
            flush(header_rest, seq_lines)

    return records, merged_line_count


def load_species_priority(path):
    # Same format/convention as PickSequenceRepresentatives.py: tab-
    # separated, species scientific name in column 2, row order is
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
    parser.add_argument("input", nargs="+", help="Input FASTA file(s), e.g. Sequences/*.fasta")
    parser.add_argument("--species-list",
                         help="Optional tab-separated priority list (species name in column 2) - "
                              "if given, records matching an earlier-listed species are moved ahead "
                              "of everything else so seqkit rmdup -s's first-wins rule prefers them")
    parser.add_argument("-o", "--out-file", default="-", help="Output FASTA path (default: stdout)")
    args = parser.parse_args()

    records, merged_line_count = parse_fasta_records(args.input)
    print(f"Split {merged_line_count} merged header line(s) into their own records "
          f"({len(records)} record(s) total).", file=sys.stderr)

    if args.species_list:
        species_priority = load_species_priority(args.species_list)

        def tier(desc):
            for i, species in enumerate(species_priority):
                if species in desc:
                    return i
            return len(species_priority)

        # Stable sort - only species priority moves anything, original
        # relative order is otherwise preserved (including within a
        # duplicate group where no member matches any priority species).
        tiers = [tier(desc) for _, desc, _ in records]
        records = [r for _, r in sorted(zip(tiers, records), key=lambda pair: pair[0])]
        movedCount = sum(1 for t in tiers if t < len(species_priority))
        print(f"Reordered {movedCount} record(s) matching a priority species ahead of the rest.", file=sys.stderr)

    out = sys.stdout if args.out_file == "-" else open(args.out_file, "w")
    for seq_id, desc, seq in records:
        header_line = f">{seq_id}"
        if desc:
            header_line += f" {desc}"
        out.write(header_line + "\n")
        out.write(seq)
    if args.out_file != "-":
        out.close()

    print(f"Wrote {len(records)} record(s).", file=sys.stderr)


if __name__ == "__main__":
    main()
