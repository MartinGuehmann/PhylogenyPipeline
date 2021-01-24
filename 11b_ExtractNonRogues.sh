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
shuffle="$4"

shopt -s extglob

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

seqsOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner")
rogueFreeTreesDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$((iteration + 1))" -a "$aligner")


numTreads=$(nproc)
seqsOfInterest="$seqsOfInterestDir/SequencesOfInterest.fasta"
baseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.part_"
rogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.csv"
droppedFinal="$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"
nextSeqsOfInterest="$rogueFreeTreesDir/SequencesOfInterest.fasta"
SequencesOfInterestShuffled="$rogueFreeTreesDir/SequencesOfInterestShuffled.fasta"
droppedAll="$rogueFreeTreesDir/SequencesOfInterestAll.dropped.fasta"
sequencesAll="$rogueFreeTreesDir/SequencesOfInterestAll.fasta"
droppedListAll=""

if [ -f $droppedFinal ]
then
	mv $droppedFinal "$droppedAll"
fi

if [ -f $nextSeqsOfInterest ]
then
	mv $nextSeqsOfInterest "$sequencesAll"
fi

if [ -f "$droppedAll" ]
then
	cat "$rogueFreeTreesDir/SequencesOfInterest.csv" "$baseRogueNaRokDropped"*".csv" > "$rogueNaRokDropped"
else
	cat "$baseRogueNaRokDropped"*".csv" > "$rogueNaRokDropped"
fi

seqkit grep -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$droppedFinal"

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped > 0 ))
then
	seqkit grep -v -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$nextSeqsOfInterest"
else
	cp "$seqsOfInterest" "$nextSeqsOfInterest"
fi

if [[ ! -z "$shuffle" && $shuffle == "true" ]]
then
	partSequences="SequencesOfInterestShuffled.part_"
	for fastaFile in "$rogueFreeTreesDir/$partSequences"+([0-9])".fasta"
	do
		baseFile=$(basename $fastaFile ".fasta")
		mv $fastaFile "$rogueFreeTreesDir/$baseFile.old.fasta"
	done

	seqsPerChunk="900"

	seqkit shuffle -2 -j "$numTreads" "$nextSeqsOfInterest" > "$SequencesOfInterestShuffled"

	numSeqs=$(grep -c '>' $SequencesOfInterestShuffled)

	restSeqChunk=$(($numSeqs % $seqsPerChunk))
	numSeqChunks=$(($numSeqs / $seqsPerChunk))

	numSeqsCorrPerChunk=$(($seqsPerChunk + 1 + $restSeqChunk / $numSeqChunks))

	# Warns that output directoy is not empty, but it is supposed to be non-empty
	seqkit split2 -j $numTreads -s $numSeqsCorrPerChunk -O $rogueFreeTreesDir $SequencesOfInterestShuffled
fi

seqkit stats "$rogueFreeTreesDir/"*".fasta" > "$rogueFreeTreesDir/Statistics.txt"

AlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner")
$DIR/11c_CalculateAverageSupport.sh "$AlignmentDir" "$rogueFreeTreesDir"
