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
rounds="5000"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

memFile="$DIR/$gene/MemArgForClans.txt"
javaMem="-Xmx176G"

if [ -f $memFile ]
then
	while read line
	do
		if [[ "#" == "${line:0:1}" ]]
		then
			continue
		fi

		javaMem=$line
		break

	done < $memFile
fi

numThreads=$(nproc)             # Get the number of the currently available processing units to this process, which maybe less than the number of online processors
clansDir="$DIR/$gene/Clans"
clansFile="$clansDir/NonRedundantSequences90.clans"

java $javaMem -XX:ActiveProcessorCount=$numThreads -jar "$DIR/../clans/clans.jar" -cpu $numThreads -load $clansFile -saveto $clansFile -rounds $rounds
