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
        --runPMSF)
            ;&
        -P)
            runPMSF="--runPMSF"
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
echo "runPMSF:          $runPMSF"          >&2
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
#
# Uses a single regular (non-allSeqs) round by default, matching the
# main aligner's own regular loop it's meant to compare against. When
# bigTreeIteration=="0" the main aligner isn't doing a regular loop at
# all (BigTree0-only, see above/below) - a regular-mode comparison
# round wouldn't be comparing against anything real then, so use a
# single BigTree0 round instead, matching what the main aligner
# actually builds. Confirmed 2026-08-11 on PRRs.
otherAlignerAllSeqs="$allSeqs"
otherAlignerSuffix="$suffix"
otherAlignerResumeSuffixArg=""
if [ "$bigTreeIteration" == "0" ]
then
	otherAlignerAllSeqs="--allSeqs"
	otherAlignerSuffix="-x BigTree0"
	otherAlignerResumeSuffixArg="-x BigTree0"
fi
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
			resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$usedAligner" $otherAlignerResumeSuffixArg -m 0)
			resumeStatus=$?
			if [ $resumeStatus -ne 0 ]
			then
				echo "GetResumeIteration.sh failed (exit $resumeStatus) for $usedAligner - not submitting" >&2
				hadError="true"
			elif [ -n "$resumeIteration" ]
			then
				if "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$usedAligner" $otherAlignerResumeSuffixArg >/dev/null
				then
					echo "$usedAligner's matching round is already running on the cluster - not submitting a duplicate" >&2
				else
					echo "Submitting $usedAligner's comparison round (iteration $resumeIteration)" >&2
					"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$usedAligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$otherAlignerAllSeqs, suffix=$otherAlignerSuffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
					    "$DIR/Scheduler-09-RogueOptAlign.sh"
				fi
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

# Normally this call only ever submits a single round (numRoundsLeft
# hardcoded to 0 below) - BigTree0 gets its real bigNumRoundsLeft
# refinement later, from Scheduler-11-RemoveMoreRougues.sh's own
# bigTreeIteration check once the *regular small-scale loop* reaches
# iteration $bigTreeIteration (matched by suffix, "BigTree$iteration").
# That mechanism can't fire at all if bigTreeIteration is "0" and the
# regular loop is skipped entirely (numRoundsLeft="0", further below) -
# confirmed 2026-08-11 on PRRs, which wants only BigTree0, no regular
# loop at all. Have this call carry the continuation itself in that one
# case, checking/resuming across the full bigNumRoundsLeft range
# instead of just iteration 0. For any other bigTreeIteration value,
# leave this as the one-shot early snapshot it's always been -
# continuation still comes from the regular loop reaching that
# iteration later.
bigTreeNumRounds="$numRoundsLeftZero"
bigTreeMaxCheck="0"
if [ "$bigTreeIteration" == "0" ]
then
	bigTreeNumRounds="$bigNumRoundsLeft"
	bigTreeMaxCheck="$bigNumRoundsLeft"
fi

resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -x "BigTree0" -m "$bigTreeMaxCheck")
resumeStatus=$?
if [ $resumeStatus -ne 0 ]
then
	echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner.BigTree0 - not submitting" >&2
	hadError="true"
elif [ -n "$resumeIteration" ]
then
	remainingBigTreeRounds="$bigTreeNumRounds"
	# runPMSF only ever applies to this BigTree0 chain when
	# bigTreeIteration=="0" - that's the only case where BigTree0 *is*
	# the gene's real, final result (otherwise it's just a one-shot
	# seed round, superseded later by the real BigTree$bigTreeIteration
	# branch Scheduler-11-RemoveMoreRougues.sh spins off on its own -
	# see that script's own runPMSF handling).
	bigTree0RunPMSF=""
	if [ "$bigTreeIteration" == "0" ]
	then
		remainingBigTreeRounds=$((bigTreeNumRounds - resumeIteration))
		bigTree0RunPMSF="$runPMSF"
	fi
	if "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" -x "BigTree0" >/dev/null
	then
		echo "$aligner.BigTree0 is already running on the cluster - not submitting a duplicate" >&2
	else
		echo "Submitting $aligner.BigTree0 (iteration $resumeIteration)" >&2
		"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$remainingBigTreeRounds, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl, runPMSF=$bigTree0RunPMSF" \
		    "$DIR/Scheduler-09-RogueOptAlign.sh"
	fi
else
	echo "$aligner.BigTree0 already has a completed round - skipping" >&2
fi
suffix=$oldSuffix

# BigTree$bigTreeIteration (when bigTreeIteration != "0") is a
# completely separate branch from BigTree0 above - it's created by
# Scheduler-11-RemoveMoreRougues.sh's own bigTreeIteration check once
# the regular loop below reaches that iteration, carrying the regular
# loop's current iteration number straight in (so this branch's own
# rounds are numbered starting at $bigTreeIteration itself, not 0), and
# every subsequent round is driven entirely by that same recursive
# chain - this script has never submitted any of it directly. A round
# that crashes outright (FAILED, not TIMEOUT - e.g. /work/ going down
# mid-write) is not auto-resubmitted by anything (Scheduler-10's own
# self-resubmission only fires on a genuine walltime TIMEOUT, by
# design), so without this check such a crash sits stuck until
# resubmitted by hand - confirmed 2026-10-12 on Mas1/PeptideReceptors'
# own FAMSA.BigTree5/RogueIter_8 crashes during a /work/ outage.
#
# previousAligner is intentionally omitted below, unlike the
# transitional round's own submission inside Scheduler-11 (which needs
# it to find its input in the regular loop's own differently-suffixed
# output) - every round this check could actually resubmit is strictly
# after that transitional round (see the resumeIteration check below),
# so its input already lives under this same BigTree$bigTreeIteration
# suffix.
if [ "$bigTreeIteration" != "0" ] && [[ $bigNumRoundsLeft =~ ^[0-9]+$ ]] && (( bigNumRoundsLeft > 0 ))
then
	# The matching BigTree0 continuation above checks iterations 0
	# through bigNumRoundsLeft inclusive (bigTreeMaxCheck="$bigNumRoundsLeft"),
	# i.e. bigNumRoundsLeft+1 total rounds - this branch's own rounds
	# are offset by bigTreeIteration (see the -s flag below) but use
	# the same bigNumRoundsLeft+1 convention, so its last iteration is
	# bigTreeIteration + bigNumRoundsLeft, not -1.
	bigTreeLastIteration=$((bigTreeIteration + bigNumRoundsLeft))
	resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -x "BigTree$bigTreeIteration" -s "$bigTreeIteration" -m "$bigTreeLastIteration")
	resumeStatus=$?
	if [ $resumeStatus -ne 0 ]
	then
		echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner.BigTree$bigTreeIteration - not submitting" >&2
		hadError="true"
	elif [ -z "$resumeIteration" ]
	then
		echo "$aligner.BigTree$bigTreeIteration already has a completed round - skipping" >&2
	elif [ "$resumeIteration" == "$bigTreeIteration" ]
	then
		# The transitional round itself (iteration == bigTreeIteration)
		# hasn't completed yet - it's created by the regular loop
		# reaching this iteration, not resubmitted here, to avoid a
		# premature/duplicate submission racing against it. That could
		# mean it hasn't started yet OR it's actively running OR it
		# crashed - previously left silent (no message in any of these
		# three cases), which looked indistinguishable from "this branch
		# wasn't even checked" from the printed output alone. Now at
		# least reports which of the three, same IsRoundRunning.sh check
		# already used for every other branch here - still never
		# submits anything itself either way.
		if "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" -x "BigTree$bigTreeIteration" >/dev/null
		then
			echo "$aligner.BigTree$bigTreeIteration's transitional round (iteration $bigTreeIteration) is running on the cluster" >&2
		else
			echo "$aligner.BigTree$bigTreeIteration's transitional round (iteration $bigTreeIteration) hasn't completed and isn't running on the cluster - not submitting (only the regular loop reaching this iteration creates it)" >&2
		fi
	else
		remainingBigTreeRounds=$((bigTreeLastIteration - resumeIteration))
		if "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" -x "BigTree$bigTreeIteration" >/dev/null
		then
			echo "$aligner.BigTree$bigTreeIteration is already running on the cluster - not submitting a duplicate" >&2
		else
			echo "Submitting $aligner.BigTree$bigTreeIteration (iteration $resumeIteration) - resuming a crashed or never-started round" >&2
			"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$remainingBigTreeRounds, shuffleSeqs=$shuffleSeqs, allSeqs=--allSeqs, suffix=-x BigTree$bigTreeIteration, extension=$extension, trimAl=$trimAl, runPMSF=$runPMSF" \
			    "$DIR/Scheduler-09-RogueOptAlign.sh"
		fi
	fi
fi

### Add check whether Opsins/SequencesOfInterest/Opsins/RogueIter_0
geneOnlyDataSet=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -p "$(basename $gene)")

if [ -d $geneOnlyDataSet ]
then
	suffix="-x $(basename $gene).BigTree0"
	# Must be the basename, matching $geneOnlyDataSet's own -p above - the
	# unresolved $gene (e.g. "../PeptideReceptors") was used here until
	# 2026-09-01, which silently pointed this at the wrong directory:
	# GetSequencesOfInterestDirectory.sh builds
	# "$DIR/$gene/SequencesOfInterest/$previousAligner/RogueIter_$iteration"
	# by plain string concatenation, so a previousAligner still carrying
	# "../GeneName" doesn't just get appended - the filesystem later
	# resolves the embedded ".." by cancelling the literal "SequencesOfInterest"
	# path component in front of it, landing on
	# ".../GeneName/GeneName/RogueIter_0" instead of
	# ".../GeneName/SequencesOfInterest/GeneName/RogueIter_0" (what step 16
	# actually creates) - a directory that can never exist, not a transient
	# race. Confirmed 2026-09-01 on PeptideReceptors: both jobs below failed
	# every time (Check-InputFile.sh's "does not exist" guard caught it),
	# while $geneOnlyDataSet's own check above still passed, because *it*
	# correctly used the basename.
	previousAligner="-p $(basename $gene)"
	# Make a big tree with the main aligner and without outgroup
	#
	# The resume check below deliberately omits previousAligner (unlike
	# the submission itself, right above, which needs it to find this
	# round's special iteration-0 input): GetResumeIteration.sh only ever
	# asks GetSequencesOfInterestDirectory.sh for iteration 1's own
	# output marker here (-m 0), and that always lives under
	# "$aligner$suffix" regardless of where iteration 0's input came from
	# - previousAligner only overrides that path (ignoring aligner/suffix
	# entirely) when it's actually passed through, so simply not passing
	# it here sidesteps the quirk instead of tripping over it. Confirmed
	# 2026-10-21 against a real completed round
	# (SequencesOfInterest/FAMSA.PeptideReceptors/RogueIter_1/Statistics.txt)
	# - this branch used to unconditionally redo both of its rounds on
	# every restart regardless of completion, overwriting already-
	# finished output (with shuffleSeqs on, not even reproducibly).
	resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -x "${suffix#-x }" -m 0)
	resumeStatus=$?
	if [ $resumeStatus -ne 0 ]
	then
		echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner.${suffix#-x } - not submitting" >&2
		hadError="true"
	elif [ -z "$resumeIteration" ]
	then
		echo "$aligner.${suffix#-x } already has a completed round - skipping" >&2
	elif "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" -x "${suffix#-x }" >/dev/null
	then
		echo "$aligner.${suffix#-x } is already running on the cluster - not submitting a duplicate" >&2
	else
		echo "Submitting $aligner.${suffix#-x }" >&2
		"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=0, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
		    "$DIR/Scheduler-09-RogueOptAlign.sh"
	fi

	allSeqs=""
	suffix="-x $(basename $gene)"
	# Make also small trees with the main aligner and without outgroup -
	# same resume-check reasoning as just above.
	resumeIteration=$("$DIR/../GetResumeIteration.sh" -g "$gene" -a "$aligner" -x "${suffix#-x }" -m 0)
	resumeStatus=$?
	if [ $resumeStatus -ne 0 ]
	then
		echo "GetResumeIteration.sh failed (exit $resumeStatus) for $aligner.${suffix#-x } - not submitting" >&2
		hadError="true"
	elif [ -z "$resumeIteration" ]
	then
		echo "$aligner.${suffix#-x } already has a completed round - skipping" >&2
	elif "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" -x "${suffix#-x }" >/dev/null
	then
		echo "$aligner.${suffix#-x } is already running on the cluster - not submitting a duplicate" >&2
	else
		echo "Submitting $aligner.${suffix#-x }" >&2
		"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=0, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
		    "$DIR/Scheduler-09-RogueOptAlign.sh"
	fi
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
		if "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" >/dev/null
		then
			echo "$aligner's regular loop is already running on the cluster - not submitting a duplicate" >&2
		else
			echo "Submitting $aligner's regular loop (iteration $resumeIteration)" >&2
			"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$remainingRounds, bigNumRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl, bigTreeIteration=$bigTreeIteration" \
			    "$DIR/Scheduler-09-RogueOptAlign.sh"
		fi
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

# Same reasoning as the other-aligner comparison loop above: when
# bigTreeIteration=="0" the main aligner isn't running a regular loop
# at all (BigTree0-only), so this trimAl/noTrimAl comparison round
# should also be BigTree0-scale to actually be comparing against
# something real, rather than a regular-mode round that no longer
# exists for this gene family. Confirmed on PRRs.
if [ "$bigTreeIteration" == "0" ]
then
	allSeqs="--allSeqs"
	suffix="-x BigTree0.${suffix#-x }"
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
	if "$DIR/../IsRoundRunning.sh" -g "$gene" -a "$aligner" -x "${suffix#-x }" >/dev/null
	then
		echo "$aligner.${suffix#-x } is already running on the cluster - not submitting a duplicate" >&2
	else
		echo "Submitting $aligner.${suffix#-x } (iteration $resumeIteration)" >&2
		"$DIR/Scheduler-Sub.sh" -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$resumeIteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
		    "$DIR/Scheduler-09-RogueOptAlign.sh"
	fi
else
	echo "$aligner.${suffix#-x } already has a completed round - skipping" >&2
fi

if [ -n "$hadError" ]
then
	echo "One or more GetResumeIteration.sh calls failed - see above" >&2
	exit 1
fi
