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
            # Actually ignored
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
echo "numRoundsLeft:    $numRoundsLeft"    >&2
echo "bigNumRoundsLeft: $bigNumRoundsLeft" >&2
echo "shuffleSeqs:      $shuffleSeqs"      >&2
echo "extension:        $extension"        >&2
echo "trimAl:           $trimAl"           >&2
echo "Note the script is copied to"        >&2
echo "another place with another name"     >&2

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

if [ -z "$bigTreeIteration" ]
then
	bigTreeIteration="10"
fi

if [ -z $numRoundsLeft ]
then
	numRoundsLeft="20"
fi

if [ -z $bigNumRoundsLeft ]
then
	bigNumRoundsLeft="10"
fi

if [ -z $aligner ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

# Change the working directory to the directory of this script
# so that the standard and error output files go to the directory of this script
cd $DIR

numRoundsLeftZero="0"
allSeqs=""
suffix=""
extension="-e treefile"
previousAligner=""

# Every submission below used to always restart at iteration 0 with the
# full round count, regardless of how far a previous run had actually
# gotten - wasting already-completed rounds and, worse, risking a fresh
# submission colliding with a round that's still genuinely in progress
# on the cluster (confirmed 2026-07-28 on Mas1: a restart would have
# resubmitted MAGUS's BigTree0 and regular loop from scratch while both
# were still actively running). GetResumeIteration.sh checks for
# 11b_ExtractNonRogues.sh's Statistics.txt (the last file a round's
# whole chain writes) to tell "not yet done" apart from "done", so each
# submission point below now resumes at the first incomplete round
# instead, and is skipped entirely once every round it's responsible for
# is already finished. This still can't tell "never started" apart from
# "actively running right now" - that's a separate problem, deliberately
# not addressed here.
#
# GetResumeIteration.sh exits 0 whether it found an incomplete round or
# not - only its own genuine failures (missing gene, wrong permissions,
# etc.) exit non-zero. A real permission-denied call and a legitimate
# "everything's done" both print nothing, so $? has to be checked
# explicitly - confirmed 2026-07-28: a newly-added script losing its
# executable bit (this repo has core.fileMode=false, so a plain chmod +x
# before committing isn't enough - see this same commit for the fix)
# made every single call fail silently, and every submission point below
# read that as "already done" and skipped, including MAGUS's regular
# loop, which very much still had a stuck round waiting on it. hadError
# tracks whether that happened so this script exits non-zero instead of
# reporting a clean, misleading success.
hadError=""

# Make an iteration for all available aligners, except for the main
# aligner and anything listed in SkippedAligners.cfg - a way to turn an
# aligner off pipeline-wide (e.g. one that isn't panning out) without
# touching its own 09_Scheduler-AlignWith<Name>.sh or anything that
# calls it, so turning it back on later is just deleting a line there.
for alignerScript in "$DIR/09_Scheduler-AlignWith"*".sh"*
do
	if [[ $alignerScript =~ 09_Scheduler-AlignWith(.*)\.sh ]]
	then
		usedAligner=${BASH_REMATCH[1]}
		if [ -f "$DIR/SkippedAligners.cfg" ] && grep -v '^#' "$DIR/SkippedAligners.cfg" | grep -v '^[[:space:]]*$' | grep -qFx "$usedAligner"
		then
			echo "$usedAligner is listed in SkippedAligners.cfg - not submitting" >&2
		elif [[ $usedAligner != $aligner ]]
		then
			resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$usedAligner" -m 0)
			resumeStatus=$?
			if [ $resumeStatus -ne 0 ]
			then
				echo "GetResumeIteration.sh failed (exit $resumeStatus) for $usedAligner - not submitting" >&2
				hadError="true"
			elif [ -n "$resumeIteration" ]
			then
				"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$usedAligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
				    "$DIR/Scheduler-09-RogueOptAlign.sh"
			else
				echo "$usedAligner already has a completed round - skipping" >&2
			fi
		fi
	fi
done

oldSuffix=$suffix
suffix="-x BigTree0"
# Make the big tree with the main aligner
allSeqs="--allSeqs"
resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -x "BigTree0" -m 0)
resumeStatus=$?
if [ $resumeStatus -ne 0 ]
then
	echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner.BigTree0 - not submitting" >&2
	hadError="true"
elif [ -n "$resumeIteration" ]
then
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"
else
	echo "$aligner.BigTree0 already has a completed round - skipping" >&2
fi
suffix=$oldSuffix

### Add check whether Opsins/SequencesOfInterest/Opsins/RogueIter_0
geneOnlyDataSet=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -p "$(basename $gene)")

if [ -d $geneOnlyDataSet ]
then
	suffix="-x $(basename $gene).BigTree0"
	previousAligner="-p $gene"
	# Make a big tree with the main aligner and without outgroup
	# Not covered by the resume-check above: GetSequencesOfInterestDirectory.sh
	# resolves the path from previousAligner alone once it's set, ignoring
	# aligner/suffix entirely, and this branch isn't exercised by any
	# locally-testable gene - left as an unconditional restart rather than
	# risk an unverified resume check here.
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=0, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"

	allSeqs=""
	suffix="-x $(basename $gene)"
	# Make also small trees with the main aligner and without outgroup
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=0, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"
else
	echo "No reduced dataset in $geneOnlyDataSet" >&2
	echo "Skipping" >&2
fi

allSeqs=""
suffix=""
previousAligner=""

# Make up to $numRoundsLeft iterations with the main aligner, make a big
# tree after $bigTreeIteration iterations - resume at the first
# incomplete round, with numRoundsLeft reduced by however many rounds
# are already done, instead of always restarting at iteration 0 with the
# full original count.
#
# numRoundsLeft="0" means skip this loop entirely, not "run round 0 and
# then stop" - GetResumeIteration.sh -m 0 checks iteration 0 alone and,
# since it isn't done yet, prints "0" (a non-empty string meaning
# "iteration 0 still needs doing"), which used to submit round 0
# regardless of numRoundsLeft. Confirmed 2026-08-11 needed for a gene
# family small enough that only the BigTree0 branch above is wanted at
# all, with no separate small-scale split-chunk loop alongside it.
if [ "$numRoundsLeft" == "0" ]
then
	echo "numRoundsLeft is 0 - skipping $aligner's regular (small-scale) round loop entirely" >&2
else
	resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -m "$numRoundsLeft")
	resumeStatus=$?
	if [ $resumeStatus -ne 0 ]
	then
		echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner's regular loop - not submitting" >&2
		hadError="true"
	elif [ -n "$resumeIteration" ]
	then
		remainingRounds=$((numRoundsLeft - resumeIteration))
		"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$remainingRounds, bigNumRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl, bigTreeIteration=$bigTreeIteration" \
		    "$DIR/Scheduler-09-RogueOptAlign.sh"
	else
		echo "$aligner's regular loop already completed all $numRoundsLeft rounds - skipping" >&2
	fi
fi

if [ -z "$trimAl" ]
then
	# Switch pruning on if it was off
	suffix="-x trimAl"
	trimAl="-t Default"
else
	# Switch pruning off if it was on
	suffix="-x noTrimAl"
	trimAl=""
fi

# Make an iteration for the main aligner, with switched pruning settings
resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -x "${suffix#-x }" -m 0)
resumeStatus=$?
if [ $resumeStatus -ne 0 ]
then
	echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner.${suffix#-x } - not submitting" >&2
	hadError="true"
elif [ -n "$resumeIteration" ]
then
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"
else
	echo "$aligner.${suffix#-x } already has a completed round - skipping" >&2
fi

if [ -n "$hadError" ]
then
	echo "One or more GetResumeIteration.sh calls failed - see above" >&2
	exit 1
fi
