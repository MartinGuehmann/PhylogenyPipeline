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
            inputTrees="$1"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix="-x $1"
            ;;
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
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

if [ -z $inputTrees ]
then
	echo "You must give a file with InputTrees, for instance:" >&2
	echo "./$thisScript -f InputTrees" >&2
	exit 1
fi

if [ ! -f $inputTrees ]
then
	echo "File $inputTrees does not exist. Existing." >&2
	exit 2
fi

seqsOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix $previousAligner)
rogueFreeTreesDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$((iteration + 1))" -a "$aligner" $suffix)

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
