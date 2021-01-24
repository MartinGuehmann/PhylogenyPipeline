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
inputTrees="$2"
aligner="$3"
iteration="$4"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

if [ ! -f $inputTrees ]
then
	echo "File $inputTrees does not exist. Existing."
	exit
fi

seqsOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner")
rogueFreeTreesDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$((iteration + 1))" -a "$aligner")

mkdir -p $rogueFreeTreesDir

numTreads=$(nproc)
base=$(basename $inputTrees ".alignment.$aligner.fasta.raxml.reduced.phy.ufboot")
bbase="$base.bipartition"
alignmentBase=$(basename $inputTrees ".ufboot")
alignmentDir=$(dirname $inputTrees)
bbaseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.$bbase"
baseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.$base"
baseRogueNaRokDroppedCSV="$baseRogueNaRokDropped.csv"
baseShrunken="$rogueFreeTreesDir/$base.txt"
consenseTree="$alignmentDir/$alignmentBase.contree"
seqsOfInterestIDs="$seqsOfInterestDir/SequencesOfInterestIDs.txt"
droppedFinal="$rogueFreeTreesDir/$base.dropped.fasta"

# If we call this again we want to overwrite the output
rm -f "$baseRogueNaRokDroppedCSV"
rm -f "$baseRogueNaRokDropped"
rm -f "$rogueFreeTreesDir/RogueNaRok_info.$base"
rm -f "$rogueFreeTreesDir/RogueNaRok_info.$bbase"

"$DIR/../RogueNaRok/RogueNaRok-parallel" -s 2 -i $inputTrees -n $base -w $rogueFreeTreesDir -T $numTreads
"$DIR/../RogueNaRok/RogueNaRok-parallel" -s 2 -i $inputTrees -n $bbase -b -w $rogueFreeTreesDir -T $numTreads

# Creates a .contree file in the target directory
run_treeshrink.py -t "$consenseTree" -o "$rogueFreeTreesDir" -f -O "$base"

grep -o -f "$seqsOfInterestIDs" "$baseRogueNaRokDropped" > "$baseRogueNaRokDroppedCSV"
grep -o -f "$seqsOfInterestIDs" "$bbaseRogueNaRokDropped" >> "$baseRogueNaRokDroppedCSV"
grep -o -f "$seqsOfInterestIDs" "$baseShrunken" >> "$baseRogueNaRokDroppedCSV"

seqkit grep -f "$baseRogueNaRokDroppedCSV" -j "$numTreads" "$seqsOfInterestDir/$base.fasta" > "$droppedFinal"

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped > 0 ))
then
	seqkit grep -v -f "$baseRogueNaRokDroppedCSV" -j "$numTreads" "$seqsOfInterestDir/$base.fasta" > "$rogueFreeTreesDir/$base.fasta"
else
	cp "$seqsOfInterestDir/$base.fasta" "$rogueFreeTreesDir/$base.fasta"
fi
