#!/bin/bash

#PBS -l select=1:ncpus=24:mem=32gb
#PBS -l walltime=12:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
module add apps/iqtree/2.0.6

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "10" -l "10" -i "$iteration" -a "$aligner" -f "$alignmentToUse" $suffix
date
