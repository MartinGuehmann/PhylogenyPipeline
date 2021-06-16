#!/bin/bash

#PBS -l select=1:ncpus=8:mem=8gb
#PBS -l walltime=1:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to load, we use the standard python3

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "12" -i "$iteration" -a "$aligner" $suffix $extension $update $updateBig $ignoreIfMasterFileDoesNotExist
date
