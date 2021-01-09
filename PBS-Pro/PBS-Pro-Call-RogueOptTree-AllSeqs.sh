#!/bin/bash

if [ -z $DIR ]
then
	# Get the directory where this script is
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
		DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	done
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
fi
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

if [ ! -z "$1" ]
then
	gene="$1"
fi

if [ ! -z "$2" ]
then
	iteration="$2"
fi

if [ ! -z "$3" ]
then
	aligner="$3"
fi

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

# Change the working directory to the directory of this script
# so that the standard and error output files to the directory of this script
cd $DIR

jobIDs=$($DIR/PBS-Pro-Call.sh              "$gene" 10 "$iteration" "$aligner" "" "hold" "allSeqs")
echo $jobIDs

qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner" -W "depend=afternotok$jobIDs" "$DIR/PBS-Pro-Call-RogueOptTree-AllSeqs.sh"

# Start hold jobs
jobIDs=$(echo $jobIDs | sed "s/:/ /g")
qrls $jobIDs
