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

# Generalized from what used to be get_nr_database.sh (nr-only) - nr,
# refseq_protein, and tsa_nr are all fetched the exact same way: NCBI's
# own pre-formatted BLAST database volumes via update_blastdb.pl, so this
# takes the database name as an argument instead of hardcoding "nr".
database="$1"

if [ -z "$database" ]
then
	echo "You must give a database name, for instance:" >&2
	echo "./$(basename "$0") nr" >&2
	exit 1
fi

mkdir -p "$DIR/$database"

cd "$DIR/$database"

# Only one process at a time may check/download/build this database - same
# reasoning as get_uniprot_database.sh's lock (two gene pipelines both
# needing the same database before either has fetched it yet must not both
# run update_blastdb.pl into the same directory at once). A second process
# just blocks on the lock until the first is done, then finds the
# database already there and skips straight past the check below.
(
flock -x 200

# Exit code contract for callers: 0 = a usable local database is ready.
# 1 = a genuinely broken environment (blastdbcmd itself missing) - this
# would also break local uniprot searches and every blastp call in this
# pipeline, so it's worth failing the whole run over, not just this
# database. 2 = this database specifically couldn't be fetched/built
# (missing update_blastdb.pl, a failed download, or a still-invalid
# result afterward) - unlike blastdbcmd, a working remote search doesn't
# depend on any of this, so callers should treat this as "fall back to a
# remote search for this database" rather than failing outright.
if ! command -v blastdbcmd >/dev/null 2>&1
then
	echo "blastdbcmd not found - cannot check for or use a local $database database" >&2
	exit 1
fi

# blastdbcmd -info is the same version-/volume-agnostic "is this a
# complete, usable BLAST database" check used everywhere else this
# pipeline touches these databases. Only fetch anything if that fails -
# unlike the uniprot databases, these are meant to be downloaded and
# built once and then reused across runs, not checked against NCBI for
# updates every time.
if ! blastdbcmd -db "$database" -info >/dev/null 2>&1
then
	if ! command -v update_blastdb.pl >/dev/null 2>&1
	then
		echo "update_blastdb.pl not found - cannot download $database" >&2
		exit 2
	fi

	# update_blastdb.pl downloads NCBI's pre-formatted database volumes
	# directly (not a FASTA file), so there's no separate makeblastdb
	# step here unlike the uniprot databases above. It does its own
	# per-volume checksum verification and retries internally.
	if ! update_blastdb.pl --decompress "$database"
	then
		echo "update_blastdb.pl failed to fetch $database" >&2
		exit 2
	fi

	if ! blastdbcmd -db "$database" -info >/dev/null 2>&1
	then
		echo "$database was downloaded but is still not a valid BLAST database" >&2
		exit 2
	fi
fi
) 200>"$database.lock"
status=$?

wait # Wait until all are done

exit $status
