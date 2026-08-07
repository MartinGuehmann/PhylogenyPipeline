# Not meant to be run directly - source it, then call condaEnvPython
# <envName> to get that conda environment's own python interpreter, by
# absolute path.
#
# `conda run -n <env> <name>` resolves <name> by modifying PATH and then
# doing a normal command-name lookup - confirmed 2026-08-07 that this
# isn't reliable inside this repo's Nix devShell: `conda run -n
# vcmsa_env python -m pip install ...` resolved "python" itself to a
# bare Nix-store Python 3.14 with no pip module at all, not vcmsa_env's
# own conda Python 3.9 - even though earlier runs' `conda run -n
# vcmsa_env python -c "import ..."` checks through the same `conda run`
# had reliably hit the right interpreter, so the lookup isn't safe to
# trust even when it's worked before. Resolving the env's prefix
# directly via `conda env list` (a plain conda invocation, not `conda
# run` - reliable throughout this investigation) and returning
# "$prefix/bin/python" by absolute path avoids that name lookup
# entirely.
#
# Even invoked by absolute path, that interpreter can still see a Nix
# devShell's own Python packages via an inherited PYTHONPATH - nixpkgs'
# python setup-hook adds every Python package in this repo's devShell
# packages list (flake.nix's pythonWithEte3) to PYTHONPATH in the shell
# automatically, intentionally so e.g. 12_ConvertTreesToFigures.py's
# bare `python3 script.py` sees ete3 - but that leaks into every other
# Python this script runs too. Confirmed 2026-08-07: this leaked an
# incompatible-ABI numpy (built for Nix's Python 3.14) into vcmsa_env's
# own Python 3.9, breaking `import numpy` there despite vcmsa_env having
# its own correct numpy installed. Callers must run the returned path
# with `env -u PYTHONPATH` for the same reason - this function doesn't
# do that itself, since not every caller necessarily wants it cleared.
#
# Usage:
#   pythonPath=$(condaEnvPython "$envName")
#   [ -n "$pythonPath" ] && env -u PYTHONPATH "$pythonPath" ...
#
# Echoes nothing (caller sees an empty string) if $envName doesn't exist.
condaEnvPython() {
	local envName="$1"
	local prefix
	prefix=$(conda env list | awk -v n="$envName" '$1 == n { print $NF; exit }')
	[ -n "$prefix" ] && echo "$prefix/bin/python"
}
