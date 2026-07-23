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
# --localNr was passed, search a local copy instead, pulled out of
# RemoteDataBases below and treated just like the uniprot databases: the
# build loop further down fetches it (via get_nr_database.sh) if it isn't
# there yet, once, and reuses it across runs after that.
localNrPath="$DIR/ProteinDatabase/nr/nr"
declare -a remainingRemoteDataBases=()
for DB in "${RemoteDataBases[@]}"
do
	if [ "$localNr" == "--localNr" ] && [ "$DB" == "nr" ]
	then
		LocalDataBases+=("$localNrPath")
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
		if [ "$dbName" == "nr" ]
		then
			"$DIR/ProteinDatabase/get_nr_database.sh"
			nrStatus=$?
			if [ $nrStatus -eq 0 ]
			then
				"$DIR/00a_GetGenes.sh" $gene $DB
			elif [ $nrStatus -eq 2 ]
			then
				# nr specifically couldn't be fetched/built (see
				# get_nr_database.sh's exit code contract) - a working
				# remote nr search doesn't depend on any of that, so fall
				# back to it here instead of failing the whole run. This
				# can rarely run concurrently with the sequential remote
				# loop below (its own blastp -remote call, plus this
				# one) - acceptable since it only happens on this
				# failure path, unlike the deliberate one-at-a-time
				# sequencing below.
				echo "--localNr was given but the local nr database could not be fetched/built - falling back to remote nr for this run" >&2
				"$DIR/00a_GetGenes.sh" $gene nr
			else
				echo "Failed to get/build nr" >&2
				exit 1
			fi
		else
			if "$DIR/ProteinDatabase/get_uniprot_database.sh" "$dbName"
			then
				"$DIR/00a_GetGenes.sh" $gene $DB
			else
				echo "Failed to get/build $dbName" >&2
				exit 1
			fi
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
