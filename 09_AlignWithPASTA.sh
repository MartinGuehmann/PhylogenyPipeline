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
outFile="$alignmentDir/$base.alignment.PASTA.fasta"
cleanedinputSequences="$alignmentDir/$base.fasta"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit 0
elif [ -f $outFile ]
then
	# Something went wrong while aligning
	# but PASTA does not overwrite the old files if they exists
	# so delete them manually
	rm $alignmentDir/${base}*
fi

# Make alignment directory if it does not exist
mkdir -p $alignmentDir

###########################################################
# Copy sequences and replace Js by Ls
# Since PASTA cannot cope with that
# Remove special characters from sequence IDs
# So that we do not have trouble with them later
sed -e '/^>/!s/J/L/g' \
    -e '/^>/!s/j/l/g' \
    -e 's/[],[]//g' \
    -e 's/[);(]//g' \
    -e "s/[']//g" \
    -e 's/ $//g' \
    -e 's/[: /]/_/g' \
    $inputSequences > $cleanedinputSequences

###########################################################
# Align the sequences with PASTA
# PASTA outputs stuff to stdout, even so it should go to stderr
# This just cloaks the return stuff of this script
maxMB="16384"
run_pasta.py -i $cleanedinputSequences -d protein -o $alignmentDir --num-cpus=$numTreads --max-mem-mb=$maxMB --alignment-suffix="alignment.PASTA.fasta" -j $base >&2

# Remove temporary output files
rm $alignmentDir/${base}_temp_*

sed -i -e 's/^;$//g' "$alignmentDir/${base}.tre"

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
