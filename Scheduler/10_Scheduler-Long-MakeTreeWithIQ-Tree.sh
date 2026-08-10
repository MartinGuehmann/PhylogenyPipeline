#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_IQTREE

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

# Normally unset - this script is meant for a single whole-dataset
# alignment (BigTree/allSeqs), passed directly as $alignmentToUse via
# -v. Added 2026-08-10 so noTrimAl array jobs can also be routed
# through this script's 72h walltime budget instead of the regular
# 24h one (see Resources.cfg's own comment on 10_Scheduler-
# MakeTreeWithIQ-Tree.sh) without needing a second near-duplicate
# script - same array-index resolution as that script, copied
# verbatim, harmless no-op when $alignmentFiles isn't set.
if [ ! -z $alignmentFiles ]
then
	alignmentToUse=$(cut -d " " -f $("$DIR/Scheduler-GetArrayIndex.sh") $alignmentFiles)
fi

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "10" -i "$iteration" -a "$aligner" -f "$alignmentToUse" $suffix $previousAligner
status=$?
sstat -j "$SLURM_JOB_ID.batch" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
