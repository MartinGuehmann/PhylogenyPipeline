#!/bin/bash

#PBS -l select=1:ncpus=8:mem=60gb
#PBS -l walltime=24:00:00

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
time "$DIR/../RunAll.sh" "$gene" "9" "9" "$iteration" "PASTA" "$seqsToAlign"
date
