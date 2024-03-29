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

# Uniprot databases not needed here
# Download and make the uniprot databases if they do not exist
#"$DIR/ProteinDatabase/get_uniprot_databases.sh"

#TRMBL="$DIR/ProteinDatabase/uniprot_trembl/uniprot_trembl"
#SPROT="$DIR/ProteinDatabase/uniprot_sprot/uniprot_sprot"

declare -a DataBases=(
                    # Exclude local databases
                    # $TRMBL            # UniProt TRMBL saved locally
                    # $SPROT            # UniProt SwissProt saved locally
                      "nr"              # Non-redundant protein sequences
                      "refseq_protein"  # Reference proteins
                    # "landmark"        # Model Organisms, does not work
                      "swissprot"       # UniProtKB/Swiss-Prot, just the confirmed sequences, the version from uniprot is more up to date, but including those does not hurt
                    # "pataa"           # Patented protein sequences, mutated proteins from patients are not needed
                    # "pdb"             # Protein Data Bank Proteins, chimeras for christalization just screw up things
                    # "env_nr"          # Metagenomic proteins, most come back empty for opsins, so it is not worth 
                      "tsa_nr"          # Transcriptome Shotgun Assembly proteins
                     )


hitsAll="$DIR/$gene/Hits/All"

mkdir -p $hitsAll
hitsAllFile="$hitsAll/AllHits.csv"
sorted="$hitsAll/SortedHitsByName.csv"
sortedUnique="$hitsAll/AllHitsUnique.csv"

rm -f $hitsAllFile
                     
for DB in "${DataBases[@]}"
do
	databaseName=$(basename $DB)
	hitsFile="$DIR/$gene/Hits/$databaseName/SortedHitsByName.csv"

	sed -E "s/^ *[0-9]* //g" $hitsFile >> $hitsAllFile
done


sort -k 2 $hitsAllFile | uniq -c > $sorted

# Nice for some statistics, but we don't need that here
# sort -k 2 $hitsAllFile | uniq -u > $sortedUnique

rm -f $hitsAllFile # Remove this file since it uses up some space
