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
rm -f "$sequences"/efetch_batch_*.fasta "$sequences"/efetch_batch_*.stderr

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
	part=${IDs[@]:$i:$range}
	part=$(echo $part | tr ' ' ',')

	# Write each batch to its own file rather than appending directly -
	# efetch can fail partway through a response (e.g. the connection
	# dying mid-transfer), and appending straight to $sequenceNCBIFile
	# would leave a truncated record behind on the next retry instead of
	# just overwriting the bad attempt. Named predictably in $sequences
	# (not mktemp's random /tmp path) so a batch can actually be found and
	# inspected while the job is still running, e.g. to check progress or
	# see a failed attempt's raw output/stderr before the next retry
	# overwrites it.
	batchFile="$sequences/efetch_batch_$i.fasta"
	stderrFile="$sequences/efetch_batch_$i.stderr"
	trials=0
	maxTrials=5
	success="false"

	while [ $trials -lt $maxTrials ]
	do
		efetch -db sequences -format fasta -id $part > "$batchFile" 2> "$stderrFile"
		cat "$stderrFile" >&2
		# efetch exits 0 even when it fails, so the exit code alone can't
		# be trusted (same issue as blastp -remote elsewhere in this
		# pipeline). A data-level failure (e.g. an ID NCBI didn't
		# recognize) prints "Error:" to stdout instead of any actual FASTA.
		# For transport-level failures, nquire prints "ERROR: curl command
		# failed" to stderr on *every* transient curl hiccup, even ones
		# entrez-direct's own internal retry (ecommon.sh) then quietly
		# recovers from - so grepping for that would flag almost every
		# batch as failed. "QUERY FAILURE" is what ecommon.sh's retry loop
		# prints instead, and only once, when all of its internal attempts
		# are truly exhausted - confirmed 2026-07-22 via a real cluster run
		# where one 8000-ID batch's internal sub-chunk hit exactly this
		# after repeated empty results, dropping ~49 accessions from the
		# output with no other signal (the previous check here,
		# `grep -q "^ERROR:"`, never matches ecommon.sh's actual message,
		# which has a leading space before "ERROR:").
		if ! grep -q "QUERY FAILURE" "$stderrFile" && ! grep -q "^Error:" "$batchFile"
		then
			success="true"
			break
		fi
		echo "efetch failed for IDs $i..$((i + range - 1)), trying $((maxTrials - trials - 1)) more time(s)" >&2
		sleep 30 # Back off before hammering NCBI again - untuned starting value
		((++trials))
	done
	rm -f "$stderrFile"

	if [ "$success" == "true" ]
	then
		cat "$batchFile" >> $sequenceNCBIFile
	else
		echo "efetch permanently failed for IDs $i..$((i + range - 1)) after $maxTrials trials" >&2
		failed="true"
	fi
	rm -f "$batchFile"

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
