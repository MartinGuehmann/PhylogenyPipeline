#!/bin/bash

#PBS -l select=1:ncpus=24:mem=187gb
#PBS -l walltime=24:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
module load apps/mafft/7.429

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
time "$DIR/../RunAll.sh" -g "$gene" -s "9" -i "$iteration" -a "LINSI" -f "$seqsToAlign" $suffix $previousAligner $trimAl
date
