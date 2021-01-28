#!/bin/bash

#PBS -l select=1:ncpus=24:mem=100gb
#PBS -l walltime=4:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to be loaded

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "9" -l "9" -i "$iteration" -a "FAMSA" -f "$seqsToAlign"
date
