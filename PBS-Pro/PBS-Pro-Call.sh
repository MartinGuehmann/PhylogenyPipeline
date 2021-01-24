
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

gene="$1"
step="$2"
iteration="$3"
aligner="$4"
depend="$5"
hold="$6"
extraBit="$7"

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

if [ -z "$aligner" ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

if [ -z "$depend" ]
then
	depend=""
else
	depend="-W depend=afterok$depend"
fi

if [ -z "$hold" ]
then
	hold=""
else
	if [ $hold == "$hold" ]
	then
		hold="-h"
	else
		hold=""
	fi
fi

alignFileStart="$DIR/09_PBS-Pro-AlignWith"
bashExtension="sh"
alignerFile="$alignFileStart$aligner.$bashExtension"

if [ -z "$alignerFile" ]
then
	echo "Aligner file for $aligner does not exist."
	aligner=$($DIR/../GetDefaultAligner.sh)
	echo "Use default aligner $aligner instead."
	alignerFile="$alignFileStart$aligner.$bashExtension"
fi

SequencesOfInterestDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner")

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

AlignmentDir=$("$DIR/../GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner")
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=".alignment.$aligner.fasta.raxml.reduced.phy"
AllSeqs="$AlignmentDir/SequencesOfInterest$AlignmentLastBit"

jobIDs=""

case $step in
#0)
#	Depends on the server of NCBI, thus quite slow and thus a cluster is not useful
#	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/00_PBS-Pro-GetGenesFromAllDataBases.sh")
#	;;
1)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/01_PBS-Pro-CombineHitsForEachDatabase.sh")
	;;
2)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/02_PBS-Pro-CombineHitsFromAllNCBIDatabases.sh")
	;;
#3)
#	Efetch is missing for that, anyway this can be done on a laptop
#	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/03_PBS-Pro-ExtractSequences.sh")
#	;;
4)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/04_PBS-Pro-MakeNonRedundant.sh")
	;;
5)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/05_PBS-Pro-MakeClansFile.sh")
	;;
6)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/06_PBS-Pro-ClusterWithClans.sh")
	;;
7)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/07_PBS-Pro-MakeTreeForPruning.sh")
	;;
8)
	jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/08_PBS-Pro-ExtractSequencesOfInterest.sh")
	;;
9)
	if [[ ! -z $extraBit && $extraBit == "allSeqs" ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest, iteration=$iteration" "$alignerFile")
	else
		for fastaFile in "$SequencesOfInterestParts"+([0-9])".fasta"
		do
			if [[ -f $fastaFile ]]
			then
				jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile, iteration=$iteration" "$alignerFile")
			fi
		done
	fi
	;;
10)
	if [[ ! -z $extraBit && $extraBit == "allSeqs" ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$AllSeqs, iteration=$iteration, aligner=$aligner" "$DIR/10_PBS-Pro-Long-MakeTreeWithIQ-Tree.sh")
	else
		for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
		do
			if [[ -f $phyFile ]]
			then
				jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile, iteration=$iteration, aligner=$aligner" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh")
			fi
		done
	fi
	;;
11)
	jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, shuffleSeqs=$extraBit" "$DIR/11_PBS-Pro-RemoveRogues.sh")
	;;

# Adjust lastStep if you add more steps here
*)
	echo "Step $step is not a valid step."
esac

echo $jobIDs
