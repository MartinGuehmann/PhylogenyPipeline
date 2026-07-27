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
for attempt in 1 2
do
	rm -f "$reducedAlignmentFile" "$alignmentFile.raxml.log"
	raxml-ng --msa "$alignmentFile" --threads $numTreads --model LG+G --check >&2
	checkStatus=$?
	if [ $checkStatus -eq 0 ]
	then
		break
	fi
	if [ $attempt -eq 1 ]
	then
		echo "$alignmentFile: raxml-ng --check failed (exit $checkStatus) - retrying once" >&2
		sleep 5
	fi
done

if [ $checkStatus -ne 0 ]
then
	echo "$alignmentFile: raxml-ng --check failed twice in a row (exit $checkStatus) - giving up" >&2
	exit $checkStatus
fi

# If there is nothing to remove for raxml-ng it will not
# create a phylip file and we have to do it ourselves.
if [ ! -f "$reducedAlignmentFile" ]
then
	seqNum=$(grep -c '>' "$alignmentFile")
	seqLength=$(seqkit head -j $numTreads -n 1 "$alignmentFile" | seqkit seq -j $numTreads -s | tr -d '\n' | wc -m)
	echo "$seqNum $seqLength" > "$reducedAlignmentFile"
	# --only-id: without it, fx2tab's name column is the full FASTA header
	# (accession + description), and the sed below then turns the tab
	# between it and the sequence into a plain space - in phylip's
	# whitespace-delimited format that makes the description indistinguishable
	# from sequence data. Confirmed 2026-07-24 against a real Mas1 chunk
	# where a description containing a literal digit ("...sequence 1
	# [Mastomys coucha]") made trimAl reject the file outright ("unknown (1)
	# character"); descriptions without digits would have corrupted the
	# alignment silently instead. raxml-ng's own native reduced-phylip
	# writer already strips the description down to just the ID - this
	# fallback needs to match that.
	seqkit fx2tab -j $numTreads --only-id "$alignmentFile" | sed -e "s/	$//" -e "s/	/ /g" >> "$reducedAlignmentFile"
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
