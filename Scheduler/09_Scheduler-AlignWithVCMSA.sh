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

# Enter-NixDevShell.sh (sourced above, needed further down for RunAll.sh's
# raxml-ng/seqkit post-processing) leaves PYTHONPATH pointing at Nix's own
# Python 3.14 site-packages, including its numpy build. conda activate
# doesn't clear that - it only prepends vcmsa_env's own bin/lib to PATH -
# so the env's Python 3.9 `vcmsa` script still finds the Nix-built numpy
# first and dies importing a cpython-314 .so from cpython-39 ("No module
# named 'numpy._core._multiarray_umath'"), confirmed 2026-08-02 on every
# task of a 26-task array. Nothing downstream of here is Python, so
# clearing it is safe - raxml-ng/seqkit resolve via PATH, not PYTHONPATH.
unset PYTHONPATH

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
sstat -j "$SLURM_JOB_ID.batch" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
