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
outFile="$alignmentDir/$base.alignment.VCMSA.fasta"
cleanedInputSequences="$alignmentDir/$base.fasta"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit 0
elif [ -f $outFile ]
then
	# Something went wrong while aligning
	# but PASTA does not overwrite the old files if they exist
	# so delete them manually
	rm $alignmentDir/${base}*
fi

# Make the alignment directory if it does not exist
mkdir -p $alignmentDir

###########################################################
# Remove special characters from sequence IDs
# So that we do not have trouble with them later
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
# Align the sequences with VCMSA
model="$DIR/../Models/prot_t5_xl_uniref50"
# -l/--layers defaults to the last 16 hidden layers, concatenated per
# residue (1024*16 dims) and padded out to the longest sequence in the
# whole input file before being kept for every sequence at once -
# confirmed 2026-08-07 this alone needs ~137GiB for a 930-sequence
# chunk with a 2414-residue outlier (930 * 2414 * 1024*16 * 4 bytes),
# which OOM-killed real runs at both 30GB and 62GB. Limit to the last 2
# layers instead - cuts this dominant cost by ~8x.
vcmsa --exclude -l -2 -1 -i $cleanedInputSequences -o $outFile -m $model >&2 # Redirect anything to the error stream

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
