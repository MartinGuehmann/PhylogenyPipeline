
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

# These would need not defind guards if called via qsub
iteration="0"
hold=""
depend=""
allSeqs=""
shuffleSeqs=""
suffix=""
extension=""

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
        --extension)
            ;&
        -e)
            shift
            extension="-e $1"
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
            trimAl="-t $1"
            ;;
        --restore)
            ;&
        -r)
            restore="--restore"
            ;;
        --update)
            ;&
        -u)
            update="-u"
            ;;
        --updateBig)
            ;&
        -U)
            updateBig="-U"
            ;;
        --ignoreIfMasterFileDoesNotExist)
            ;&
        -X)
            ignoreIfMasterFileDoesNotExist="-X"
            ;;
        --folder)
            ;&
        -f)
            shift
            inputDir="-f $1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored" >&2
            ;;
    esac
    shift
done

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName and a StepNumber, for instance:" >&2
	echo "./$thisScript GeneName StepNumber" >&2
	exit 1
fi

if [ -z "$step" ]
then
	echo "StepNumber missing" >&2
	echo "You must give a GeneName and a StepNumber, for instance:" >&2
	echo "./$thisScript GeneName StepNumber" >&2
	exit 1
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

SequencesOfInterestDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix $previousAligner)

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

SeqenceChunksForPruningDir="$DIR/../$gene/SeqenceChunksForPruning"
SeqencesForPruningParts="$SeqenceChunksForPruningDir/SequencesForPruning.part_"
TreesForPruningFromPASTADir="$DIR/../$gene/TreesForPruningFromPASTA"
seqFiles="$SeqenceChunksForPruningDir/SequenceFiles.txt"
alignmentFiles="$SeqenceChunksForPruningDir/AlignmentFiles.txt"

partPruning="NonRedundantSequences90Shuffled.part_"
AllPruningSeqs="$TreesForPruningFromPASTADir/$partPruning"
PruningLastBit=$("$DIR/../GetAlignmentBit.sh" -a "PASTA")

AlignmentDir=$("$DIR/../GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=$("$DIR/../GetAlignmentBit.sh" -a $aligner)
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
	if [[ ! -z $inputFile ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$inputFile, iteration=$iteration, suffix=$suffix, previousAligner=$previousAligner, trimAl=$trimAl" "$alignerFile")
	elif [[ $allSeqs == "allSeqs" ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest, iteration=$iteration, suffix=$suffix, previousAligner=$previousAligner, trimAl=$trimAl" "$alignerFile")
	else
		for fastaFile in "$SequencesOfInterestParts"+([0-9])".fasta"
		do
			if [[ -f $fastaFile ]]
			then
				jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, seqsToAlign=$fastaFile, iteration=$iteration, suffix=$suffix, previousAligner=$previousAligner, trimAl=$trimAl" "$alignerFile")
			fi
		done
	fi
	;;
10)
	if [[ $allSeqs == "allSeqs" ]]
	then
		jobIDs=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$AllSeqs, iteration=$iteration, aligner=$aligner, suffix=$suffix, previousAligner=$previousAligner" "$DIR/10_PBS-Pro-Long-MakeTreeWithIQ-Tree.sh")
	else
		for phyFile in "$AlignmentParts"*"$AlignmentLastBit"
		do
			if [[ -f $phyFile ]]
			then
				jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, alignmentToUse=$phyFile, iteration=$iteration, aligner=$aligner, suffix=$suffix, previousAligner=$previousAligner" "$DIR/10_PBS-Pro-MakeTreeWithIQ-Tree.sh")
			fi
		done
	fi
	;;
11)
	jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, shuffleSeqs=$shuffleSeqs, suffix=$suffix, previousAligner=$previousAligner, restore=$restore" "$DIR/11_PBS-Pro-RemoveRogues.sh")
	;;
12)
	jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, suffix=$suffix, extension=$extension, update=$update, updateBig=$updateBig, inputDir=$inputDir, ignoreIfMasterFileDoesNotExist=$ignoreIfMasterFileDoesNotExist" "$DIR/12_PBS-Pro-ConvertTreesToFigures.sh")
	;;
13)
	jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene" "$DIR/13_PBS-Pro-SplitNonRedundantSequences.sh")
	;;
14)
	echo "$SeqenceChunksForPruningDir/"*".part_"+([0-9])".fasta" > $seqFiles
	numFiles=$(wc -w $seqFiles | cut -d " " -f1)
	jobIDs+=:$(qsub $hold $depend -J "1-$numFiles" -v "DIR=$DIR, gene=$gene, seqFiles=$seqFiles, trimAl=$trimAl" "$DIR/14_PBS-Pro-AlignWithPASTAForPruning.sh")
	;;
15)
	echo "$AllPruningSeqs"+([0-9])"$PruningLastBit" > $alignmentFiles
	numFiles=$(wc -w $alignmentFiles | cut -d " " -f1)
	jobIDs+=:$(qsub $hold $depend -J "1-$numFiles" -v "DIR=$DIR, gene=$gene, alignmentFiles=$alignmentFiles" "$DIR/15_PBS-Pro-MakeTreeWithIQ-TreeForPruning.sh")
	;;
16)
	jobIDs+=:$(qsub $hold $depend -v "DIR=$DIR, gene=$gene, extension=$extension" "$DIR/16_PBS-Pro-ExtractSequencesOfInterest.sh")
	;;

*)
	echo "Step $step is not a valid step." >&2
esac

echo $jobIDs
