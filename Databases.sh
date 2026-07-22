# Single source of truth for which protein databases this pipeline
# searches/combines - source this (not run it) from any script that
# needs the list, instead of hardcoding a separate copy. Steps drifted
# out of sync before this existed (01/02 included remote swissprot hits
# that 00 never actually searched for, since 00 excludes it below).
#
# Usage: source "$DIR/Databases.sh"
#
# Defines $LocalDataBases/$RemoteDataBases. Resolves its own directory
# independently via BASH_SOURCE, so it's safe to source regardless of
# whatever $DIR the sourcing script has already set for itself.

_databasesSource="${BASH_SOURCE[0]}"
while [ -h "$_databasesSource" ]; do
	_databasesDir="$( cd -P "$( dirname "$_databasesSource" )" && pwd )"
	_databasesSource="$(readlink "$_databasesSource")"
	[[ $_databasesSource != /* ]] && _databasesSource="$_databasesDir/$_databasesSource"
done
_databasesDir="$( cd -P "$( dirname "$_databasesSource" )" && pwd )"
unset _databasesSource

declare -a LocalDataBases=(
	"$_databasesDir/ProteinDatabase/uniprot_trembl/uniprot_trembl"  # UniProt TRMBL saved locally
	"$_databasesDir/ProteinDatabase/uniprot_sprot/uniprot_sprot"    # UniProt SwissProt saved locally
)

declare -a RemoteDataBases=(
	"refseq_protein"  # Reference proteins
	# "landmark"        # Model Organisms, does not work
	# "swissprot"       # UniProtKB/Swiss-Prot, just the confirmed sequences, redundant with the local, more up-to-date uniprot_sprot above, not worth the extra NCBI remote load
	# "pataa"           # Patented protein sequences, mutated proteins from patients are not needed
	# "pdb"             # Protein Data Bank Proteins, chimeras for christalization just screw up things
	# "env_nr"          # Metagenomic proteins, most come back empty for opsins, so it is not worth
	"tsa_nr"          # Transcriptome Shotgun Assembly proteins
	"nr"              # Non-redundant protein sequences
)

unset _databasesDir
