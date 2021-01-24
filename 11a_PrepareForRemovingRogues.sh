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
aligner="$2"
iteration="$3"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./$thisScript GeneName"
	exit
fi

seqsOfInterestDir=$("$DIR/GetSequencesOfInterestDirectory.sh" -d "$DIR" -g "$gene" -i "$iteration" -a "$aligner")

numTreads=$(nproc)

seqsOfInterest="$seqsOfInterestDir/SequencesOfInterest.fasta"
seqsOfInterestIDs="$seqsOfInterestDir/SequencesOfInterestIDs.txt"

seqkit seq -j $numTreads -i -n "$seqsOfInterest" > "$seqsOfInterestIDs"

