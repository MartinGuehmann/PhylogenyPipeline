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
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./RunAll.sh GeneName StepNumber"
	exit
fi

if [ -z "$step" ]
then
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./RunAll.sh GeneName StepNumber"
	exit
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
	;&
3)
	echo "3. Extract sequences from the databases."
	$DIR/ExtractSequences.sh $gene
	echo "3. Sequences from the database were extracted."
	;&
4)
	echo "4. Make non redundant databases."
	$DIR/MakeNonRedundant.sh $gene
	echo "4. Non reduntant database were made."
	;&
5)
	echo "5. Align sequences with regressive T-Coffee."
	$DIR/AlignWithTCoffee.sh $gene
	echo "5. Sequences aligned with regressive T-Coffee."
	;;
*)
	echo "Step $step is not a valid step."
esac
