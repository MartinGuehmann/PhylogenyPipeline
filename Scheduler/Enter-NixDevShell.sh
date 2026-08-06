# Not meant to be run directly - source it near the top of a job script,
# before `source Load-Module.sh` if the script has one, so that a real
# cluster module can still shadow whatever Nix provides afterward (see
# README's PATH-precedence note under "Scheduler Setup").
#
# Usage: source "$DIR/Enter-NixDevShell.sh"
#
# Re-execs the calling job script inside flake.nix's devShell if Nix (or
# nix-portable) is available and we're not already inside one. Does
# nothing otherwise - no error, no requirement - so every job script can
# source this unconditionally regardless of whether a given cluster has
# Nix installed at all, relies entirely on `module load`, or has
# everything installed by hand on PATH already.

# A multi-user Nix install isn't on PATH until its profile scripts are
# sourced - harmless if they don't apply here, since each is only
# sourced when present (same pattern as BuildNixDependencies.sh).
# Computed unconditionally (not just when entering fresh) since the
# verify-and-retry step below needs $nixCmd too.
for profileScript in \
	/nix/var/nix/profiles/default/etc/profile.d/nix.sh \
	/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
do
	[ -f "$profileScript" ] && . "$profileScript"
done

nixCmd=""
if command -v nix >/dev/null 2>&1
then
	nixCmd="nix"
elif command -v nix-portable >/dev/null 2>&1
then
	nixCmd="nix-portable nix"
fi

# nix develop/nix shell set this - skip re-entering if we're already in
# one, otherwise the exec below would recurse into itself forever.
if [ -z "$IN_NIX_SHELL" ]
then
	# No Nix on this cluster at all: fall through and rely entirely on
	# module load and/or a manual PATH install instead - Nix is a
	# fallback, never a requirement.
	if [ -n "$nixCmd" ]
	then
		exec $nixCmd develop "$DIR/.." --command "$0" "$@"
	fi
fi

# We're now either freshly re-entered into the devShell above, were
# already in one, or Nix isn't available here at all (rely-on-module
# case, $nixCmd empty, nothing to verify). Confirmed 2026-08-06 on the
# cluster: when many array tasks launch `nix develop` simultaneously, a
# handful can come back with an incomplete PATH - some devShell tools
# resolve, others don't - instead of either a clean failure or a fully
# populated shell. First seen with raxml-ng missing while famsa worked;
# a later batch hit t_coffee missing instead - a fixed shortlist of
# "representative" tools to check (tried first, see git history) chases
# whichever package happens to be affected that time and misses the
# rest, so check every /nix/store path Nix put on PATH directly instead
# - name-agnostic, catches any of them. This looked like a nix
# store/profile race under concurrent launches - not consistently
# reproducible - so one retry (a fresh `nix develop`, not just
# re-checking the same shell) is worth it before giving up.
# $NIX_DEVSHELL_VERIFIED/$NIX_DEVSHELL_RETRIED are exported so nested
# scripts that source this file again inherit the already-done work
# instead of repeating it.
if [ -n "$nixCmd" ] && [ -n "$IN_NIX_SHELL" ] && [ -z "$NIX_DEVSHELL_VERIFIED" ]
then
	missingPathEntry=""
	oldIFS="$IFS"
	IFS=':'
	for pathEntry in $PATH
	do
		case "$pathEntry" in
			/nix/store/*)
				[ -d "$pathEntry" ] || missingPathEntry="$pathEntry"
				;;
		esac
	done
	IFS="$oldIFS"

	if [ -n "$missingPathEntry" ]
	then
		if [ -z "$NIX_DEVSHELL_RETRIED" ]
		then
			echo "Nix devShell looks incompletely activated ($missingPathEntry on PATH but not actually there) - retrying nix develop once before giving up." >&2
			export NIX_DEVSHELL_RETRIED=1
			unset IN_NIX_SHELL
			exec $nixCmd develop "$DIR/.." --command "$0" "$@"
		else
			echo "Nix devShell still incompletely activated after a retry ($missingPathEntry on PATH but not actually there) - giving up. This looks like the known intermittent nix store/profile race under concurrent job launches, not a real missing dependency - resubmitting this task on its own may well succeed." >&2
			exit 1
		fi
	fi

	export NIX_DEVSHELL_VERIFIED=1
fi
