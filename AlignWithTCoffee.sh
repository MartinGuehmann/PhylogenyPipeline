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
	echo "./AlignWithTCoffee.sh GeneName"
	exit
fi

skipClans="$2"
if [ -z "$skipClans" ]
then
	skipClans=0
fi

sequences="$DIR/$gene/SequencesOfInterest"
inputSequences="$sequences/SequencesOfInterest.fasta"

if [[ $skipClans != 0 ]]
then
	sequences="$DIR/$gene/Sequences"
	inputSequences="$sequences/NonRedundantSequences90.fasta"
fi

numTreads=$(nproc)
alignments="$DIR/$gene/Alignments"
outFile="$alignments/Alignment.fasta"
outTree="$alignments/Tree.mbed"

mkdir -p $alignments

#run_pasta.py -i $inputSequences -d protein -o $alignments -k --keepalignmenttemps
#t_coffee -i $inputSequences -d protein -o $alignments -thread 0
t_coffee -reg -seq $inputSequences -nseq 100 -tree mbed -method mafftginsi_msa -outfile $outFile -outtree $outTree -thread 0
