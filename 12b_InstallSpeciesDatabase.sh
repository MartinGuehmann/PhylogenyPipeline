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

	# Remove these files if they already exist
	# Something at downloading might have went wrong
	# Redownloads are appended with a suffix
	rm -f "taxdump_readme.txt"
	rm -f "new_taxdump.tar.gz"

	wget "ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/taxdump_readme.txt"
	wget "ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/new_taxdump/new_taxdump.tar.gz"
	tar xvzf "new_taxdump.tar.gz"
fi

# extract the genus entries from the full lineage species database
if [[ ! -f "$genusLinages" ]]
then
	sed -E "/^[0-9]+	\|	[a-zA-Z]+ .*$/d" $genusLinagesFull | \
	sed -E "s/	\|//g" | \
	sed -E "s/ $//g" > "$genusLinages"
fi
