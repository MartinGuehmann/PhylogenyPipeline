#!/bin/bash

#PBS -l select=1:ncpus=1:mem=100gb
#PBS -l walltime=24:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to load

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "7"
date
