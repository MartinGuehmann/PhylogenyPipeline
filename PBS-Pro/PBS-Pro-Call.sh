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
iteration="$3"
aligner="$4"

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

if [ -z "$iteration" ]
then
	iteration="0"
fi

defaultAligner="FAMSA"

if [ -z "$aligner" ]
then
	aligner="$defaultAligner"
fi

alignFileStart="$DIR/09_PBS-Pro-AlignWith"
bashExtension="sh"
alignerFile="$alignFileStart$aligner.$bashExtension"

if [ -z "$alignerFile" ]
then
	echo "Aligner file for $aligner does not exit."
	echo "Use default aligner $defaultAligner instead."
	aligner=$defaultAligner
	alignerFile="$alignFileStart$aligner.$bashExtension"
fi


if [ $iteration == 0 ]
then
	SequencesOfInterestDir="$DIR/../$gene/SequencesOfInterest.RogueIter_$iteration"
else
	SequencesOfInterestDir="$DIR/../$gene/SequencesOfInterest.$aligner.RogueIter_$iteration"
fi

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

RogueFreeSequencesDir="$DIR/../$gene/RogueFreeTrees"
RogueFreeSequences="$RogueFreeSequencesDir/SequencesOfInterest.roked.fasta"
RogueFreeSequencesParts="$RogueFreeSequencesDir/$partSequences"

RogueFreeAlignmentDir="$DIR/../$gene/RogueFreeAlignments"
RogueFreeAlignmentParts="$RogueFreeAlignmentDir/$partSequences"

AlignmentDir="$DIR/../$gene/Alignments.$aligner.RogueIter_$iteration"
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=".alignment.$aligner.fasta.raxml.reduced.phy"
AllSeqs="$AlignmentDir/SequencesOfInterest$AlignmentLastBit"

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
			qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile, iteration=$iteration" "$alignerFile"
		fi
	done
	qsub -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest, iteration=$iteration" "$alignerFile"
	;;
10)
	for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
	do
		if [ -f $phyFile ]
		then
			qsub -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile, iteration=$iteration, aligner=$aligner" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh"
		fi
	done
	qsub -v "DIR=$DIR, gene=$gene, alignmentToUse=$AllSeqs, iteration=$iteration, aligner=$aligner" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh"
	;;
11)
	qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner" "$DIR/11_PBS-Pro-RemoveRogues.sh"
	;;

# Adjust lastStep if you add more steps here
*)
	echo "Step $step is not a valid step."
esac
