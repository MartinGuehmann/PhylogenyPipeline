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
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

TRMBL="$DIR/../ProteinDatabase/uniprot_trembl/uniprot_trembl"
SPROT="$DIR/../ProteinDatabase/uniprot_sprot/uniprot_sprot"

declare -a DataBases=(
                      $TRMBL            # UniProt TRMBL saved locally
                      $SPROT            # UniProt SwissProt saved locally
                      "nr"              # Non-redundant protein sequences
                      "refseq_protein"  # Reference proteins
                    # "landmark"        # Model Organisms, does not work
                      "swissprot"       # UniProtKB/Swiss-Prot, just the confirmed sequences, the version from uniprot is more up to date, but including those does not hurt
                    # "pataa"           # Patented protein sequences, mutated proteins from patients are not needed
                    # "pdb"             # Protein Data Bank Proteins, chimeras for christalization just screw up things
                    # "env_nr"          # Metagenomic proteins, most come back empty for opsins, so it is not worth 
                      "tsa_nr"          # Transcriptome Shotgun Assembly proteins
                     )

for DB in "${DataBases[@]}"
do
	$DIR/GetGenes.sh $gene $DB &
done

wait # Wait on all the instances of GetGenes.sh having finished
