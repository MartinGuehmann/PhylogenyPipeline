#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Check-InputFile.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_IQTREE

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

# Unlike 10_Scheduler-Long-MakeTreeWithIQ-Tree.sh, this step is never
# resubmitted for another round - Scheduler-10-RogueOptTree.sh's self-
# resubmission loop (driven by numRoundsLeft) only ever calls steps
# 10/11/12. This step is meant to run on whichever single alignment the
# user has decided is a gene's final, converged tree (checked by hand -
# e.g. the highest existing RogueIter_N directory once no further round
# is planned), so $alignmentToUse is always passed explicitly via -v,
# never resolved from an array job.
#
# If this job hits its 72h walltime before PMSF's search finishes, it
# does get resubmitted automatically - but only if submitted via
# Scheduler-18-RefineTreeWithPMSF.sh (not directly via Scheduler-Call.sh
# -s 18), which wraps this job in the same sacct-driven resubmit-on-
# TIMEOUT chain Scheduler-10-RogueOptTree.sh uses for its own round
# chain. 18_RefineTreeWithPMSF.sh resumes from IQ-Tree's own checkpoint
# on each resubmission rather than starting over (see that script's own
# header comment), which is what makes an open-ended chain like this
# safe to leave unattended.
checkInputFile "$alignmentToUse"

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "18" -i "$iteration" -a "$aligner" -f "$alignmentToUse" $suffix $previousAligner
status=$?
sstat -j "$SLURM_JOB_ID.batch" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
