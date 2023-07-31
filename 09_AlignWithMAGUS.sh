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

# Make the alignment and work directories if they do not exist
mkdir -p $alignmentDir
mkdir -p $workDir

###########################################################
# Copy sequences and replace Js by Ls
# Since PASTA (MAGUS?) cannot cope with that
# Remove special characters from sequence IDs
# So that we do not have trouble with them later
# Let's see whether J-replacement is needed MAGUS
#sed -e '/^>/!s/J/L/g' \
#    -e '/^>/!s/j/l/g' \
sed -e 's/[],[]//g' \
    -e 's/[);(]//g' \
    -e "s/[']//g" \
    -e "s/[&]//g" \
    -e 's/ $//g' \
    -e 's/[=: /\]/_/g' \
    $inputSequences | \
sed -e 's/__/_/g' \
    -e 's/_$//g' > $cleanedInputSequences

###########################################################
# Align the sequences with MAGUS
python3 "$DIR/../MAGUS/magus.py" -np $numTreads -d $workDir -i $cleanedInputSequences -o $outFile >&2

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
