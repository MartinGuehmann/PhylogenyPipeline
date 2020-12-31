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
iteration="$2"
aligner="$3"

if [ -z "$gene" ]
then
	echo "GeneName missing"
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./$thisScript GeneName StepNumber"
	exit
fi

if [ -z "$iteration" ]
then
	iteration="0"
fi

defaultAligner="FAMSA"

if [ -z "$aligner" ]
then
	aligner="$defaultAligner"
fi

jobIDs=$($DIR/PBS-Pro-Call.sh              "$gene"  9 "$iteration" "$aligner" "" "hold")
echo $jobIDs
holdJobs=$jobIDs
jobIDs=$($DIR/PBS-Pro-Call.sh              "$gene" 10 "$iteration" "$aligner" "$jobIDs")
echo $jobIDs
jobIDs=$($DIR/PBS-Pro-Call.sh              "$gene" 11 "$iteration" "$aligner" "$jobIDs")
echo $jobIDs

qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner" -W "depend=afterok$jobIDs" "$DIR/PBS-Pro-RemoveMoreRougues.sh"

# Start hold jobs
holdJobs=$(echo $holdJobs | sed "s/:/ /g")
qrls $holdJobs