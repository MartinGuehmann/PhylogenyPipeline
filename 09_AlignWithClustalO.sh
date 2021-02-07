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
trimal="$3"                  # Whether the alignment should be trimmed

if [[ -z "$inputSequences" ]]
then
	echo "You must give a file with InputSequences, for instance:"
	echo "./$thisScript InputSequences AlignmentDirectory"
	exit
fi

if [ -z "$alignmentDir" ]
then
	echo "You must give a file with InputSequences, for instance:"
	echo "./$thisScript InputSequences AlignmentDirectory"
	exit
fi

# Make input and output file names
numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
outFile="$alignmentDir/$base.alignment.ClustalO.fasta"
outTree="$alignmentDir/$base.tree.ClustalO.newick"

# Make alignment directory if it does not exist
mkdir -p $alignmentDir

# Align the sequences with ClustalO
clustalo  --iterations 5 --threads "$numTreads" -i "$inputSequences" -o "$outFile" --guidetree-out="$outTree"

###########################################################
# Clean alignment of empty columns
raxml-ng --msa "$outFile" --threads $numTreads --model LG+G --check

reducedOutFile="$outFile.raxml.reduced.phy"

# Remove double underscores and brackets from extended sequence IDs
sed -i -e 's/__/_/g' -e 's/[][]//g' "$reducedOutFile"

if [ ! -z "$trimal" ]
then
	"$DIR/../trimal/source/trimal" -in "$reducedOutFile" -out "$reducedOutFile" -gt "$trimal"
fi
