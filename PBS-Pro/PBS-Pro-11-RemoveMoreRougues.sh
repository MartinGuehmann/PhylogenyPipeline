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

# Idiomatic parameter and option handling in sh
# Adapted from https://superuser.com/questions/186272/check-if-any-of-the-parameters-to-a-bash-script-match-a-string
# And advanced version is here https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash/7069755#7069755
while test $# -gt 0
do
    case "$1" in
        --gene)
            ;&
        -g)
            shift
            gene="$1"
            ;;
        --iteration)
            ;&
        -i)
            shift
            iteration="$1"
            ;;
        --bigTreeIteration)
            ;&
        -b)
            shift
            bigTreeIteration="$1"
            ;;
        --aligner)
            ;&
        -a)
            shift
            aligner="$1"
            ;;
        --numRoundsLeft)
            ;&
        -n)
            shift
            numRoundsLeft="$1"
            ;;
        --allSeqs)
            ;&
        -q)
            allSeqs="--allSeqs"
            ;;
        --shuffleSeqs)
            ;&
        -l)
            shuffleSeqs="--shuffleSeqs"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix="-x $1"
            ;;
        --extension)
            ;&
        -e)
            shift
            extension="-e $1"
            ;;
        --trimAl)
            ;&
        -t)
            shift
            trimAl="-t $1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored" >&2
            ;;
    esac
    shift
done

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
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
rogueFreeTreesDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$nextIteration" -a "$aligner" $suffix)
droppedFinal="$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"


if [[ ! -z "$bigTreeIteration" && $bigTreeIteration == $iteration ]]
then
	allSeqs="--allSeqs"
	qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=0, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/PBS-Pro-09-RogueOptAlign.sh"
fi

if [ -z "$numRoundsLeft" ] # Should be an unset variable or an empty string
then
	numRoundsLeft=""
elif [[ $numRoundsLeft =~ ^[+-]?[0-9]+$ ]]
then
	if (( numRoundsLeft <= 0 ))
	then
		echo "Num rounds left at $numRoundsLeft rounds left, in iteration $iteration" >&2
		exit 0
	else
		echo "$numRoundsLeft more rounds to go, next iteration: $nextIteration" >&2
		((numRoundsLeft--))
	fi
fi

if [[ ! -f $droppedFinal ]]
then
	echo "$droppedFinal does not exist, exiting" >&2
	# Break if this does not exist
	exit 1
fi

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped == 0 ))
then
	if [ -z "$numRoundsLeft" ]
	then
		numRoundsLeft=0
	fi
fi

if [[ ! -z $bigTreeIteration ]]
then
	bigTreeIteration = "-b $bigTreeIteration"
fi

"$DIR/PBS-Pro-09-RogueOptAlign.sh" -g "$gene" -i "$nextIteration" -a "$aligner" -n "$numRoundsLeft" $bigTreeIteration $shuffleSeqs $allSeqs $suffix $extension $trimAl
