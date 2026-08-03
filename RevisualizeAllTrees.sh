#!/bin/bash

#
# Local, non-cluster counterpart to Scheduler/Scheduler-12-RevisualizeAllTrees.sh -
# re-renders step 12's tree figures for every (aligner, iteration) directory
# already present on disk under $gene/Alignments/, running RunAll.sh -s 12
# directly instead of submitting one Slurm job per combination. Like
# RunAll.sh itself, this does not enter flake.nix's Nix devShell on its
# own - run it via "nix develop --command ./RevisualizeAllTrees.sh ..."
# (or with the required tools already on PATH some other way), same as
# you would run RunAll.sh directly.
#
# Parameters:
#  --gene (-g) <GeneName>
#     The gene of interest, actually a subdirectory
#  --iteration (-i) <IterationNumber>
#     The iteration of pruning with RogueNaRok and TreeShrink, default "0"
#  --aligner (-a) <AlignerName>
#     The aligner whose BigTree defines each clade's representative
#     sequence (see 12_ConvertTreesToFigures.sh's --masterAligner) - NOT
#     which aligner/iteration directory gets re-rendered, that comes from
#     the alignerDir/iterDir loop below regardless of this value.
#     Defaults to GetDefaultAligner.sh's choice if not given.
#  --masterAligner (-A) <AlignerName>
#     Overrides --aligner specifically for the master/BigTree lookup
#     (12_ConvertTreesToFigures.sh's --masterAligner) - only useful
#     together with --masterSuffix, since --aligner alone already
#     becomes the master aligner by default. Not passed at all if omitted.
#  --masterSuffix (-X) <SuffixForAlignmentDirectory>
#     The BigTree suffix identifying which master tree defines clade
#     membership, e.g. "BigTree0" for Mas1/Alignments/FAMSA.BigTree0/ -
#     without this, the master tree is looked up at the unsuffixed
#     $aligner/RogueIter_$baseIteration, which does not exist for genes
#     whose real master tree lives under a suffixed BigTree directory.
#     Not passed at all if omitted, same as the cluster version's own
#     (equally affected) behavior.
#  --extension (-e) <TreeFileExtension>
#     The extension of the Newick tree files, for instance "tre" (PASTA)
#     or "contree"/"treefile" (IQ-Tree). Passed through unchanged if given.
#

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Idiomatic parameter and option handling in sh
# Adapted from https://superuser.com/questions/186272/check-if-any-of-the-parameters-to-a-bash-script-match-a-string
# And advanced version is here https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash/7069755#7069755
while test $# -gt 0
do
    case "$1" in
        --gene)
            ;&
        -g)
            shift
            gene="$1"
            ;;
        --iteration)
            ;&
        -i)
            shift
            iteration="$1"
            ;;
        --aligner)
            ;&
        -a)
            shift
            aligner="$1"
            ;;
        --masterAligner)
            ;&
        -A)
            shift
            masterAligner="-A $1"
            ;;
        --masterSuffix)
            ;&
        -X)
            shift
            masterSuffix="-X $1"
            ;;
        --extension)
            ;&
        -e)
            shift
            extension="-e $1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored in $thisScript" >&2
            ;;
    esac
    shift
done

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

if [ -z "$iteration" ]
then
	iteration="0"
fi

if [ -z "$aligner" ]
then
	aligner=$("$DIR/GetDefaultAligner.sh")
fi

# Print the parameters to stderr for debugging, same as the cluster version
echo "Running $thisScript with"    >&2
echo "gene:             $gene"     >&2
echo "iteration:        $iteration" >&2
echo "aligner:          $aligner"  >&2
echo "masterAligner:    $masterAligner" >&2
echo "masterSuffix:     $masterSuffix" >&2
echo "extension:        $extension" >&2

stepFailed="false"
for alignerDir in "$DIR/$gene/Alignments/"*
do
	if [ -d "$alignerDir" ]
	then
		for iterDir in "$alignerDir/"*
		do
			if ! "$DIR/RunAll.sh" -g "$gene" -s "12" -i "$iteration" -a "$aligner" -f "$iterDir" $masterAligner $masterSuffix $extension -u
			then
				echo "Failed to revisualize trees for $iterDir." >&2
				stepFailed="true"
			fi
		done
	fi
done

if [ "$stepFailed" == "true" ]
then
	echo "Failed to revisualize some trees, see above for which ones." >&2
	exit 1
fi
