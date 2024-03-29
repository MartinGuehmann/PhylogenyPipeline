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

# This is needed, because these might be definded from qsub
suffix=""
previousAligner=""

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
        --aligner)
            ;&
        -a)
            shift
            aligner="$1"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix=".$1"
            ;;
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="$1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored in $thisScript" >&2
            ;;
    esac
    shift
done

if [ -z "$iteration" ]
then
	iteration="0"
fi

if [ -z "$aligner" ]
then
	aligner=$("$DIR/GetDefaultAligner.sh")
fi

if [ -z "$gene" ]
then
	thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript --gene GeneName" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

if [ ! -z $previousAligner ]
then
	seqsOfInterestDir="$DIR/$gene/SequencesOfInterest/$previousAligner/RogueIter_$iteration"
elif [ $iteration == 0 ]
then
	seqsOfInterestDir="$DIR/$gene/SequencesOfInterest/RogueIter_$iteration"
else
	seqsOfInterestDir="$DIR/$gene/SequencesOfInterest/$aligner$suffix/RogueIter_$iteration"
fi

echo $seqsOfInterestDir
