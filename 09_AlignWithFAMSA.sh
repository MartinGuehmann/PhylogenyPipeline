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
outFile="$alignmentDir/$base.alignment.FAMSA.fasta"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit 0
fi

# Make alignment directory if it does not exist
mkdir -p $alignmentDir

# Align the sequences with FAMSA
"$DIR/../FAMSA/famsa" -fr -t $numTreads $inputSequences $outFile >&2 # Actually this does not put anything to stdout, but just to have it like the others

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
