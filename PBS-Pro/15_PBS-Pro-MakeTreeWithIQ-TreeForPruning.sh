#!/bin/bash

#PBS -l select=1:ncpus=8:mem=32gb
#PBS -l walltime=20:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
module add apps/iqtree/2.0.6

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

alignmentToUse=$(cut -d " " -f $("$DIR/Schel-GetArrayIndex.sh") $alignmentFiles)

date
time "$DIR/../RunAll.sh" -g "$gene" -s "15" -f "$alignmentToUse"
date
