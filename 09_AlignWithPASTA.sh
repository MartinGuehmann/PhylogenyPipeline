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
	echo "You must give a file with InputSequences, for instance:" >&2
	echo "./$thisScript InputSequences AlignmentDirectory" >&2
	exit
fi

if [ -z "$alignmentDir" ]
then
	echo "You must give a file with InputSequences, for instance:" >&2
	echo "./$thisScript InputSequences AlignmentDirectory" >&2
	exit
fi

# Make input and output file names
numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
outFile="$alignmentDir/$base.alignment.PASTA.fasta"
cleanedinputSequences="$alignmentDir/$base.fasta"

# Make alignment directory if it does not exist
mkdir -p $alignmentDir

###########################################################
# Copy sequences and replace Js by Ls
# since PASTA cannot cope with that
cp $inputSequences $cleanedinputSequences
sed -i -e '/^#/!s/J/L/g' -e '/^#/!s/j/l/g' $cleanedinputSequences

###########################################################
# Align the sequences with PASTA
maxMB="16384"
run_pasta.py -i $cleanedinputSequences -d protein -o $alignmentDir --num-cpus=$numTreads --max-mem-mb=$maxMB

###########################################################
# Rename PASTA output file to $outFile
for pastaAlnFile in "$alignmentDir/"*".$base.aln"
do
	# We might have more than one, some even be empty, from previous incomplete runs
	# So just rename the first non-empty one
	if [ -s $pastaAlnFile ]
	then
		mv $pastaAlnFile $outFile
		break
	fi
done

echo "$outFile"
