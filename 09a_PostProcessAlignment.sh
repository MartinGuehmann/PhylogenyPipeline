#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done

# Directory and the name of this script
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Input parameters
alignmentFile="$1"           # The alignment file
trimal="$2"                  # Whether the alignment should be trimmed

if [[ -z "$alignmentFile" ]]
then
	echo "You must give a file with an alignment, for instance:"  >&2
	echo "./$thisScript AlignmentFile" >&2
	exit
fi

if [[ ! -f $alignmentFile ]]
then
	echo "Warning alignment file does not exist: $alignmentFile" >&2
fi

numTreads=$(nproc)

###########################################################
# Remove empty columns from alignment
raxml-ng --msa "$alignmentFile" --threads $numTreads --model LG+G --check >&2

reducedAlignmentFile="$alignmentFile.raxml.reduced.phy"

# Remove double underscores and brackets from extended sequence IDs
sed -i -e 's/__/_/g' -e 's/[][]//g' "$reducedAlignmentFile"

if [ ! -z "$trimal" ]
then
	"$DIR/../trimal/source/trimal" -in "$reducedAlignmentFile" -out "$reducedAlignmentFile" -gt "$trimal"
fi
