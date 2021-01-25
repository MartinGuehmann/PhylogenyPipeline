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
	numRoundsLeft="$4"
fi

if [ ! -z "$5" ]
then
	shuffleSeqs="$5"
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

if [ -z "$aligner" ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

nextIteration="$((iteration + 1))"
rogueFreeTreesDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$nextIteration" -a "$aligner")
droppedFinal="$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"


if [ -z "$numRoundsLeft" ] # Should be an unset variable or an empty string
then
	numRoundsLeft=""
elif [[ $numRoundsLeft =~ ^[+-]?[0-9]+$ ]]
then
	if (( numRoundsLeft <= 0 ))
	then
		echo "Num rounds left at $numRoundsLeft rounds left, in iteration $iteration"
		exit
	else
		echo "$numRoundsLeft more rounds to go, next iteration: $nextIteration"
		((numRoundsLeft--))
	fi
fi

if [[ ! -f $droppedFinal ]]
then
	echo "$droppedFinal does not exist, existing"
	# Break if this does not exist
	exit
fi

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped == 0 ))
then
	if [ -z "$numRoundsLeft" ]
	then
		numRoundsLeft=0
	fi
fi

"$DIR/PBS-Pro-Call-RogueOptAlign.sh" "$gene" "$nextIteration" "$aligner" "$numRoundsLeft" "$shuffleSeqs"
