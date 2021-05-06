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

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit
fi

DB="$2"
databaseName=$(basename $DB)
evalue="0.00005" # Default value: 10
maxkeep="100000" # Max value in online form: 20000, 100000 gives already some errors, but still the data is saved
outfmt="\"6 saccver evalue stitle\"" # Is not replaced properly

HitDir="$DIR/$gene/Hits/$databaseName/"
BaitDir="$DIR/$gene/BaitSequences/"
AdditionalBaitDir="$DIR/$gene/AdditionalBaitSequences/"

declare -a seqFiles=( $BaitDir*.fasta )

if [ -d $AdditionalBaitDir ]
then
	seqFiles+=($AdditionalBaitDir*.fasta)
fi

if [ $DB == $databaseName ]
then
	remoteOrNumThreads="-remote"
else
	remoteOrNumThreads="-num_threads $(nproc)"
fi

mkdir -p $HitDir

trials=0
maxTrials=16

while [ $trials -lt $maxTrials ]
do
	for seqFile in ${seqFiles[@]}
	do
		[ -f "$seqFile" ] || continue # In case you put a folder with the *.fasta extension into that folder

		outFileBase=$(basename $seqFile .fasta)
		outFile="$HitDir$outFileBase.csv"

		if [ ! -f "$outFile" ]
		then
			echo "Writing to $outFile" >&2
			blastp -query "$seqFile" -db $DB -evalue $evalue -max_target_seqs $maxkeep $remoteOrNumThreads -out $outFile -outfmt "6 saccver stitle evalue"
		fi
	done

	needMoreTrials="false"

	for hitFile in $HitDir*.csv
	do
		[ -f "$hitFile" ] || continue # In case you put a folder with the *.csv extension into that folder

		if [ ! -s "$hitFile" ]
		then
			needMoreTrials="true"
			echo "File is empty: $hitFile" >&2
			rm "$hitFile"
		fi
	done

	if [ $needMoreTrials == "true" ]
	then
		echo "Not all files were downloaded, correctly. Trying $((maxTrials - trials -1)) more time(s)." >&2
		((++trials))
	else
		trials=$maxTrials
	fi

done
