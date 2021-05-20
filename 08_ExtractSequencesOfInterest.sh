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

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

SequencesOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene")

mkdir -p $SequencesOfInterestDir

TreeForPruningDir="$DIR/$gene/TreeForPruning"
TreeForPruning="$TreeForPruningDir/TreeForPruning.newick"
TreeWithSequencesOfInterest="$SequencesOfInterestDir/TreeWithSequencesOfInterest.newick"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestShuffled="$SequencesOfInterestDir/SequencesOfInterestShuffled.fasta"
treeLabels="$TreeForPruningDir/LabelsOfInterest.txt"
BaitDir="$DIR/$gene/BaitSequences/"
AdditionalBaitDir="$DIR/$gene/AdditionalBaitSequences/"
AdditionalSequences="$DIR/$gene/OutgroupSequences/"
seqsPerChunk="900"


LeavesOfSubTreeToKeep=""

declare -a seqFiles=( $BaitDir*.fasta )

if [ -d $AdditionalBaitDir ]
then
	seqFiles+=($AdditionalBaitDir*.fasta)
fi

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
			long="${long//[],[]/}"
			long="${long//[)(]/}"
			long="${long// /_}"
			long="${long//\//_}"
			long="${long//:/_}"
			long="${long//;/}"

			LeavesOfSubTreeToKeep="$LeavesOfSubTreeToKeep '$long'"
		fi

	done < $seqFile
done

"$DIR/../newick_utils/src/nw_clade" "$TreeForPruning" $LeavesOfSubTreeToKeep > $TreeWithSequencesOfInterest
"$DIR/../newick_utils/src/nw_labels" $TreeWithSequencesOfInterest > $treeLabels

sed -i "s/'//g" $treeLabels
sed -i "s/\(^.*|.*|[^_]*_[^_]*\).*$/\1/g" $treeLabels
sed -i "s/\(^[a-zA-Z]*_*[0-9]*\.[0-9]*\).*/\1/g" $treeLabels
sed -i "s/\(^[a-zA-Z]*-[a-zA-Z0-9-]*\)_.*/\1/g" $treeLabels
sed -i "s/\(^pdb|[a-zA-Z0-9-]*|[a-zA-Z0-9-]*\)_.*/\1/g" $treeLabels
sed -i "s/\(^prf||[a-zA-Z0-9-]*\)_.*/\1/g" $treeLabels

sequences="$DIR/$gene/Sequences"
nrSequenceFile90="$sequences/NonRedundantSequences90.fasta"
numTreads=$(nproc)

seqkit grep -j $numTreads -f $treeLabels -t protein $nrSequenceFile90 > $SequencesOfInterest
seqkit stats $SequencesOfInterest

numExtractedSeqs=$(grep -c '>' $SequencesOfInterest)
numExtractedLabels=$(grep -cve '^\s*$' $treeLabels)

echo "$numExtractedLabels labels from subtree extracted." >&2
echo "$numExtractedSeqs sequences of interest extracted." >&2
if [[ $numExtractedSeqs == $numExtractedLabels ]]
then
	echo "No sequence where lost while extraction" >&2
else
	echo "WARNING: Sequence lost during extraction, costum sequences might contain underscores that could not be detected." >&2
fi

$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$SequencesOfInterest" -o "$SequencesOfInterestShuffled" -O "$SequencesOfInterestDir"
