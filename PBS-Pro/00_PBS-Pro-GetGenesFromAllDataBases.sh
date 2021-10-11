#!/bin/bash

# We either need the maximum number of nodes
# or more than we have database otherwise
# we would use more nodes than allowed
#PBS -l select=1:ncpus=24:mem=187gb
#PBS -l walltime=72:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
module load apps/blast/2.11.0+

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "0"
date
