
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
depend="$5"
hold="$6"

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
	echo "Aligner file for $aligner does not exit."
	aligner=$("$DIR/../GetDefaultAligner.sh")
	echo "Use default aligner $aligner instead."
	alignerFile="$alignFileStart$aligner.$bashExtension"
fi

SequencesOfInterestDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner")

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

AlignmentDir=$("$DIR/../GetAlignmentDirectory.sh" -d "$DIR" -g "$gene" -i "$iteration" -a "$aligner")
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=".alignment.$aligner.fasta.raxml.reduced.phy"
AllSeqs="$AlignmentDir/SequencesOfInterest$AlignmentLastBit"

jobIDs=""

#jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest, iteration=$iteration" "$alignerFile")
#holdJobs=$jobIDs
#echo $jobIDs
#depend=$jobIDs
jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$AllSeqs, iteration=$iteration, aligner=$aligner" "$DIR/10_PBS-Pro-Long-MakeTreeWithIQ-Tree.sh")

echo $jobIDs

# Start hold jobs
#holdJobs=$(echo $holdJobs | sed "s/:/ /g")
#qrls $holdJobs
