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
inputTrees="$2"
aligner="$3"
iteration="$4"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

if [ $iteration == 0 ]
then
	seqsOfInterestDir="$DIR/$gene/SequencesOfInterest.RogueIter_$iteration"
else
	seqsOfInterestDir="$DIR/$gene/SequencesOfInterest.$aligner.RogueIter_$iteration"
fi

rogueFreeTreesDir="$DIR/$gene/SequencesOfInterest.$aligner.RogueIter_$((iteration + 1))"
mkdir -p $rogueFreeTreesDir

numTreads=$(nproc)
base=$(basename $inputTrees ".alignment.$aligner.fasta.raxml.reduced.phy.ufboot")
baseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.$base"
baseRogueNaRokDroppedCSV="$baseRogueNaRokDropped.csv"
seqsOfInterestIDs="$seqsOfInterestDir/SequencesOfInterestIDs.txt"

# If we call this again we want to overwrite the output
rm -f "$baseRogueNaRokDroppedCSV"
rm -f "$baseRogueNaRokDropped"
rm -f "$rogueFreeTreesDir/RogueNaRok_info.$base"

"$DIR/../RogueNaRok/RogueNaRok-parallel" -i $inputTrees -n $base -w $rogueFreeTreesDir -T $numTreads

grep -o -f "$seqsOfInterestIDs" $baseRogueNaRokDropped > "$baseRogueNaRokDroppedCSV"

seqkit grep -f "$baseRogueNaRokDroppedCSV" -j $numTreads "$seqsOfInterestDir/$base.fasta" > "$rogueFreeTreesDir/$base.dropped.fasta"
seqkit grep -v -f "$baseRogueNaRokDroppedCSV" -j $numTreads "$seqsOfInterestDir/$base.fasta" > "$rogueFreeTreesDir/$base.fasta"
