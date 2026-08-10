#!/usr/bin/env python3

# NonRedundantSequences90.fasta is gitignored for some gene repos once
# it gets too big (e.g. PeptideReceptors, matching the same pattern
# already used for Opsins) - confirmed 2026-08-10. It's still fully
# reconstructable, but *not* by just rerunning 04_MakeNonRedundant.sh's
# steps from scratch: that script's own comment already documents that
# cd-hit's clustering isn't reproducible run-to-run, so a fresh cd-hit
# pass could pick different cluster memberships/representatives than
# what's actually in the .clstr file that WAS committed.
#
# Instead this reconstructs from what's already fixed and committed:
# - The .clstr file (cd-hit's own cluster membership + its original
#   representative choice per cluster, the "*"-marked member).
# - The job's own log, for the "Replacing representative X with Y"
#   lines PickSequenceRepresentatives.py prints when it swaps cd-hit's
#   choice for a species-priority one - it rewrites the FASTA output
#   but does NOT write the swap back into the .clstr file, so the log
#   is the only remaining record of which swaps actually happened.
# - The raw pre-dedup FASTA files (Sequences/*.fasta as originally
#   globbed), split the same way PrepareSequencesForDedup.py does,
#   since a cluster's representative can be an accession that only
#   exists as its own record after that split (NCBI's merged-header
#   records - see that script's own header comment).
#
# Does not replicate 04_MakeNonRedundant.sh's final `seqkit rmdup -s |
# seqkit rename` pass over the assembled output - a no-op in every
# case checked so far (MustKeepSequences empty, and two different
# clusters ending up with byte-identical representative sequences
# after swapping would be a genuine coincidence, not something this
# script tries to detect).

import argparse
import re
import sys

from PrepareSequencesForDedup import parse_fasta_records

CLUSTER_MEMBER_RE = re.compile(r">(.+)\.\.\. (\*|at )")
SWAP_LINE_RE = re.compile(r"Replacing representative (\S+) with (\S+)")


def parse_clstr(path):
    # Returns a list of (member_ids_in_file_order, representative_index),
    # same as PickSequenceRepresentatives.py's own parse_clstr.
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


def parse_swaps(path):
    swaps = {}
    with open(path) as f:
        for line in f:
            m = SWAP_LINE_RE.search(line)
            if m:
                swaps[m.group(1)] = m.group(2)
    return swaps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="+", help="Raw pre-dedup FASTA file(s), e.g. Sequences/*.fasta")
    parser.add_argument("--clstr", required=True, help="cd-hit's own .clstr file")
    parser.add_argument("--log", required=True,
                         help="04_MakeNonRedundant.sh's own job log (.err), for the "
                              "'Replacing representative X with Y' lines")
    parser.add_argument("-o", "--out-file", default="-", help="Output FASTA path (default: stdout)")
    args = parser.parse_args()

    records, _ = parse_fasta_records(args.input)
    # First occurrence wins, matching seqkit rmdup -s's own documented
    # behavior ("only the first record is saved for duplicates") - the
    # same accession can genuinely appear more than once in the raw
    # NCBI dump with slightly different description text (confirmed
    # 2026-08-10 on real PRRs data), and whichever occurrence came
    # first is exactly what ends up in the real pipeline's output.
    sequences = {}
    for seq_id, desc, seq in records:
        if seq_id not in sequences:
            sequences[seq_id] = (desc, seq)

    clusters = parse_clstr(args.clstr)
    swaps = parse_swaps(args.log)

    out = sys.stdout if args.out_file == "-" else open(args.out_file, "w")

    written = 0
    missing = []
    swapped_used = 0
    for members, rep_index in clusters:
        if rep_index is None:
            continue
        original_rep = members[rep_index]
        final_rep = swaps.get(original_rep, original_rep)
        if final_rep != original_rep:
            swapped_used += 1

        if final_rep not in sequences:
            missing.append(final_rep)
            continue

        desc, seq = sequences[final_rep]
        header_line = f">{final_rep}"
        if desc:
            header_line += f" {desc}"
        out.write(header_line + "\n")
        out.write(seq)
        written += 1

    if args.out_file != "-":
        out.close()

    print(f"Wrote {written} record(s) ({swapped_used} via a swap from the log).", file=sys.stderr)
    if missing:
        print(f"WARNING: {len(missing)} representative(s) not found in the given input file(s): "
              f"{', '.join(missing[:10])}{' ...' if len(missing) > 10 else ''}", file=sys.stderr)


if __name__ == "__main__":
    main()
