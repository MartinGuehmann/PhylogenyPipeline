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

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

seqsOfInterest="$DIR/$gene/SequencesOfInterest/SequencesOfInterest.fasta"
rogueFreeTreesDir="$DIR/$gene/RogueFreeTrees"

numTreads=$(nproc)
baseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.part_"
rogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.csv"

cat "$baseRogueNaRokDropped"*".csv" > $rogueNaRokDropped

seqkit grep -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"
seqkit grep -v -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$rogueFreeTreesDir/SequencesOfInterest.roked.fasta"
