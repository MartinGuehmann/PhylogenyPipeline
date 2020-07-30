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
step="$2"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./RunAll.sh GeneName"
	exit
fi

if [ -z "$step" ]
then
	step=0
fi

echo "Reconstruct phylogeny for $gene."
echo ""

case $step in
0)
	# Note if you want to rerun this step you must delete the files in \$gene\Hits\
	echo "0. Obtaining gene IDs from all databases."
	echo "   Searching for sequences in NCBI databases remotely, takes some time."
	echo "   Therefore, just skip if files in $DIR/$gene/Hits/ already exist."
	$DIR/GetGenesFromAllDataBases.sh $gene
	echo "0. Gene IDs from all databases were obtained."
	;&
1)
	echo "1. Combine the gene IDs for each database into one file, remove duplicates."
	$DIR/CombineHitsForEachDatabase.sh $gene
	echo "1. Gene IDs for each database were combined into one file, duplicates were removed."
	;&
2)
	echo "2. Combine the gene IDs for each database into one file, remove duplicates."
	$DIR/CombineHitsFromAllNCBIDatabases.sh $gene
	echo "2. Gene IDs for each database were combined into one file, duplicates were removed."
	;;
*)
	echo "Step $step is not a valid step."
esac
