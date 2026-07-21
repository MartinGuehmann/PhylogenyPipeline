#!/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Exits 0 if either local Uniprot BLAST database still needs building,
# exit 1 if both already exist - mirrors the check in get_uniprot_database.sh
for database in uniprot_sprot uniprot_trembl
do
	if [[ ! -f "$DIR/$database/$database.pdb" ]]
	then
		exit 0
	fi
done

exit 1
