#!/bin/bash

#PBS -l select=1:ncpus=1:mem=1gb
#PBS -l walltime=0:10:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to load

if [ -z $DIR ]
then
	# Get the directory where this script is
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
		DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	done
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
fi
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"


if [ ! -z $1 ]
then
	gene="$1"
fi

if [ ! -z $2 ]
then
	iteration="$2"
fi

if [ ! -z $3 ]
then
	aligner="$3"
fi

if [ ! -z $4 ]
then
	isExtraRound="$4"
fi

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
elif [ -z "$isExtraRound" ]
	"$DIR/PBS-Pro-Call-RogueOptAlign.sh" "$gene" "$nextIteration" "$aligner" "extraRound"
fi
