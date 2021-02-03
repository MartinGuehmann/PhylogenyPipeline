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
        --numRoundsLeft)
            ;&
        -n)
            shift
            numRoundsLeft="$1"
            ;;
        --allSeqs)
            ;&
        -q)
            allSeqs="--allSeqs"
            ;;
        --shuffleSeqs)
            ;&
        -l)
            shuffleSeqs="--shuffleSeqs"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix="-x $1"
            ;;
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
            ;;
        -*)
            ;&
        --*)
            ;&
        *)
            echo "Bad option $1 is ignored"
            ;;
    esac
    shift
done

if [ -z "$gene" ]
then
	echo "GeneName missing"
	echo "You must give a GeneName and a StepNumber, for instance:"
	echo "./$thisScript GeneName StepNumber"
	exit
fi

if [ -z "$iteration" ]
then
	iteration="0"
fi

if [ -z "$aligner" ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

# Change the working directory to the directory of this script
# so that the standard and error output files to the directory of this script
cd $DIR

jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "9" -i "$iteration" -a "$aligner" --hold $allSeqs $suffix $previousAligner)
echo $jobIDs

qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, previousAligner=$previousAligner" -W "depend=afterok$jobIDs" "$DIR/PBS-Pro-Call-RogueOptTree.sh"

# Start hold jobs
jobIDs=$(echo $jobIDs | sed "s/:/ /g")
qrls $jobIDs
