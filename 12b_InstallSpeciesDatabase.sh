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
speciesLinages="$speciesDatabase/SpeciesLinage.csv"
ambiguousGenera="$speciesDatabase/AmbiguousGenera.txt"
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

# Genus names are not unique across kingdoms (botanical and zoological
# nomenclature codes are independent, so e.g. "Morus" is both a bird genus
# and the mulberry genus) - genusInterestingTaxaMap in
# 12_ConvertTreesToFigures.py only keys by genus, so on a collision whichever
# row happens to be read last from this file silently wins. Confirmed
# 2026-10-23 against a real tree: real vertebrates (a tenrec, a gannet, a
# night monkey, ...) were misclassified as Viridiplantae this way.
#
# Fix: also keep full binomial (genus+species) entries from the SAME
# already-downloaded fullnamelineage.dmp - normally excluded by the sed
# above - but ONLY for genera that are actually ambiguous (>1 distinct taxID
# row in GenusLinage.csv). This targets just the ~1355 genera that need it
# instead of keeping all ~2.7M species-level rows, so the result
# (SpeciesLinage.csv) stays about the same size as GenusLinage.csv itself
# (confirmed 2026-10-23: 131,222 lines vs GenusLinage.csv's 169,519) rather
# than the 872MB fullnamelineage.dmp this is drawn from.
if [[ ! -f "$ambiguousGenera" ]]
then
	awk -F'\t' '{print $2}' "$genusLinages" | sort | uniq -d > "$ambiguousGenera"
fi

if [[ ! -f "$speciesLinages" ]]
then
	awk -F'\t' '
		NR==FNR { ambiguous[$1] = 1; next }
		{
			split($3, words, " ")
			if (words[1] in ambiguous && words[2] != "") {
				print
			}
		}
	' "$ambiguousGenera" "$genusLinagesFull" | \
	sed -E "s/	\|//g" | \
	sed -E "s/ $//g" > "$speciesLinages"
fi
