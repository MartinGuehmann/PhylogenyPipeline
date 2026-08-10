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
inputSequences="$1"          # The input sequences to be aligned
alignmentDir="$2"            # The output directories for the alignments

if [[ -z "$inputSequences" ]]
then
	echo "You must give a file with InputSequences, for instance:" >&2
	echo "./$thisScript InputSequences AlignmentDirectory" >&2
	exit 1
fi

if [ -z "$alignmentDir" ]
then
	echo "You must give a file with InputSequences, for instance:" >&2
	echo "./$thisScript InputSequences AlignmentDirectory" >&2
	exit 1
fi

# Make input and output file names
numTreads=$(nproc)
base=$(basename $inputSequences .fasta)
outFile="$alignmentDir/$base.alignment.RegTCoffee.fasta"
outFileFixed="$alignmentDir/$base.alignment.RegTCoffee.fixed.fasta"
outTree="$alignmentDir/$base.tree.RegTCoffee.newick"

# Do not realign if the outfile already exists and is not empty
if [ -s $outFile ]
then
	# In this case we still want to return the outfile
	echo "$outFile"
	exit 0
fi

# Make the alignment directory if it does not exist
mkdir -p $alignmentDir

# Align the sequences with regressive t-coffee
#
# T-Coffee refuses to fork a subprocess once its PID exceeds a
# hardcoded MAX_N_PID - on this cluster real PIDs already run into the
# millions, well past the 260000 this pinned version (13.41.0.28bdc39,
# see flake.nix) compiles in. Used to be worked around here via a
# MAX_N_PID_4_TCOFFEE env var, but confirmed 2026-08-10 (after 2 of 26
# real chunks failed with "current: 260000") that this version's source
# has no such env-var override at all - that fix was written against a
# different t-coffee version and had silently been a no-op since the
# pin was switched down to 13.41.0. Fixed for real at the source
# instead: flake.nix's t-coffee derivation now patches MAX_N_PID up to
# 4194304 (Linux's own pid_max ceiling) at build time.
#
# -thread 0 ("all those defined in the environment", per `t_coffee
# -help`) does NOT respect this job's actual Slurm/cgroup CPU
# allocation the way $numTreads (nproc, already computed above) does -
# confirmed 2026-07-31: every one of a 26-task RegTCoffee array
# coredumped after printing "!Maximum N Threads --- 96", the physical
# node's full core count, while Resources.cfg only ever gave this job
# 24 - t_coffee tried to run ~4x oversubscribed and crashed before
# writing any output. Pass the already-detected, cgroup-respecting
# count explicitly instead of trusting -thread 0's own detection.
t_coffee -reg -seq $inputSequences -nseq 100 -tree mbed -method mafftlinsi_msa -outfile $outFile -outtree $outTree -thread "$numTreads"  >&2 # In case this puts something to stdout

# Without this check, a t_coffee failure (e.g. the coredump above) fell
# through silently into the seqkit rename below, which then manufactured
# a 0-byte $outFile of its own (seqkit failing to read the never-written
# $outFile, redirected into $outFileFixed, then mv'd over $outFile) -
# so the only thing that ever caught the failure was raxml-ng's
# downstream --check happening to notice the alignment was empty.
# Fail fast here instead, so a t_coffee failure that left behind
# non-empty garbage doesn't slip past that indirect check unnoticed.
if [ $? -ne 0 ]
then
	echo "9. t_coffee failed to align $inputSequences with RegTCoffee." >&2
	exit 1
fi

###########################################################
# Restore sequence names, so that we have some idea of what we are looking when we are looking at the tree
mapFile="$alignmentDir/$base.map.txt"

rm -f "$mapFile"
while read line
do
	if [[ ">" == "${line:0:1}" ]]
	then
		long="${line#?}"
		short="${long%% *}"
		echo "$short	$long" >> "$mapFile"
	fi

done < $inputSequences

seqkit replace -p '(.+)$' -k "$mapFile" -r '{kv}' -K "$outFile" > "$outFileFixed"
mv "$outFileFixed" "$outFile"

# This must be the only stuff that goes to stdout here, since we use this as a return value
echo "$outFile"
