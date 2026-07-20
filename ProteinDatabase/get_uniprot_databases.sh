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

declare -a databases=(uniprot_sprot uniprot_trembl)
declare -a pids=()

for database in "${databases[@]}"
do
	"$DIR/get_uniprot_database.sh" "$database" &
	pids+=($!)
done

failed="false"

# Wait for all jobs completed, individually so each one's exit code is
# actually checked - a bare `wait` with no arguments always returns 0
# regardless of whether the backgrounded builds succeeded.
for ((i = 0; i < ${#pids[@]}; i++))
do
	if ! wait "${pids[$i]}"
	then
		echo "Failed to get/build ${databases[$i]}" >&2
		failed="true"
	fi
done

if [ "$failed" == "true" ]
then
	exit 1
fi
