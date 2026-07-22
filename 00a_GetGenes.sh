#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

gene="$1"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

DB="$2"
databaseName=$(basename $DB)
evalue="0.00005" # Default value: 10
maxkeep="100000" # Max value in online form: 20000, 100000 gives already some errors, but still the data is saved
outfmt="\"6 saccver evalue stitle\"" # Is not replaced properly

HitDir="$DIR/$gene/Hits/$databaseName/"
BaitDir="$DIR/$gene/BaitSequences/"
AdditionalBaitDir="$DIR/$gene/AdditionalBaitSequences/"

declare -a seqFiles=( "$BaitDir"*".fasta" )

if [ -d "$AdditionalBaitDir" ]
then
	seqFiles+=("$AdditionalBaitDir"*".fasta")
fi

if [ $DB == $databaseName ]
then
	remoteOrNumThreads="-remote"
	# blastp's own -remote path is broken behind a proxy from BLAST+
	# 2.10.0 onward (see README's "Remote NCBI access" section) - prefer
	# the pinned pre-dispatcher 2.9.0 build flake.nix's devShell puts on
	# PATH as blastp_2_9_0 if it's there, otherwise fall back to
	# whatever `blastp` already resolves to (e.g. a cluster module, or a
	# plain install where this was never a problem to begin with).
	if command -v blastp_2_9_0 >/dev/null 2>&1
	then
		blastpCmd="blastp_2_9_0"
	else
		blastpCmd="blastp"
	fi
else
	remoteOrNumThreads="-num_threads $(nproc)"
	blastpCmd="blastp"
fi

mkdir -p "$HitDir"

trials=0
maxTrials=16

while [ $trials -lt $maxTrials ]
do
	for ((i = 0; i < ${#seqFiles[@]}; i++))
	do
		seqFile="${seqFiles[$i]}"
		[ -f "$seqFile" ] || continue # In case you put a folder with the *.fasta extension into that folder

		outFileBase=$(basename "$seqFile" .fasta)
		outFile="$HitDir$outFileBase.csv"

		# Retry if there's nothing here yet, or what's here is an empty
		# file without its ".ok" marker - i.e. indistinguishable from a
		# still-in-progress or aborted attempt rather than a confirmed
		# zero-hit result (see the marker's own comment below).
		if [ ! -f "$outFile" ] || { [ ! -s "$outFile" ] && [ ! -f "$outFile.ok" ]; }
		then
			echo "Writing to $outFile" >&2
			stderrFile=$(mktemp)
			"$blastpCmd" -query "$seqFile" -db $DB -evalue $evalue -max_target_seqs $maxkeep $remoteOrNumThreads -out "$outFile" -outfmt "6 saccver stitle evalue" 2> "$stderrFile"
			status=$?
			cat "$stderrFile" >&2
			# A remote search can come back as a non-zero exit code
			# (connection/parse failure) or as exit 0 with a fatal "Error:"
			# line on stderr (the server answered, but the answer was an
			# error - e.g. NCBI's own CPU usage limit killing the search
			# server-side) - either one means this attempt produced no
			# usable output and needs to be retried, not exit code alone.
			failed="false"
			[ $status -ne 0 ] && failed="true"
			grep -q "^Error:" "$stderrFile" && failed="true"
			rm -f "$stderrFile"
			if [ "$failed" == "true" ]
			then
				echo "blastp failed for $outFile" >&2
				# Keep one non-empty failed attempt around for inspection
				# instead of just discarding it - but only one, so a run
				# that keeps failing doesn't pile up copies.
				if [ -s "$outFile" ] && [ ! -f "$outFile.error" ]
				then
					mv "$outFile" "$outFile.error"
					echo "Kept the failed output for inspection at $outFile.error" >&2
				else
					rm -f "$outFile"
				fi
			elif [ ! -s "$outFile" ]
			then
				# A confirmed successful search that genuinely found nothing
				# looks identical on disk to an empty file left behind by an
				# aborted/interrupted run - mark the former explicitly so the
				# checks below don't mistake the latter for it and skip
				# retrying a search that never actually completed. Kept as a
				# separate file rather than writing into $outFile itself,
				# since nothing downstream validates the CSV's column count
				# and a marker line there would be silently misread as a
				# real accession.
				touch "$outFile.ok"
			fi

			# Pace consecutive remote calls - confirmed 2026-07-22 that one
			# bait sequence's blastp -remote stalling/failing can make NCBI's
			# dispatcher immediately fail every following call in the same
			# trial too ("Connection stream is in bad state"): a burst of
			# ~10 back-to-back calls with zero delay between them went one
			# timeout -> instant cascade of identical failures for the rest
			# of that trial's remaining bait sequences. Untuned starting
			# value; only applies to remote calls, not local -num_threads
			# ones, which have no NCBI-side throttling to worry about.
			if [ $DB == $databaseName ]
			then
				sleep 3
			fi
		fi
	done

	needMoreTrials="false"

	for seqFile in "${seqFiles[@]}"
	do
		[ -f "$seqFile" ] || continue

		outFileBase=$(basename "$seqFile" .fasta)
		outFile="$HitDir$outFileBase.csv"

		# A missing file means blastp either hasn't run yet this trial or
		# failed and was removed above. An empty-but-present file needs its
		# ".ok" marker to count as a confirmed, legitimate zero-hit result -
		# without one, it's indistinguishable from a still-in-progress or
		# aborted attempt and needs retrying too.
		if [ ! -f "$outFile" ] || { [ ! -s "$outFile" ] && [ ! -f "$outFile.ok" ]; }
		then
			needMoreTrials="true"
		fi
	done

	if [[ $needMoreTrials == "true" && $DB == $databaseName ]]
	then
		echo "Not all files were downloaded, correctly. Trying $((maxTrials - trials -1)) more time(s)." >&2
		sleep 30 # Back off before hammering NCBI again - untuned starting value
		((++trials))
	else
		trials=$maxTrials
	fi

done

missing="false"

for seqFile in "${seqFiles[@]}"
do
	[ -f "$seqFile" ] || continue

	outFileBase=$(basename "$seqFile" .fasta)
	outFile="$HitDir$outFileBase.csv"

	if [ ! -f "$outFile" ] || { [ ! -s "$outFile" ] && [ ! -f "$outFile.ok" ]; }
	then
		echo "Missing after $maxTrials trials: $outFile" >&2
		missing="true"
	fi
done

if [ "$missing" == "true" ]
then
	echo "Failed to extract all sequences from $databaseName" >&2
	exit 1
fi

echo "All sequences extracted from $databaseName" >&2
