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
localNr="$2"

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

# Same idea for nr, but only if this gene's run actually asked for it -
# unlike the uniprot databases, it's opt-in given its size (see
# get_nr_database.sh). Downloads/builds it once if it isn't there yet and
# reuses it across runs after that, exactly like the uniprot databases.
# See get_nr_database.sh's exit code contract: 2 means nr specifically
# couldn't be fetched/built, which just falls back to the normal remote
# efetch pool below for nr's hits instead of failing the whole step -
# unlike a genuinely broken environment (1), which still does.
attemptLocalNr="false"
if [ "$localNr" == "--localNr" ]
then
	"$DIR/ProteinDatabase/get_nr_database.sh"
	nrStatus=$?
	if [ $nrStatus -eq 0 ]
	then
		attemptLocalNr="true"
	elif [ $nrStatus -eq 2 ]
	then
		echo "--localNr was given but the local nr database could not be fetched/built - falling back to remote efetch for nr hits" >&2
	else
		echo "Failed to get/build the local nr database" >&2
		exit 1
	fi
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
rm -f "$sequences"/nr_ids.txt "$sequences"/nr_local.fasta "$sequences"/nr_local.good.fasta
rm -f "$sequences"/*.raw.fasta

# efetch (and blastdbcmd, both for local nr and - since
# get_uniprot_database.sh started using -parse_seqids - for the local
# uniprot extraction below) return records whose FASTA header embeds the
# accession inside a pipe-delimited defline instead of using it as the
# bare first token - e.g. UniProt records as `sp|ACC|NAME ...` or
# `tr|ACC|NAME ...`, PDB chains as `pdb|ID|CHAIN ...`, PRF records as
# `prf||ACC ...`. Matching/collecting IDs by the header's first
# whitespace-delimited token (what `seqkit grep -f`/plain awk would do)
# never matches the bare accession actually requested, so a hit that
# fetched just fine gets silently dropped and misreported as permanently
# unfetchable. Confirmed 2026-07-23 against live NCBI responses - these
# two helpers normalize a header back to the requested ID's form for
# every shape seen in practice. With -parse_seqids, blastp/blastdbcmd
# against the local uniprot databases already report/expect the bare
# accession (confirmed 2026-07-24), so normalize() below is a no-op for
# them in practice - but calling it anyway costs nothing and keeps both
# extraction paths going through the same safety net.
extractRequestedRecords() {
	local fastaFile="$1"
	local idFile="$2"
	awk -v idFile="$idFile" '
		BEGIN {
			while ((getline id < idFile) > 0) wanted[id] = 1
		}
		function normalize(id,    a) {
			if (id ~ /^pdb\|[^|]+\|[^ \t]+/) {
				split(id, a, "|")
				return a[2] "_" a[3]
			}
			if (id ~ /^prf\|\|/) {
				sub(/^prf\|\|/, "", id)
				return id
			}
			if (id ~ /^[a-z]+\|[^|]+\|/) {
				split(id, a, "|")
				return a[2]
			}
			return id
		}
		/^>/ {
			header = substr($0, 2)
			sub(/[ \t].*/, "", header)
			keep = (normalize(header) in wanted)
		}
		keep { print }
	' "$fastaFile"
}

getNormalizedIDs() {
	grep "^>" "$1" | sed 's/^>//' \
		| sed -E 's/^pdb\|([^|]+)\|(\S+)/\1_\2/; s/^prf\|\|(\S+)/\1/; s/^[a-z]+\|([^|]+)\|.*/\1/' \
		| awk '{print $1}'
}

# Extract the sequences from uniprot
for DB_PATH in "${LocalDataBases[@]}"
do
	DB=$(basename $DB_PATH)

	sed -E "s/^ *[0-9]* //g" "$hits/$DB/SortedHitsByName.csv" | cut -f 1 | sort -u >> $tmpIDs

	# blastdbcmd instead of seqkit grep -f ... "$DB_PATH.fasta": with
	# get_uniprot_database.sh's makeblastdb now using -parse_seqids,
	# sequences can be pulled straight out of the BLAST database by
	# accession, the same way local nr already works below - no need to
	# keep the multi-GB downloaded .fasta file around just for this.
	dbRawFile="$sequences/$DB.raw.fasta"
	blastdbcmd -db "$DB_PATH" -entry_batch "$tmpIDs" -outfmt "%f" > "$dbRawFile"

	# Same reasoning as the nr extraction below: never trust blastdbcmd's
	# exit code as pass/fail for the whole batch, and never blindly
	# append its raw output either.
	extractRequestedRecords "$dbRawFile" "$tmpIDs" >> $sequenceFile

	# Unlike nr below, there's no remote fallback for a uniprot hit -
	# blastdbcmd not finding one here (e.g. withdrawn/merged since this
	# local copy was last updated) just means it's missing from this run.
	missingIDs=$(comm -23 <(sort -u "$tmpIDs") <(getNormalizedIDs "$dbRawFile" | sort -u))
	if [ -n "$missingIDs" ]
	then
		echo "blastdbcmd could not find these $DB ID(s) in the local copy: $(echo "$missingIDs" | tr '\n' ' ')" >&2
	fi

	rm -f $tmpIDs "$dbRawFile"
done

# Split the sequence file into handy chuncks if we want to store it on github
# The maximum file size is 100 MB, but we should stay below of that.
seqkit split2 -j $numTreads -s $splitSeqNum -O $sequences $sequenceFile
rm -f $sequenceFile

# Extract the sequences from NCBI
IDs=($(sed -E "s/^ *[0-9]* //g" "$hits/$AllNCBI/SortedHitsByName.csv" | cut -f 1 | sort -u))

failed="false"

# nquire (used internally by efetch) passes curl -f, which discards the
# response body on any non-2xx HTTP status - so a genuinely withdrawn/
# suppressed record's real reason ("Failed to retrieve sequence: <ID>",
# NCBI's own backend wording, confirmed 2026-07-22/23) never surfaces
# through the normal retry loop below; it just looks like the same
# generic failure as a transient network hiccup. A raw curl bypassing -f
# exposes it directly. Only ever called for the handful of IDs that
# survive the full retry loop below, so a few extra requests here is
# cheap; its own small retry budget guards against mistaking a
# coincidental transient failure on this check itself for confirmation.
isConfirmedDead() {
	local id="$1"
	local attempt
	for ((attempt = 0; attempt < 3; attempt++))
	do
		if curl -s -X POST "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi" \
			-d "db=sequences&id=$id&rettype=fasta&retmode=text&tool=edirect&email=$(whoami)%40$(hostname)" \
			2>/dev/null | grep -q "Failed to retrieve sequence: $id"
		then
			return 0
		fi
		sleep 5
	done
	return 1
}

# nr's hits are included above and would normally be fetched remotely via
# efetch below like every other NCBI-sourced hit. But if this gene's run
# asked for a local nr copy (--localNr) and get_nr_database.sh above
# confirmed it's there, its sequences are already sitting right on disk,
# so pull nr's IDs out of the efetch pool and extract them directly with
# blastdbcmd instead, entirely avoiding NCBI's efetch service (and its own
# separate flakiness - see the retry hardening below) for however many of
# this gene's hits came from nr.
localNrPath="$DIR/ProteinDatabase/nr/nr"
if [ "$attemptLocalNr" == "true" ]
then
	nrHitsFile="$hits/nr/SortedHitsByName.csv"
	if [ -f "$nrHitsFile" ]
	then
		nrIDs=($(sed -E "s/^ *[0-9]* //g" "$nrHitsFile" | cut -f 1 | sort -u))
		if [ ${#nrIDs[@]} -gt 0 ]
		then
			nrIDsFile="$sequences/nr_ids.txt"
			nrRawFile="$sequences/nr_local.fasta"
			nrGoodFile="$sequences/nr_local.good.fasta"
			printf '%s\n' "${nrIDs[@]}" > "$nrIDsFile"
			blastdbcmd -db "$localNrPath" -entry_batch "$nrIDsFile" -outfmt "%f" > "$nrRawFile"

			# Same reasoning as the efetch loop below: never trust
			# blastdbcmd's exit code as pass/fail for the whole batch (a
			# missing/suppressed entry is reported per-ID on stderr, not
			# as a nonzero exit - blastdbcmd still exits 0 overall and
			# just skips it) and never blindly append its raw output
			# either. extractRequestedRecords keeps only genuine records
			# for IDs actually asked for.
			extractRequestedRecords "$nrRawFile" "$nrIDsFile" > "$nrGoodFile"
			cat "$nrGoodFile" >> $sequenceNCBIFile

			# Anything blastdbcmd couldn't find locally (e.g. added to
			# NCBI's real nr after this local copy was last updated)
			# stays in $IDs below and gets the normal remote efetch
			# treatment instead of being silently lost - only the IDs
			# genuinely extracted here are removed from that pool.
			fetchedNrIDs=$(getNormalizedIDs "$nrGoodFile" | sort -u)
			missingNrIDs=$(comm -23 <(sort -u "$nrIDsFile") <(echo "$fetchedNrIDs"))
			if [ -n "$missingNrIDs" ]
			then
				echo "blastdbcmd could not find these nr ID(s) in the local copy, falling back to remote efetch for them: $(echo "$missingNrIDs" | tr '\n' ' ')" >&2
			fi
			mapfile -t IDs < <(comm -23 <(printf '%s\n' "${IDs[@]}" | sort -u) <(echo "$fetchedNrIDs"))

			rm -f "$nrIDsFile" "$nrRawFile" "$nrGoodFile"
		fi
	fi
fi

numIDs=${#IDs[@]}
# 8000 was chosen after a larger batch previously ran into a bash/OS
# command-line length limit (ARG_MAX, see `getconf ARG_MAX`) - the -id
# argument below is one long comma-joined string, not passed via
# stdin/a file, so raising this would need testing against that limit
# specifically. Unrelated to the retry logic below, which is for
# transient NCBI/network failures instead.
range=8000
i=0

# Some IDs (e.g. withdrawn/suppressed TSA records) are permanently gone
# from NCBI, not just transiently unreachable - see
# KnownDeadAccessions.txt for how an ID earns a place here. A batch still
# failing on exactly these after retries is expected, not a run failure;
# this pipeline is meant to run unattended via the Scheduler's afterok
# chain, so treating an unfixable, already-confirmed case as a step
# failure would just block step 4 forever for no reason. Anything NOT in
# this list still fails the step normally.
#
# Lives in the gene's own repo ($gene, not this pipeline's), since which
# accessions are dead is a property of that gene's search results, not
# of the pipeline itself - different genes' hit sets don't share it.
knownDeadFile="$DIR/$gene/KnownDeadAccessions.txt"
knownDeadIDs=$(grep -v '^#' "$knownDeadFile" 2>/dev/null | grep -v '^[[:space:]]*$' | sort -u)

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
		# stdout either. extractRequestedRecords keeps only genuine records
		# for IDs actually asked for, so a stray error line or anything else
		# is dropped instead of corrupting the real output file.
		printf '%s\n' "${remainingIDs[@]}" > "$requestedFile"
		extractRequestedRecords "$batchFile" "$requestedFile" > "$goodFile"
		cat "$goodFile" >> $sequenceNCBIFile

		# Whatever ID isn't among what was actually fetched this attempt
		# is what still needs retrying - not the whole batch.
		fetchedIDs=$(getNormalizedIDs "$goodFile" | sort -u)
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
		sortedRemaining=$(printf '%s\n' "${remainingIDs[@]}" | sort -u)
		deadRemaining=$(comm -12 <(echo "$sortedRemaining") <(echo "$knownDeadIDs"))
		unexplainedRemaining=$(comm -23 <(echo "$sortedRemaining") <(echo "$knownDeadIDs"))

		if [ -n "$deadRemaining" ]
		then
			echo "efetch permanently failed for known-dead ID(s) (see KnownDeadAccessions.txt, not treated as a failure) in batch $i..$((i + range - 1)) after $maxTrials trials: $(echo "$deadRemaining" | tr '\n' ' ')" >&2
		fi

		if [ -n "$unexplainedRemaining" ]
		then
			newlyConfirmedDead=()
			stillUnexplained=()
			while IFS= read -r id
			do
				[ -z "$id" ] && continue
				if isConfirmedDead "$id"
				then
					newlyConfirmedDead+=("$id")
				else
					stillUnexplained+=("$id")
				fi
			done <<< "$unexplainedRemaining"

			if [ ${#newlyConfirmedDead[@]} -gt 0 ]
			then
				echo "efetch permanently failed for newly-confirmed-dead ID(s) (auto-added to KnownDeadAccessions.txt, not treated as a failure) in batch $i..$((i + range - 1)) after $maxTrials trials: ${newlyConfirmedDead[*]}" >&2
				(
					flock -x 201
					{
						echo ""
						echo "# Auto-confirmed dead $(date -I) ($gene, efetch's own \"Failed to retrieve sequence\" response)"
						printf '%s\n' "${newlyConfirmedDead[@]}"
					} >> "$knownDeadFile"
				) 201>"$knownDeadFile.lock"
				knownDeadIDs=$(printf '%s\n%s\n' "$knownDeadIDs" "${newlyConfirmedDead[*]}" | tr ' ' '\n' | sort -u)
			fi

			if [ ${#stillUnexplained[@]} -gt 0 ]
			then
				echo "efetch permanently failed for unexpected ID(s) in batch $i..$((i + range - 1)) after $maxTrials trials: ${stillUnexplained[*]}" >&2
				failed="true"
			fi
		fi
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
