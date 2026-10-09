#!/bin/bash

# Resources for this job (a tiny driver, not the actual PMSF
# computation - see 18_Scheduler-RefineTreeWithPMSF.sh for that) are
# set in Scheduler/Resources.cfg.
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
source "$DIR/AbortIfJobIDsEmpty.sh"

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
            suffix="-x $1"
            ;;
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
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

# Every other entry point in this pipeline (13_RestartProcessing.sh,
# 15_..., 16_TreeBuildScheduler.sh) is invoked with -g already in the
# "../GeneName" form (they live inside the gene's own repo directory
# and auto-derive it: gene=$(basename "$DIR"); gene="../$gene") -
# Scheduler-Call.sh/GetAlignmentDirectory.sh/Scheduler-Sub.sh's own
# logDir all assume that prefix is already there. This script is called
# directly by a human instead, so -g must be given the same way by
# hand: "../GeneName", not a bare gene name. Confirmed 2026-10-09: a
# bare "-g PRRs" fed straight through unprefixed, pointing every real
# submission at a nonexistent PhylogenyPipeline/PRRs/... path instead
# of the real sibling Phylogenies/PRRs/..., so checkInputFile failed
# every job immediately, before any PMSF computation ever ran.
if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give the gene the same way the rest of this pipeline does - '../GeneName', not a bare name (see this script's own header comment for why) - plus an Iteration and an Aligner, for instance:" >&2
	echo "./$thisScript -g ../GeneName -i Iteration -a Aligner" >&2
	exit 1
fi

# Unlike Scheduler-10-RogueOptTree.sh, iteration has no sensible
# default here - this step is meant to target one specific, already-
# final round the caller has decided on (e.g. the highest existing
# RogueIter_N), never "start from round 0", so silently defaulting it
# risks quietly refining the wrong (e.g. the very first, unrefined)
# round instead of failing loudly.
if [ -z "$iteration" ]
then
	echo "Iteration missing" >&2
	echo "You must give the iteration whose tree is final (e.g. the highest existing RogueIter_N) - this step never defaults it:" >&2
	echo "./$thisScript -g GeneName -i Iteration -a Aligner" >&2
	exit 1
fi

if [ -z "$aligner" ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

# If this run is our own afterany follow-up (see the restart submission
# below), holdJobs will already be set from the environment - only
# resubmit the real PMSF job if the job we're following up after
# actually hit its walltime. Anything else it could have ended as -
# scancel'd, genuinely failed, node failure, or even succeeded - should
# just stop the chain here instead of restarting forever. Same pattern
# as Scheduler-10-RogueOptTree.sh's own restart logic (see its header
# comment for the reasoning behind checking sacct's State specifically).
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

cd $DIR

jobIDs=$($DIR/Scheduler-Call.sh -g "$gene" -s "18" -i "$iteration" -a "$aligner" $suffix $previousAligner)
abortIfJobIDsEmpty "$jobIDs" "step 18"
echo $jobIDs
holdJobs=$jobIDs

# Keep resubmitting after ourselves for as long as sacct can tell us the
# predecessor was killed for walltime specifically (see the check
# above). IQ-Tree's own checkpoint makes 18_RefineTreeWithPMSF.sh's
# resubmission a true resume, not a restart from scratch (see that
# script's own header comment) - this is what makes an open-ended
# resubmit chain safe to leave running unattended rather than wasting
# a full 72h slot repeating finished work. Without sacct (e.g. PBS),
# there is no equally simple way to ask "was this killed for walltime
# specifically" - same limitation as Scheduler-10-RogueOptTree.sh, so
# this chain simply isn't started on PBS; resubmit step 18 by hand
# there instead if it hits its walltime.
if command -v sacct >/dev/null 2>&1
then
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, suffix=$suffix, previousAligner=$previousAligner, holdJobs=$holdJobs" -W "depend=afterany$holdJobs" \
	    "$DIR/Scheduler-18-RefineTreeWithPMSF.sh"
else
	echo "sacct not found - cannot tell whether a future timeout happens, so $thisScript will not resubmit itself; resubmit step 18 by hand if it hits its walltime." >&2
fi
