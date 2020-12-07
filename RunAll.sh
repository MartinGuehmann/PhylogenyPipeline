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
step="$2"
last="$3"
seqsToAlign="$4"

if [ -z "$gene" ]
then
	echo "GeneName missing"
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./$thisScript GeneName StepNumber"
	exit
fi

if [ -z "$step" ]
then
	echo "StepNumber missing"
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./$thisScript GeneName StepNumber"
	exit
fi

SequencesOfInterestDir="$DIR/$gene/SequencesOfInterest"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/SequencesOfInterestShuffled.part_"

# Note this must be set to the last available step
lastStep="9"

if [ -z "$last" ]
then
	last=$lastStep
fi

if [[ $last -gt $lastStep ]]
then
	last=$lastStep
fi

echo "Reconstruct phylogeny for $gene."
echo ""

for ((i=$step;i<=last;i++))
do
	case $i in
	0)
		# Note if you want to rerun this step you must delete the files in \$gene\Hits\
		echo "0. Obtaining gene IDs from all databases."
		echo "   Searching for sequences in NCBI databases remotely, takes some time."
		echo "   Therefore, just skip if files in $DIR/$gene/Hits/ already exist."
		$DIR/00_GetGenesFromAllDataBases.sh "$gene"
		echo "0. Gene IDs from all databases were obtained."
		;;
	1)
		echo "1. Combine the gene IDs for each database into one file, remove duplicates."
		$DIR/01_CombineHitsForEachDatabase.sh "$gene"
		echo "1. Gene IDs for each database were combined into one file, duplicates were removed."
		;;
	2)
		echo "2. Combine the gene IDs for each database into one file, remove duplicates."
		$DIR/02_CombineHitsFromAllNCBIDatabases.sh "$gene"
		echo "2. Gene IDs for each database were combined into one file, duplicates were removed."
		;;
	3)
		echo "3. Extract sequences from the databases."
		$DIR/03_ExtractSequences.sh "$gene"
		echo "3. Sequences from the database were extracted."
		;;
	4)
		echo "4. Make non redundant databases."
		$DIR/04_MakeNonRedundant.sh "$gene"
		echo "4. Non reduntant database were made."
		;;
	5)
		echo "5. Prepare sequences for CLANS."
		$DIR/05_MakeClansFile.sh "$gene"
		echo "5. Sequences have been prepared for CLANS."
		;;
	6)
		echo "6. Cluster sequences with CLANS."
		$DIR/06_ClusterWithClans.sh "$gene"
		echo "6. Sequences have been clustered with CLANS."
		;;
	7)
		echo "7. Create newick tree from CLANS file with neighbor joining for pruning."
		$DIR/07_MakeTreeForPruning.sh "$gene"
		echo "7. Newick tree from CLANS file with neighbor joining for pruning created."
		;;
	8)
		echo "8. Extract sequences of interest."
		$DIR/08_ExtractSequencesOfInterest.sh "$gene"
		echo "8. Sequences of interest extracted."
		;;
	9)
		echo "9. Align sequences with regressive T-Coffee."
		if [ -z "$seqsToAlign" ]
		then
			for fastaFile in "$SequencesOfInterestParts"*.fasta
			do
				if [ -f $fastaFile ]
				then
					$DIR/09_AlignWithTCoffee.sh "$gene" "$fastaFile"
				fi
			done
			$DIR/09_AlignWithTCoffee.sh "$gene" "$SequencesOfInterest"
		else
			$DIR/09_AlignWithTCoffee.sh "$gene" "$seqsToAlign"
		fi
		echo "9. Sequences aligned with regressive T-Coffee."
		;;

	# Adjust lastStep if you add more steps here
	*)
		echo "Step $i is not a valid step."
	esac
done
