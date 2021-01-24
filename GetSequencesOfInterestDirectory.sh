#!/bin/bash

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
        --baseDir)
            ;&
        -d)
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
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored"
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
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript --gene GeneName"
	echo "./$thisScript -g GeneName"
	exit
fi

if [ -z "$baseDir" ]
then
	thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
	echo "You must give a directory, for instance:"
	echo "./$thisScript --baseDir directory"
	echo "./$thisScript -d directory"
	exit
fi

if [ $iteration == 0 ]
then
	seqsOfInterestDir="$baseDir/$gene/SequencesOfInterest/RogueIter_$iteration"
else
	seqsOfInterestDir="$baseDir/$gene/SequencesOfInterest/$aligner/RogueIter_$iteration"
fi

echo $seqsOfInterestDir
