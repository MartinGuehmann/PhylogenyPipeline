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
        --useFullDataset)
            ;&
        -q)
            # No value follows this flag - the shift here (copied from a
            # value-taking case like -t/-e above) used to silently swallow
            # whatever came next on the command line (e.g. --localNr, when
            # placed right after $useFullDataset - see 00_StartExtraction.sh)
            # before it could ever reach this case statement.
            useFullDataset="--useFullDataset"
            ;;
        --localNr)
            ;&
        -L)
            localNr="--localNr"
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
echo "useFullDataset:   $useFullDataset"   >&2
echo "localNr:          $localNr"          >&2
echo "Note the script is copied to"        >&2
echo "another place with another name"     >&2

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName and a StepNumber, for instance:" >&2
	echo "./$thisScript GeneName StepNumber" >&2
	exit 1
fi

if [ -z "$aligner" ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

# If this run is our own afterany follow-up (see the restart submission
# below), holdJobs will already be set from the environment - only redo
# the work and schedule another follow-up if the job we're following up
# after actually hit its walltime. Anything else it could have ended as
# - scancel'd, genuinely failed, node failure, or even succeeded - should
# just stop the chain here instead of restarting forever.
if [ -n "$holdJobs" ] && command -v sacct >/dev/null 2>&1
then
	predecessorJobIDs="${holdJobs//:/,}"
	predecessorJobIDs="${predecessorJobIDs#,}"
	state=$(sacct -j "$predecessorJobIDs" -X --format=State --noheader --parsable2 | head -1 | tr -d '[:space:]')
	if [ "$state" != "TIMEOUT" ]
	then
		echo "$predecessorJobIDs ended as '$state', not TIMEOUT - not restarting $thisScript" >&2
		exit 0
	fi
	echo "$predecessorJobIDs hit its walltime - restarting $thisScript" >&2
fi

# Change the working directory to the directory of this script
# so that the standard and error output files to the directory of this script
cd $DIR

# Align all the sequences
jobIDs=$($DIR/Scheduler-Call.sh             -g "$gene" -s "0" --hold $localNr)
echo $jobIDs
holdJobs=$jobIDs

# If we run against the wall, just restart the main task. sacct lets us
# check *why* the job ended, not just whether it succeeded, so the check
# above can restrict the actual restart to a genuine TIMEOUT instead of
# any non-success (including a manual scancel). Without sacct (e.g. PBS),
# fall back to the old afternotok behavior - PBS has no equally simple
# way to ask "was this killed for walltime specifically."
if command -v sacct >/dev/null 2>&1
then
	restartDepend="afterany$holdJobs"
	holdJobsExport=", holdJobs=$holdJobs"
else
	restartDepend="afternotok$holdJobs"
	holdJobsExport=""
fi
"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, bigTreeIteration=$bigTreeIteration, aligner=$aligner, continue=$continue, numRoundsLeft=$numRoundsLeft, bigNumRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, extension=$extension, trimAl=$trimAl, localNr=$localNr$holdJobsExport" -W "depend=$restartDepend" \
    "$DIR/Scheduler-00-ExtractSequences.sh"

if [ "$continue" == "--continue" ]
then
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, bigTreeIteration=$bigTreeIteration, aligner=$aligner, continue=$continue, numRoundsLeft=$numRoundsLeft, bigNumRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, extension=$extension, trimAl=$trimAl, useFullDataset=$useFullDataset, localNr=$localNr" -W "depend=afterok$holdJobs" \
	    "$DIR/Scheduler-01-PrepareSequences.sh"
fi

# Start held jobs
holdJobs=$(echo $holdJobs | sed "s/:/ /g")
"$DIR/Scheduler-RelHold.sh" $holdJobs
