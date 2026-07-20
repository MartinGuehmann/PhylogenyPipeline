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

# nix develop/nix shell set this - skip re-entering if we're already in
# one, otherwise the exec below would recurse into itself forever.
if [ -z "$IN_NIX_SHELL" ]
then
	# A multi-user Nix install isn't on PATH until its profile scripts
	# are sourced - harmless if they don't apply here, since each is
	# only sourced when present (same pattern as BuildNixDependencies.sh).
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

	# No Nix on this cluster at all: fall through and rely entirely on
	# module load and/or a manual PATH install instead - Nix is a
	# fallback, never a requirement.
	if [ -n "$nixCmd" ]
	then
		exec $nixCmd develop "$DIR/.." --command "$0" "$@"
	fi
fi
