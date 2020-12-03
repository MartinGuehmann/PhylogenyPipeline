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
step="$2"

if [ -z "$gene" ]
then
	echo "GeneName missing"
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./$thisScript GeneName StepNumber"
	exit
fi

if [ -z "$step" ]
then
	echo "StepNumber missing"
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./$thisScript GeneName StepNumber"
	exit
fi

case $step in
#0)
#	Depends on the server of NCBI, thus quite slow and thus a cluster is not useful
#	qsub $DIR/00_PBS-Pro-GetGenesFromAllDataBases.sh $DIR $gene
#	;;
1)
	qsub $DIR/01_PBS-Pro-CombineHitsForEachDatabase.sh $DIR $gene
	;;
2)
	qsub $DIR/02_PBS-Pro-CombineHitsFromAllNCBIDatabases.sh $DIR $gene
	;;
#3)
#	Efetch is missing for that, anyway this can be done on a laptop
#	qsub $DIR/03_PBS-Pro-ExtractSequences.sh $DIR $gene
#	;;
4)
	qsub $DIR/04_PBS-Pro-MakeNonRedundant.sh $DIR $gene
	;;
5)
	qsub $DIR/05_PBS-Pro-MakeClansFile.sh $DIR $gene
	;;
6)
	qsub $DIR/06_PBS-Pro-ClusterWithClans.sh $DIR $gene
	;;
7)
	qsub $DIR/07_PBS-Pro-MakeTreeForPruning.sh $DIR $gene
	;;
8)
	qsub $DIR/08_PBS-Pro-ExtractSequencesOfInterest.sh $DIR $gene
	;;
9)
	qsub $DIR/09_PBS-Pro-AlignWithTCoffee.sh $DIR $gene
	;;

# Adjust lastStep if you add more steps here
*)
	echo "Step $step is not a valid step."
esac
