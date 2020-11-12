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

numThreads=$(nproc)             # Get the number of the currently available processing units to this process, which maybe less than the number of online processors
clansDir="$DIR/$gene/Clans"
clansFile="$clansDir/NonRedundantSequences90.clans"

java -Xmx176G -XX:ActiveProcessorCount=$numThreads -jar "$DIR/../clans/clans.jar" -cpu $numThreads -load $clansFile -saveto $clansFile -rounds 5000
