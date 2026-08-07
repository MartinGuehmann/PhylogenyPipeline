# Not meant to be run directly - source it, then call acquireLockDir and
# releaseLockDir around a critical section.
#
# mkdir-based advisory locking, replacing flock(1)'s file-descriptor
# locks - POSIX advisory locks (what flock uses) are well known to be
# unreliable over NFS: many NFS server/client combinations don't support
# them at all, or only support them correctly when a separate lock
# manager daemon (rpc.lockd/nlockmgr) is configured and actually working
# on both ends. Confirmed 2026-08-06 on the cluster: a 26-task array all
# blocked on `flock -x 200` for over an hour with zero progress and zero
# CPU use anywhere - `ps` on the node hosting several of the waiting
# tasks showed no process anywhere actually holding the lock and doing
# real work, consistent with flock() never actually granting it to
# anyone. mkdir() is atomic and reliably supported over NFS even where
# flock() isn't, so this pipeline's shared-filesystem locks (spanning
# multiple gene pipelines that can run concurrently) use it instead.
#
# Usage:
#   if ! acquireLockDir "$someLockDir" [staleAfterSeconds]
#   then
#       exit 1 # or otherwise bail out - $someLockDir isn't held
#   fi
#   ...critical section...
#   releaseLockDir "$someLockDir"
#
# $someLockDir is a directory path, not a plain file like the old flock
# idiom's lock file - it gets created (and later removed) as the lock
# itself, so it must not collide with anything else that's meant to
# exist at that path. Its parent directory must already exist -
# acquireLockDir doesn't create it. staleAfterSeconds defaults to 3600
# (1h) - pass a larger value for anything that can legitimately run
# longer than that (see get_ncbi_blastdb.sh's ~5h nr download for an
# example), since the stale-lock recovery below can't otherwise tell
# "still legitimately running" apart from "died a long time ago".
#
# Returns 1 without acquiring anything if mkdir fails for a reason other
# than the lock already being held (e.g. a missing parent directory) -
# callers must check this, not assume it always eventually succeeds.

acquireLockDir() {
	local lockDir="$1"
	local staleAfterSeconds="${2:-3600}"
	local mkdirError

	while true
	do
		mkdirError=$(mkdir "$lockDir" 2>&1) && return 0

		# mkdir fails for reasons other than "the lock is already held" too
		# - a missing parent directory, a permissions problem, a full
		# filesystem. Those don't leave $lockDir behind, unlike genuine
		# contention, so they're distinguishable - confirmed 2026-08-07:
		# get_prot_t5_model.sh called this on a Models/ directory that had
		# never been created yet, and every retry failed the exact same
		# way, forever, with zero CPU and no lock directory ever appearing
		# - the age check below always saw "not found" (falling back to
		# "now"), so it never crossed staleAfterSeconds and never stopped
		# retrying either. Fail loudly instead of joining that silent,
		# unrecoverable retry loop.
		if [ ! -d "$lockDir" ]
		then
			echo "acquireLockDir: mkdir \"$lockDir\" failed for a reason other than the lock already being held - not retrying forever over this. mkdir's own error:" >&2
			echo "$mkdirError" >&2
			return 1
		fi

		# Unlike flock, this lock does NOT get released automatically just
		# because its owning process died (walltime, scancel, node
		# failure) - something has to reclaim it eventually, or every
		# future run blocks on it forever. Age-based, not PID-liveness
		# based (e.g. `kill -0 $pid`), since the lock's owner is frequently
		# on a different compute node than whoever's waiting on it.
		local lockAgeSeconds=$(( $(date +%s) - $(stat -c %Y "$lockDir" 2>/dev/null || date +%s) ))
		if [ "$lockAgeSeconds" -ge "$staleAfterSeconds" ]
		then
			echo "$lockDir is over ${staleAfterSeconds}s old - assuming its owner died without releasing it, and taking it over" >&2
			rmdir "$lockDir" 2>/dev/null # no-op if a concurrent waiter's own recovery attempt already won this race
			continue
		fi
		sleep 5
	done
}

releaseLockDir() {
	rmdir "$1" 2>/dev/null
}
