#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
gene="$1"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./RunAll.sh GeneName"
	exit
fi

TreeForPruningDir="$DIR/$gene/TreeForPruning"
TreeForPruning="$TreeForPruningDir/TreeForPruning.newick"
TreeWithSequencesOfInterest="$TreeForPruningDir/TreeWithSequencesOfInterest.newick"
BaitDir="$DIR/$gene/BaitSequences/"
AdditionalSequences="$DIR/$gene/AdditionalSequencesOfInterest/"


LeavesOfSubTreeToKeep=""
addSeqFiles=""

declare -a seqFiles=( $BaitDir*.fasta )

if [ -d $AdditionalSequences ]
then
	seqFiles+=($AdditionalSequences*.fasta)
fi

#echo ${seqFiles[@]}

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
