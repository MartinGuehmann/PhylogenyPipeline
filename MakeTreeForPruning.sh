#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
gene="$1"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:"
	echo "./RunAll.sh GeneName"
	exit
fi

clansDir="$DIR/$gene/Clans"
CLANSFile="$clansDir/NonRedundantSequences90.clans"

TreeForPruningDir="$DIR/$gene/TreeForPruning"
mkdir -p $TreeForPruningDir

DistanceMatrix="$TreeForPruningDir/DistanceMatrix.phy"
TreeForPruning="$TreeForPruningDir/TreeForPruning.newick"

"$DIR/../ClansTools/ClansTools" -c "$CLANSFile" -d $DistanceMatrix
"$DIR/../rapidNJ/bin/rapidnj" $DistanceMatrix -v -i pd -o t -c 1 -x $TreeForPruning
