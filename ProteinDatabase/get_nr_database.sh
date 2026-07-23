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

database="nr"

mkdir -p "$DIR/$database"

cd "$DIR/$database"

# Only one process at a time may check/download/build this database - same
# reasoning as get_uniprot_database.sh's lock (two gene pipelines both
# needing nr before either has fetched it yet must not both run
# update_blastdb.pl into the same directory at once). A second process
# just blocks on the lock until the first is done, then finds the
# database already there and skips straight past the check below.
(
flock -x 200

if ! command -v blastdbcmd >/dev/null 2>&1
then
	echo "blastdbcmd not found - cannot check for or use a local $database database" >&2
	exit 1
fi

# blastdbcmd -info is the same version-/volume-agnostic "is this a
# complete, usable BLAST database" check used everywhere else this
# pipeline touches nr. Only fetch anything if that fails - unlike the
# uniprot databases, nr is meant to be downloaded and built once and then
# reused across runs, not checked against NCBI for updates every time.
if ! blastdbcmd -db "$database" -info >/dev/null 2>&1
then
	if ! command -v update_blastdb.pl >/dev/null 2>&1
	then
		echo "update_blastdb.pl not found - cannot download $database" >&2
		exit 1
	fi

	# update_blastdb.pl downloads NCBI's pre-formatted database volumes
	# directly (not a FASTA file), so there's no separate makeblastdb
	# step here unlike the uniprot databases above. It does its own
	# per-volume checksum verification and retries internally.
	if ! update_blastdb.pl --decompress "$database"
	then
		echo "update_blastdb.pl failed to fetch $database" >&2
		exit 1
	fi

	if ! blastdbcmd -db "$database" -info >/dev/null 2>&1
	then
		echo "$database was downloaded but is still not a valid BLAST database" >&2
		exit 1
	fi
fi
) 200>"$database.lock"
status=$?

wait # Wait until all are done

exit $status
