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
outFile="$alignmentDir/$base.alignment.RegTCoffee.fasta"
outFileFixed="$alignmentDir/$base.alignment.RegTCoffee.fixed.fasta"
outTree="$alignmentDir/$base.tree.RegTCoffee.newick"

# Make alignment directory if it does not exist
mkdir -p $alignmentDir

# Align the sequences with regressive t-coffee
MAX_N_PID_4_TCOFFEE=520000 t_coffee -reg -seq $inputSequences -nseq 100 -tree mbed -method mafftlinsi_msa -outfile $outFile -outtree $outTree -thread 0  >&2 # In case this puts something to stdout

###########################################################
# Restore sequence names, so that we have some idea of what we are looking when we are looking at the tree
mapFile="$alignmentDir/$base.map.txt"

rm -f "$mapFile"
while read line
do
	if [[ ">" == "${line:0:1}" ]]
	then
		long="${line#?}"
		short="${long%% *}"
		echo "$short	$long" >> "$mapFile"
	fi

done < $inputSequences

seqkit replace -p '(.+)$' -k "$mapFile" -r '{kv}' -K "$outFile" > "$outFileFixed"
mv "$outFileFixed" "$outFile"

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
