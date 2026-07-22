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

# Download and make the uniprot databases if they do not exist
if ! "$DIR/ProteinDatabase/get_uniprot_databases.sh"
then
	echo "Failed to get/build the local Uniprot databases" >&2
	exit 1
fi

source "$DIR/Databases.sh"

AllNCBI="All"

hits="$DIR/$gene/Hits"
sequences="$DIR/$gene/Sequences"
sequenceFileBase="$sequences/Sequences"
sequenceNCBIFileBase="$sequences/NCBISequences"
sequenceFile="$sequenceFileBase.fasta"
sequenceNCBIFile="$sequenceNCBIFileBase.fasta"

tmpIDs="$sequences/IDs.txt"

numTreads=$(nproc)

mkdir -p $sequences

splitSeqNum=40000

rm -f $tmpIDs
rm -f $sequenceFile
rm -f $sequenceNCBIFile

rm -f $sequenceFileBase*".fasta"
rm -f $sequenceNCBIFileBase*".fasta"
rm -f "$sequences"/efetch_batch_*.fasta "$sequences"/efetch_batch_*.stderr "$sequences"/efetch_batch_*.requested

# Extract the sequences from uniprot
for DB_PATH in "${LocalDataBases[@]}"
do
	DB=$(basename $DB_PATH)

	sed -E "s/^ *[0-9]* //g" "$hits/$DB/SortedHitsByName.csv" | cut -f 1 | sort -u >> $tmpIDs

	seqkit grep -j $numTreads -f $tmpIDs -t protein "$DB_PATH.fasta" >> $sequenceFile

	rm -f $tmpIDs
done

# Split the sequence file into handy chuncks if we want to store it on github
# The maximum file size is 100 MB, but we should stay below of that.
seqkit split2 -j $numTreads -s $splitSeqNum -O $sequences $sequenceFile
rm -f $sequenceFile

# Extract the sequences from NCBI
IDs=($(sed -E "s/^ *[0-9]* //g" "$hits/$AllNCBI/SortedHitsByName.csv" | cut -f 1 | sort -u))

numIDs=${#IDs[@]}
# 8000 was chosen after a larger batch previously ran into a bash/OS
# command-line length limit (ARG_MAX, see `getconf ARG_MAX`) - the -id
# argument below is one long comma-joined string, not passed via
# stdin/a file, so raising this would need testing against that limit
# specifically. Unrelated to the retry logic below, which is for
# transient NCBI/network failures instead.
range=8000
i=0

failed="false"

while [ $i -lt $numIDs ]
do
	# A whole batch's efetch call can come back "failed" (non-zero exit,
	# "QUERY FAILURE" on stderr, etc.) while still having successfully
	# fetched almost everything - efetch keeps working through its own
	# internal sub-chunks even after one of them permanently fails, so a
	# "failed" attempt usually still contains most of the batch's data.
	# Rather than trusting efetch's own pass/fail signal for the whole
	# request (unreliable - see below) and discarding the lot on any
	# failure, each attempt below keeps whatever it actually returned and
	# only retries the specific IDs still missing afterward - confirmed
	# 2026-07-22 that a batch's "failure" is often really just one
	# permanently-dead accession (NCBI's own backend explicitly saying
	# "Failed to retrieve sequence" for what looks like a withdrawn/
	# suppressed record) poisoning one ~50-ID internal sub-chunk, while
	# the other ~7950 IDs in the same 8000-ID batch fetch fine. Retrying
	# the entire batch wasted ~5 minutes per trial re-fetching already-
	# good data, then discarded all 8000 IDs once trials ran out, instead
	# of just the actually-bad ones.
	remainingIDs=("${IDs[@]:$i:$range}")

	# Named predictably in $sequences (not mktemp's random /tmp path) so
	# a batch can actually be found and inspected while the job is still
	# running, e.g. to check progress or see a failed attempt's raw
	# output/stderr before the next retry overwrites it.
	batchFile="$sequences/efetch_batch_$i.fasta"
	stderrFile="$sequences/efetch_batch_$i.stderr"
	requestedFile="$sequences/efetch_batch_$i.requested"
	goodFile="$sequences/efetch_batch_$i.good.fasta"
	trials=0
	maxTrials=5

	while [ $trials -lt $maxTrials ] && [ ${#remainingIDs[@]} -gt 0 ]
	do
		part=$(IFS=,; echo "${remainingIDs[*]}")
		efetch -db sequences -format fasta -id $part > "$batchFile" 2> "$stderrFile"
		cat "$stderrFile" >&2

		# Never trust efetch's exit code or stderr text as pass/fail for
		# the whole request (it exits 0 even when it fails, and a
		# data-level failure can print a literal "Error: ..." line to
		# stdout instead of a record) and never blindly append its raw
		# stdout either. seqkit grep -f keeps only genuine records for
		# IDs actually asked for, so a stray error line or anything else
		# is dropped instead of corrupting the real output file.
		printf '%s\n' "${remainingIDs[@]}" > "$requestedFile"
		seqkit grep -j "$numTreads" -f "$requestedFile" "$batchFile" > "$goodFile" 2>/dev/null
		cat "$goodFile" >> $sequenceNCBIFile

		# Whatever ID isn't among what was actually fetched this attempt
		# is what still needs retrying - not the whole batch.
		fetchedIDs=$(grep "^>" "$goodFile" | sed 's/^>//' | awk '{print $1}' | sort -u)
		mapfile -t remainingIDs < <(comm -23 <(sort -u "$requestedFile") <(echo "$fetchedIDs"))

		rm -f "$batchFile" "$stderrFile" "$requestedFile" "$goodFile"

		if [ ${#remainingIDs[@]} -gt 0 ]
		then
			echo "efetch: ${#remainingIDs[@]} ID(s) still missing from batch $i..$((i + range - 1)), trying $((maxTrials - trials - 1)) more time(s)" >&2
			sleep 30 # Back off before hammering NCBI again - untuned starting value
			((++trials))
		fi
	done

	if [ ${#remainingIDs[@]} -gt 0 ]
	then
		echo "efetch permanently failed for ${#remainingIDs[@]} ID(s) in batch $i..$((i + range - 1)) after $maxTrials trials: ${remainingIDs[*]}" >&2
		failed="true"
	fi

	let i+=range
done

if [ "$failed" == "true" ]
then
	echo "Some NCBI sequences could not be fetched, see above for which ID ranges - $sequenceNCBIFile is incomplete" >&2
	exit 1
fi

# Split the sequence file into handy chuncks if we want to store it on github
# The maximum file size is 100 MB, but we should stay below of that.
seqkit split2 -j $numTreads -s $splitSeqNum -O $sequences $sequenceNCBIFile
rm -f $sequenceNCBIFile
