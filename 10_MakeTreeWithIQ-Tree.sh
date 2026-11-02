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

inputAlignment="$1"

if [[ -z "$inputAlignment" ]]
then
	echo "You must give a InputAlignmentFile, for instance:" >&2
	echo "./$thisScript InputAlignmentFile.fasta" >&2
	exit 1
fi

numTreads=$(nproc)

# IQ-Tree truncates "$inputAlignment.log" the moment it starts, before it
# even checks its own checkpoint - so a resubmit of an already-finished
# alignment (e.g. this array task got resubmitted after a sibling task in
# the same job array failed) clobbers the real, complete log with just a
# few startup lines before IQ-Tree notices the checkpoint and bails out.
# Back it up first and restore it in that case so the original run's full
# log (model selection, bootstrap summary, timing, etc.) survives.
logFile="$inputAlignment.log"
logBackup=""
if [ -f "$logFile" ]
then
	logBackup=$(mktemp)
	cp "$logFile" "$logBackup"
fi

# Capture stderr separately (without disturbing stdout, which Slurm
# still streams straight to the job's .out log) so a resubmit of an
# already-finished alignment can be told apart from a real failure.
# IQ-Tree exits non-zero (observed: 2) and refuses to redo the analysis
# when its own checkpoint file shows this exact alignment already
# finished successfully in an earlier run (e.g. this array task got
# resubmitted after a sibling task in the same job array failed) -
# that's not a new failure, it's confirmation the earlier output is
# already valid, so it must not fail this step.
iqtreeStderr=$(mktemp)
iqtree2 -s "$inputAlignment" -B 1000 --abayes --alrt 1000 -m TEST -nt $numTreads -ntmax $numTreads --boot-trees 2>"$iqtreeStderr"
status=$?
cat "$iqtreeStderr" >&2

if [ $status -ne 0 ] && grep -q "indicates that a previous run successfully finished" "$iqtreeStderr"
then
	echo "$inputAlignment: IQ-Tree's checkpoint shows a previous run already finished successfully - treating as done, not as a failure." >&2
	status=0
	if [ -n "$logBackup" ]
	then
		mv "$logBackup" "$logFile"
		logBackup=""
	fi
fi

rm -f "$iqtreeStderr" "$logBackup"
exit $status
