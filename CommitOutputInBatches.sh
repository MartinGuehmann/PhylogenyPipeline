#!/bin/bash

# Commits a gene repo's accumulated untracked pipeline output
# (Alignments/, SequencesOfInterest/) in small, per-aligner/BigTree-
# round batches instead of one bulk `git add -A && git commit`, pushing
# each batch right after it's committed. SSH keepalives in ~/.ssh/config
# already fix the known "unexpected disconnect while reading sideband
# packet" failure on a large push from a cluster login node (see
# project-cluster-git-push-disconnects memory), but after months of
# unattended runs a repo can still accumulate output across many
# aligner/BigTree combinations at once - smaller, logically-scoped
# commits stay easier to review regardless, and keep the blast radius
# of any future push failure down to one batch instead of everything.
#
# Usage: ./CommitOutputInBatches.sh [RepoPath] [--no-push]
# RepoPath defaults to the current directory. Run from (or point it at)
# a gene repo such as PeptideReceptors/, not PhylogenyPipeline itself.

set -e

repoPath="."
push="true"

for arg in "$@"
do
	case "$arg" in
		--no-push)
			push="false"
			;;
		-*)
			echo "Bad option $arg is ignored" >&2
			;;
		*)
			repoPath="$arg"
			;;
	esac
done

cd "$repoPath"

# These are the top-level directories observed to accumulate one
# sub-directory per aligner/BigTree-round combination (e.g.
# Alignments/FAMSA.BigTree0/, SequencesOfInterest/FAMSA.BigTree0/) -
# add another name here if a future repo layout grows a third one.
parentDirs=("Alignments" "SequencesOfInterest")

repoName=$(basename "$(git rev-parse --show-toplevel)")

# Collect every untracked top-level name under each parent dir. Two
# cases: a partially-tracked parent dir (git status shows individual
# untracked subdirs/files, e.g. "Alignments/FAMSA/round3/x.fasta" - the
# sed below grabs "FAMSA" out of that), and a parent dir with nothing
# ever committed under it yet, which git status collapses to a single
# "$parent/" line instead of expanding it - caught explicitly below
# and expanded from the real subdirectories on disk instead.
keys=()
for parent in "${parentDirs[@]}"
do
	[ -d "$parent" ] || continue
	while IFS= read -r path
	do
		if [ "$path" == "$parent/" ]
		then
			for sub in "$parent"/*/
			do
				[ -d "$sub" ] && keys+=("$(basename "$sub")")
			done
		else
			name=$(echo "$path" | sed -E "s#^${parent}/([^/]+).*#\1#")
			[ -n "$name" ] && keys+=("$name")
		fi
	done < <(git status --porcelain -- "$parent" | awk '{print $2}')
done

mapfile -t uniqueKeys < <(printf '%s\n' "${keys[@]}" | sort -u)

if [ ${#uniqueKeys[@]} -eq 0 ]
then
	echo "No untracked output found under: ${parentDirs[*]}" >&2
	exit 0
fi

echo "Found ${#uniqueKeys[@]} batch(es) to commit: ${uniqueKeys[*]}" >&2

for key in "${uniqueKeys[@]}"
do
	paths=()
	for parent in "${parentDirs[@]}"
	do
		[ -e "$parent/$key" ] && paths+=("$parent/$key")
	done

	if [ ${#paths[@]} -eq 0 ]
	then
		echo "Skipping $key - no matching path found" >&2
		continue
	fi

	echo "=== $key (${paths[*]}) ===" >&2
	git add -- "${paths[@]}"

	if git diff --cached --quiet
	then
		echo "Nothing staged for $key, skipping" >&2
		continue
	fi

	git commit -m "Add $repoName $key output"

	if [ "$push" == "true" ]
	then
		git push
	fi
done
