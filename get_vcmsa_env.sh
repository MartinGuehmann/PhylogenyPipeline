#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

envName="vcmsa_env"
repoURL="https://github.com/clairemcwhite/vcmsa.git"

# `conda env remove` refuses to touch a directory that exists but isn't
# recognized as a valid conda environment (e.g. missing conda-meta/,
# from a `conda create` that got interrupted before ever finishing) -
# confirmed 2026-07-27 on the cluster ("EnvironmentLocationNotFound:
# Not a conda environment"), so it's not enough on its own to clear the
# exact kind of leftover this is meant to guard against. Fall back to
# removing the directory directly wherever conda would have put a named
# env, since by the time this is called we already know it's not
# usable. Parses envs_dirs from `conda config --show` rather than
# hardcoding a path, since that's user/cluster-specific.
removeStaleEnv() {
	conda env remove -y -n "$envName" >/dev/null 2>&1
	for envsDir in $(conda config --show envs_dirs | sed -n 's/^[[:space:]]*-[[:space:]]*//p')
	do
		rm -rf "$envsDir/$envName"
	done
}

# Only one process at a time may check/create this environment - same
# reasoning as get_nr_database.sh's/get_uniprot_database.sh's lock (two
# gene pipelines both needing vcmsa_env before either has created it yet
# must not both run conda create into it at once). A second process just
# blocks on the lock until the first is done, then finds the environment
# already there and skips straight past the check below.
(
flock -x 200

if ! command -v conda >/dev/null 2>&1
then
	echo "conda not found - cannot check for or create the $envName environment" >&2
	exit 1
fi

# A bare "does an env with this name exist" check (e.g. parsing `conda
# env list`) isn't enough - same reasoning as blastdbcmd -info elsewhere
# in this pipeline: existence isn't the same as usable. A previous
# attempt could have created the env but failed partway through
# installing vcmsa itself. Check that the actual command is on PATH
# inside the environment instead.
if conda run -n "$envName" command -v vcmsa >/dev/null 2>&1
then
	exit 0
fi

# The check above only tells us this env isn't usable - it may still
# exist as a stale/partial leftover (e.g. an earlier attempt got killed
# before the pip-install-failure cleanup further down could run, or
# before this script existed at all). `conda create` refuses to write
# into an already-existing prefix regardless of whether it's actually
# usable ("CondaValueError: prefix already exists"), confirmed
# 2026-07-27 blocking every one of a 26-task array identically. Clear
# out anything left at this name first, so create always starts fresh.
# A no-op if nothing is there yet.
removeStaleEnv

# vcMSA doesn't publish its conda environment spec on PyPI, only in its
# own repo - clone just to get environment.txt, then install the actual
# vcmsa package from PyPI as normal. Per vcMSA's own install
# instructions (see README's "Porting to a new cluster" section): use
# -n here, not vcMSA's own suggested --prefix vcmsa_env -
# 09_Scheduler-AlignWithVCMSA.sh activates the env by bare name
# (`conda activate vcmsa_env`), which only a named env (registered in
# conda's envs_dirs) resolves correctly regardless of the job's working
# directory.
cloneDir=$(mktemp -d)
trap 'rm -rf "$cloneDir"' EXIT

if ! git clone --depth 1 "$repoURL" "$cloneDir/vcmsa"
then
	echo "Failed to clone $repoURL to fetch $envName's environment.txt" >&2
	exit 1
fi

if [ ! -f "$cloneDir/vcmsa/environment.txt" ]
then
	echo "$cloneDir/vcmsa/environment.txt not found after cloning $repoURL - vcMSA may have changed its repo layout" >&2
	exit 1
fi

if ! conda create -y -n "$envName" --file "$cloneDir/vcmsa/environment.txt"
then
	echo "conda create failed for $envName" >&2
	exit 1
fi

if ! conda run -n "$envName" pip install vcmsa
then
	echo "pip install vcmsa failed inside $envName - removing the incomplete environment so the next attempt starts fresh instead of finding a half-installed one" >&2
	removeStaleEnv
	exit 1
fi
) 200>"$DIR/get_vcmsa_env.lock"
status=$?

wait # Wait until all are done

exit $status
