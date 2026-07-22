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

source "$DIR/Databases.sh"

declare -a pids=()
declare -a dbNames=()

# nr is normally searched remotely (see Databases.sh) - NCBI's own CPU
# quota can kill a broad-homology gene's remote search outright (SIGXCPU),
# and the remote path is generally more fragile than a local one. If
# --localNr was passed and a local copy exists, search that copy instead,
# pulled out of RemoteDataBases below. No build/download step here unlike
# the uniprot databases above: a local nr copy is 200+GB and expected to
# be fetched and kept updated separately (e.g. via NCBI's own
# update_blastdb.pl, run manually or as its own cron job), not managed by
# this pipeline.
localNrPath="$DIR/ProteinDatabase/nr/nr"
declare -a remainingRemoteDataBases=()
for DB in "${RemoteDataBases[@]}"
do
	if [ "$localNr" == "--localNr" ] && [ "$DB" == "nr" ]
	then
		# blastdbcmd (rather than guessing file extensions ourselves)
		# correctly resolves a BLAST database regardless of BLAST+
		# version/on-disk format, and regardless of whether nr is split
		# into multiple volumes (it will be, at this size).
		if command -v blastdbcmd >/dev/null 2>&1 && blastdbcmd -db "$localNrPath" -info >/dev/null 2>&1
		then
			LocalDataBases+=("$localNrPath")
		else
			echo "--localNr was given but no local nr BLAST database was found at $localNrPath - falling back to remote nr" >&2
			remainingRemoteDataBases+=("$DB")
		fi
	else
		remainingRemoteDataBases+=("$DB")
	fi
done
RemoteDataBases=("${remainingRemoteDataBases[@]}")

# Each local database is built and then searched as its own background
# chain, independent of the other one - uniprot_sprot's search can start
# the moment uniprot_sprot is built, without waiting on uniprot_trembl
# (usually the much bigger, slower one to build) or vice versa. All of
# this also runs concurrently with the remote searches below, since NCBI's
# one-request-at-a-time rule only applies to BLAST+ searches against their
# servers, not to plain file downloads or local searches.
for DB in "${LocalDataBases[@]}"
do
	dbName=$(basename $DB)
	(
		if [ "$dbName" == "nr" ] || "$DIR/ProteinDatabase/get_uniprot_database.sh" "$dbName"
		then
			"$DIR/00a_GetGenes.sh" $gene $DB
		else
			echo "Failed to get/build $dbName" >&2
			exit 1
		fi
	) &
	pids+=($!)
	dbNames+=("$dbName")
done

failed="false"

# NCBI asks that only one BLAST+ remote search run against their servers at
# a time (see the BLAST+ remote service docs), so these run one after
# another instead of in parallel - concurrently with the per-database
# build+search chains above, since they don't depend on them.
for DB in "${RemoteDataBases[@]}"
do
	if ! "$DIR/00a_GetGenes.sh" $gene $DB
	then
		echo "Failed to fully extract sequences from $(basename $DB)" >&2
		failed="true"
	fi
done

for ((i = 0; i < ${#pids[@]}; i++))
do
	if ! wait "${pids[$i]}"
	then
		echo "Failed to get/build or search ${dbNames[$i]}" >&2
		failed="true"
	fi
done

if [ "$failed" == "true" ]
then
	exit 1
fi
