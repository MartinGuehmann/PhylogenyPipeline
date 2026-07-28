#!/bin/bash

# makeblastdb does not care about the number of CPUs
# assigns, it seems to just to try to use all on the
# machine, so go with the maximum number od CPUs on
# the node and also take the all the memory, even so
# not needed.

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
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

# $localDatabases is set via this job's --export (see Scheduler-Call.sh's
# step-0 case) - a colon-separated list of Databases.sh's RemoteDataBases
# names (e.g. "nr:refseq_protein") already combined there from whichever
# --local* flags the Scheduler-00-ExtractSequences.sh caller passed;
# unset/empty here means the default, all-remote behavior. Already in its
# final form, so just forwarded on as-is - unlike the old single-database
# $localNr "true"/flag translation this replaced, there's no per-database
# boilerplate to repeat here.
date >&2
time "$DIR/../RunAll.sh" -g "$gene" -s "0" --localDatabases "$localDatabases"
status=$?
sstat -j "$SLURM_JOB_ID.batch" --format=JobID,MaxRSS,AveCPU,MaxVMSize -n 2>&1 >&2
date >&2
exit $status
