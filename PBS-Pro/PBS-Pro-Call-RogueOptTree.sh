#!/bin/bash

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
        --extension)
            ;&
        -e)
            shift
            extension="-e $1"
            ;;
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
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

if [ -z "$gene" ]
then
	echo "GeneName missing" >&2
	echo "You must give a GeneName and a StepNumber, for instance:" >&2
	echo "./$thisScript GeneName StepNumber" >&2
	exit 1
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

jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "10" -i "$iteration" -a "$aligner" $allSeqs --hold $suffix $previousAligner)
echo $jobIDs
holdJobs=$jobIDs
jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "11" -i "$iteration" -a "$aligner" $allSeqs -d "$jobIDs" $shuffleSeqs $suffix $previousAligner)
echo $jobIDs

qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, trimAl=$trimAl" -W "depend=afterok$jobIDs" "$DIR/PBS-Pro-RemoveMoreRougues.sh"

if [[ "$allSeqs" == "--allSeqs" && $numRoundsLeft == "0" ]]
then
	jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "12" -i "$iteration" -a "$aligner" -d "$holdJobs" $suffix $extension -U)

	# ToDo: Call script to update all pdf files
else
	# Depends only on the jobs from step 10
	jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "12" -i "$iteration" -a "$aligner" -d "$holdJobs" $suffix $extension -u -X)
	echo $jobIDs
fi

if [[ "$allSeqs" == "--allSeqs" ]]
then
	# If we run against the wall, just restart the main task
	qsub -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, numRoundsLeft=$numRoundsLeft, shuffleSeqs=$shuffleSeqs, allSeqs=$allSeqs, suffix=$suffix, extension=$extension, previousAligner=$previousAligner, trimAl=$trimAl" -W "depend=afternotok$holdJobs" "$DIR/PBS-Pro-Call-RogueOptTree.sh"
fi

# Start hold jobs
holdJobs=$(echo $holdJobs | sed "s/:/ /g")
qrls $holdJobs
