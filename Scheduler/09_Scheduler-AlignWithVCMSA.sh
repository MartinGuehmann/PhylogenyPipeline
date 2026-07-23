#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_PYTHON_VCMSA

# Create the vcmsa_env conda environment if it isn't there yet (once per
# cluster, not managed by conda modules the way the other aligners are -
# see get_vcmsa_env.sh). Unlike nr, there's no fallback aligner to
# degrade to here, so a build failure fails this job outright instead of
# limping on with the wrong environment (or none) active.
if ! "$DIR/../get_vcmsa_env.sh"
then
	echo "Failed to get/build the vcmsa_env conda environment" >&2
	exit 1
fi

conda activate vcmsa_env

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
time "$DIR/../RunAll.sh" -g "$gene" -s "9" -i "$iteration" -a "VCMSA" -f "$seqsToAlign" $suffix $previousAligner $trimAl
status=$?
date >&2
exit $status
