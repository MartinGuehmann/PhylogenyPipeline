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

# Expand aliases in sourced scripts
#shopt -s expand_aliases

test_12_ConvertTreesToFigures_general()
{
	# Check whether the expected output files exist
	# ../12_ConvertTreesToFigures.sh
	notImplemented=""
}

test_12_ConvertTreesToFigures_errorNoGeneName()
{
	../12_ConvertTreesToFigures.sh 2>/dev/null
	assertEquals "Did not fail even so no gene name was given" \
	        1 $?
}

test_12_ConvertTreesToFigures_errorNoinputFileFailGracefully()
{
	../12_ConvertTreesToFigures.sh -g "UnitTests/TestGene" -X 2>/dev/null
	assertEquals "Missing information to derive output file, but wrong return code, but failed to ignore" \
	        0 $?

	../12_ConvertTreesToFigures.sh -g "UnitTests/TestGene" --ignoreIfMasterFileDoesNotExist 2>/dev/null
	assertEquals "Missing information to derive output file, but wrong return code, but failed to ignore" \
	        0 $?

	../12_ConvertTreesToFigures.sh -g "UnitTests/TestGene" 2>/dev/null
	assertEquals "Missing information to derive output file, but wrong return code" \
	        1 $?
}

test_12_ConvertTreesToFigures_errorInputFileCannotBeReconstructed()
{
	# Check various parameters such as --iteration --aliner --extension--suffix
	# Choose them so that the script will fail for a set and for another set
	# succeed

	notImplemented=""
}

# Setup an alias for a program to get a mock version
# for it when starting all tests
#oneTimeSetUp()
#{
#	alias program2=".."
#}

# Cleanup, for instance undefine aliases
#oneTimeTearDown()
#{
#	unalias program1
#	unalias program2
#}

. shunit2

