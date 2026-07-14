#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
source "$DIR/Load-Module.sh"
load_module MODULE_IQTREE

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

if [ ! -z $alignmentFiles ]
then
	alignmentToUse=$(cut -d " " -f $("$DIR/Scheduler-GetArrayIndex.sh") $alignmentFiles)
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "10" -i "$iteration" -a "$aligner" -f "$alignmentToUse" $suffix $previousAligner
date
