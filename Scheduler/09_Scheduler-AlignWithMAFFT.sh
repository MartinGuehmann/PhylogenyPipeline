#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Load-Module.sh"
load_module MODULE_MAFFT

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

date
time "$DIR/../RunAll.sh" -g "$gene" -s "9" -i "$iteration" -a "MAFFT" -f "$seqsToAlign" $suffix $previousAligner $trimAl
date
