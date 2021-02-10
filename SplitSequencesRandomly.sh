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

seqsPerChunk="900"

# Idiomatic parameter and option handling in sh
# Adapted from https://superuser.com/questions/186272/check-if-any-of-the-parameters-to-a-bash-script-match-a-string
# And advanced version is here https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash/7069755#7069755
while test $# -gt 0
do
    case "$1" in
        --seqsPerChunk)
            ;&
        -c)
            shift
            seqsPerChunk="$1"
            ;;
        --outputDir)
            ;&
        -O)
            shift
            outputDir="$1"
            ;;
        --inputFile)
            ;&
        -f)
            shift
            inputSequences="$1"
            ;;
        --outputFile)
            ;&
        -o)
            shift
            shuffledSequences="$1"
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

if [ -z "$outputDir" ]
then
	echo "You must give an output directory OutDir, for instance:" >&2
	echo "./$thisScript -O OutDir" >&2
	exit
fi

if [ -z "$shuffledSequences" ]
then
	shuffleInfix="Shuffled"
	inFileName=$(basename $inputSequences)
	inFileBase=${inFileName%.*}
	inFileExt=${inFileName##*.}
	shuffledSequences="$outputDir/$inFileBase$shuffleInfix.$inFileExt"
fi

numTreads=$(nproc)

seqkit shuffle -2 -j "$numTreads" "$inputSequences" > "$shuffledSequences"

numSeqs=$(grep -c '>' $shuffledSequences)

restSeqChunk=$(($numSeqs % $seqsPerChunk))
numSeqChunks=$(($numSeqs / $seqsPerChunk))

numSeqsCorrPerChunk=$(($seqsPerChunk + 1 + $restSeqChunk / $numSeqChunks))

# Warns that output directoy is not empty, but it is supposed to be non-empty
seqkit split2 -j $numTreads -s $numSeqsCorrPerChunk -O $outputDir $shuffledSequences
