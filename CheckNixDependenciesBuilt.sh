#!/bin/bash

# Fails fast if Nix is available but BuildNixDependencies.sh's GC roots
# (.nix-gcroots/, see that script's own comments) are missing or broken,
# instead of letting a Slurm array job discover it many minutes later on
# a compute node - confirmed 2026-07-29 on Mas1: a 26-task PASTA array
# all failed the same way because a store path referenced by a symlink
# baked into an already-built derivation (PASTA's tool directory, pointed
# at raxmlHPC) had been garbage-collected out from under it. Meant to be
# sourced (not run in a subshell) near the top of Scheduler-Call.sh, so
# that a missing/broken GC root can exit the calling script before it
# submits anything.
#
# Does nothing (exit 0) if Nix (or nix-portable) is not on PATH at all -
# same "Nix is a fallback, never a requirement" stance as
# Scheduler/Enter-NixDevShell.sh, for clusters that rely entirely on
# `module load` or a manual PATH install instead.

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  checkNixDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$checkNixDIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
checkNixDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# A multi-user Nix install isn't on PATH until its profile scripts are
# sourced - harmless to source these if they don't apply here, since each
# is only sourced when present (same pattern as BuildNixDependencies.sh).
for profileScript in \
	/nix/var/nix/profiles/default/etc/profile.d/nix.sh \
	/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
do
	[ -f "$profileScript" ] && . "$profileScript"
done

checkNixCmd=""
if command -v nix >/dev/null 2>&1
then
	checkNixCmd="nix"
elif command -v nix-portable >/dev/null 2>&1
then
	checkNixCmd="nix-portable nix"
fi

if [ -n "$checkNixCmd" ]
then
	gcRootDir="$checkNixDIR/.nix-gcroots"

	if [ ! -d "$gcRootDir" ] || [ -z "$(ls -A "$gcRootDir" 2>/dev/null)" ]
	then
		echo "Nix is on PATH but $gcRootDir does not exist or is empty." >&2
		echo "Run $checkNixDIR/BuildNixDependencies.sh once before submitting jobs." >&2
		exit 1
	fi

	# -xtype l finds symlinks whose target does not exist (dangling) -
	# exactly what a garbage-collected store path leaves behind.
	brokenRoots=$(find "$gcRootDir" -xtype l 2>/dev/null)
	if [ -n "$brokenRoots" ]
	then
		echo "Some Nix GC roots in $gcRootDir are broken (their store path was garbage-collected):" >&2
		echo "$brokenRoots" >&2
		echo "Run $checkNixDIR/BuildNixDependencies.sh again before submitting jobs." >&2
		exit 1
	fi
fi
