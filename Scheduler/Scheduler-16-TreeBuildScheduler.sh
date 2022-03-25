#!/bin/bash

#PBS -l select=1:ncpus=1:mem=1gb
#PBS -l walltime=0:10:00

# Go to the first program line,
# any PBS directive below that is ignored.
# No modules to load

if [ -z $DIR ]
then
	# Get the directory where this script is
	SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
		DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	done
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
fi
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
        --bigTreeIteration)
            ;&
        -b)
            shift
            bigTreeIteration="$1"
            ;;
        --aligner)
            ;&
        -a)
            shift
            aligner="$1"
            ;;
        --numRoundsLeft)
            ;&
        -n)
            shift
            numRoundsLeft="$1"
            ;;
        --bigNumRoundsLeft)
            ;&
        -N)
            shift
            bigNumRoundsLeft="$1"
            ;;
        --shuffleSeqs)
            ;&
        -l)
            shuffleSeqs="--shuffleSeqs"
            ;;
        --extension)
            ;&
        -e)
            shift
            # Actually ignored
            extension="-e $1"
            ;;
        --trimAl)
            ;&
        -t)
            shift
            trimAl="-t $1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored" >&2
            ;;
    esac
    shift
done

# Print the parameters to stderr for debugging
echo "Running $thisScript with"            >&2
echo "gene:             $gene"             >&2
echo "bigTreeIteration: $bigTreeIteration" >&2
echo "aligner:          $aligner"          >&2
echo "numRoundsLeft:    $numRoundsLeft"    >&2
echo "bigNumRoundsLeft: $bigNumRoundsLeft" >&2
echo "shuffleSeqs:      $shuffleSeqs"      >&2
echo "extension:        $extension"        >&2
echo "trimAl:           $trimAl"           >&2
echo "Note the script is copied to"        >&2
echo "another place with another name"     >&2


if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

if [ -z "$bigTreeIteration" ]
then
	bigTreeIteration="10"
fi

if [ -z $numRoundsLeft ]
then
	numRoundsLeft="20"
fi

if [ -z $bigNumRoundsLeft ]
then
	bigNumRoundsLeft="10"
fi

if [ -z $aligner ]
then
	aligner="$DIR/../GetDefaultAligner.sh"
fi

# Change the working directory to the directory of this script
# so that the standard and error output files go to the directory of this script
cd $DIR

iteration="0"
numRoundsLeftZero="0"
allSeqs=""
suffix=""
extension="-e treefile"
previousAligner=""

# Make an iteration for all available aligners, except for the main aligner
for alignerScript in "$DIR/09_Scheduler-AlignWith"*".sh"*
do
	if [[ $alignerScript =~ 09_Scheduler-AlignWith(.*)\.sh ]]
	then
		usedAligner=${BASH_REMATCH[1]}
		if [[ $usedAligner != $aligner ]]
		then
			"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$usedAligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
			    "$DIR/Scheduler-09-RogueOptAlign.sh"
		fi
	fi
done

oldSuffix=$suffix
suffix="-x BigTree0"
# Make the big tree with the main aligner
allSeqs="--allSeqs"
"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
    "$DIR/Scheduler-09-RogueOptAlign.sh"
suffix=$oldSuffix

### Add check whether Opsins/SequencesOfInterest/Opsins/RogueIter_0
geneOnlyDataSet=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -p "$(basename $gene)")

if [ -d $geneOnlyDataSet ]
then
	suffix="-x $(basename $gene).BigTree0"
	previousAligner="-p $gene"
	# Make a big tree with the main aligner and without outgroup
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"

	allSeqs=""
	suffix="-x $(basename $gene)"
	# Make also small trees with the main aligner and without outgroup
	"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
	    "$DIR/Scheduler-09-RogueOptAlign.sh"
else
	echo "No reduced dataset in $geneOnlyDataSet" >&2
	echo "Skipping" >&2
fi

suffix=""
previousAligner=""

# Make 20 iterations with the main aligner, make a big tree after 10 iterations
"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeft, bigNumRoundsLeft=$bigNumRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl, bigTreeIteration=$bigTreeIteration" \
    "$DIR/Scheduler-09-RogueOptAlign.sh"

if [ -z "$trimAl" ]
then
	# Switch pruning on if it was off
	suffix="-x trimAl"
	trimAl="-t Default"
else
	# Switch pruning off if it was on
	suffix="-x noTrimAl"
	trimAl=""
fi

# Make an iteration for the main aligner, with switched pruning settings
"$DIR/Scheduler-Sub.sh" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeftZero, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" \
    "$DIR/Scheduler-09-RogueOptAlign.sh"
