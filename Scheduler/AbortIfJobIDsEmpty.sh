# Not meant to be run directly - source it near the top of a
# Scheduler-Call.sh-chaining script, then call:
#   abortIfJobIDsEmpty "$jobIDs" "step description"
# right after every `jobIDs=$("$DIR/Scheduler-Call.sh" ...)` (or
# jobIDs+=/holdJobs=) assignment.
#
# Scheduler-Call.sh always echoes a leading-colon job ID list (e.g.
# ":12345") on success - see its own `jobIDs=:$(...)` lines - so an empty
# $jobIDs here only ever means Scheduler-Call.sh exited before reaching
# its own echo, i.e. it failed outright (its own stderr already explains
# why - e.g. CheckNixDependenciesBuilt.sh's Nix GC-root check). Nothing
# that follows in the calling script - a --depend on this job, releasing
# a hold on it - is meaningful if it was never actually submitted, so
# stop here instead of producing a confusing downstream error instead
# (confirmed 2026-07-29: an empty jobIDs reaching Scheduler-RelHold.sh
# unnoticed turned into a bare `scontrol release` with no job ID and a
# cryptic "too few arguments for keyword:release").
#
# Usage: source "$DIR/AbortIfJobIDsEmpty.sh"
abortIfJobIDsEmpty()
{
	if [ -z "$1" ]
	then
		echo "$2: Scheduler-Call.sh failed to submit (see its own stderr for why) - aborting $thisScript" >&2
		exit 1
	fi
}
