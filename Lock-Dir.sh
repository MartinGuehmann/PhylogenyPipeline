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
#   acquireLockDir "$someLockDir" [staleAfterSeconds]
#   ...critical section...
#   releaseLockDir "$someLockDir"
#
# $someLockDir is a directory path, not a plain file like the old flock
# idiom's lock file - it gets created (and later removed) as the lock
# itself, so it must not collide with anything else that's meant to
# exist at that path. staleAfterSeconds defaults to 3600 (1h) - pass a
# larger value for anything that can legitimately run longer than that
# (see get_ncbi_blastdb.sh's ~5h nr download for an example), since the
# stale-lock recovery below can't otherwise tell "still legitimately
# running" apart from "died a long time ago".

acquireLockDir() {
	local lockDir="$1"
	local staleAfterSeconds="${2:-3600}"

	while ! mkdir "$lockDir" 2>/dev/null
	do
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
