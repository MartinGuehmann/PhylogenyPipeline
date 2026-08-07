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

source "$DIR/Lock-Dir.sh"

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

# `conda run -n "$envName" <name>` resolves <name> by modifying PATH and
# then doing a normal command-name lookup - confirmed 2026-08-07 that
# this isn't reliable inside this Nix devShell: `conda run -n vcmsa_env
# python -m pip install ...` resolved "python" itself to a bare Nix-store
# Python 3.14 with no pip module at all, not vcmsa_env's own conda
# Python 3.9, even though earlier runs' `conda run -n vcmsa_env python
# -c "import ..."` checks had reliably hit the right interpreter -
# proving that lookup isn't safe to trust either, not just the `pip`
# lookup a previous fix here tried to route around. Resolve the env's
# own interpreter by absolute path instead, via plain `conda env list`
# (not `conda run` - every plain conda invocation in this script, e.g.
# removeStaleEnv's `conda config --show`, has been reliable throughout
# this investigation; it's specifically conda run's PATH-search step
# that isn't), so every python/pip call below runs the exact binary
# this script means, with no name lookup left for anything else on PATH
# to win a race against. Echoes nothing (caller sees an empty string) if
# $envName doesn't exist yet.
envPython() {
	local prefix
	prefix=$(conda env list | awk -v n="$envName" '$1 == n { print $NF; exit }')
	[ -n "$prefix" ] && echo "$prefix/bin/python"
}

# Only one process at a time may check/create this environment - same
# reasoning as get_ncbi_blastdb.sh's/get_uniprot_database.sh's lock (two
# gene pipelines both needing vcmsa_env before either has created it yet
# must not both run conda create into it at once). A second process just
# blocks on the lock until the first is done, then finds the environment
# already there and skips straight past the check below.
#
# Release via an EXIT trap, not just a plain call after the subshell
# below - confirmed 2026-08-06: a task scancelled while inside that
# subshell (e.g. mid conda-create) kills this parent script too, with
# no trap installed nothing ever ran the plain call that used to sit
# after it, leaving the lock orphaned for other tasks to sit out its
# full staleAfterSeconds even though its holder was already dead. EXIT
# fires on every exit path - normal, `exit $status` below, or killed by
# a signal - so the lock comes free as soon as this script actually
# does, not after a timeout guessing that it might have.
acquireLockDir "$DIR/get_vcmsa_env.lockdir"
trap 'releaseLockDir "$DIR/get_vcmsa_env.lockdir"' EXIT
(

if ! command -v conda >/dev/null 2>&1
then
	echo "conda not found - cannot check for or create the $envName environment" >&2
	exit 1
fi

# A bare "does an env with this name exist" check (e.g. parsing `conda
# env list`) isn't enough - same reasoning as blastdbcmd -info elsewhere
# in this pipeline: existence isn't the same as usable. A previous
# attempt could have created the env but failed partway through
# installing vcmsa itself. Checking that the vcmsa command is merely on
# PATH isn't enough either - confirmed 2026-08-06: it was, but every
# task of a 26-task array still died with "ModuleNotFoundError: No
# module named 'combat'" the moment vcmsa's own code ran, since that's
# imported by vcmsa_utils.py but never installed (see the combat
# install below). Actually import vcmsa's own top-level module instead,
# so a partially-broken env like that one gets caught and rebuilt below
# rather than waved through.
pythonPath=$(envPython)
if [ -n "$pythonPath" ] && "$pythonPath" -c "import vcmsa.vcmsa_utils" >/dev/null 2>&1
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
# own repo - clone just to get environment.txt. Per vcMSA's own install
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

pythonPath=$(envPython)
if [ -z "$pythonPath" ]
then
	echo "$envName was just created but doesn't show up in \`conda env list\` afterward - cannot resolve its own python to install into" >&2
	removeStaleEnv
	exit 1
fi

# The package is NOT actually published on PyPI despite the README's
# "vcmsa can be directly installed ... from pypi" claim - `pip install
# vcmsa` 404s (confirmed 2026-07-31: "Could not find a version that
# satisfies the requirement vcmsa (from versions: none)" on every one
# of a 26-task array). Install from the clone already sitting here
# instead, same as the README's own "install from source" fallback
# (`cd vcmsa && python setup.py install`) - `pip install <dir>` is the
# modern equivalent and needs no extra network access beyond the clone
# already done above.
if ! "$pythonPath" -m pip install "$cloneDir/vcmsa"
then
	echo "pip install of the cloned vcmsa source failed inside $envName - removing the incomplete environment so the next attempt starts fresh instead of finding a half-installed one" >&2
	removeStaleEnv
	exit 1
fi

# vcMSA's own vcmsa_utils.py does `from combat.pycombat import pycombat`,
# but neither its setup.py (no install_requires at all) nor its
# environment.txt actually declares this - confirmed 2026-08-06: every
# task of a 26-task array died with "ModuleNotFoundError: No module
# named 'combat'" the moment vcmsa's code ran. The PyPI package that
# provides this import is called "combat" (not "pycombat" - that name
# is taken by an unrelated package on PyPI).
if ! "$pythonPath" -m pip install combat
then
	echo "pip install of combat (vcmsa's own undeclared dependency) failed inside $envName - removing the incomplete environment so the next attempt starts fresh instead of finding a half-installed one" >&2
	removeStaleEnv
	exit 1
fi

# vcMSA's own environment.txt pins icecream 2.1.3 and executing 1.2.0
# (confirmed matching its requirements.txt too), and that exact pair
# does import cleanly - confirmed 2026-08-06 in an isolated venv. But
# on the cluster, `conda create --file environment.txt` sometimes still
# ends up with an executing that's incompatible with icecream
# (`AttributeError: module 'executing' has no attribute 'Source'`,
# icecream/icecream.py's own `class Source(executing.Source)` failing
# at import), the same "conda create doesn't reliably land on the
# versions its own explicit environment.txt asked for" territory as
# the combat gap above. Root cause on the conda side unconfirmed - not
# worth chasing further given pip can just directly force the known-
# good pair regardless of what conda's own resolution produced.
if ! "$pythonPath" -m pip install "icecream==2.1.3" "executing==1.2.0"
then
	echo "pip install of icecream/executing (pinning them to vcmsa's own known-compatible versions) failed inside $envName - removing the incomplete environment so the next attempt starts fresh instead of finding a half-installed one" >&2
	removeStaleEnv
	exit 1
fi

# Every step above can succeed individually and the result can still be
# unusable - confirmed 2026-08-06: this exact sequence completed with
# no errors and still left `from Bio.Align import MultipleSeqAlignment`
# broken inside vcmsa_utils.py (vcMSA's own environment.txt pins
# biopython 1.80, which does have that symbol when installed via pip
# directly - so this isn't a wrong-version-pinned gap like combat/
# icecream/executing above, still being root-caused). Whatever the next
# such gap turns out to be, re-run the exact same usability check used
# at the top of this script to decide whether to rebuild in the first
# place, so a still-broken environment is caught and reported HERE -
# once, clearly, with the real traceback - instead of every waiting
# task inheriting the same silently-broken environment and each only
# discovering it later, deep inside its own real alignment run.
importCheckOutput=$("$pythonPath" -c "import vcmsa.vcmsa_utils" 2>&1)
if [ $? -ne 0 ]
then
	echo "$envName was rebuilt without any individual step failing, but vcmsa.vcmsa_utils still doesn't import cleanly - removing the environment rather than leaving a silently-broken one for the next attempt to find. Traceback:" >&2
	echo "$importCheckOutput" >&2
	removeStaleEnv
	exit 1
fi
)
status=$?

exit $status
