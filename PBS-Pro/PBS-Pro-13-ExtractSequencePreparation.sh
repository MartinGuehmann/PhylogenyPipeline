#!/bin/bash

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
        --continue)
            ;&
        -c)
            continue="--continue"
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
        --shuffleSeqs)
            ;&
        -l)
            shuffleSeqs="--shuffleSeqs"
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

# Print the parameters to stderr for debugging
echo "Running $thisScript with"            >&2
echo "gene:             $gene"             >&2
echo "bigTreeIteration: $bigTreeIteration" >&2
echo "aligner:          $aligner"          >&2
echo "continue:         $continue"         >&2
echo "numRoundsLeft:    $numRoundsLeft"    >&2
echo "bigNumRoundsLeft: $bigNumRoundsLeft" >&2
echo "shuffleSeqs:      $shuffleSeqs"      >&2
echo "extension:        $extension"        >&2
echo "trimAl:           $trimAl"           >&2
echo "Note PBS-Pro copies the script to"   >&2
echo "another place with another name"     >&2

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

# Change the working directory to the directory of this script
# so that the standard and error output files to the directory of this script
cd $DIR

jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "13" --hold)
echo $jobIDs
holdJobs=$jobIDs

qsub -v "DIR=$DIR, gene=$gene, bigTreeIteration=$bigTreeIteration, aligner=$aligner, continue=$continue, numRoundsLeft=$numRoundsLeft, bigNumRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, extension=$extension, trimAl=$trimAl" -W "depend=afterok$jobIDs" \
    "$DIR/PBS-Pro-14-ExtractSequencesOfInterestWithPASTA.sh"

# Start held jobs
holdJobs=$(echo $holdJobs | sed "s/:/ /g")
qrls $holdJobs
