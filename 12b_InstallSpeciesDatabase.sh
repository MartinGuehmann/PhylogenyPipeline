#!/bin/bash

# This bash script downloads and unpacks the species species database
# from NCBI. Then it extract the full linage entries of the genera to be used.

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

speciesDatabase="$DIR/SpeciesDatabase"
genusLinagesRaw="$speciesDatabase/rankedlineage.dmp"
genusLinagesFull="$speciesDatabase/fullnamelineage.dmp"
genusLinages="$speciesDatabase/GenusLinage.csv"
taxonIDs="$speciesDatabase/TaxonIds.txt"

mkdir -p "$speciesDatabase"

# Download and unpack the species database if it is not already there
if [[ ! -f "$genusLinagesRaw" ]]
then
	cd "$speciesDatabase"
	wget "ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/taxdump_readme.txt"
	wget "ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/new_taxdump.tar.gz"
	tar xvzf "new_taxdump.tar.gz"
fi

# extract the genus entries from the full lineage species database
if [[ ! -f "$genusLinages" ]]
then
	# That is a dirty workaround with the 10 underscores
	# with ^ matching the bbeginning of the line directly
	# grep runs out of memory
	grep -o -e "^[[:digit:]]\+	|	[[:alpha:]]\+	|		|		|	[[:alpha:]]\+	|" $genusLinagesRaw | \
	grep -o -e "^[[:digit:]]\+" | \
	sed "s/^\(.*$\)/__________\1/g" > $taxonIDs

	sed "s/^\(.*$\)/__________\1/g" $genusLinagesFull | \
	grep -w -f $taxonIDs | \
	sed "s/\t|\t/\t/g" | \
	sed "s/ \t|//g" | \
	sed "s/^__________//g" > "$genusLinages"
fi
