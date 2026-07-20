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
	exit 1
fi

# 01a_CombineHits.sh only sorts/dedupes hit CSVs that step 0 already
# wrote to $gene/Hits/ - it never reads the actual databases, so unlike
# steps 0 and 3, there's nothing here that needs them downloaded/built.
source "$DIR/Databases.sh"

declare -a DataBases=("${LocalDataBases[@]}" "${RemoteDataBases[@]}")

for DB in "${DataBases[@]}"
do
	"$DIR/01a_CombineHits.sh" $gene $DB &
done

wait # Wait on all the instances of 01a_CombineHits.sh to finish
