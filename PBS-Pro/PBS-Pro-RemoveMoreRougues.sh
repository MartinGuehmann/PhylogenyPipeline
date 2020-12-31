#!/bin/bash

#PBS -l select=1:ncpus=1:mem=1gb
#PBS -l walltime=0:10:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to load

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"


if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

if [ -z "$iteration" ]
then
	iteration="0"
fi

defaultAligner="FAMSA"

if [ -z "$aligner" ]
then
	aligner="$defaultAligner"
fi

nextIteration=$((iteration + 1))
rogueFreeTreesDir="$DIR/../$gene/SequencesOfInterest.$aligner.RogueIter_$nextIteration"
droppedFinal="$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped > 0 ))
then
	"$DIR/PBS-Pro-Call-RogueOptAlign.sh" "$gene" "$nextIteration" "$aligner"
fi
