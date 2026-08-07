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

source "$DIR/Lock-Dir.sh"
gene="$1"
localDatabases="$2"

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

# Same idea for any NCBI database in $localDatabases (a colon-separated
# list of Databases.sh's RemoteDataBases names, e.g. "nr:refseq_protein" -
# colon-, not comma-separated, since this reaches this script via Slurm's
# --export=Var1=Val1,Var2=Val2, which already uses comma to separate
# different variables), but only for whichever ones this gene's run
# actually asked for - unlike the uniprot databases, it's opt-in given
# their size (see get_ncbi_blastdb.sh). Downloads/builds each once if it
# isn't there yet and reuses it across runs after that, exactly like the
# uniprot databases. See get_ncbi_blastdb.sh's exit code contract: 2
# means that database specifically couldn't be fetched/built, which just
# falls back to the normal remote efetch pool below for its hits instead
# of failing the whole step - unlike a genuinely broken environment (1),
# which still does.
builtLocalDatabases=""
IFS=':' read -ra requestedLocalDatabases <<< "$localDatabases"
for db in "${requestedLocalDatabases[@]}"
do
	[ -z "$db" ] && continue
	"$DIR/ProteinDatabase/get_ncbi_blastdb.sh" "$db"
	dbStatus=$?
	if [ $dbStatus -eq 0 ]
	then
		builtLocalDatabases="${builtLocalDatabases:+$builtLocalDatabases:}$db"
	elif [ $dbStatus -eq 2 ]
	then
		echo "$db was opted into localDatabases but could not be fetched/built locally - falling back to remote efetch for its hits" >&2
	else
		echo "Failed to get/build the local $db database" >&2
		exit 1
	fi
done

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

# This step can run for hours (the efetch loop below, one NCBI round
# trip at a time), and used to unconditionally wipe and redo everything
# from scratch on every invocation - fine for a step that fails outright,
# since Slurm's afterok dependency chain just never runs the next step,
# but wasteful for a job that gets killed by walltime/scancel/node
# failure partway through and gets resubmitted, as happened on a real
# ACEs run 2026-07-29 (2.5 hours in when checked). Resuming below assumes
# this gene's Hits/ haven't changed since whatever attempt is being
# resumed from - if they have (e.g. step 0 was manually rerun for this
# gene), delete $sequences (or at least UniprotExtraction.ok,
# NCBIExtraction.ok, and efetch_batch_*.done) to force a full redo.
#
# What follows here is only genuinely transient per-attempt scratch, safe
# to clear unconditionally regardless of whether we're resuming - none of
# it represents finished, accumulated work, just leftovers from whatever
# database/batch was being processed when a previous attempt (if any) was
# interrupted.
rm -f "$sequences"/efetch_batch_*.fasta "$sequences"/efetch_batch_*.stderr "$sequences"/efetch_batch_*.requested "$sequences"/efetch_batch_*.good.fasta
rm -f "$sequences"/*.local_ids.txt "$sequences"/*.local.fasta "$sequences"/*.local.good.fasta
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

# blastdbcmd has no multithreading flag of its own (-entry_batch is a
# single, serial index lookup, unlike -num_threads on blastp/blastn) -
# the only way to actually parallelize it is running several blastdbcmd
# processes at once, each against its own slice of the ID list, then
# concatenating their output back together (order doesn't matter, both
# call sites below just filter the combined output by ID afterward).
# minIDsPerChunk keeps a small ID list from being split into near-empty
# chunks that would spend more time forking processes than doing lookups
# - untuned starting value, same spirit as $range's ARG_MAX-driven choice
# below.
minIDsPerChunk=1000
runBlastdbcmdParallel() {
	local db="$1"
	local idFile="$2"
	local outFile="$3"

	local numIDsHere
	numIDsHere=$(wc -l < "$idFile")

	local numChunks=$(( (numIDsHere + minIDsPerChunk - 1) / minIDsPerChunk ))
	[ "$numChunks" -lt 1 ] && numChunks=1
	[ "$numChunks" -gt "$numTreads" ] && numChunks=$numTreads

	if [ "$numChunks" -le 1 ]
	then
		blastdbcmd -db "$db" -entry_batch "$idFile" -outfmt "%f" > "$outFile"
		return
	fi

	local chunkPrefix="$idFile.chunk."
	rm -f "$chunkPrefix"*
	split -n "l/$numChunks" "$idFile" "$chunkPrefix"

	local pids=()
	local chunkOutFiles=()
	local chunkFile
	for chunkFile in "$chunkPrefix"*
	do
		local chunkOut="$chunkFile.fasta"
		blastdbcmd -db "$db" -entry_batch "$chunkFile" -outfmt "%f" > "$chunkOut" &
		pids+=($!)
		chunkOutFiles+=("$chunkOut")
	done

	local pid
	for pid in "${pids[@]}"
	do
		wait "$pid"
	done

	# Same "never trust blastdbcmd's exit code" reasoning as the call
	# sites below applies per-chunk too - just concatenate whatever each
	# chunk actually produced and let the existing post-hoc ID
	# reconciliation (comm against the requested ID list) catch anything
	# missing, exactly as it already does for a single non-parallel call.
	cat "${chunkOutFiles[@]}" > "$outFile"
	rm -f "$chunkPrefix"*
}

# Extract the sequences from uniprot - skipped entirely once already
# done (see the resume comment above), since a job resuming into the
# much slower efetch phase below shouldn't have to redo this first.
uniprotDoneMarker="$sequences/UniprotExtraction.ok"
if [ ! -f "$uniprotDoneMarker" ]
then
	rm -f $tmpIDs
	rm -f $sequenceFile
	rm -f "$sequenceFileBase.part_"*".fasta"

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
		runBlastdbcmdParallel "$DB_PATH" "$tmpIDs" "$dbRawFile"

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

	touch "$uniprotDoneMarker"
else
	echo "$uniprotDoneMarker already exists - uniprot extraction already done, skipping" >&2
fi

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

# Any database in $builtLocalDatabases above has its hits included in
# $IDs and would normally be fetched remotely via efetch below like every
# other NCBI-sourced hit. But its sequences are already sitting right on
# disk, so pull its IDs out of the efetch pool and extract them directly
# with blastdbcmd instead, entirely avoiding NCBI's efetch service (and
# its own separate flakiness - see the retry hardening below) for however
# many of this gene's hits came from it.
IFS=':' read -ra confirmedLocalDatabases <<< "$builtLocalDatabases"
for db in "${confirmedLocalDatabases[@]}"
do
	[ -z "$db" ] && continue
	dbPath="$DIR/ProteinDatabase/$db/$db"
	dbHitsFile="$hits/$db/SortedHitsByName.csv"
	if [ -f "$dbHitsFile" ]
	then
		dbIDs=($(sed -E "s/^ *[0-9]* //g" "$dbHitsFile" | cut -f 1 | sort -u))
		if [ ${#dbIDs[@]} -gt 0 ]
		then
			dbIDsFile="$sequences/$db.local_ids.txt"
			dbRawFile="$sequences/$db.local.fasta"
			dbGoodFile="$sequences/$db.local.good.fasta"
			printf '%s\n' "${dbIDs[@]}" > "$dbIDsFile"
			runBlastdbcmdParallel "$dbPath" "$dbIDsFile" "$dbRawFile"

			# Same reasoning as the efetch loop below: never trust
			# blastdbcmd's exit code as pass/fail for the whole batch (a
			# missing/suppressed entry is reported per-ID on stderr, not
			# as a nonzero exit - blastdbcmd still exits 0 overall and
			# just skips it) and never blindly append its raw output
			# either. extractRequestedRecords keeps only genuine records
			# for IDs actually asked for.
			extractRequestedRecords "$dbRawFile" "$dbIDsFile" > "$dbGoodFile"
			cat "$dbGoodFile" >> $sequenceNCBIFile

			# Anything blastdbcmd couldn't find locally (e.g. added to
			# NCBI's real database after this local copy was last
			# updated) stays in $IDs below and gets the normal remote
			# efetch treatment instead of being silently lost - only the
			# IDs genuinely extracted here are removed from that pool.
			fetchedDbIDs=$(getNormalizedIDs "$dbGoodFile" | sort -u)
			missingDbIDs=$(comm -23 <(sort -u "$dbIDsFile") <(echo "$fetchedDbIDs"))
			if [ -n "$missingDbIDs" ]
			then
				echo "blastdbcmd could not find these $db ID(s) in the local copy, falling back to remote efetch for them: $(echo "$missingDbIDs" | tr '\n' ' ')" >&2
			fi
			mapfile -t IDs < <(comm -23 <(printf '%s\n' "${IDs[@]}" | sort -u) <(echo "$fetchedDbIDs"))

			rm -f "$dbIDsFile" "$dbRawFile" "$dbGoodFile"
		fi
	fi
done

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
	# A batch already fully resolved by a previous (possibly interrupted)
	# attempt gets skipped outright, not just retried faster - its results
	# are already sitting in $sequenceNCBIFile from that earlier run (no
	# longer wiped at the top of this script, see the resume comment
	# above). Only touched once every ID in the batch is genuinely
	# accounted for (fetched, or a confirmed/known-dead accession) -
	# batchFullyResolved is reset every iteration and only ever flipped to
	# "false" further below, when some ID is neither, so a batch with a
	# real unexplained failure deliberately stays unmarked and gets a
	# fresh set of retries on the next attempt instead of being skipped
	# forever.
	batchDoneMarker="$sequences/efetch_batch_$i.done"
	if [ -f "$batchDoneMarker" ]
	then
		let i+=range
		continue
	fi
	batchFullyResolved="true"

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
				# Release via an EXIT trap, not just the plain call right after
				# the append below - see get_vcmsa_env.sh's identical lock for
				# why: a plain call there never ran when a task got killed
				# mid-critical-section, orphaning the lock for everyone else
				# until its full staleAfterSeconds elapsed. Cleared again right
				# after releasing so it doesn't linger armed for the rest of
				# this script's (possibly much later) normal exit.
				if ! acquireLockDir "$knownDeadFile.lockdir"
				then
					echo "Failed to acquire $knownDeadFile.lockdir - see acquireLockDir's own error above" >&2
					exit 1
				fi
				trap 'releaseLockDir "$knownDeadFile.lockdir"' EXIT
				{
					echo ""
					echo "# Auto-confirmed dead $(date -I) ($gene, efetch's own \"Failed to retrieve sequence\" response)"
					printf '%s\n' "${newlyConfirmedDead[@]}"
				} >> "$knownDeadFile"
				releaseLockDir "$knownDeadFile.lockdir"
				trap - EXIT
				knownDeadIDs=$(printf '%s\n%s\n' "$knownDeadIDs" "${newlyConfirmedDead[*]}" | tr ' ' '\n' | sort -u)
			fi

			if [ ${#stillUnexplained[@]} -gt 0 ]
			then
				echo "efetch permanently failed for unexpected ID(s) in batch $i..$((i + range - 1)) after $maxTrials trials: ${stillUnexplained[*]}" >&2
				failed="true"
				batchFullyResolved="false"
			fi
		fi
	fi

	if [ "$batchFullyResolved" == "true" ]
	then
		touch "$batchDoneMarker"
	fi

	let i+=range
done

if [ "$failed" == "true" ]
then
	echo "Some NCBI sequences could not be fetched, see above for which ID ranges - $sequenceNCBIFile is incomplete" >&2
	exit 1
fi

# Skipped if a previous attempt already finished this too - needed since
# a fully-resumed run (every batch above already marked done) never
# appends anything new to $sequenceNCBIFile, and a prior successful run
# already removed it right after this same split, so it wouldn't even
# exist to split again.
ncbiExtractionDoneMarker="$sequences/NCBIExtraction.ok"
if [ ! -f "$ncbiExtractionDoneMarker" ]
then
	# Only the split *.part_*.fasta output, never a bare
	# "$sequenceNCBIFileBase*.fasta" glob - that would also match
	# $sequenceNCBIFile itself ($sequenceNCBIFileBase with no infix at
	# all still satisfies a middle "*"), deleting the very file about to
	# be split right before splitting it - confirmed 2026-07-29 while
	# testing this resume logic end to end.
	rm -f "$sequenceNCBIFileBase.part_"*".fasta"

	# A gene with zero NCBI-sourced hits (numIDs=0 above, so the while
	# loop never runs) never creates $sequenceNCBIFile at all - pre-existing
	# behavior, not introduced by the resume logic here, but worth guarding
	# against now that this block is conditional anyway rather than letting
	# seqkit error on a file that was never going to exist.
	if [ -s "$sequenceNCBIFile" ]
	then
		# Split the sequence file into handy chuncks if we want to store it on github
		# The maximum file size is 100 MB, but we should stay below of that.
		seqkit split2 -j $numTreads -s $splitSeqNum -O $sequences $sequenceNCBIFile
		rm -f $sequenceNCBIFile
	fi

	touch "$ncbiExtractionDoneMarker"
fi
