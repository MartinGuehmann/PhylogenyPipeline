#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done

# Directory and the name of this script
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Input parameters
alignmentFile="$1"           # The alignment file
trimal="$2"                  # Whether the alignment should be trimmed

if [[ -z "$alignmentFile" ]]
then
	echo "You must give a file with an alignment, for instance:" >&2
	echo "./$thisScript AlignmentFile" >&2
	exit 1
fi

if [[ ! -f $alignmentFile ]]
then
	echo "Warning alignment file does not exist: $alignmentFile" >&2
	exit 2
fi

numTreads=$(nproc)

###########################################################
# Remove empty columns from alignment
reducedAlignmentFile="$alignmentFile.raxml.reduced.phy"

# raxml-ng's own --check occasionally rejects an alignment it was just
# handed with "ERROR: The sequence ... has an unknown (N) character",
# even though the exact same, untouched file is clean and passes fine
# on a later, standalone re-check - confirmed 2026-07-27 across five
# different aligners on real Mas1 output, with the same handful of
# parts failing identically across independently-scheduled cluster
# jobs. Root cause unconfirmed (ruled out so far: corrupted bytes in
# the file, alignment file size, a specific bad compute node). Retry
# once before giving up. A failed run can still leave behind a
# reduced.phy that would otherwise read as "already exists" to the
# check below without actually being valid, so always clear it (and
# the log) first, on both the initial attempt and the retry.
#
# Also covers a second, distinct failure mode sharing this same loop:
# raxml-ng itself missing ("command not found", exit 127) even though
# Enter-NixDevShell.sh's own verification (which runs once, at job
# start) reported the devShell fully activated. Confirmed 2026-08-10 on
# real RegTCoffee chunks, always in same-node pairs (two array tasks on
# the same compute node failing identically). A first theory - stale
# NFS directory-cache entries on that node, needing only a longer wait
# - was ruled out the same day: bumping this retry's sleep to 60s and
# re-running the exact same `raxml-ng` command still failed identically
# (confirmed via the job's own `real` runtime genuinely including the
# full 60s, not a short-circuited failure). That rules out anything
# that self-heals with time alone from inside this shell - the retry
# runs in the very same process/environment as the first attempt, so if
# raxml-ng's own store path was simply never included when this job's
# $PATH was originally composed (plausible given the recurring "SQLite
# database ... is busy" warnings seen elsewhere in these same logs,
# from nix's own eval-cache under concurrent job launches), no amount
# of waiting inside that already-built shell can add it after the
# fact. Only a fresh `nix develop` invocation gives nix a genuine new
# chance to compose $PATH correctly, so the retry now goes through that
# instead of just re-running raxml-ng in place - still preceded by the
# 60s sleep, in case whatever's causing the contention on this node
# hasn't cleared yet either. Falls back to a plain re-run if nix isn't
# available at all (same "fallback, never a requirement" stance as
# Enter-NixDevShell.sh) - can't do better than the original attempt
# there, but no worse either.
#
# Confirmed 2026-08-10 this fallback was silently the one actually
# taken on real failing chunks - both attempts' "command not found"
# blamed the exact same source line (the plain in-place call), meaning
# `command -v nix` itself failed here too, not just raxml-ng. This
# process is already running inside whatever devShell Enter-
# NixDevShell.sh composed, and that's the same $PATH this broken
# attempt inherited - so `command -v nix` alone is trusting the very
# thing suspected of being incomplete. Enter-NixDevShell.sh never makes
# that assumption for its own first entry: it re-sources nix's profile
# scripts unconditionally before ever checking for the nix command,
# since those don't depend on whatever the current $PATH happens to
# contain. Do the same here before checking, so a real "just missing
# raxml-ng, nix itself still resolvable" case doesn't fall back to the
# no-better-than-before path for the wrong reason.
for profileScript in \
	/nix/var/nix/profiles/default/etc/profile.d/nix.sh \
	/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
do
	[ -f "$profileScript" ] && . "$profileScript"
done

nixCmd=""
if command -v nix >/dev/null 2>&1
then
	nixCmd="nix"
elif command -v nix-portable >/dev/null 2>&1
then
	nixCmd="nix-portable nix"
fi

for attempt in 1 2
do
	rm -f "$reducedAlignmentFile" "$alignmentFile.raxml.log"
	if [ $attempt -eq 1 ] || [ -z "$nixCmd" ]
	then
		[ $attempt -eq 2 ] && echo "$alignmentFile: retrying in-place, not via a fresh nix develop - nix itself wasn't found even after re-sourcing its profile scripts" >&2
		raxml-ng --msa "$alignmentFile" --threads $numTreads --model LG+G --check >&2
	else
		echo "$alignmentFile: retrying via a fresh '$nixCmd develop'" >&2
		$nixCmd develop "$DIR" --command raxml-ng --msa "$alignmentFile" --threads $numTreads --model LG+G --check >&2
	fi
	checkStatus=$?
	if [ $checkStatus -eq 0 ]
	then
		break
	fi
	if [ $attempt -eq 1 ]
	then
		echo "$alignmentFile: raxml-ng --check failed (exit $checkStatus) - retrying once, via a fresh nix develop" >&2
		sleep 60
	fi
done

if [ $checkStatus -ne 0 ]
then
	echo "$alignmentFile: raxml-ng --check failed twice in a row (exit $checkStatus) - giving up" >&2
	exit $checkStatus
fi

# raxml-ng's own native reduced-phylip writer (used below whenever
# there actually was something to reduce - duplicate sequences or
# gap-only columns) strips each sequence's name down to just its ID,
# discarding the rest of the FASTA description. Downstream steps (tree
# figures, clade labeling) want the full description on the tree tips,
# not just the bare accession - so rebuild an ID -> sanitized-full-name
# mapping from the original $alignmentFile here, and apply it below to
# whatever reduced.phy ends up on disk, whether raxml-ng wrote it
# itself or the fallback further down has to build it from scratch.
#
# Phylip is whitespace-delimited with no quoting, so a description kept
# verbatim would make its own internal spaces indistinguishable from
# the name/sequence boundary - confirmed 2026-07-24 against a real Mas1
# chunk where a description containing a literal digit ("...sequence 1
# [Mastomys coucha]") made trimAl reject the file outright ("unknown
# (1) character"); descriptions without digits would have corrupted
# the alignment silently instead. Sanitize first instead of just
# dropping the description to dodge the problem: convert every
# character disallowed in a Phylip/Newick name (raxml-ng's own error
# text for this lists space, ; : , ( ) ') to a single underscore,
# collapsing repeats, before it's ever written to either file. Most
# NCBI/UniProt descriptions end with a bracketed species name (e.g.
# "[Mastomys coucha]"), so without also trimming a leading/trailing
# underscore this would leave one on nearly every name (confirmed
# 2026-07-28: ~87% of a real Mas1 alignment's names) - trim exactly one
# from each end, not more, since gsub above already collapsed interior
# runs to a single underscore.
nameMap=$(mktemp)
trap 'rm -f "$nameMap"' EXIT
seqkit fx2tab -j $numTreads "$alignmentFile" | awk -F'\t' '{
	id = $1
	sub(/ .*/, "", id)
	name = $1
	gsub(/[][ ;:,()\047\042]/, "_", name)
	gsub(/_+/, "_", name)
	sub(/^_/, "", name)
	sub(/_$/, "", name)
	print id, name
}' > "$nameMap"

# If there is nothing to remove for raxml-ng it will not
# create a phylip file and we have to do it ourselves.
if [ ! -f "$reducedAlignmentFile" ]
then
	seqNum=$(grep -c '>' "$alignmentFile")
	seqLength=$(seqkit head -j $numTreads -n 1 "$alignmentFile" | seqkit seq -j $numTreads -s | tr -d '\n' | wc -m)
	echo "$seqNum $seqLength" > "$reducedAlignmentFile"
	seqkit fx2tab -j $numTreads --only-id "$alignmentFile" | awk -F'\t' -v mapFile="$nameMap" '
		BEGIN { while ((getline line < mapFile) > 0) { split(line, p, " "); map[p[1]] = p[2] } }
		{ name = ($1 in map) ? map[$1] : $1; print name, $2 }
	' >> "$reducedAlignmentFile"
else
	awk -v mapFile="$nameMap" '
		BEGIN { while ((getline line < mapFile) > 0) { split(line, p, " "); map[p[1]] = p[2] } }
		NR==1 { print; next }
		{ if ($1 in map) $1 = map[$1]; print }
	' "$reducedAlignmentFile" > "$reducedAlignmentFile.tmp"
	mv "$reducedAlignmentFile.tmp" "$reducedAlignmentFile"
fi

# Remove double underscores and brackets from extended sequence IDs
sed -i -e 's/__/_/g' -e 's/[][]//g' "$reducedAlignmentFile"

if [ ! -z "$trimal" ]
then
	# Was a vendored, repo-relative binary ($DIR/../trimal/source/trimal)
	# until 2026-07-23 - same class of bug as the old FAMSA path, and same
	# fix: flake.nix's devShell already provides trimal directly (see
	# README's "Installing prerequisites with Nix"), so no vendored copy
	# is needed at all.
	#
	# -in/-out used to both point at $reducedAlignmentFile directly - that
	# had worked with whatever trimAl build used to be vendored here, but
	# segfaults with nixpkgs' trimal (1.5.1) on real alignments (confirmed
	# 2026-07-24 on the cluster). Write to a temp file in the same
	# directory and move it over the original instead, so trimAl never
	# reads and writes the same file at once, regardless of why that
	# stopped being safe.
	trimalTempFile=$(mktemp "$reducedAlignmentFile.XXXXXX")
	trimal -in "$reducedAlignmentFile" -out "$trimalTempFile" -gt "$trimal"
	trimalStatus=$?
	if [ $trimalStatus -eq 0 ]
	then
		mv "$trimalTempFile" "$reducedAlignmentFile"
	else
		rm -f "$trimalTempFile"
		exit $trimalStatus
	fi
fi
