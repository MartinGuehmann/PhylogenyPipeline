#!/bin/bash

# makeblastdb does not care about the number of CPUs
# assigns, it seems to just to try to use all on the
# machine, so go with the maximum number od CPUs on
# the node.
# So if you need to rebuild the protein databases here,
# increase ncpus to the maximum and also the wall time.

# We need quite some time since we
# interact with the server of NCBI
#PBS -l select=1:ncpus=8:mem=8gb
#PBS -l walltime=8:00:00

# Go to the first program line,
# any PBS directive below that is ignored.
# Load modules
#efetch from e-utilities is missing
# In principle we just need the uniprot fasta files
# but erroring because makeblastdb is not there, is
# not nice. Even so pipeline should continue without
# further errors.
module load apps/blast/2.11.0+

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
