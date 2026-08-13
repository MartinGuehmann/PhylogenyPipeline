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
	#
	# Confirmed 2026-08-13: "does not overwrite" means run_pasta.py
	# silently renames its own job internally (e.g. "part_005" ->
	# "part_0051") whenever it finds any pre-existing file under the
	# current job name - including leftover _temp_iteration_* files
	# from a run that was killed mid-way (e.g. hit its walltime)
	# rather than genuinely failing. It does not inspect or resume
	# from them. Tried leaving those checkpoint files in place for
	# exactly that reason (real, hours of PASTA progress otherwise
	# discarded for nothing) - confirmed on a real PeptideReceptors
	# chunk that PASTA just renames around them instead, which then
	# breaks this script's own $outFile (it stays pointed at the old
	# name while PASTA writes results under the new one). So the
	# blanket wipe here is required, not just defensive.
	rm $alignmentDir/${base}*
fi

# Make the alignment directory if it does not exist
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
    -e "s/[&]//g" \
    -e 's/ $//g' \
    -e 's/[=: /]/_/g' \
    $inputSequences | \
sed -e 's/__/_/g' \
    -e 's/_$//g' > $cleanedInputSequences

###########################################################
# Align the sequences with PASTA
# PASTA outputs stuff to stdout, even so it should go to stderr
# This just clogs the return stuff of this script
maxMB="16384"
run_pasta.py -i $cleanedInputSequences -d protein -o $alignmentDir --num-cpus=$numTreads --max-mem-mb=$maxMB --alignment-suffix="alignment.PASTA.fasta" -j $base >&2

# Remove temporary output files
rm $alignmentDir/${base}_temp_*

sed -i -e 's/^;$//g' "$alignmentDir/${base}.tre"

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
