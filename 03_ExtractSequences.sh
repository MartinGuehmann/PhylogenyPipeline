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

# Download and make the uniprot databases if they do not exist
"$DIR/ProteinDatabase/get_uniprot_databases.sh"

TRMBL_DB="$DIR/ProteinDatabase/uniprot_trembl/uniprot_trembl"
SPROT_DB="$DIR/ProteinDatabase/uniprot_sprot/uniprot_sprot"

TRMBL=$(basename $TRMBL_DB)
SPROT=$(basename $SPROT_DB)
AllNCBI="All"

hits="$DIR/$gene/Hits"
sequences="$DIR/$gene/Sequences"
sequenceFileBase="$sequences/Sequences"
sequenceNCBIFileBase="$sequences/NCBISequences"
sequenceFile="$sequenceFileBase.fasta"
sequenceNCBIFile="$sequenceNCBIFileBase.fasta"

tmpIDs="$sequences/IDs.txt"

numTreads=$(nproc)

mkdir -p $sequences

splitSeqNum=40000

rm -f $tmpIDs
rm -f $sequenceFile
rm -f $sequenceNCBIFile

rm -f $sequenceFileBase*".fasta"
rm -f $sequenceNCBIFileBase*".fasta"

# Extract the sequences from uniprot
for DB_PATH in $SPROT_DB $TRMBL_DB
do
	DB=$(basename $DB_PATH)

	sed -E "s/^ *[0-9]* //g" "$hits/$DB/SortedHitsByName.csv" | cut -f 1 | sort -u >> $tmpIDs

	seqkit grep -j $numTreads -f $tmpIDs -t protein "$DB_PATH.fasta" >> $sequenceFile

	rm -f $tmpIDs
done

# Split the sequence file into handy chuncks if we want to store it on github
# The maximum file size is 100 MB, but we should stay below of that.
seqkit split2 -j $numTreads -s $splitSeqNum -O $sequences $sequenceFile
rm -f $sequenceFile

# Extract the sequences from NCBI
IDs=($(sed -E "s/^ *[0-9]* //g" "$hits/$AllNCBI/SortedHitsByName.csv" | cut -f 1 | sort -u))

numIDs=${#IDs[@]}
range=8000 # With more we seem to get into trouble
i=0

while [ $i -lt $numIDs ]
do
	part=${IDs[@]:$i:$range}
	part=$(echo $part | tr ' ' ',')
	efetch -db sequences -format fasta -id $part >> $sequenceNCBIFile
	let i+=range
done

# Split the sequence file into handy chuncks if we want to store it on github
# The maximum file size is 100 MB, but we should stay below of that.
seqkit split2 -j $numTreads -s $splitSeqNum -O $sequences $sequenceNCBIFile
rm -f $sequenceNCBIFile
