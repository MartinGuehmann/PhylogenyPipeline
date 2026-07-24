#!/bin/bash

# makeblastdb does not care about the number of CPUs
# assigns, it seems to just to try to use all on the
# machine, so go with the maximum number od CPUs on
# the node.
# So if you need to rebuild the protein databases here,
# increase ncpus to the maximum and also the wall time.

# We need quite some time since we
# interact with the server of NCBI

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
#efetch from e-utilities is missing
# In principle we just need the uniprot fasta files
# but erroring because makeblastdb is not there, is
# not nice. Even so pipeline should continue without
# further errors.
source "$DIR/Enter-NixDevShell.sh"
source "$DIR/Load-Module.sh"
load_module MODULE_BLAST

thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

# $localNr is set via this job's --export (see Scheduler-Call.sh's step-3
# case), only when the original Scheduler-00-ExtractSequences.sh caller
# passed --localNr - unset/empty here means the default, unchanged remote
# nr.
# Scheduler-Call.sh deliberately hands this over as the fixed string
# "true", not the "--localNr" flag string itself (bash has no actual
# boolean type, so this is just a literal both ends agree on) - translate
# it back into the flag form here, since everything downstream of this
# job (RunAll.sh/03_ExtractSequences.sh) is CLI-argument-driven again,
# not environment-variable-driven.
localNrFlag=""
[ "$localNr" == "true" ] && localNrFlag="--localNr"

date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "3" $localNrFlag
status=$?
sstat -j "$SLURM_JOB_ID" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
