#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
# TreeShrink does not work with R >= 4.0, and needs Python 2.7
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_R
load_module MODULE_PYTHON_TREESHRINK

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "11" -i "$iteration" -a "$aligner" $shuffleSeqs $suffix $previousAligner $restore
date >&2
