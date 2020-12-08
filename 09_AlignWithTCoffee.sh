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

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

skipClans="$3"
if [ -z "$skipClans" ]
then
	skipClans=0
fi


sequences="$DIR/$gene/Sequences"

if [[ $skipClans != 0 ]]
then
	inputSequences="$sequences/NonRedundantSequences90.fasta"
elif [[ -z "$inputSequences" ]]
then
	inputSequences="$sequences/SequencesOfInterest.fasta"
fi

#numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
alignments="$DIR/$gene/Alignments"
outFile="$alignments/$base.alignment.fasta"
outTree="$alignments/$base.tree.mbed"

mkdir -p $alignments

MAX_N_PID_4_TCOFFEE=520000 t_coffee -reg -seq $inputSequences -nseq 100 -tree mbed -method mafftginsi_msa -outfile $outFile -outtree $outTree -thread 0
