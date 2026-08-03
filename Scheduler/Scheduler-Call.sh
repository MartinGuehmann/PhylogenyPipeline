#!/bin/bash

# Resources for this job (cpus, mem, walltime) are set in Scheduler/Resources.cfg.
# No modules to load

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
thisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
shopt -s extglob

# Every step below submits at least one Slurm job that will itself enter
# flake.nix's Nix devShell (see Enter-NixDevShell.sh) - checking the
# devShell's dependencies are actually still there *before* submitting is
# a lot cheaper than an array job discovering a garbage-collected store
# path on a compute node (see CheckNixDependenciesBuilt.sh's own comments
# for the incident this is guarding against).
source "$DIR/../CheckNixDependenciesBuilt.sh"

# These would not need to be defined guards if called via "$DIR/Scheduler-Sub.sh"
iteration="0"
hold=""
depend=""
allSeqs=""
shuffleSeqs=""
suffix=""
masterAligner=""
masterSuffix=""
extension=""

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
        --step)
            ;&
        -s)
            shift
            step="$1"
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
        --file)
            ;&
        -f)
            shift
            inputFile="$1"
            ;;
        --depend)
            ;&
        -d)
            shift
            depend="-W depend=afterok$1"
            ;;
        --hold)
            ;&
        -h)
            hold="-h"
            ;;
        --allSeqs)
            ;&
        -q)
            allSeqs="allSeqs"
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
        --previousAligner)
            ;&
        -p)
            shift
            previousAligner="-p $1"
            ;;
        --localNr)
            ;&
        -L)
            # Deliberately "true", not "--localNr" - this is the last hop
            # that speaks getopt-style CLI flags. From here on this value
            # only ever travels via Slurm's --export (see the -v string in
            # the step-0/3 cases below), landing as a plain environment
            # variable in a job script that just does a literal string
            # comparison against it (see
            # 00_Scheduler-GetGenesFromAllDataBases.sh/
            # 03_Scheduler-ExtractSequences.sh) - bash has no actual
            # boolean type, so "true" here is just a fixed string both
            # ends agree on, not a re-usable CLI flag string. Combined
            # with the other two --local* flags below into a single
            # localDatabases list further down, instead of exporting three
            # separate booleans through Slurm.
            localNr="true"
            ;;
        --localRefseqProtein)
            ;&
        -R)
            localRefseqProtein="true"
            ;;
        --localTsaNr)
            ;&
        -T)
            localTsaNr="true"
            ;;
        --trimAl)
            ;&
        -t)
            shift
            trimAl="-t $1"
            ;;
        --restore)
            ;&
        -r)
            restore="--restore"
            ;;
        --update)
            ;&
        -u)
            update="-u"
            ;;
        --updateBig)
            ;&
        -U)
            updateBig="-U"
            ;;
        --ignoreIfMasterFileDoesNotExist)
            ;&
        -M)
            ignoreIfMasterFileDoesNotExist="-M"
            ;;
        --folder)
            ;&
        -f)
            shift
            inputDir="-f $1"
            ;;
        --overwrite)
            ;&
        -o)
            overwrite="--overwrite"
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

if [ -z "$step" ]
then
	echo "StepNumber missing" >&2
	echo "You must give a GeneName and a StepNumber, for instance:" >&2
	echo "./$thisScript GeneName StepNumber" >&2
	exit 1
fi

if [ -z "$aligner" ]
then
	aligner=$("$DIR/../GetDefaultAligner.sh")
fi

# Combine the separate --local* flags above into one colon-separated list
# (matching Databases.sh's RemoteDataBases names) - keeps the three flags
# independently settable at the CLI/Config.sh level while only exporting
# a single env var through Slurm (see the -v strings in the step-0/3
# cases below), instead of tripling the "true"-to-flag translation
# boilerplate in the job scripts that consume it. Colon-, not
# comma-separated: Slurm's --export=Var1=Val1,Var2=Val2 already uses
# comma to separate different variables, so a comma-joined value here
# would risk being misparsed as more than one variable - colon is the
# same separator $holdJobs (also passed through --export, see
# Scheduler-00-ExtractSequences.sh) already uses for exactly this reason.
localDatabases=""
[ "$localNr" == "true" ] && localDatabases="${localDatabases:+$localDatabases:}nr"
[ "$localRefseqProtein" == "true" ] && localDatabases="${localDatabases:+$localDatabases:}refseq_protein"
[ "$localTsaNr" == "true" ] && localDatabases="${localDatabases:+$localDatabases:}tsa_nr"

alignFileStart="$DIR/09_Scheduler-AlignWith"
bashExtension="sh"
alignerFile="$alignFileStart$aligner.$bashExtension"

if [ -z "$alignerFile" ]
then
	echo "Aligner file for $aligner does not exist."
	aligner=$($DIR/../GetDefaultAligner.sh)
	echo "Use default aligner $aligner instead."
	alignerFile="$alignFileStart$aligner.$bashExtension"
fi

AlingmentFilesFile="AlignmentFiles.txt"
SequenceFilesFile="SequenceFiles.txt"

SequencesOfInterestDir=$("$DIR/../GetSequencesOfInterestDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix $previousAligner)

partSequences="SequencesOfInterestShuffled.part_"
SequencesOfInterest="$SequencesOfInterestDir/SequencesOfInterest.fasta"
SequencesOfInterestParts="$SequencesOfInterestDir/$partSequences"

SequenceChunksForPruningDir="$DIR/../$gene/SequenceChunksForPruning"
SeqencesForPruningParts="$SequenceChunksForPruningDir/SequencesForPruning.part_"
TreesForPruningFromPASTADir="$DIR/../$gene/TreesForPruningFromPASTA"
seqFiles="$SequenceChunksForPruningDir/$SequenceFilesFile"
alignmentFiles="$SequenceChunksForPruningDir/$AlingmentFilesFile"

partPruning="NonRedundantSequences90Shuffled.part_"
AllPruningSeqs="$TreesForPruningFromPASTADir/$partPruning"
PruningLastBit=$("$DIR/../GetAlignmentBit.sh" -a "PASTA")

AlignmentDir=$("$DIR/../GetAlignmentDirectory.sh" -g "$gene" -i "$iteration" -a "$aligner" $suffix)
AlignmentParts="$AlignmentDir/$partSequences"
AlignmentLastBit=$("$DIR/../GetAlignmentBit.sh" -a $aligner)
AllSeqs="$AlignmentDir/SequencesOfInterest$AlignmentLastBit"

jobIDs=""

case $step in
0)
	# Depends on the server of NCBI, thus quite slow and thus a cluster is not useful
	# This is a bit supoptimal, but still works
	# Ask for the whole node if the local Uniprot BLAST databases still
	# need building - makeblastdb ignores its assigned CPU count
	resourceOverride=""
	"$DIR/../ProteinDatabase/NeedsBuilding.sh" && resourceOverride="-R AskForWholeNode"
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" $resourceOverride -v "DIR=$DIR, gene=$gene, localDatabases=$localDatabases" "$DIR/00_Scheduler-GetGenesFromAllDataBases.sh")
	;;
1)
	# Same database-build concern as step 0 above
	resourceOverride=""
	"$DIR/../ProteinDatabase/NeedsBuilding.sh" && resourceOverride="-R AskForWholeNode"
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" $resourceOverride -v "DIR=$DIR, gene=$gene" "$DIR/01_Scheduler-CombineHitsForEachDatabase.sh")
	;;
2)
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene" "$DIR/02_Scheduler-CombineHitsFromAllNCBIDatabases.sh")
	;;
3)
	# Efetch is missing for that, anyway this can be done on a laptop
	# Same database-build concern as step 0 above
	resourceOverride=""
	"$DIR/../ProteinDatabase/NeedsBuilding.sh" && resourceOverride="-R AskForWholeNode"
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" $resourceOverride -v "DIR=$DIR, gene=$gene, localDatabases=$localDatabases" "$DIR/03_Scheduler-ExtractSequences.sh")
	;;
4)
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, overwrite=$overwrite" "$DIR/04_Scheduler-MakeNonRedundant.sh")
	;;
5)
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene" "$DIR/05_Scheduler-MakeClansFile.sh")
	;;
6)
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene" "$DIR/06_Scheduler-ClusterWithClans.sh")
	;;
7)
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene" "$DIR/07_Scheduler-MakeTreeForPruning.sh")
	;;
8)
	jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene" "$DIR/08_Scheduler-ExtractSequencesOfInterest.sh")
	;;
9)
	if [[ ! -z $inputFile ]]
	then
		jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, seqsToAlign=$inputFile, iteration=$iteration, suffix=$suffix, previousAligner=$previousAligner, trimAl=$trimAl" "$alignerFile")
	elif [[ $allSeqs == "allSeqs" ]]
	then
		jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, seqsToAlign=$SequencesOfInterest, iteration=$iteration, suffix=$suffix, previousAligner=$previousAligner, trimAl=$trimAl" "$alignerFile")
	else
		# Make alignment directory if it does not exist
		mkdir -p $AlignmentDir

		seqFiles="$AlignmentDir/$SequenceFilesFile"
		alignmentFiles="$AlignmentDir/$AlingmentFilesFile"

		echo "$SequencesOfInterestParts"+([0-9])".fasta" > $seqFiles
		numFiles=$(wc -w $seqFiles | cut -d " " -f1)
		jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -J "1-$numFiles" -v "DIR=$DIR, gene=$gene, seqFiles=$seqFiles, iteration=$iteration, suffix=$suffix, previousAligner=$previousAligner, trimAl=$trimAl" "$alignerFile")
	fi
	;;
10)
	if [[ $allSeqs == "allSeqs" ]]
	then
		jobIDs=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, alignmentToUse=$AllSeqs, iteration=$iteration, aligner=$aligner, suffix=$suffix, previousAligner=$previousAligner" "$DIR/10_Scheduler-Long-MakeTreeWithIQ-Tree.sh")
	else
		alignmentFiles="$AlignmentDir/$AlingmentFilesFile"

		echo "$AlignmentParts"*"$AlignmentLastBit" > $alignmentFiles
		numFiles=$(wc -w $alignmentFiles | cut -d " " -f1)
		jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -J "1-$numFiles" -v "DIR=$DIR, gene=$gene, alignmentFiles=$alignmentFiles, iteration=$iteration, aligner=$aligner, suffix=$suffix, previousAligner=$previousAligner" "$DIR/10_Scheduler-MakeTreeWithIQ-Tree.sh")
	fi
	;;
11)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, shuffleSeqs=$shuffleSeqs, suffix=$suffix, previousAligner=$previousAligner, restore=$restore" "$DIR/11_Scheduler-RemoveRogues.sh")
	;;
12)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, iteration=$iteration, aligner=$aligner, suffix=$suffix, masterAligner=$masterAligner, masterSuffix=$masterSuffix, extension=$extension, update=$update, updateBig=$updateBig, inputDir=$inputDir, ignoreIfMasterFileDoesNotExist=$ignoreIfMasterFileDoesNotExist" "$DIR/12_Scheduler-ConvertTreesToFigures.sh")
	;;
13)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, overwrite=$overwrite" "$DIR/13_Scheduler-SplitNonRedundantSequences.sh")
	;;
14)
	echo "$SequenceChunksForPruningDir/"*".part_"+([0-9])".fasta" > $seqFiles
	numFiles=$(wc -w $seqFiles | cut -d " " -f1)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -J "1-$numFiles" -v "DIR=$DIR, gene=$gene, seqFiles=$seqFiles, trimAl=$trimAl" "$DIR/14_Scheduler-AlignWithPASTAForPruning.sh")
	;;
15)
	echo "$AllPruningSeqs"+([0-9])"$PruningLastBit" > $alignmentFiles
	numFiles=$(wc -w $alignmentFiles | cut -d " " -f1)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -J "1-$numFiles" -v "DIR=$DIR, gene=$gene, alignmentFiles=$alignmentFiles" "$DIR/15_Scheduler-MakeTreeWithIQ-TreeForPruning.sh")
	;;
16)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, extension=$extension, overwrite=$overwrite" "$DIR/16_Scheduler-ExtractSequencesOfInterest.sh")
	;;
17)
	jobIDs+=:$("$DIR/Scheduler-Sub.sh" $hold $depend -g "$gene" -v "DIR=$DIR, gene=$gene, overwrite=$overwrite" "$DIR/17_Scheduler-SkipSequenceExtraction.sh")
	;;

*)
	echo "Step $step is not a valid step." >&2
esac

echo $jobIDs
