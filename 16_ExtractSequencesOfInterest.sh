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
TreesForPruningFromPASTADir="$2"

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
AdditionalSequences="$DIR/$gene/OutgroupSequences/"
seqsPerChunk="900"


LeavesOfSubTreeToKeep=""

declare -a seqFiles=( $BaitDir*.fasta )

if [ -d $AdditionalSequences ]
then
	seqFiles+=($AdditionalSequences*.fasta)
fi

for seqFile in ${seqFiles[@]}
do
	while read line
	do
		if [[ ">" == "${line:0:1}" ]]
		then
			long="${line#?}"
			long="${long%% *}"

			LeavesOfSubTreeToKeep="$LeavesOfSubTreeToKeep '$long'"
		fi

	done < $seqFile
done

echo $LeavesOfSubTreeToKeep
rm -f $treeLabels

for TreeForPruning in "$TreesForPruningFromPASTADir/"*"contree"
do
	sed -e "s/ [^']*//g" "$TreeForPruning" | \
	"$DIR/../newick_utils/src/nw_clade" - $LeavesOfSubTreeToKeep | \
	"$DIR/../newick_utils/src/nw_labels" - | \
	sed -e "s/'//g" >> $treeLabels
done

sequences="$DIR/$gene/Sequences"
nrSequenceFile90="$sequences/NonRedundantSequences90.fasta"
numTreads=$(nproc)

echo $nrSequenceFile90

seqkit grep -j $numTreads -f $treeLabels -t protein $nrSequenceFile90 > $SequencesOfInterest

$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$SequencesOfInterest" -O "$SequencesOfInterestDir"

seqkit stats $SequencesOfInterest > "$SequencesOfInterestDir/Stats.txt"
