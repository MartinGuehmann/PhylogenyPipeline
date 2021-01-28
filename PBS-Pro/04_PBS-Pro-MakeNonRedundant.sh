#!/bin/bash

#PBS -l select=1:ncpus=8:mem=8gb
#PBS -l walltime=4:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
# cd-hit missing

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "4" -l "4"
date
