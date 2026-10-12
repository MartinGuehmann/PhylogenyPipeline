#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
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
        --bigNumRoundsLeft)
            ;&
        -N)
            shift
            bigNumRoundsLeft="$1"
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
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
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

# Print the parameters to stderr for debugging
echo "Running $thisScript with"            >&2
echo "gene:             $gene"             >&2
echo "iteration:        $iteration"        >&2
echo "bigTreeIteration: $bigTreeIteration" >&2
echo "aligner:          $aligner"          >&2
echo "numRoundsLeft:    $numRoundsLeft"    >&2
echo "bigNumRoundsLeft: $bigNumRoundsLeft" >&2
echo "allSeqs:          $allSeqs"          >&2
echo "shuffleSeqs:      $shuffleSeqs"      >&2
echo "suffix:           $suffix"           >&2
echo "extension:        $extension"        >&2
echo "previousAligner:  $previousAligner"  >&2
echo "trimAl:           $trimAl"           >&2
echo "Note the script is copied to"        >&2
echo "another place with another name"     >&2

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
	oldSuffix=$suffix

	if [ -z "$suffix" ]
	then
		suffix="-x BigTree$iteration"
	else
		suffix="$suffix.BigTree$iteration" # Flag -x already included in $suffix
	fi

	if [[ -z $bigNumRoundsLeft ]]
	then
		bigNumRoundsLeft="0"
	fi

	oldAllSeqs=$allSeqs
	allSeqs="--allSeqs"
	# oldSuffix (not olfSuffix - a prior typo here always left this
	# empty, so the else branch below was dead code) is the suffix the
	# regular loop was using before switching to BigTree$iteration -
	# empty for Mas1/PeptideReceptors (no observable effect there, both
	# names held the same empty value), but matters for a gene whose
	# regular loop already runs under a non-empty suffix (e.g. the
	# without-outgroup variant) when it reaches bigTreeIteration.
	if [ -z "$oldSuffix" ]
	then
		previousAligner="-p $aligner"
	else
		previousAligner="-p $aligner.$oldSuffix"
	fi

	"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"
	allSeqs=$oldAllSeqs
	suffix=$oldSuffix
fi

# An unset or empty-string numRoundsLeft used to be treated as "no
# limit" (continue indefinitely) rather than "stop" - confirmed
# 2026-10-12 as the real cause of Mas1's FAMSA.BigTree0 overrun: a
# one-off manual aligner-comparison submission (bypassing
# Scheduler-16-TreeBuildScheduler.sh, which always passes a literal
# numeric value) omitted -n/--numRoundsLeft, so it arrived blank and
# every downstream script faithfully threaded that blank through
# forever. Pinning it to "0" here instead makes "missing" behave the
# same as an explicit one-shot snapshot - the safe default.
if [ -z "$numRoundsLeft" ]
then
	numRoundsLeft="0"
fi

if [[ $numRoundsLeft =~ ^[+-]?[0-9]+$ ]]
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

if [[ ! -z $bigTreeIteration ]]
then
	bigTreeIteration="-b $bigTreeIteration"
fi

if [[ ! -z $bigNumRoundsLeft ]]
then
	bigNumRoundsLeft="-N $bigNumRoundsLeft"
fi

# This seems to be in the environment with Slurm
# So set it to the empty string, since it should not be passed on
previousAligner=""
"$DIR/Scheduler-09-RogueOptAlign.sh" -g "$gene" -i "$nextIteration" -a "$aligner" -n "$numRoundsLeft" $bigTreeIteration $bigNumRoundsLeft $shuffleSeqs $allSeqs $suffix $extension $trimAl
