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
            inputFile="$1"
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
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
            ;;
        --trimAl)
            ;&
        -t)
            shift
            if [ "$1" == "Default" ]
            then
                trimAl="0.1"
            else
                trimAl="$1"
            fi
            ;;
        --restore)
            ;&
        -r)
            restore="--restore"
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

SequencesOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix $previousAligner)

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

TreesForPruningFromPASTADir="$DIR/$gene/TreesForPruningFromPASTA"
TreesForPruningFromPASTAParts="SequencesForPruning.part_"

AlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=".alignment.$aligner.fasta.raxml.reduced.phy"
AllSeqs="$AlignmentDir/SequencesOfInterest$AlignmentLastBit"
UFBootPart="$AlignmentLastBit.ufboot"
AllSeqsUFBoot="$AllSeqs.ufboot"

echo "Reconstruct phylogeny for $gene."
echo ""

case $step in
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
	if [ -z "$inputFile" ]
	then
		for fastaFile in "$SequencesOfInterestParts"+([0-9])".fasta"
		do
			if [ -f $fastaFile ]
			then
				alignmentFile=$("$alignerFile" "$fastaFile" "$AlignmentDir")
				$DIR/09a_PostProcessAlignment.sh "$alignmentFile" "$trimAl"
			fi
		done
	else
		alignmentFile=$($alignerFile "$inputFile" "$AlignmentDir")
		$DIR/09a_PostProcessAlignment.sh "$alignmentFile" "$trimAl"
	fi
	echo "9. Sequences aligned with $aligner."
	;;
10)
	echo "10. Build trees with IQ-Tree."
	if [ -z "$inputFile" ]
	then
		for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
		do
			if [ -f $phyFile ]
			then
				$DIR/10_MakeTreeWithIQ-Tree.sh "$phyFile"
			fi
		done
	else
		$DIR/10_MakeTreeWithIQ-Tree.sh "$inputFile"
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
			$DIR/11_RemoveRogues.sh -g "$gene" -f "$ufbootFile" -a "$aligner" -i "$iteration" $suffix $previousAligner
		fi
	done
	if [ -f $AllSeqsUFBoot ]
	then
		$DIR/11_RemoveRogues.sh -g "$gene" -f $AllSeqsUFBoot -a "$aligner" -i "$iteration" $suffix $previousAligner
	fi
	$DIR/11b_ExtractNonRogues.sh -g "$gene" -a "$aligner" -i "$iteration" $shuffleSeqs $suffix $previousAligner $restore
	echo "11. Rogue sequences removed with RogueNaRok and TreeShrink."
	;;
12)
	echo "12. Visualise trees."
	echo "12. Trees visualized."
	;;
13)
	echo "13. Split sequences into chunks for subset extraction."
	echo "13. Sequences split into chunks for subset extraction."
	;;
14)
	echo "14. Build trees with PASTA for pruning."
	if [ -z "$inputFile" ]
	then
		for fastaFile in "$TreesForPruningFromPASTAParts"+([0-9])".fasta"
		do
			if [ -f $fastaFile ]
			then
				alignmentFile=$($DIR/09_AlignWithPASTA.sh "$fastaFile" "$TreesForPruningFromPASTADir")
			fi
		done
	else
		#Remove the gene argument
		alignmentFile=$($DIR/09_AlignWithPASTA.sh "$inputFile" "$TreesForPruningFromPASTADir")
	fi
	echo "14. Trees built with PASTA for pruning."
	;;
15)
	echo "15. Extract sequences of interest."
	echo "15. Sequences of interest extracted."
	;;
*)
	echo "Step $i is not a valid step."
esac
