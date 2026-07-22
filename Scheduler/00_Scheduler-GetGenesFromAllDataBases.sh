#!/bin/bash

# makeblastdb does not care about the number of CPUs
# assigns, it seems to just to try to use all on the
# machine, so go with the maximum number od CPUs on
# the node and also take the all the memory, even so
# not needed.

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_BLAST

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

# $localNr is set via this job's --export (see Scheduler-Call.sh's step-0
# case), only when the Scheduler-00-ExtractSequences.sh caller passed
# --localNr - unset/empty here means the default, unchanged remote nr.
localNrFlag=""
[ "$localNr" == "true" ] && localNrFlag="--localNr"

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "0" $localNrFlag
date >&2
