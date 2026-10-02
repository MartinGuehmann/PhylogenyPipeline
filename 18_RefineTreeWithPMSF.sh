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
	echo "You must give a InputAlignmentFile that already has a completed IQ-Tree run (its .treefile is used as the PMSF guide tree), for instance:" >&2
	echo "./$thisScript InputAlignmentFile.fasta" >&2
	exit 1
fi

guideTree="$inputAlignment.treefile"

if [[ ! -f "$guideTree" ]]
then
	echo "$guideTree does not exist - run step 10/15 on $inputAlignment first, this step only refines an already-built tree." >&2
	exit 1
fi

numTreads=$(nproc)

# PMSF (posterior mean site frequency) refinement pass. Meant to be run
# once, manually, on whichever single alignment+tree the user has
# decided is a gene's final result (e.g. the last rogue-removal round)
# - unlike step 10, this is never part of the automatic round-
# resubmission chain (Scheduler-10-RogueOptTree.sh), see
# 18_Scheduler-RefineTreeWithPMSF.sh's own header comment.
#
# -ft only uses $guideTree to build PMSF's site-frequency profile;
# IQ-Tree then runs its own independent multi-start search under the
# mixture model rather than refining $guideTree's exact topology
# (confirmed empirically during feasibility testing - starting-tree
# flags -t/-te were deliberately left out for this reason). -m LG+C20+F+G,
# -B 1000, --alrt 1000, --abayes and -nt (no -ntmax, no --boot-trees)
# match exactly what was feasibility-tested locally, not guessed. -pre
# keeps this run's output under its own prefix so it can't collide with
# or overwrite the original standard-model round's own output files
# living in the same directory.
#
# Same checkpoint-aware exit-status handling as 10_MakeTreeWithIQ-
# Tree.sh: IQ-Tree exits non-zero and refuses to redo the analysis when
# its own checkpoint shows this exact run already finished successfully
# (e.g. after a resubmission following a walltime timeout) - that is
# confirmation of success, not a new failure. Doubly relevant here since
# a PMSF run is expensive enough to plausibly span multiple walltime-
# limited resubmissions (see Resources.cfg's comment on this script) -
# rerunning this same script with the same arguments resumes from
# IQ-Tree's own checkpoint automatically, no extra flag needed.
iqtreeStderr=$(mktemp)
iqtree2 -s "$inputAlignment" -ft "$guideTree" -m LG+C20+F+G -B 1000 --abayes --alrt 1000 -nt $numTreads -pre "$inputAlignment.pmsf" 2>"$iqtreeStderr"
status=$?
cat "$iqtreeStderr" >&2

if [ $status -ne 0 ] && grep -q "indicates that a previous run successfully finished" "$iqtreeStderr"
then
	echo "$inputAlignment: IQ-Tree's checkpoint shows a previous PMSF run already finished successfully - treating as done, not as a failure." >&2
	status=0
fi

rm -f "$iqtreeStderr"
exit $status
