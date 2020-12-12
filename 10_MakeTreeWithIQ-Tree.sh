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

inputAlignment="$1"

if [[ -z "$inputAlignment" ]]
then
	echo "You must give a InputAlignmentFile, for instance:"
	echo "./$thisScript InputAlignmentFile.fasta"
	exit
fi

numTreads=$(nproc)

iqtree2 -s "$inputAlignment" -B 1000 --abayes --alrt 1000 -m TEST -nt AUTO -ntmax 24 --boot-trees
