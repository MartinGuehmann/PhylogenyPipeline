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
localDatabases="$2"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

source "$DIR/Databases.sh"

declare -a pids=()
declare -a dbNames=()

# NCBI's databases (see Databases.sh's RemoteDataBases) are normally
# searched remotely - NCBI's own CPU quota can kill a broad-homology
# gene's remote search outright (SIGXCPU), and the remote path is
# generally more fragile than a local one. $localDatabases is a
# colon-separated list of RemoteDataBases names (e.g. "nr:refseq_protein")
# opted into a local copy instead - colon-, not comma-separated, since
# this reaches this script via Slurm's --export=Var1=Val1,Var2=Val2,
# which already uses comma to separate different variables (see
# Scheduler-Call.sh's own comment on this). Pulled out of RemoteDataBases
# below into their own array (not mixed into the uniprot LocalDataBases,
# since they need a different build script - get_ncbi_blastdb.sh instead
# of get_uniprot_database.sh) and built/searched the same way as the
# uniprot databases: fetched once if not there yet, reused across runs
# after that.
declare -a LocalNCBIDataBases=()
declare -a remainingRemoteDataBases=()
for DB in "${RemoteDataBases[@]}"
do
	if [[ ":$localDatabases:" == *":$DB:"* ]]
	then
		LocalNCBIDataBases+=("$DIR/ProteinDatabase/$DB/$DB")
	else
		remainingRemoteDataBases+=("$DB")
	fi
done
RemoteDataBases=("${remainingRemoteDataBases[@]}")

# Each local database is built and then searched as its own background
# chain, independent of the others - uniprot_sprot's search can start the
# moment uniprot_sprot is built, without waiting on uniprot_trembl
# (usually the much bigger, slower one to build) or vice versa. All of
# this also runs concurrently with the remote searches below, since NCBI's
# one-request-at-a-time rule only applies to BLAST+ searches against their
# servers, not to plain file downloads or local searches.
for DB in "${LocalDataBases[@]}"
do
	dbName=$(basename $DB)
	(
		if "$DIR/ProteinDatabase/get_uniprot_database.sh" "$dbName"
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

# Same idea for any NCBI database opted into $localDatabases above (nr,
# refseq_protein, tsa_nr) - unlike the uniprot databases, a working remote
# search doesn't depend on any of this, so a database that specifically
# couldn't be fetched/built (get_ncbi_blastdb.sh's exit code 2) falls back
# to searching it remotely instead of failing the whole run outright.
for DB in "${LocalNCBIDataBases[@]}"
do
	dbName=$(basename $DB)
	(
		"$DIR/ProteinDatabase/get_ncbi_blastdb.sh" "$dbName"
		dbStatus=$?
		if [ $dbStatus -eq 0 ]
		then
			"$DIR/00a_GetGenes.sh" $gene $DB
		elif [ $dbStatus -eq 2 ]
		then
			# This can rarely run concurrently with the sequential remote
			# loop below (its own blastp -remote call, plus this one) -
			# acceptable since it only happens on this failure path,
			# unlike the deliberate one-at-a-time sequencing below.
			echo "$dbName was opted into localDatabases but could not be fetched/built locally - falling back to a remote search for this run" >&2
			"$DIR/00a_GetGenes.sh" $gene "$dbName"
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
