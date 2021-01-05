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
aligner="$2"
iteration="$3"

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


numTreads=$(nproc)
seqsOfInterest="$seqsOfInterestDir/SequencesOfInterest.fasta"
baseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.part_"
rogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.csv"
droppedFinal="$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"
nextSeqsOfInterest="$rogueFreeTreesDir/SequencesOfInterest.fasta"

if [ -f $droppedFinal ]
then
	mv $droppedFinal "$rogueFreeTreesDir/SequencesOfInterestAll.dropped.fasta"
fi

if [ -f $nextSeqsOfInterest ]
then
	mv $nextSeqsOfInterest "$rogueFreeTreesDir/SequencesOfInterestAll.fasta"
fi

cat "$baseRogueNaRokDropped"*".csv" > "$rogueNaRokDropped"

seqkit grep -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$droppedFinal"

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped > 0 ))
then
	seqkit grep -v -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$nextSeqsOfInterest"
else
	cp "$seqsOfInterest" "$nextSeqsOfInterest"
fi

seqkit stats "$rogueFreeTreesDir/"*".fasta" > "$rogueFreeTreesDir/Statistics.txt"
