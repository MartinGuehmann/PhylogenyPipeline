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

# Only one process at a time may check/download/build this database -
# without this, two concurrent callers (e.g. two gene pipelines both
# needing it before either has built it yet) can both wget into the
# same file and/or both makeblastdb into the same output basename at
# once, silently corrupting it. A second process just blocks on the
# lock until the first is done, then finds the database already built
# and skips straight past both checks below.
(
flock -x 200

if [[ ! -f "$database.fasta" ]]
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
	if ! gunzip "$database.fasta.gz"
	then
		echo "gunzip failed on $database.fasta.gz" >&2
		exit 1
	fi
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
) 200>"$database.lock"
status=$?

wait # Wait until all are done

exit $status
