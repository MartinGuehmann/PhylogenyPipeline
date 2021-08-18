#!/bin/bash

# We need quite some time since we
# interact with the server of NCBI
#PBS -l select=1:ncpus=8:mem=8gb
#PBS -l walltime=60:00:00

# 60h, since we may have to download and build the uniprot databases 

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
#efetch from e-utilities is missing

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

date
time "$DIR/../RunAll.sh" -g "$gene" -s "3"
date
