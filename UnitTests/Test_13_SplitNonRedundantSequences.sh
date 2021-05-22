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

test_13_SplitNonRedundantSequences_general()
{
	numChunks=4
	outDir="$DIR/13_OutputDir"
	numTreads=$(nproc)

	# Cleanup files from last check if they exist
	rm -f $outDir/*

	. ../13_SplitNonRedundantSequences.sh  -g "UnitTests/TestGene" -O $outDir -h $numChunks 2>/dev/null
	assertEquals "Arg numChunks was not passed correctly" \
	        $numChunks $seqsPerChunk

	for fastaFile in "$outDir/"*".part_"*"fasta"
	do
		checkForID_0=$(seqkit grep -j $numTreads -p "tr|A0A0K0YBE3|A0A0K0YBE3_PLADU"  $fastaFile | wc -m)
		checkForID_1=$(seqkit grep -j $numTreads -p "Platynereis_dumerilii_Go-opsin1" $fastaFile | wc -m)
		checkForID_2=$(seqkit grep -j $numTreads -p "tr|A0A1J0CN90|A0A1J0CN90_ARGIR"  $fastaFile | wc -m)
		checkForID_3=$(seqkit grep -j $numTreads -p "RDD39864.1"                      $fastaFile | wc -m)
		checkForID_4=$(seqkit grep -j $numTreads -p "SeqID_does_not_exist"            $fastaFile | wc -m)
		
		assertTrue "SeqId tr|A0A0K0YBE3|A0A0K0YBE3_PLADU xor SeqId Platynereis_dumerilii_Go-opsin1 must be in file $fastaFile" \
		        "(( $checkForID_0 > 0 && $checkForID_1 == 0 || $checkForID_0 == 0 && $checkForID_1 > 0 ))"

		assertTrue "SeqId tr|A0A1J0CN90|A0A1J0CN90_ARGIR must be in file $fastaFile" \
		        "(( $checkForID_2 > 0 ))"

		assertTrue "SeqId RDD39864.1 must be in file $fastaFile" \
		        "(( $checkForID_3 > 0 ))"

		assertTrue "SeqId SeqID_does_not_exist must not be in file $fastaFile" \
		        "(( $checkForID_4 == 0 ))"
	done
}

test_13_SplitNonRedundantSequences_errorNoOutputDirectory()
{
	../13_SplitNonRedundantSequences.sh -g "UnitTests/TestGene" 2>/dev/null
	assertEquals "Did not fail on missing output directory" \
	        1 $?
}

test_13_SplitNonRedundantSequences_errorNoGeneName()
{
	../13_SplitNonRedundantSequences.sh -O "$DIR/13_OutputDir" 2>/dev/null
	assertEquals "Did not fail on input file does not exist" \
	        1 $?
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

