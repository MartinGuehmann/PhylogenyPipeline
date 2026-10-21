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

# Checks whether a round (gene + aligner + suffix combination, e.g.
# "FAMSA.BigTree0") already has a job actively RUNNING on the cluster
# right now, by scanning the live stdout/stderr log of every job this
# user currently has RUNNING for this gene (StdOut/StdErr under its own
# Logs/ directory - see Scheduler-Sub.sh) for that round's own
# alignment-directory name. "$aligner$suffix" (suffix dot-prefixed, or
# empty) mirrors GetAlignmentDirectory.sh's own naming exactly, so a
# running job's log contains it (e.g. in an "iqtree2 -s .../FAMSA.BigTree0/..."
# Command: line) whenever that job is genuinely building/refining this
# same round, regardless of which RogueIter_N it's currently on.
#
# Exists because GetResumeIteration.sh can only tell "not yet done"
# apart from "done" via the filesystem - it has no way to tell "still
# actively running" apart from "never started" (see its own header
# comment). Without this, restarting 16_TreeBuildScheduler.sh (e.g. to
# resubmit one crashed round by hand) risks resubmitting a duplicate job
# on top of a different round that's still genuinely mid-flight for the
# same gene, confirmed 2026-10-21 as a real risk when manually
# restarting PeptideReceptors' crashed BigTree5 while its BigTree0 round
# was still actively computing.
#
# Deliberately checks RUNNING jobs only, not PENDING ones: a duplicate
# PENDING submission just wastes a queue slot - harmless, since
# GetResumeIteration.sh's own filesystem check will see the first one's
# completion and skip the duplicate before it would ever actually start.
# A duplicate job that starts computing on the same live round's output
# is the real collision this guards against.
#
# Prints "true" and exits 0 if such a running job is found, exits 1 (no
# output) otherwise - use as `if "$DIR/IsRoundRunning.sh" ...; then`.

suffix=""

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
            suffix=".$1"
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

if [ -z "$gene" ] || [ -z "$aligner" ]
then
	echo "You must give a GeneName and an Aligner, for instance:" >&2
	echo "./$thisScript -g GeneName -a Aligner [-x Suffix]" >&2
	exit 1
fi

if ! command -v squeue >/dev/null 2>&1
then
	# No Slurm here (e.g. PBS) - nothing to check against, so don't
	# block the caller over a check this platform can't perform.
	exit 1
fi

geneName=$(basename "$gene")
pattern="${aligner}${suffix}/RogueIter_"

for jobID in $(squeue -u "$USER" -h -t RUNNING -o "%i" 2>/dev/null)
do
	jobInfo=$(scontrol show job "$jobID" 2>/dev/null)
	stdOut=$(echo "$jobInfo" | grep -oP 'StdOut=\K\S+')
	[[ "$stdOut" == *"/$geneName/Logs/"* ]] || continue
	stdErr=$(echo "$jobInfo" | grep -oP 'StdErr=\K\S+')
	if grep -qF -- "$pattern" "$stdOut" "$stdErr" 2>/dev/null
	then
		echo "true"
		exit 0
	fi
done

exit 1
