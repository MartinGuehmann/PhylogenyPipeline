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
outFile="$alignmentDir/$base.alignment.MUSCLE5.fasta"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit 0
fi

# Make the alignment directory if it does not exist
mkdir -p $alignmentDir

# Announce this round is actively being worked on before the aligner
# runs, so IsRoundRunning.sh's live-log grep for "$aligner$suffix/
# RogueIter_" always finds something - see 09_AlignWithClustalO.sh's
# own comment on this line for the full story (confirmed this exact
# script was one of the two that genuinely wasn't being detected).
echo "Aligning into $alignmentDir.." >&2

# Drop extreme length outliers (e.g. a bacterial contamination/fusion
# artifact) before MUSCLE5 ever sees them. Confirmed 2026-11-04: a
# NuclearReceptors chunk containing one ran the full walltime budget
# (34h, nowhere near a timeout) and then hit MUSCLE5's own internal
# guard - "---Fatal error--- Memory object >4Gb, probably due to long
# seqences" - a second, separate failure mode from the plain walltime
# issue this chunk also has (see Resources.cfg's own walltime-bump
# comment for that one). Same contaminant already fixed for PASTA/
# MAGUS/LINSI; this aligner was missed in that retrofit since the
# chunk that exposed walltime sizing (a different chunk, no outlier)
# was investigated first. See FilterLengthOutliers.py for the method.
lengthFiltered="$alignmentDir/$base.LengthFiltered.fasta"
lengthOutliersDropped="$alignmentDir/$base.LengthOutliers.dropped.fasta"
python3 "$DIR/FilterLengthOutliers.py" --input "$inputSequences" --output "$lengthFiltered" --dropped "$lengthOutliersDropped"

# Align the sequences with Muscle5
muscle5 -threads $numTreads -align $lengthFiltered -output $outFile >&2 # In case this puts something to stdout

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
