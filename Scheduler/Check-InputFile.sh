# Not meant to be run directly - source it, then call checkInputFile.
#
# Usage: source "$DIR/Check-InputFile.sh"; checkInputFile "$seqsToAlign"
#
# Fails the job with a clear message if FILE is empty/unset, or doesn't
# exist, or exists but is zero bytes. Catches an upstream step having
# failed (walltime kill, crash, ...) and never having been rerun -
# without this, the step either silently skips its share of the work (if
# the glob that builds its own array file list didn't find anything) or
# silently runs on a leftover empty/partial file instead of failing loudly.
checkInputFile() {
	local file="$1"

	if [ -z "$file" ]
	then
		echo "$thisScript: no input file given - the previous step's output is missing" >&2
		exit 1
	fi

	if [ ! -s "$file" ]
	then
		echo "$thisScript: input file '$file' does not exist or is empty - the previous step likely failed and needs to be rerun" >&2
		exit 1
	fi
}
