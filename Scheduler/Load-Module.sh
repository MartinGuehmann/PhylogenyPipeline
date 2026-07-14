# Not meant to be run directly - source it, then call load_module.
#
# Usage: source "$DIR/Load-Module.sh"; load_module MODULE_MUSCLE5
#
# Looks KEY up in Scheduler/Modules.cfg and, if it has a value, loads it
# with `module load`. Does nothing - falling back to whatever is already
# on PATH, e.g. a Nix devShell - if the `module` command itself isn't
# present on this cluster, or if KEY is missing or blank in Modules.cfg.
load_module() {
	local key="$1"
	local moduleLine
	local moduleName

	if ! command -v module > /dev/null 2>&1
	then
		return 0
	fi

	moduleLine=$(grep -E -m1 "^$key([[:space:]]|\$)" "$DIR/Modules.cfg")
	if [ -n "$moduleLine" ]
	then
		read -r _ moduleName <<< "$moduleLine"
		if [ -n "$moduleName" ]
		then
			module load $moduleName
		fi
	fi
}
