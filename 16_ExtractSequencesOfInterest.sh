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

extension="tre"

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
        --directory)
            ;&
        -d)
            shift
            TreesForPruningFromPASTADir="$1"
            ;;
        --suffix)
            ;&
        -x)
            shift
            extension="$1"
            ;;
        --chunkDir)
            ;&
        -c)
            shift
            SeqenceChunksForPruningDir="$1"
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
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit
fi

if [ -z "$TreesForPruningFromPASTADir" ]
then
	echo "You must give a directory with tree files for pruning, for instance:" >&2
	echo "./$thisScript TreeFileDirectory" >&2
	exit
fi

SequencesOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene")

mkdir -p $SequencesOfInterestDir

treeLabels="$SequencesOfInterestDir/LabelsOfInterest.txt"

#TreeForPruningDir="$DIR/$gene/TreeForPruning"
#TreeForPruning="$TreeForPruningDir/TreeForPruning.newick"
#TreeWithSequencesOfInterest="$SequencesOfInterestDir/TreeWithSequencesOfInterest.newick"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
#treeLabels="$TreeForPruningDir/LabelsOfInterest.txt"
BaitDir="$DIR/$gene/BaitSequences/"
OutgroupSequences="$DIR/$gene/OutgroupSequences/"
seqsPerChunk="900"


LeavesOfSubTreeToKeep=""

declare -a seqFiles=( $BaitDir*.fasta )

#if [ -d $OutgroupSequences ]
#then
#	seqFiles+=($OutgroupSequences*.fasta)
#fi

for seqFile in ${seqFiles[@]}
do
	while read line
	do
		if [[ ">" == "${line:0:1}" ]]
		then
			long="${line#?}"
			long="${long%% *}"

			LeavesOfSubTreeToKeep="$LeavesOfSubTreeToKeep $long"
		fi

	done < $seqFile
done

echo $LeavesOfSubTreeToKeep
#exit
rm -f $treeLabels

numTreads=$(nproc)

#sedScript="$sequences/NonRedundantSequencesSedScript.txt"

#seqFiles+=($nrSequenceFile90)

#rm -f "$sedScript"

#for seqFile in ${seqFiles[@]}
#do
#	seqkit seq -j $numTreads -i -n "$seqFile" | sed "s|\(^.*$\)|s/\1\[^:]\*/\1/g|g" >> "$sedScript"
#done

for TreeForPruning in "$TreesForPruningFromPASTADir/"*"$extension"
do
	base=$(basename $TreeForPruning)
	mainBase=${base%%.*}
	partBase=${base#$mainBase.*}
	partBase=${partBase%%.*}
#	origSeqFile="$SeqenceChunksForPruningDir/$mainBase.$partBase.fasta"
	origSeqFile="$TreesForPruningFromPASTADir/$mainBase.$partBase.fasta"
	sedScript="$TreesForPruningFromPASTADir/$mainBase.$partBase.script"
	echo $origSeqFile

#	grep -o '^>\S*' "$origSeqFile" | sed "s|>||g" | sed "s|\(^.*$\)|s/\1\[^']\*/\1/g|g" > "$sedScript"
	seqkit seq -j $numTreads -n -i "$origSeqFile" | sed "s|\(^.*$\)|s/\1\[^']\*/\1/g|g" > "$sedScript"

	sed -f $sedScript "$TreeForPruning" | \
	sed -e "s/'//g" | \
	"$DIR/../newick_utils/src/nw_clade" - $LeavesOfSubTreeToKeep | \
	"$DIR/../newick_utils/src/nw_labels" - >> $treeLabels
done

sequences="$DIR/$gene/Sequences"
nrSequenceFile90="$sequences/NonRedundantSequences.fasta"

seqkit grep -j $numTreads -f $treeLabels -t protein $nrSequenceFile90 > $SequencesOfInterest

$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$SequencesOfInterest" -O "$SequencesOfInterestDir"

seqkit stats $SequencesOfInterest > "$SequencesOfInterestDir/Stats.txt"
