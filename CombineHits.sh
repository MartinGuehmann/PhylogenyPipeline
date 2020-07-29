#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
gene="$1"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./RunAll.sh GeneName"
	exit
fi

databaseName=$(basename $2)

HITS="$DIR/$gene/Hits/$databaseName"
sorted="$HITS/SortedHitsByName.csv"
sortedUnique="$HITS/SortedHitsByNameUnique.csv"

allHits="$HITS/CombinedHits.csv"

rm -f $allHits
rm -f $sorted
rm -f $sortedUnique

for fastaFile in "$HITS/"*.csv
do
	cut -f 1,2 $fastaFile | sort -u >> $allHits
done

sort -k 2 $allHits | uniq -c > $sorted

sort -k 2 $allHits | uniq -u > $sortedUnique

rm -f $allHits # Remove this file since it uses up some space
