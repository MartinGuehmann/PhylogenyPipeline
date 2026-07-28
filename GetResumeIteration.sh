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

# Finds the earliest iteration of the align/build-tree/remove-rogues loop
# (steps 9-11b) that hasn't finished yet, for a given gene/aligner, so a
# restart (13_RestartProcessing.sh -> Scheduler-16-TreeBuildScheduler.sh)
# can resume there instead of always redoing iteration 0 regardless of
# how far a round had actually gotten - confirmed 2026-07-28 that always
# restarting from 0 both wastes already-completed rounds and risks
# resubmitting a round that's still genuinely in progress.
#
# 11b_ExtractNonRogues.sh's Statistics.txt is the last file that round's
# whole chain writes (after pooling dropped rogues and prepping the next
# round's input), so its presence in RogueIter_(N+1)/ means iteration N
# fully completed - see 11b_ExtractNonRogues.sh's own final line. Echoes
# the first N whose RogueIter_(N+1)/Statistics.txt is missing or empty,
# checking N from 0 up to --maxIteration inclusive; prints nothing if
# every round up to that bound is already done.
#
# This can only tell "not yet done" apart from "done" - not "never
# started" apart from "actively running right now" - so it does not by
# itself prevent colliding with a round that's currently in progress on
# the cluster. That's a separate problem (needs checking the live Slurm
# queue, not the filesystem) and deliberately out of scope here.

suffix=""
previousAligner=""
maxIteration="0"

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
            suffix="-x $1"
            ;;
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
            ;;
        --maxIteration)
            ;&
        -m)
            shift
            maxIteration="$1"
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

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

if [ -z "$maxIteration" ] || [[ ! $maxIteration =~ ^[0-9]+$ ]]
then
	maxIteration="0"
fi

for (( i=0; i<=maxIteration; i++ ))
do
	nextDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$((i + 1))" -a "$aligner" $suffix $previousAligner)
	if [ ! -s "$nextDir/Statistics.txt" ]
	then
		echo "$i"
		exit 0
	fi
done

# Every round up to maxIteration is already done - nothing to resume,
# print nothing. Exit 0 deliberately (not just falling off the end,
# whose status would be whatever the last [ -s ... ] test happened to
# return) so callers can tell "ran fine, genuinely nothing to do" apart
# from "failed to even run" (e.g. exit 126, permission denied) by
# checking $? instead of just empty output alone - confirmed 2026-07-28
# a permission-denied GetResumeIteration.sh call and empty output are
# otherwise indistinguishable to a caller that only checks the output.
exit 0
