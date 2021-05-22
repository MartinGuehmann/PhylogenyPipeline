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
        --continue)
            ;&
        -c)
            continue="--continue"
            ;;
        --trimAl)
            ;&
        -t)
            shift
            trimAl="-t $1"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix="-x $1"
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
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

# Change the working directory to the directory of this script
# so that the standard and error output files go to the directory of this script
cd $DIR

jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "14" --hold $trimAl)
holdJobs=$jobIDs
echo $jobIDs

if [ "$suffix" == "-x tre" ]
then
	jobIDs=$($DIR/PBS-Pro-Call.sh             -g "$gene" -s "16" -d "$jobIDs" $suffix)
	echo $jobIDs

	if [ "$continue" == "--continue" ]
	then
		echo "Continue is not implemented" >&2
	fi

else
	qsub -v "DIR=$DIR, gene=$gene, trimAl=$trimAl, continue=$continue, suffix=$suffix" -W "depend=afterok$jobIDs" "$DIR/PBS-Pro-Call-ExtractSequencesOfInterestWithIQ-Tree.sh"
fi

# Start hold jobs
holdJobs=$(echo $holdJobs | sed "s/:/ /g")
qrls $holdJobs
