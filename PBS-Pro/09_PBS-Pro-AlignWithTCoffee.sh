#!/bin/bash

#PBS -l select=1:ncpus=24:mem=24gb
#PBS -l walltime=8:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
module load apps/tcoffee/13.41.0

DIR="$1"

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
gene="$2"

seqsToAlign="$3"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

date
time "$DIR/../RunAll.sh" "$gene" "9" "9" "$seqsToAlign"
date
