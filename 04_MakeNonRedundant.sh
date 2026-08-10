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
overwrite="$2"

if [ -z "$gene" ]
then
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript GeneName" >&2
	exit 1
fi

numTreads=$(nproc)
sequences="$DIR/$gene/Sequences"
sequencesToKeep="$DIR/$gene/MustKeepSequences"
speciesForSeqReps="$DIR/$gene/SpeciesForSeqReps.csv"
nrSequenceFile="$sequences/NonRedundantSequences.fasta"
nrSequenceFile90="$sequences/NonRedundantSequences90.fasta"

# Rebuilding this from scratch reshuffles which sequence cd-hit picks as
# each cluster's representative (its clustering isn't guaranteed
# reproducible run to run, confirmed 2026-07-26), so anything already
# built downstream from the current $nrSequenceFile90 (alignments,
# trees, rogue-removal output) silently stops matching it once this
# reruns - confirmed 2026-07-26 to be exactly what an accidental
# 04_RestartProcessing.sh rerun did to a Mas1 round that had already
# been aligned. Skip instead of clobbering unless explicitly told to.
if [ "$overwrite" != "--overwrite" ] && [ -s "$nrSequenceFile90" ]
then
	echo "$nrSequenceFile90 already exists - skipping (pass --overwrite to force rebuilding it)." >&2
	exit 0
fi

# Remove $nrSequenceFile if it already exists created from a previous run,
# without complaining if it does not exist.
# So that we do not include it in the analysis.
rm -f $nrSequenceFile
rm -f $nrSequenceFile90

seqFiles=$sequences/*.fasta

# NCBI's own efetch output can bundle accessions that share a byte-
# identical sequence into a single FASTA record (multiple ">accession
# desc [organism]" segments concatenated on one header line, no
# newline between them) - every accession after the first in such a
# line is invisible to seqkit rmdup below (and every other FASTA tool)
# otherwise, since a record boundary is defined as a line *starting*
# with ">". Split those back into individual records first, and (if
# this gene has a species priority list) reorder so rmdup's own "only
# the first record is saved for duplicates" rule (no other way to
# control which duplicate survives - see its own --help) prefers a
# priority-species accession within any group of identical sequences,
# same list already used to override cd-hit's own representative
# choice below. Confirmed 2026-08-10, 631 such merged lines in a
# single PRRs part file alone.
speciesListArg=""
[ -f "$speciesForSeqReps" ] && speciesListArg="--species-list $speciesForSeqReps"

python3 "$DIR/PrepareSequencesForDedup.py" $seqFiles $speciesListArg | seqkit rmdup -s -j $numTreads > $nrSequenceFile

cd-hit -i $nrSequenceFile -o $nrSequenceFile90 -c 0.9 -M 0 -d 0 -T $numTreads

# Replace cd-hit's own (longest-sequence-wins) representative for a cluster
# with a higher-priority one by species, wherever a cluster happens to
# contain a member matching a species in this gene's own priority list -
# e.g. always preferring a well-annotated human/mouse/etc. sequence over
# whichever one cd-hit's length-based sort happened to pick first. Falls
# back to cd-hit's own choice for any cluster with no matching member, and
# is a no-op entirely if this gene has no such list.
if [ -f "$speciesForSeqReps" ]
then
	python3 "$DIR/PickSequenceRepresentatives.py" \
		--input "$nrSequenceFile" \
		--cdhit-output "$nrSequenceFile90" \
		--clstr "$nrSequenceFile90.clstr" \
		--species-list "$speciesForSeqReps"
fi

if [ -d $sequencesToKeep ]
then
	for fastaFile in $sequencesToKeep/*.fasta
	do
		if [ -f $fastaFile ]
		then
			grep -v '^ *$' $fastaFile >> $nrSequenceFile90
		fi
	done
fi

seqkit rmdup -s -j $numTreads $nrSequenceFile90 | seqkit rename -j $numTreads > "$nrSequenceFile90.tmp"
mv "$nrSequenceFile90.tmp" "$nrSequenceFile90"

# Record the statistics of all files, including the one we have just created.
# The expression in $seqFiles is re-evaluated.
seqkit stats $seqFiles > "$sequences/Stats.txt"
