#!/bin/bash

cat OpsinBait.csv | while read line; do
	ID="${line%%_*}";

#	echo $line;
#	echo $ID;

	for fastaFile in "${1}"/*.fasta
	do
		if [[ "$fastaFile" =~ "$ID" ]]
		then
			mv $fastaFile "${1}"/"$line.fasta"
		fi
	done
done
