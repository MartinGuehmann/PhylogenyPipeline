#!/bin/bash

#PBS -l select=1:ncpus=4:mem=30gb
#PBS -l walltime=8:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to be loaded

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

seqsToAlign=$(cut -d " " -f ${PBS_ARRAY_INDEX} $seqFiles)

date
time "$DIR/../RunAll.sh" -g "$gene" -s "14" -i "$iteration" -a "PASTA" -f "$seqsToAlign" $suffix $previousAligner $trimAl
date
