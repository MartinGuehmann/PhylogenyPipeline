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
gene="$1"                    # The gene name, the base directory for this analysis
inputSequences="$2"          # The input sequences to be aligned
alignmentDir="$3"            # The output directories for the alignments

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName InputSequences AlignmentDirectory"
	exit
fi

if [[ -z "$inputSequences" ]]
then
	echo "You must give a file with InputSequences, for instance:"
	echo "./$thisScript GeneName InputSequences AlignmentDirectory"
	exit
fi

if [ -z "$alignmentDir" ]
then
	echo "You must give a file with InputSequences, for instance:"
	echo "./$thisScript GeneName InputSequences AlignmentDirectory"
	exit
fi

# Make input and output file names
numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
outFile="$alignmentDir/$base.alignment.MAFFT.fasta"

# Make alignment directory if it does not exist
mkdir -p $alignmentDir

# Align the sequences with regressive MAFFT
mafft --thread $numTreads $inputSequences > $outFile

###########################################################
# Clean alignment of empty columns
raxml-ng --msa "$outFile" --threads $numTreads --model LG+G --check

# Remove double underscores and brackets from extended sequence IDs
sed -i -e 's/__/_/g' -e 's/[][]//g' "$outFile.raxml.reduced.phy"
