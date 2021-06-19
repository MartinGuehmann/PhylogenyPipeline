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

seqsPerChunk="700"

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
        --outputDir)
            ;&
        -O)
            shift
            outputDir="$1"
            ;;
        --seqsPerChunk)
            ;&
        -h)
            shift
            seqsPerChunk="$1"
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

if [[ -z "$outputDir" ]]
then
	echo "You must give an output directory OutputDir, for instance:" >&2
	echo "./$thisScript -O OutputDir" >&2
	exit 1
fi

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

mkdir -p $outputDir

NonRedundandSequences90="$DIR/$gene/Sequences/NonRedundantSequences90.fasta"
BaitDir="$DIR/$gene/BaitSequences/"
AdditionalBaitDir="$DIR/$gene/AdditionalBaitSequences/"
OutgroupDir="$DIR/$gene/OutgroupSequences/"
RerootSequences="$DIR/$gene/RerootSequences/"

declare -a seqFiles=( $BaitDir*.fasta )

if [ -d $AdditionalBaitDir ]
then
	seqFiles+=($AdditionalBaitDir*.fasta)
fi

if [ -d $OutgroupDir ]
then
	seqFiles+=($OutgroupDir*.fasta)
fi

if [ -d $RerootSequences ]
then
	seqFiles+=($RerootSequences*.fasta)
fi

numTreads=$(nproc)
$DIR/SplitSequencesRandomly.sh -c "$seqsPerChunk" -f "$NonRedundandSequences90" -O $outputDir

for partSeqFile in $outputDir/*".part_"*".fasta"
do
	for fastaFile in ${seqFiles[@]}
	do
		grep -v '^ *$' $fastaFile >> $partSeqFile
	done

	partSeqFileCleaned="$partSeqFile.cleaned"
	seqkit rmdup -s -j $numTreads $partSeqFile | seqkit rename -j $numTreads > $partSeqFileCleaned
	mv $partSeqFileCleaned $partSeqFile
done

seqkit stats "$outputDir/"*".fasta" > "$outputDir/Stats.txt"
