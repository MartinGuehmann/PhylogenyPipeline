#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
# No modules to be loaded

source "$DIR/Enter-NixDevShell.sh"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

seqsToAlign=$(cut -d " " -f $("$DIR/Scheduler-GetArrayIndex.sh") $seqFiles)

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "14" -i "$iteration" -a "PASTA" -f "$seqsToAlign" $suffix $previousAligner $trimAl
status=$?
sstat -j "$SLURM_JOB_ID.batch" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
