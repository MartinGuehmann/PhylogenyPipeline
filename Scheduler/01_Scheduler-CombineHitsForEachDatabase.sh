#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
# No modules to load

source "$DIR/Enter-NixDevShell.sh"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "1"
status=$?
date >&2
exit $status
