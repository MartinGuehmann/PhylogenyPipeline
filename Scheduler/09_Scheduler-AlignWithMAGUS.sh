#!/bin/bash

#PBS -l select=1:ncpus=4:mem=30gb
#PBS -l walltime=24:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
module load lang/python/anaconda/3.8.8-2021.05-2.5
# You also need to install dendropy
# Installs dendropy for the current user and the selected python version
# python3 -m pip install --user  -U dendropy

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

if [ ! -z $seqFiles ]
then
	seqsToAlign=$(cut -d " " -f $("$DIR/Scheduler-GetArrayIndex.sh") $seqFiles)
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "9" -i "$iteration" -a "MAGUS" -f "$seqsToAlign" $suffix $previousAligner $trimAl
date
