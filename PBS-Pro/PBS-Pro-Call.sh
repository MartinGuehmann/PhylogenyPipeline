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

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterestDir="$DIR/../$gene/SequencesOfInterest"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

RogueFreeSequencesDir="$DIR/../$gene/RogueFreeTrees"
RogueFreeSequences="$RogueFreeSequencesDir/SequencesOfInterest.roked.fasta"
RogueFreeSequencesParts="$RogueFreeSequencesDir/$partSequences"

RogueFreeAlignmentDir="$DIR/../$gene/RogueFreeAlignments"
RogueFreeAlignmentParts="$RogueFreeAlignmentDir/$partSequences"

AliFAMSADir="$DIR/../$gene/AliFAMSA"
AliFAMSAParts="$AliFAMSADir/$partSequences"
AliFAMSALastBit=".aliFAMSA.fasta.raxml.reduced.phy"

AlignmentDir="$DIR/../$gene/Alignments"
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=".alignment.fasta.raxml.reduced.phy"

case $step in
#0)
#	Depends on the server of NCBI, thus quite slow and thus a cluster is not useful
#	qsub -v "DIR=$DIR, gene=$gene" "$DIR/00_PBS-Pro-GetGenesFromAllDataBases.sh"
#	;;
1)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/01_PBS-Pro-CombineHitsForEachDatabase.sh"
	;;
2)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/02_PBS-Pro-CombineHitsFromAllNCBIDatabases.sh"
	;;
#3)
#	Efetch is missing for that, anyway this can be done on a laptop
#	qsub -v "DIR=$DIR, gene=$gene" "$DIR/03_PBS-Pro-ExtractSequences.sh"
#	;;
4)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/04_PBS-Pro-MakeNonRedundant.sh"
	;;
5)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/05_PBS-Pro-MakeClansFile.sh"
	;;
6)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/06_PBS-Pro-ClusterWithClans.sh"
	;;
7)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/07_PBS-Pro-MakeTreeForPruning.sh"
	;;
8)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/08_PBS-Pro-ExtractSequencesOfInterest.sh"
	;;
9)
	for fastaFile in "$SequencesOfInterestParts"*.fasta
	do
		if [ -f $fastaFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile" "$DIR/09_PBS-Pro-AlignWithTCoffee.sh"
		fi
	done
	qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest" "$DIR/09_PBS-Pro-AlignWithTCoffee.sh"
	for fastaFile in "$SequencesOfInterestParts"*.fasta
	do
		if [ -f $fastaFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile" "$DIR/09_PBS-Pro-AlignWithTCoffee.sh"
		fi
	done
	qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest" "$DIR/09_PBS-Pro-AlignWithTCoffee.sh"
	;;
10)
	for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
	do
		if [ -f $phyFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh"
		fi
	done
	for phyFile in "$AliFAMSAParts"*"$AliFAMSALastBit"
	do
		if [ -f $phyFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh"
		fi
	done
	;;
11)
	qsub -v "DIR=$DIR, gene=$gene" "$DIR/11_PBS-Pro-RemoveRogues.sh"
	;;
12)
	for fastaFile in "$RogueFreeSequencesParts"*.roked.fasta
	do
		if [ -f $fastaFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile" "$DIR/12_PBS-Pro-AlignRogueFreeWithTCoffee.sh"
		fi
	done
	qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$RogueFreeSequences" "$DIR/12_PBS-Pro-AlignRogueFreeWithTCoffee.sh"
	;;
13)
	for phyFile in "$RogueFreeAlignmentParts"*"$AlignmentLastBit"
	do
		if [ -f $phyFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile" "$DIR/13_PBS-Pro-MakeRogueFreeTreeWithIQ-Tree.sh"
		fi
	done
	;;

# Adjust lastStep if you add more steps here
*)
	echo "Step $step is not a valid step."
esac
