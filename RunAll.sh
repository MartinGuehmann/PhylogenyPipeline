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
shopt -s extglob

iteration="0"
shuffleSeqs=""
suffix=""

# Idiomatic parameter and option handling in sh
# Adapted from https://superuser.com/questions/186272/check-if-any-of-the-parameters-to-a-bash-script-match-a-string
# And advanced version is here https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash/7069755#7069755
while test $# -gt 0
do
    case "$1" in
        --gene)
            ;&
        -g)
            shift
            gene="$1"
            ;;
        --step)
            ;&
        -s)
            shift
            step="$1"
            ;;
        --lastStep)
            ;&
        -l)
            shift
            last="$1"
            ;;
        --iteration)
            ;&
        -i)
            shift
            iteration="$1"
            ;;
        --aligner)
            ;&
        -a)
            shift
            aligner="$1"
            ;;
        --file)
            ;&
        -f)
            shift
            seqsToAlignOrAlignment="$1"
            ;;
        --shuffleSeqs)
            ;&
        -l)
            shuffleSeqs="--shuffleSeqs"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix="-x $1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored"
            ;;
    esac
    shift
done

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

if [ -z "$aligner" ]
then
	aligner=$("$DIR/GetDefaultAligner.sh")
fi

alignFileStart="$DIR/09_AlignWith"
bashExtension="sh"
alignerFile="$alignFileStart$aligner.$bashExtension"

if [ -z "$alignerFile" ]
then
	echo "Aligner file for $aligner does not exit."
	echo "Use default aligner $defaultAligner instead."
	aligner=$defaultAligner
	alignerFile="$alignFileStart$aligner.$bashExtension"
fi

SequencesOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

AlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=".alignment.$aligner.fasta.raxml.reduced.phy"
AllSeqs="$AlignmentDir/SequencesOfInterest$AlignmentLastBit"
UFBootPart="$AlignmentLastBit.ufboot"
AllSeqsUFBoot="$AllSeqs.ufboot"

# Note this must be set to the last available step
lastStep="11"

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
		echo "9. Align sequences with $aligner."
		if [ -z "$seqsToAlignOrAlignment" ]
		then
			for fastaFile in "$SequencesOfInterestParts"+([0-9])".fasta"
			do
				if [ -f $fastaFile ]
				then
					"$alignerFile" "$gene" "$fastaFile" "$AlignmentDir"
				fi
			done
			# We deal with the big alignment in the end
			#"$alignerFile" "$gene" "$SequencesOfInterest" "$AlignmentDir"
		else
			$alignerFile "$gene" "$seqsToAlignOrAlignment" "$AlignmentDir"
		fi
		echo "9. Sequences aligned with $aligner."
		;;
	10)
		echo "10. Build trees with IQ-Tree."
		if [ -z "$seqsToAlignOrAlignment" ]
		then
			for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
			do
				if [ -f $phyFile ]
				then
					$DIR/10_MakeTreeWithIQ-Tree.sh "$phyFile"
				fi
			done
			# We deal with the big alignment in the end
			#$DIR/10_MakeTreeWithIQ-Tree.sh "$AllSeqs"
		else
			$DIR/10_MakeTreeWithIQ-Tree.sh "$seqsToAlignOrAlignment"
		fi
		echo "10. Trees built with IQ-Tree."
		;;
	11)
		echo "11. Remove rogue sequences with RogueNaRok and TreeShrink."
		$DIR/11a_PrepareForRemovingRogues.sh "$SequencesOfInterestDir"
		for ufbootFile in "$AlignmentParts"*"$UFBootPart"
		do
			if [ -f $ufbootFile ]
			then
				$DIR/11_RemoveRogues.sh -g "$gene" -f "$ufbootFile" -a "$aligner" -i "$iteration" $suffix
			fi
		done
		if [ -f $AllSeqsUFBoot ]
		then
			$DIR/11_RemoveRogues.sh -g "$gene" -f $AllSeqsUFBoot -a "$aligner" -i "$iteration" $suffix
		fi
		$DIR/11b_ExtractNonRogues.sh -g "$gene" -a "$aligner" -i "$iteration" $shuffleSeqs $suffix
		echo "11. Rogue sequences removed with RogueNaRok and TreeShrink."
		;;

	# Adjust lastStep if you add more steps here
	*)
		echo "Step $i is not a valid step."
	esac
done
