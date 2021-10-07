#/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done

# Directory and the name of this script
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

database="$1"

mkdir -p "$DIR/$database"

cd "$DIR/$database"

if [[ ! -f "$database.fasta" ]]
then
	wget "ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/$database.fasta.gz"
	gunzip "$database.fasta.gz"
	makeblastdb -in "$database.fasta" -out "$database" -dbtype prot
fi

wait # Wait until all are done
