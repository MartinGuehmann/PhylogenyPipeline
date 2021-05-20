#!/bin/bash

# Expand aliases in sourced scripts
#shopt -s expand_aliases

test_09a_PostProcessAlignment_outputFileExists()
{

	# Define alias for mock output if necessary
	# alias program1=".."
	for fastaFile in "./Input_09a_PostProcessAlignment/"*".fasta"
	do
		rm -f $fastaFile.*
		. ../09a_PostProcessAlignment.sh $fastaFile 2>/dev/null
		assertTrue "The output file $reducedAlignmentFile should exist" \
		        '[[ -f $reducedAlignmentFile ]]'
		if [[ ! -f $reducedAlignmentFile ]]
		then
			# Running the rest does not make any sense if this does not exist
			startSkipping
		fi

		numSeq=$(grep -c '>' "$fastaFile")
		numSeqInPhylip=$(head -n 1 $reducedAlignmentFile | cut -d ' ' -f1 )

		assertEquals "Phylip alignment file $reducedAlignmentFile does not contain the number of sequences in its header." \
		        $numSeq $numSeqInPhylip

		actualNumInPhylipFile=$(sed '/^\s*$/d' $reducedAlignmentFile | wc -l)
		((actualNumInPhylipFile--)) # Remove the header line from the count
		assertEquals "Phylip alignment file $reducedAlignmentFile does not contain the expected number of sequences." \
		        $numSeq $actualNumInPhylipFile

		lengthSeq=$(head -n 2 "$reducedAlignmentFile" | tail -n 1 | cut -d ' ' -f2 | tr -d '\n' | wc -m)
		lengthSeqInPhylip=$(head -n 1 $reducedAlignmentFile | cut -d ' ' -f2)

		assertEquals "Phylip alignment file $reducedAlignmentFile does not contain the length of sequences in its header." \
		        $lengthSeq $lengthSeqInPhylip

	done
}

test_09a_PostProcessAlignment_errorNoInputFile()
{
	../09a_PostProcessAlignment.sh 2>/dev/null
	assertEquals "Did not fail on missing input file" \
	        1 $?
}

test_09a_PostProcessAlignment_errorInputFileDoesNotExist()
{
	../09a_PostProcessAlignment.sh dddd 2>/dev/null
	assertEquals "Did not fail on input file does not exist" \
	        2 $?
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

