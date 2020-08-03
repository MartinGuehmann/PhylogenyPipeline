#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
gene="$1"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./RunAll.sh GeneName"
	exit
fi

numTreads=$(nproc)
sequences="$DIR/$gene/Sequences"
nrSequenceFile="$sequences/NonRedundantSequences.fasta"
nrSequenceFile90="$sequences/NonRedundantSequences90.fasta"

# Remove $nrSequenceFile if it already exists created from a previous run,
# without complaining if it does not exist.
# So that we do not include it in the analysis.
rm -f $nrSequenceFile
rm -f $nrSequenceFile90

seqFiles=$sequences/*.fasta

seqkit rmdup -s -j $numTreads $seqFiles > $nrSequenceFile

cd-hit -i $nrSequenceFile -o $nrSequenceFile90 -c 0.9 -M 0 -d 0 -T $numTreads

# Record the statistics of all files, including the one we have just created.
# The expression in $seqFiles is re-evaluated.
seqkit stats $seqFiles > "$sequences/Stats.txt"
