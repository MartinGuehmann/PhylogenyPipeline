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
        --shuffleSeqs)
            ;&
        -l)
            shuffleSeqs="--shuffleSeqs"
            ;;
        --restore)
            ;&
        -r)
            restore="--restore"
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

shopt -s extglob

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

seqsOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix $previousAligner)
rogueFreeTreesDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$((iteration + 1))" -a "$aligner" $suffix)

numTreads=$(nproc)
seqsOfInterest="$seqsOfInterestDir/SequencesOfInterest.fasta"
baseRogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.part_"
rogueNaRokDropped="$rogueFreeTreesDir/RogueNaRok_droppedRogues.SequencesOfInterestShuffled.csv"
droppedFinal="$rogueFreeTreesDir/SequencesOfInterest.dropped.fasta"
nextSeqsOfInterest="$rogueFreeTreesDir/SequencesOfInterest.fasta"
SequencesOfInterestShuffled="$rogueFreeTreesDir/SequencesOfInterestShuffled.fasta"
droppedAll="$rogueFreeTreesDir/SequencesOfInterestAll.dropped.fasta"
sequencesAll="$rogueFreeTreesDir/SequencesOfInterestAll.fasta"
droppedListAll=""

if [ -f $droppedFinal ]
then
	mv $droppedFinal "$droppedAll"
fi

if [ -f $nextSeqsOfInterest ]
then
	mv $nextSeqsOfInterest "$sequencesAll"
fi

if [ -f "$droppedAll" ]
then
	cat "$rogueFreeTreesDir/SequencesOfInterest.csv" "$baseRogueNaRokDropped"*".csv" > "$rogueNaRokDropped"
else
	cat "$baseRogueNaRokDropped"*".csv" > "$rogueNaRokDropped"
fi

seqkit grep -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$droppedFinal"

numDropped=$(grep -c ">" $droppedFinal)

if (( numDropped > 0 ))
then
	seqkit grep -v -f "$rogueNaRokDropped" -j $numTreads "$seqsOfInterest" > "$nextSeqsOfInterest"
else
	cp "$seqsOfInterest" "$nextSeqsOfInterest"
fi

if [[ ! -z "$shuffleSeqs" && $shuffleSeqs == "--shuffleSeqs" ]]
then
	partSequences="SequencesOfInterestShuffled.part_"
	for fastaFile in "$rogueFreeTreesDir/$partSequences"+([0-9])".fasta"
	do
		baseFile=$(basename $fastaFile ".fasta")
		mv $fastaFile "$rogueFreeTreesDir/$baseFile.old.fasta"
	done

	nextAlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "$((iteration + 1))" -a "$aligner" $suffix)
	if [[ restore == "--restore" && ! -z $nextAlignmentDir ]]
	then
		rm -f "$SequencesOfInterestShuffled"
		seqIDs="$rogueFreeTreesDir/SeqIDs.txt"
		for fastaFile in "$nextAlignmentDir/$partSequences"+([0-9])".alignment.$aligner.fasta"
		do
			seqkit seq -i $fastaFile > $seqIDs
			baseFile=$(basename $fastaFile ".alignment.$aligner.fasta")
			seqkit grep -f "$seqIDs" -j $numTreads "$nextSeqsOfInterest" > "$baseFile.fasta"

			echo "$baseFile.fasta" >> "$SequencesOfInterestShuffled"
		done

		rm -f $seqIDs
	else
		seqsPerChunk="900"
		$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$nextSeqsOfInterest" -o "$SequencesOfInterestShuffled" -O $rogueFreeTreesDir
	fi
fi

seqkit stats "$rogueFreeTreesDir/"*".fasta" > "$rogueFreeTreesDir/Statistics.txt"

AlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
$DIR/11c_CalculateAverageSupport.sh "$AlignmentDir" "$rogueFreeTreesDir"
