#!/bin/bash

# Builds every dependency in flake.nix and caches it in the Nix store, so
# that entering the `nix develop` shell (see README.md's "Installing
# prerequisites with Nix") only ever has to link an already-built
# environment instead of building tools - some of them from source - the
# first time a pipeline run happens to need them. Run this once after
# cloning, and again whenever flake.nix changes.
#
# All of flake.nix's derivations have already been build-tested and their
# `hash = pkgs.lib.fakeHash;` placeholders resolved to real hashes, so a
# normal run of this script should just report OK for everything below.
# If flake.nix is edited to add a new derivation or bump a pinned version,
# though, Nix will refuse the build for that one and print the real hash
# of what it downloaded - paste that hash in place of fakeHash for the
# named derivation in flake.nix, then re-run this script.
#
# Every build below is rooted under .nix-gcroots/ (via --out-link) instead
# of just realized (--no-link, the previous behavior) - a store path that
# is merely realized but never rooted is fair game for the next
# `nix-collect-garbage`, by this user or anyone else sharing the same
# store, and array jobs a day later can then find a symlink baked into an
# already-built derivation (e.g. PASTA's tool directory pointing at
# raxmlHPC) pointing at nothing. Confirmed 2026-07-29 on Mas1: an entire
# 26-task PASTA array failed this way, and the user had assumed
# submitting the job would itself take care of building/keeping the
# environment - Scheduler-Call.sh's CheckNixDependenciesBuilt.sh call now
# checks these roots exist and aren't broken before submitting anything,
# specifically to catch this earlier and cheaper than a failed array job.

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

cd "$DIR"

# Where every build's GC root goes - one symlink per package plus one for
# the devShell, see the comment block above for why these need to exist
# at all instead of just building with --no-link.
gcRootDir="$DIR/.nix-gcroots"
mkdir -p "$gcRootDir"

# A multi-user Nix install isn't on PATH until its profile scripts are
# sourced - harmless to source these if they don't apply here, since each
# is only sourced when present.
for profileScript in \
	/nix/var/nix/profiles/default/etc/profile.d/nix.sh \
	/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
do
	[ -f "$profileScript" ] && . "$profileScript"
done

# Clusters often have no Nix install and no root access to add one - see
# README.md's "Installing prerequisites with Nix" - so fall back to
# nix-portable the same way that section documents for `nix develop`.
if command -v nix >/dev/null 2>&1
then
	nixCmd="nix"
elif command -v nix-portable >/dev/null 2>&1
then
	nixCmd="nix-portable nix"
else
	echo "Neither nix nor nix-portable is on PATH." >&2
	echo "See README.md's 'Installing prerequisites with Nix' section." >&2
	exit 1
fi

# One buildable output per custom derivation in flake.nix's `packages`.
declare -a packages=(
	raxml-ng
	roguenarok
	famsa
	treeshrink
	magus
	entrez-direct
	t-coffee
	clustalw
	fasttree
	prank
	muscle3
	muscle5
	iqtree2
	pasta
	ete3
	pythonWithEte3
	blast2_9
)

declare -a failed=()

for pkg in "${packages[@]}"
do
	echo "=== Building $pkg ===" >&2
	# --refresh: this script exists specifically to be re-run against a
	# changing flake.nix (the fakeHash-fix-rerun workflow above), and
	# without it Nix has been observed serving a stale cached evaluation
	# of an unchanged-looking .drv path even after a real fix landed in
	# flake.nix - confirmed on 2026-07-17, cost real time to track down.
	# --out-link roots the result under .nix-gcroots/ instead of just
	# realizing it (see the comment block at the top of this file).
	if ! $nixCmd build ".#$pkg" --out-link "$gcRootDir/$pkg" -L --refresh
	then
		failed+=("$pkg")
	fi
done

# Also realizes (and, via --out-link, roots) the plain nixpkgs tools
# (seqkit, blast, mafft, etc.) that the devShell pulls in directly and
# aren't their own named package above. `nix build` on the devShell
# derivation itself forces every one of its packages/buildInputs to be
# built first, same as `nix develop --command true` used to, but leaves a
# GC root behind instead of not rooting anything.
echo "=== Building devShell ===" >&2
system=$($nixCmd eval --impure --raw --expr builtins.currentSystem)
if ! $nixCmd build ".#devShells.$system.default" --out-link "$gcRootDir/devShell" -L --refresh
then
	failed+=("devShell")
fi

if [ ${#failed[@]} -gt 0 ]
then
	echo "Failed to build: ${failed[*]}" >&2
	echo "See the fakeHash note above - that's the most likely cause for a first run." >&2
	exit 1
fi

echo "All dependencies built and cached in the Nix store." >&2
