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

extension="treefile"

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
        --extension)
            ;&
        -e)
            shift
            extension="$1"
            ;;
        --suffix)
            ;&
        -x)
            shift
            suffix="-x $1"
            ;;
        --update)
            ;&
        -u)
            update="True"
            ;;
        --updateBig)
            ;&
        -U)
            updateBig="True"
            update="True"
            ;;
        --ignoreIfMasterFileDoesNotExist)
            ;&
        -X)
            ignoreIfMasterFileDoesNotExist="True"
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
	echo "You must give a GeneName, for instance:" >&2
	echo "./$thisScript -g GeneName" >&2
	exit 1
fi

firstAlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "0" -a "$aligner" $suffix)
AlignmentDir=$("$DIR/GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
alignmentExtension=$("$DIR/GetAlignmentBit.sh" -a $aligner)
partSequences="SequencesOfInterestShuffled.part_"
AlignmentParts="$AlignmentDir/$partSequences"

cladeFile="$DIR/$gene/Clades.cvs"

inputTree="$firstAlignmentDir/SequencesOfInterest$alignmentExtension.$extension"
inputTreeBase=$(basename $inputTree ".$extension")
inputTreeDir=$(dirname $inputTree)

cladeTreeFile="$inputTreeDir/$inputTreeBase.cladeTrees"

if [ ! -f $inputTree ]
then
	if [ -z $ignoreIfMasterFileDoesNotExist ]
	then
		echo "In ./$thisScript" >&2
		echo "File $inputTree does not exist. Exiting." >&2
		echo "Check the parameters:" >&2
		echo "--gene $gene" >&2
		echo "--iteration $iteration" >&2
		echo "--aliner $aligner" >&2
		echo "--extension $extension" >&2
		echo "--suffix $suffix" >&2
		exit 2
	else
		echo "In ./$thisScript" >&2
		echo "Master File $inputTree does not exist, yet. Exiting." >&2
		exit 0
	fi
fi

echo "Using $cladeFile" >&2

if [[ ! -f $cladeTreeFile || ! -z $updateBig ]]
then
	echo "Processing $inputTree" >&2
	echo "Creating $cladeTreeFile" >&2
	python3 "$DIR/12_ConvertTreesToFigures.py" -i $inputTree -c $cladeFile
fi

inputTree="$AlignmentDir/SequencesOfInterest$alignmentExtension.$extension"
inputTreeBase=$(basename $inputTree ".$extension")
inputTreeDir=$(dirname $inputTree)
outputFile="$inputTreeDir/$inputTreeBase.collapsedTree.pdf"

echo "Using $cladeTreeFile" >&2

if [[ -f $inputTree && ! -f $outputFile || -f $inputTree && ! -z $update && $iteration != "0" ]]
then
	echo "Processing $inputTree" >&2
	python3 "$DIR/12_ConvertTreesToFigures.py" -i $inputTree -c $cladeFile -t $cladeTreeFile
fi

for inputTree in "$AlignmentParts"*"$AlignmentLastBit.$extension"
do
	inputTreeBase=$(basename $inputTree ".$extension")
	inputTreeDir=$(dirname $inputTree)
	outputFile="$inputTreeDir/$inputTreeBase.collapsedTree.pdf"

	if [[ ! -f $outputFile || ! -z $update ]]
	then
		echo "Processing $inputTree" >&2
		python3 "$DIR/12_ConvertTreesToFigures.py" -i $inputTree -c $cladeFile -t $cladeTreeFile
	fi
done
