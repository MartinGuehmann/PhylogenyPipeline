#!/bin/bash

#PBS -l select=1:ncpus=1:mem=8gb
#PBS -l walltime=2:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to load

DIR="$1"

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
gene="$2"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

date
time "$DIR/../RunAll.sh" "$gene" "1" "1"
date
