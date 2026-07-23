#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_PYTHON_MAGUS
# You also need to install dendropy
# Installs dendropy for the current user and the selected python version
# python3 -m pip install --user  -U dendropy

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

if [ ! -z $seqFiles ]
then
	seqsToAlign=$(cut -d " " -f $("$DIR/Scheduler-GetArrayIndex.sh") $seqFiles)
fi

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "9" -i "$iteration" -a "MAGUS" -f "$seqsToAlign" $suffix $previousAligner $trimAl
status=$?
sstat -j "$SLURM_JOB_ID" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
