
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
hold=""
depend=""
allSeqs=""
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
        --depend)
            ;&
        -d)
            shift
            depend="-W depend=afterok$1"
            ;;
        --hold)
            ;&
        -h)
            hold="-h"
            ;;
        --allSeqs)
            ;&
        -q)
            allSeqs="allSeqs"
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
	aligner=$("$DIR/../GetDefaultAligner.sh")
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

SequencesOfInterestDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

AlignmentDir=$("$DIR/../GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
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
	if [[ $allSeqs == "allSeqs" ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest, iteration=$iteration, suffix=$suffix" "$alignerFile")
	else
		for fastaFile in "$SequencesOfInterestParts"+([0-9])".fasta"
		do
			if [[ -f $fastaFile ]]
			then
				jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile, iteration=$iteration, suffix=$suffix" "$alignerFile")
			fi
		done
	fi
	;;
10)
	if [[ $allSeqs == "allSeqs" ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$AllSeqs, iteration=$iteration, aligner=$aligner, suffix=$suffix" "$DIR/10_PBS-Pro-Long-MakeTreeWithIQ-Tree.sh")
	else
		for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
		do
			if [[ -f $phyFile ]]
			then
				jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile, iteration=$iteration, aligner=$aligner, suffix=$suffix" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh")
			fi
		done
	fi
	;;
11)
	jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, shuffleSeqs=$shuffleSeqs, suffix=$suffix" "$DIR/11_PBS-Pro-RemoveRogues.sh")
	;;

*)
	echo "Step $step is not a valid step."
esac

echo $jobIDs
