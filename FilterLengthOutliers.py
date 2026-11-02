#!/usr/bin/env python3

# Drops sequences whose length is an extreme outlier relative to the rest
# of the given FASTA file - e.g. a bacterial contamination/gene-fusion
# artifact that's far longer than anything else in the pool - before it
# can crash an aligner's internal MAFFT-style iterative refinement (OOM)
# on whichever chunk it happens to land in after shuffling/splitting.
# Stdlib only, on purpose - no dependency on whatever Python environment
# happens to have Biopython/pandas/etc. available.
#
# Protein lengths are closer to log-normal than normal (long real tail,
# e.g. real isoforms/fusions), so plain length or a mean+stdev z-score
# either lets a genuine outlier through or also flags real long
# sequences. Using a modified z-score (Iglewicz & Hoaglin) on log-length,
# with median/MAD instead of mean/stdev so a handful of real long
# sequences can't drag the threshold around, cleanly separated a real
# 13393aa bacterial contaminant (modified z ~7.9) from NuclearReceptors'
# own legitimate long tail (up to 5147aa, modified z ~5.5) on real data -
# see project memory/git history around 2026-11-02 for that investigation.
# Only the long tail is checked - unusually short sequences are a
# separate, not-yet-investigated question.

import argparse
import math
import statistics
import sys


def parse_fasta(path):
    # Returns list of (seq_id, header_rest, sequence_lines_joined), in
    # file order.
    records = []
    seq_id = None
    header_rest = None
    seq_lines = []

    def flush():
        if seq_id is not None:
            records.append((seq_id, header_rest, "".join(seq_lines)))

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


def write_fasta(path, records):
    with open(path, "w") as out:
        for seq_id, header_rest, seq in records:
            header_line = f">{seq_id}"
            if header_rest:
                header_line += f" {header_rest}"
            out.write(header_line + "\n")
            out.write(seq)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="input FASTA")
    parser.add_argument("--output", required=True,
                         help="FASTA with length outliers removed")
    parser.add_argument("--dropped", required=True,
                         help="FASTA of the dropped outlier(s), for audit")
    parser.add_argument("--threshold", type=float, default=6.0,
                         help="modified z-score (log-length) above which a "
                              "sequence is dropped (default: 6.0)")
    args = parser.parse_args()

    records = parse_fasta(args.input)
    lengths = [len(seq.replace("\n", "")) for _, _, seq in records]

    if len(records) < 3:
        print(f"Only {len(records)} sequence(s) in {args.input} - too few "
              f"to compute a robust length distribution, not filtering.",
              file=sys.stderr)
        write_fasta(args.output, records)
        write_fasta(args.dropped, [])
        return

    log_lengths = [math.log(length) for length in lengths]
    median = statistics.median(log_lengths)
    mad = statistics.median([abs(x - median) for x in log_lengths])

    if mad == 0:
        print(f"Zero length variation (MAD=0) in {args.input} - not "
              f"filtering.", file=sys.stderr)
        write_fasta(args.output, records)
        write_fasta(args.dropped, [])
        return

    kept = []
    dropped = []
    for (seq_id, header_rest, seq), length, log_length in zip(records, lengths, log_lengths):
        modified_z = 0.6745 * (log_length - median) / mad
        if modified_z > args.threshold:
            dropped.append((seq_id, header_rest, seq))
            print(f"Dropping {seq_id} as a length outlier: {length}aa, "
                  f"modified z-score {modified_z:.2f} (threshold "
                  f"{args.threshold})", file=sys.stderr)
        else:
            kept.append((seq_id, header_rest, seq))

    write_fasta(args.output, kept)
    write_fasta(args.dropped, dropped)

    if dropped:
        print(f"Dropped {len(dropped)} length outlier(s) out of "
              f"{len(records)} sequence(s).", file=sys.stderr)
    else:
        print("No length outliers found.", file=sys.stderr)


if __name__ == "__main__":
    main()
