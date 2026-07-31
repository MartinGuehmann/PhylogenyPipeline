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
outFile="$alignmentDir/$base.alignment.ClustalO.fasta"
outTree="$alignmentDir/$base.tree.ClustalO.newick"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit
fi

# Make the alignment directory if it does not exist
mkdir -p $alignmentDir

# Align the sequences with ClustalO
#
# --force: the only thing guarding against a rerun here is $outFile
# being non-empty (above) - a previous attempt that got killed after
# clustalo wrote $outTree but before $outFile was complete leaves the
# tree file behind, and clustalo refuses to overwrite it by default
# ("Cowardly refusing to overwrite already existing file"), aborting
# every subsequent retry outright even though this script's own resume
# logic says a redo is exactly what should happen. Confirmed 2026-07-31
# on Mas1's part_026, the one part out of 26 whose earlier attempt
# hadn't fully failed yet when jobs briefly got resource-starved.
clustalo --force --iterations 5 --threads "$numTreads" -i "$inputSequences" -o "$outFile" --guidetree-out="$outTree" >&2 # In case this puts something to stdout

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
