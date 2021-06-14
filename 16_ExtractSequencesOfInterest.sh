#!/bin/bash

#
# This script extracts from a set of Newick trees the according sequences of interest.
# Parameters:
#  --gene (-g)
#     The gene of interest, actually a subdirectory
#  --directory (-d)
#     The directory where the Newick trees are found
#  --chunkDir (-c)
#     The directory where the extracted sequences go.
#     They go into a big file and into a big files where
#     the sequences are ordered randomly, which is then
#     split into smaller files
#  --extension (-e)
#     The extension of the Newick tree files, for instance
#     "tre", which is used by PASTA, alternatives
#     are "contree" (default) and "treefile", which are used by IQ-Tree
#

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Default extension for newick tree files
# This is generated by IQ-Tree and is for consensus trees
extension="contree"

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
        --extension)
            ;&
        -e)
            shift
            extension="$1"
            ;;
        --chunkDir)
            ;&
        -c)
            shift
            SequenceChunksForPruningDir="$1"
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
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

if [ -z "$TreesForPruningFromPASTADir" ]
then
	echo "You must give a directory with tree files for pruning, for instance:" >&2
	echo "./$thisScript -d TreeFileDirectory" >&2
	exit 1
fi

# Get the name of the sequences of interest directory and make it if it does not exist
SequencesOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene")
mkdir -p $SequencesOfInterestDir

treeLabels="$SequencesOfInterestDir/LabelsOfInterest.txt"
rm -f $treeLabels

SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
BaitDir="$DIR/$gene/BaitSequences/"
RerootSequences="$DIR/$gene/RerootSequences/"
seqsPerChunk="900"

# Collect the sequence IDs of the bait sequences for subclade extraction
declare -a seqFiles=( $BaitDir*.fasta )
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

# Collect the sequence ID(s) for rerooting, to avoid problems if the clade to extract includes the root
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

# Save the leave labels of the leaves for subclade extraction, so that they can be used for debugging
echo $LeavesOfSubTreeToKeep > "$TreesForPruningFromPASTADir/LeavesToKeep.txt"

# Save this for trouble shooting
# Use this file Dendroscope to see that the selected sequences form a monophyletic clade
# If not than move the outliers from BaitSequences to AdditionalBaitSequences
echo $LeavesOfSubTreeToKeep | sed "s/ /\n/g"> "$TreesForPruningFromPASTADir/LeavesToKeep.txt"

numTreads=$(nproc)

echo "Counts should be in the same order of magnitude across files" >&2
echo "otherwise check the trees with LeavesToKeep.txt in Dendroscope." >&2
echo "Move those sequences that do not belong to the target clade from BaitSequences to AdditionalBaitSequences" >&2
echo "SeqenceFile" "AccumulativeCount" "Count" >&2

accCount=0

# Get all the sequence IDs of the genes of interest
for TreeForPruning in "$TreesForPruningFromPASTADir/"*"$extension"
do
	# Get the file names needed from the input file base name
	base=$(basename $TreeForPruning)
	mainBase=${base%%.*}
	partBase=${base#$mainBase.*}
	partBase=${partBase%%.*}
	origSeqFile="$SequenceChunksForPruningDir/$mainBase.$partBase.fasta"
	sedScript="$TreesForPruningFromPASTADir/$mainBase.$partBase.script"

	# Create the regular expressions for stripping the long parts of the sequence IDs
	# We need to store those in a file, since we may hit the character and argument limit
	# for the command line
	seqkit seq -j $numTreads -n -i "$origSeqFile" | sed "s|\(^.*$\)|s/\1\[^:]\*/\1/g|g" > "$sedScript"

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

	count=$accCount
	accCount=$(wc -l "$treeLabels" | sed 's\ .*$\\g')
	count=$((accCount - count))
	echo $TreeForPruning $accCount $count  >&2
done

# Get the file of all the reduced set of non redundant sequences to extract the sequences of interest from
sequences="$DIR/$gene/Sequences"
nrSequenceFile90="$sequences/NonRedundantSequences90.fasta"

# Extract the sequences of interests
seqkit grep -j $numTreads -f $treeLabels -t protein $nrSequenceFile90 > $SequencesOfInterest

# Extract 1000 randomly chosen outgroup sequences and add them to the sequence of interest file.
seqkit grep -v -j $numTreads -f $treeLabels -t protein $nrSequenceFile90 | \
seqkit shuffle -j $numTreads | \
seqkit head -n 1000 >> $SequencesOfInterest

namesOfInterestsFile="$DIR/$gene/NamesOfInterests.txt"

if [ -f $namesOfInterestsFile ]
then
	while read line
	do
		if [[ "#" == "${line:0:1}" ]]
		then
			continue
		fi

		if [[ "\n" == "${line:0:1}" ]]
		then
			continue
		fi

		seqkit grep -j $numTreads -n -r -p "Trichoplax" $nrSequenceFile90 >> $SequencesOfInterest

	done < $namesOfInterestsFile
fi

# Randomly shuffle the sequences of interests and split them into chunks of
# about 900 sequences, this is not exactly set, since the actual number of sequences
# won't be devidabel by 900 without rest. However, the rest is distributed over the files.
$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$SequencesOfInterest" -O "$SequencesOfInterestDir"

# Get statistics about the generated files
seqkit stats "$SequencesOfInterestDir/"*.fasta > "$SequencesOfInterestDir/Stats.txt"
