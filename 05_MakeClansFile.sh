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
	exit
fi

numThreads=$(nproc)             # Get the number of the currently available processing units to this process, which maybe less than the number of online processors
sequences="$DIR/$gene/Sequences"
nrSequenceFile90="$sequences/NonRedundantSequences90.fasta"

clansDir="$DIR/$gene/Clans"

mkdir -p $clansDir


baseInFile=$(basename ${nrSequenceFile90%.*})
BlastDB="$clansDir/$baseInFile.BlastDB"
BlastOut="$clansDir/$baseInFile.csv"
CLANSFile="$clansDir/$baseInFile.clans"
queryFilesBase="$clansDir/$baseInFile"
numSeqs=$(grep -c ">" $nrSequenceFile90)
eValue="1e-20" # Maybe turn this into an option
task="blastp-fast"

makeblastdb -in "$nrSequenceFile90" -dbtype prot -out "$BlastDB"
blastp -task "$task" -evalue "$eValue" -max_target_seqs "$numSeqs" -db "$BlastDB" -query "$nrSequenceFile90" -outfmt "6 qseqid sseqid evalue" -out "$BlastOut" -num_threads "$numThreads"
"$DIR/../ClansTools/ClansTools" -i "$BlastOut" -s "$nrSequenceFile90" -o "$CLANSFile"


