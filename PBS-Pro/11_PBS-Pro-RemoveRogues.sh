#!/bin/bash

#PBS -l select=1:ncpus=8:mem=8gb
#PBS -l walltime=1:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Modules to load, TreeShrink does not work with R >= 4.0
# And we need Phython 2.7
module load lang/r/3.6.1
module load lang/python/anaconda/2.7-2019.10

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "11" -l "11" -i "$iteration" -a "$aligner" $shuffleSeqs $suffix $previousAligner
date
