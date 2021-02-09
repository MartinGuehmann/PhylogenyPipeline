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
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
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

echo "$numExtractedLabels labels from subtree extracted."
echo "$numExtractedSeqs sequences of interest extracted."
if [[ $numExtractedSeqs == $numExtractedLabels ]]
then
	echo "No sequence where lost while extraction"
else
	echo "WARNING: Sequence lost during extraction, costum sequences might contain underscores that could not be detected."
fi
 
seqkit shuffle -2 -j "$numTreads" "$SequencesOfInterest" > "$SequencesOfInterestShuffled"

# The IDs getting to long for t_coffee so outcomment this
#sed -i "s/[],[]//g" $SequencesOfInterestShuffled
#sed -i "s/[)(]//g" $SequencesOfInterestShuffled
#sed -i "s/ /_/g" $SequencesOfInterestShuffled
#sed -i "s/\//_/g" $SequencesOfInterestShuffled
#sed -i "s/:/_/g" $SequencesOfInterestShuffled
#sed -i "s/;//g" $SequencesOfInterestShuffled

numSeqs=$(grep -c '>' $SequencesOfInterestShuffled)

restSeqChunk=$(($numSeqs % $seqsPerChunk))
numSeqChunks=$(($numSeqs / $seqsPerChunk))

numSeqsCorrPerChunk=$(($seqsPerChunk + 1 + $restSeqChunk / $numSeqChunks))

# Warns that output directoy is not empty, but it is supposed to be non-empty
seqkit split2 -j $numTreads -s $numSeqsCorrPerChunk -O $SequencesOfInterestDir $SequencesOfInterestShuffled
