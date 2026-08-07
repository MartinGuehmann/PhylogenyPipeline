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

source "$DIR/../Lock-Dir.sh"

# Only one process at a time may check/download/build this database - same
# reasoning as get_uniprot_database.sh's lock (two gene pipelines both
# needing the same database before either has fetched it yet must not both
# run update_blastdb.pl into the same directory at once). A second process
# just blocks on the lock until the first is done, then finds the
# database already there and skips straight past the check below.
# staleAfterSeconds generous (12h) - a full nr fetch/build measured at
# ~5h below.
#
# Release via an EXIT trap, not just a plain call after the subshell
# below - see get_vcmsa_env.sh's identical lock for why: a plain call
# there never ran when a task got killed mid-build, orphaning the lock
# for everyone else until its full staleAfterSeconds elapsed. EXIT fires
# on every exit path, including a kill mid-download here, so the lock
# comes free immediately instead of after a 12h guess.
if ! acquireLockDir "$database.lockdir" 43200
then
	echo "Failed to acquire $database.lockdir - see acquireLockDir's own error above" >&2
	exit 2
fi
trap 'releaseLockDir "$database.lockdir"' EXIT
(

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
#
# -info alone isn't enough, though: it catches a wholly missing volume
# but not a truncated one still present on disk (confirmed 2026-07-29 -
# deleting one volume's files made -info fail as expected, but merely
# truncating one volume's .psq mid-file did not). $database.ok is only
# touched right after a fetch actually succeeds and passes -info, so a
# job killed mid-download (walltime, scancel, node failure) is always
# caught here on the next run regardless of what -info alone would say.
if ! blastdbcmd -db "$database" -info >/dev/null 2>&1 || [ ! -f "$database.ok" ]
then
	if ! command -v update_blastdb.pl >/dev/null 2>&1
	then
		echo "update_blastdb.pl not found - cannot download $database" >&2
		exit 2
	fi

	# $database.ok missing alongside some files already present means a
	# previous attempt was interrupted partway. update_blastdb.pl's own
	# --force is documented as "force download even if there is an
	# archive already on local directory," implying its default is to
	# skip re-fetching an archive it finds already sitting there by name
	# rather than verify it - which would let a truncated volume from an
	# interrupted transfer persist forever untouched. There's also no
	# per-volume "verify what's there, only refetch what's bad" option
	# exposed by this tool, and real nr download timestamps (2026-07-29)
	# show volumes being fetched concurrently out of numeric order, so
	# there's no reliable way to identify just "the one volume in flight
	# when the job died" either. Wiping this database's own files (never
	# the lock dir - that's a different, always-current mechanism, and
	# we're holding it open right now besides) and forcing a full fresh
	# redownload is the only way to guarantee a clean result - measured
	# at ~5 hours for nr's ~170 volumes, so expensive, but this is a rare
	# recovery path, not the common case.
	find . -maxdepth 1 -name "$database.*" ! -name "$database.lockdir" -delete

	# update_blastdb.pl downloads NCBI's pre-formatted database volumes
	# directly (not a FASTA file), so there's no separate makeblastdb
	# step here unlike the uniprot databases above. It does its own
	# per-volume checksum verification and retries internally.
	if ! update_blastdb.pl --decompress --force "$database"
	then
		echo "update_blastdb.pl failed to fetch $database" >&2
		exit 2
	fi

	if ! blastdbcmd -db "$database" -info >/dev/null 2>&1
	then
		echo "$database was downloaded but is still not a valid BLAST database" >&2
		exit 2
	fi

	touch "$database.ok"
fi
)
status=$?

exit $status
