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
modelRepo="Rostlab/prot_t5_xl_uniref50"
modelDir="$DIR/../Models/prot_t5_xl_uniref50"

source "$DIR/Lock-Dir.sh"
source "$DIR/Conda-Env-Python.sh"

# acquireLockDir's mkdir needs $modelDir's parent to already exist -
# confirmed 2026-08-07: without this, a first-ever run (nothing has
# created Models/ before) made mkdir fail every single retry with
# "No such file or directory", which acquireLockDir couldn't tell apart
# from genuine contention at the time - a silent, unrecoverable hang for
# over an hour with zero CPU anywhere. Lock-Dir.sh itself is now
# hardened to fail loudly instead of retrying forever over that class of
# error, but this still needs to actually exist rather than relying on
# that as a safety net.
mkdir -p "$(dirname "$modelDir")"

# Only one process at a time may check/download this model - same
# reasoning as get_ncbi_blastdb.sh's/get_vcmsa_env.sh's lock (two gene
# pipelines both needing it before either has fetched it yet must not
# both save_pretrained into the same directory at once). A second
# process just blocks on the lock until the first is done, then finds
# the model already there and skips straight past the check below.
# staleAfterSeconds generous (6h) - this is one ~11GB Hugging Face
# download, not vcmsa_env's own much larger multi-package build.
#
# Release via an EXIT trap, not just a plain call after the subshell
# below - see get_vcmsa_env.sh's identical lock for why: a plain call
# there never ran when a task got killed mid-build, orphaning the lock
# for everyone else until its full staleAfterSeconds elapsed.
if ! acquireLockDir "$modelDir.lockdir" 21600
then
	echo "Failed to acquire $modelDir.lockdir - see acquireLockDir's own error above" >&2
	exit 1
fi
trap 'releaseLockDir "$modelDir.lockdir"' EXIT
(

# $modelDir/config.json existing alone isn't enough - same "existence
# isn't the same as complete" reasoning as this pipeline's other
# get_*.sh scripts: a job killed mid-save_pretrained (walltime,
# scancel, node failure) can leave a partial directory behind.
# $modelDir.ok is only touched right after both save_pretrained calls
# below actually succeed.
if [ -f "$modelDir/config.json" ] && [ -f "$modelDir.ok" ]
then
	exit 0
fi

if ! command -v conda >/dev/null 2>&1
then
	echo "conda not found - cannot download $modelRepo into $modelDir" >&2
	exit 1
fi

# transformers/torch aren't part of the general Nix devShell's own
# python (flake.nix's pythonWithEte3 only carries ete3/biopython/
# pandas/matplotlib/logomaker) - $envName is the only place on this
# cluster with them installed, since vcMSA's own environment.txt pins
# them. get_vcmsa_env.sh must have already built $envName by the time
# this runs.
pythonPath=$(condaEnvPython "$envName")
if [ -z "$pythonPath" ]
then
	echo "$envName conda environment not found - cannot download $modelRepo (needs its own transformers/torch install; get_vcmsa_env.sh must run first)" >&2
	exit 1
fi

# Wipe any partial leftover before retrying - save_pretrained doesn't
# itself guard against writing into a directory that already has some
# (but not all) of a previous attempt's files.
rm -rf "$modelDir" "$modelDir.ok"

# vcMSA's own README ("Downloading a language model from Huggingface")
# documents fetching this exact model this way - both the tokenizer and
# the model itself, saved into the same local directory, so vcmsa can
# be pointed at a plain local path (-m) instead of needing network
# access or a Hub repo-id lookup at alignment time (09_AlignWithVCMSA.sh
# passes $DIR/../Models/prot_t5_xl_uniref50 as -m). env -u PYTHONPATH
# for the same reason as get_vcmsa_env.sh's own python/pip calls - see
# Conda-Env-Python.sh for why that's needed even with an absolute path.
if ! env -u PYTHONPATH "$pythonPath" -c "
from transformers import T5Tokenizer, T5Model
tokenizer = T5Tokenizer.from_pretrained('$modelRepo')
tokenizer.save_pretrained('$modelDir')
model = T5Model.from_pretrained('$modelRepo')
model.save_pretrained('$modelDir')
"
then
	echo "Failed to download $modelRepo into $modelDir" >&2
	rm -rf "$modelDir"
	exit 1
fi

touch "$modelDir.ok"
)
status=$?

exit $status
