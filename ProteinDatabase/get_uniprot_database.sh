#/bin/bash

# Get the directory where this script is
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done

# Directory and the name of this script
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

database="$1"
url="ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/$database.fasta.gz"

mkdir -p "$DIR/$database"

cd "$DIR/$database"

source "$DIR/../Lock-Dir.sh"

# Only one process at a time may check/download/build this database -
# without this, two concurrent callers (e.g. two gene pipelines both
# needing it before either has built it yet) can both wget into the
# same file and/or both makeblastdb into the same output basename at
# once, silently corrupting it. A second process just blocks on the
# lock until the first is done, then finds the database already built
# and skips straight past both checks below.
acquireLockDir "$database.lockdir" 21600
(

# $database.fasta existing isn't enough on its own: gunzip writes its
# output directly to that name and only deletes the source .gz on
# success, so a job killed mid-decompression (walltime, scancel, node
# failure) leaves a truncated-but-present .fasta file behind. Without a
# separate completion marker, the next run would see that truncated file
# "already there," skip straight past this whole block, and feed the
# partial FASTA straight into makeblastdb below with no error at all -
# confirmed 2026-07-29 as a real gap while auditing this lock section,
# not yet observed in an actual failure. $database.fasta.ok is only
# touched right after gunzip actually succeeds, same idiom as
# $database.parseseqids below for makeblastdb's own completion.
if [[ ! -f "$database.fasta" ]] || [[ ! -f "$database.fasta.ok" ]]
then
	if ! gzip -t "$database.fasta.gz" 2>/dev/null
	then
		wget -c "$url"
		if ! gzip -t "$database.fasta.gz" 2>/dev/null
		then
			# Resuming still left an invalid file - the remote file may
			# have changed since the partial download started, so a
			# byte-offset resume no longer lines up with it. Start over.
			rm -f "$database.fasta.gz"
			wget "$url"
			if ! gzip -t "$database.fasta.gz" 2>/dev/null
			then
				echo "$database.fasta.gz is still not a valid gzip file after a fresh download" >&2
				exit 1
			fi
		fi
	fi
	# -f: the .gz check above can pass (a complete, valid download) while
	# $database.fasta itself is still the truncated leftover of a
	# previously interrupted gunzip - force overwriting it rather than
	# gunzip refusing/skipping because the destination already exists.
	if ! gunzip -f "$database.fasta.gz"
	then
		echo "gunzip failed on $database.fasta.gz" >&2
		exit 1
	fi
	touch "$database.fasta.ok"
fi


# -parse_seqids lets blastdbcmd retrieve sequences by accession afterward
# (03_ExtractSequences.sh's uniprot extraction, mirroring how local nr
# already works via NCBI's own pre-parsed volumes) - without it,
# blastdbcmd refuses any -entry/-entry_batch lookup outright ("DB
# contains no accession info"), confirmed 2026-07-24. A database built
# before this flag was added has no way to tell that apart from one built
# with it just by the presence of $database.pdb, so key the rebuild check
# off a marker file instead, touched only right after a build that did
# include -parse_seqids.
if [[ ! -f "$database.pdb" ]] || [[ ! -f "$database.parseseqids" ]]
then
	makeblastdb -in "$database.fasta" -out "$database" -dbtype prot -parse_seqids
	touch "$database.parseseqids"
fi
)
status=$?
releaseLockDir "$database.lockdir"

exit $status
