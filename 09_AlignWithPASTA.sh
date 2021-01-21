#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
gene="$1"
inputSequences="$2"
alignmentDir="$3"

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

numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
outFile="$alignmentDir/$base.alignment.PASTA.fasta"

mkdir -p $alignmentDir

run_pasta.py -i $inputSequences -d protein -o $alignmentDir -k

# Missing code
# Rename PASTA output file to $outFile

raxml-ng --msa "$outFile" --threads $numTreads --model LG+G --check

