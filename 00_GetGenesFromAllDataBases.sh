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

TRMBL="$DIR/ProteinDatabase/uniprot_trembl/uniprot_trembl"
SPROT="$DIR/ProteinDatabase/uniprot_sprot/uniprot_sprot"

declare -a LocalDataBases=(
                      $TRMBL            # UniProt TRMBL saved locally
                      $SPROT            # UniProt SwissProt saved locally
                     )

declare -a RemoteDataBases=(
                      "nr"              # Non-redundant protein sequences
                      "refseq_protein"  # Reference proteins
                    # "landmark"        # Model Organisms, does not work
                    # "swissprot"       # UniProtKB/Swiss-Prot, just the confirmed sequences, redundant with the local, more up-to-date uniprot_sprot above, not worth the extra NCBI remote load
                    # "pataa"           # Patented protein sequences, mutated proteins from patients are not needed
                    # "pdb"             # Protein Data Bank Proteins, chimeras for christalization just screw up things
                    # "env_nr"          # Metagenomic proteins, most come back empty for opsins, so it is not worth
                      "tsa_nr"          # Transcriptome Shotgun Assembly proteins
                     )

declare -a pids=()
declare -a dbNames=()

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
