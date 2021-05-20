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

seqsOfInterestDir="$1"

if [ -z "$seqsOfInterestDir" ]
then
	echo "You must give a SeqsOfInterestDir, for instance:" >&2
	echo "./$thisScript SeqsOfInterestDir" >&2
	exit 1
fi

numTreads=$(nproc)

seqsOfInterest="$seqsOfInterestDir/SequencesOfInterest.fasta"
seqsOfInterestIDs="$seqsOfInterestDir/SequencesOfInterestIDs.txt"

seqkit seq -j $numTreads -i -n "$seqsOfInterest" > "$seqsOfInterestIDs"

