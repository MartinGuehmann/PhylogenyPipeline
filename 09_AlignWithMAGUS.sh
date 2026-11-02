#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done

# Directory and the name of this script
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Input parameters
inputSequences="$1"          # The input sequences to be aligned
alignmentDir="$2"            # The output directories for the alignments

if [[ -z "$inputSequences" ]]
then
	echo "You must give a file with InputSequences, for instance:" >&2
	echo "./$thisScript InputSequences AlignmentDirectory" >&2
	exit 1
fi

if [ -z "$alignmentDir" ]
then
	echo "You must give a file with InputSequences, for instance:" >&2
	echo "./$thisScript InputSequences AlignmentDirectory" >&2
	exit 1
fi

# Make input and output file names
numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
outFile="$alignmentDir/$base.alignment.MAGUS.fasta"
workDir="$alignmentDir/$base.alignment.MAGUS"
cleanedInputSequences="$alignmentDir/$base.fasta"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit 0
fi

# Wipe any work directory left behind by a previous, non-TIMEOUT attempt
# (crash, OOM-kill, or - as confirmed 2026-11-02 - a resubmit after fixing
# the input) before making a fresh one. MAGUS caches its own decomposition
# (decomposition/subset_N.txt) under here and silently reuses it on a
# rerun instead of recomputing it from whatever input is given now -
# confirmed via a real incident: after filtering a length outlier out of
# the input, MAGUS still OOM-killed on the same subset, and the log showed
# "Decomposed ... in 0.06 sec" (vs. ~15.7 minutes for a genuine
# decomposition) with a wall of "Detected existing subset file" lines -
# i.e. it reused the stale subset still containing the outlier instead of
# ever seeing the filtered input. Same class of problem
# 09_AlignWithPASTA.sh already wipes its own output for, just not caught
# here until now.
rm -rf $workDir

# Make the alignment and work directories if they do not exist
mkdir -p $alignmentDir
mkdir -p $workDir

# Drop extreme length outliers (e.g. a bacterial contamination/fusion
# artifact) before MAGUS ever sees them - its internal MAFFT subalignment
# step scales badly with one. This is a retrofit for chunks that were
# already split before 04_MakeNonRedundant.sh started filtering the full
# pool upstream; see FilterLengthOutliers.py for the method.
lengthFiltered="$alignmentDir/$base.LengthFiltered.fasta"
lengthOutliersDropped="$alignmentDir/$base.LengthOutliers.dropped.fasta"
python3 "$DIR/FilterLengthOutliers.py" --input "$inputSequences" --output "$lengthFiltered" --dropped "$lengthOutliersDropped"

###########################################################
# Copy sequences and replace Js by Ls
# Since PASTA (MAGUS?) cannot cope with that
# Remove special characters from sequence IDs
# So that we do not have trouble with them later
# Let's see whether J-replacement is needed MAGUS
#sed -e '/^>/!s/J/L/g' \
#    -e '/^>/!s/j/l/g' \
# {}: confirmed 2026-10-19 on a real Renins header ("pepsinogen III
# {N-terminal}") - MAGUS's own internal Newick parser (dendropy) chokes
# on a literal '{' in a label ("Expecting ':', ')', ',' or ';' ... but
# found '{'"), aborting that chunk's alignment entirely. Only MAGUS has
# this problem (it's the only aligner that builds its own internal
# guide tree from these raw headers before this pipeline's own
# post-alignment sanitization in 09a_PostProcessAlignment.sh ever runs),
# so fixed narrowly here rather than earlier in the pipeline for every
# aligner.
# Confirmed 2026-11-02, reproduced directly against a local MAFFT build:
# MAFFT silently truncates FASTA headers over ~245 characters when it
# writes its own output (cut a 516-char header down to 245, mid-word).
# MAGUS keeps the untruncated header in its own bookkeeping but then
# looks a taxon up by that same string in the dict it builds from
# reading MAFFT's (truncated) output back in - a mismatch that throws
# KeyError in magus/align/alignment_context.py's
# initializeBackboneSequenceMapping() and aborts the whole chunk. Only
# a few sequences in a typical chunk are long enough to hit this (a
# verbose description with many alternate protein/gene names chained
# together, e.g. "Angiopoietin-related_protein_1Ficolin-1-A..."), but
# whether a given one actually triggers the crash depends on MAGUS's
# own guide-tree-driven decomposition (which taxa get sampled as
# "backbone"), not just the length - so trimming to a safe length here
# rather than leaving it to chance. 200 is comfortably under MAFFT's
# observed ~245-char truncation point (allowing for a harmless version-
# to-version difference in the exact limit) while every ordinary
# sequence ID in this pipeline is already well under 150 chars, so this
# never touches normal input. This only affects what MAGUS itself sees
# internally for this one chunk - the pipeline's real record of each
# sequence (SequencesOfInterest.fasta) keeps the full original header
# regardless, and losing the tail of an oversized description (usually
# the species name) here is an accepted tradeoff, not a data-loss risk.
sed -e 's/[],[{}]//g' \
    -e 's/[);(]//g' \
    -e "s/[']//g" \
    -e "s/[&]//g" \
    -e 's/ $//g' \
    -e 's/[=: /\]/_/g' \
    $lengthFiltered | \
sed -e 's/__/_/g' \
    -e 's/_$//g' | \
sed -e '/^>/ s/^\(.\{1,200\}\).*/\1/' > $cleanedInputSequences

###########################################################
# Align the sequences with MAGUS
magus -np $numTreads -d $workDir -i $cleanedInputSequences -o $outFile >&2

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
