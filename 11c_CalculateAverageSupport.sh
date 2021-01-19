#!/bin/bash

inputDir="$1"
outputDir="$2"

if [ -z "$outputDir" ]
then
	outputDir="$inputDir"
fi

outputFile="$outputDir/TreeStatistics.csv"

SHaLRTSum="0"
aBayesSum="0"
UFBootSum="0"

i="0"

echo "File	SHaLRTAverage	aBayesAverage	UFBootAverage" > $outputFile

for file in $inputDir/*.treefile
do
	values=$(grep -o -E '[[:digit:]]+(\.[[:digit:]]+)/[[:digit:]]+(\.[[:digit:]]+)/[[:digit:]]+' $file)
	if [ -z "$values" ]
	then
		continue
	fi

	numValues=$(echo "$values" | wc -l)

	SHaLRT=$(echo "$values" | cut -d / -f1)
	aBayes=$(echo "$values" | cut -d / -f2)
	UFBoot=$(echo "$values" | cut -d / -f3)

	SHaLRT=$(echo "$SHaLRT" | paste -s -d+ - | bc)
	aBayes=$(echo "$aBayes" | paste -s -d+ - | bc)
	UFBoot=$(echo "$UFBoot" | paste -s -d+ - | bc)

	SHaLRT=$(echo "$SHaLRT / $numValues" | bc -l )
	aBayes=$(echo "$aBayes / $numValues" | bc -l )
	UFBoot=$(echo "$UFBoot / $numValues" | bc -l )

	SHaLRTSum=$(echo "$SHaLRTSum + $SHaLRT" | bc -l )
	aBayesSum=$(echo "$aBayesSum + $aBayes" | bc -l )
	UFBootSum=$(echo "$UFBootSum + $UFBoot" | bc -l )

	echo "$file	$SHaLRT	$aBayes	$UFBoot" >> $outputFile

	((i++))
done

SHaLRTAverage=$(echo "$SHaLRTSum / $i" | bc -l )
aBayesAverage=$(echo "$aBayesSum / $i" | bc -l )
UFBootAverage=$(echo "$UFBootSum / $i" | bc -l )

echo "Average	$SHaLRTAverage	$aBayesAverage	$UFBootAverage" >> $outputFile
