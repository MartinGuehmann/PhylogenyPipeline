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
RerootSequences="$DIR/$gene/RerootSequences/"
#OutgroupSequences="$DIR/$gene/OutgroupSequences/"
seqsPerChunk="900"


declare -a seqFiles=( $BaitDir*.fasta )

#if [ -d $OutgroupSequences ]
#then
#	seqFiles+=($OutgroupSequences*.fasta)
#fi

LeavesOfSubTreeToKeep=""
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

declare -a rerootFiles=($RerootSequences*.fasta)
RerootLeaves=""
for rerootFile in ${rerootFiles[@]}
do
	while read line
	do
		if [[ ">" == "${line:0:1}" ]]
		then
			long="${line#?}"
			long="${long%% *}"

			RerootLeaves="$RerootLeaves $long"
		fi

	done < $rerootFile
done

echo $RerootLeaves

echo $LeavesOfSubTreeToKeep > "$TreesForPruningFromPASTADir/LeavesToKeep.txt"

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
	origSeqFile="$SeqenceChunksForPruningDir/$mainBase.$partBase.fasta"
	sedScript="$TreesForPruningFromPASTADir/$mainBase.$partBase.script"

	seqkit seq -j $numTreads -n -i "$origSeqFile" | sed "s|\(^.*$\)|s/\1\[^']\*/\1/g|g" > "$sedScript"

	# Shorten the long labels to IDs only
	sed -f $sedScript "$TreeForPruning" | \
	# Remove the single quotation marks
	sed -e "s/'//g" | \
	# And reroot the tree
	"$DIR/../newick_utils/src/nw_reroot" - $RerootLeaves | \
	# Extract the clade with the proteins of interest
	"$DIR/../newick_utils/src/nw_clade" - $LeavesOfSubTreeToKeep | \
	# And then extract all the lables
	"$DIR/../newick_utils/src/nw_labels" -I - >> $treeLabels

	count=$(wc -l "$treeLabels" | sed 's\ .*$\\g')
	echo $origSeqFile $count
done

sequences="$DIR/$gene/Sequences"
nrSequenceFile90="$sequences/NonRedundantSequences.fasta"

seqkit grep -j $numTreads -f $treeLabels -t protein $nrSequenceFile90 > $SequencesOfInterest

$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$SequencesOfInterest" -O "$SequencesOfInterestDir"

seqkit stats "$SequencesOfInterestDir/"*.fasta > "$SequencesOfInterestDir/Stats.txt"
