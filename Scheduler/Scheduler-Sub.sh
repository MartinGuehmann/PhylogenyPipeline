#!/bin/bash

# Wrapper for calling qsub from PBS-Pro or sbatch from Slurm
# The parameters mapped from qsub to sbatch are hold, range,
# dependency, and exported environment variables. Add if you
# need more. Call this script with these options as you would
# call qsub.

hold=""
depend=""
range=""
export=""
exportFlag=""
script=""

if [ -x "$(command -v qsub)" ]
then
	# Idiomatic parameter and option handling in sh
	# Adapted from https://superuser.com/questions/186272/check-if-any-of-the-parameters-to-a-bash-script-match-a-string
	# And advanced version is here https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash/7069755#7069755
	while test $# -gt 0
	do
		case "$1" in
			--depend)
				;&
			-W)
				shift
				depend="-W $1"
				;;
			--range)
				;&
			-J)
				shift
				range="-J $1"
				;;
			--hold)
				;&
			-h)
				hold="-h"
				;;
			--export)
				;&
			-v)
				shift
				export="$1"
				exportFlag="-v"
				;;
			-*)
				;&
			--*)
				echo "Bad option $1 is ignored" >&2
				;;
			*)
				# The first string without an option string is the script to run
				if [ -z $script ]
				then
					script=$1
				# Everything further is ignored
				else
					echo "Bad option $1 is ignored" >&2
				fi
				;;
		esac
		shift
	done

	qsub $hold $depend $range $exportFlag "$export" $script
elif [ -x "$(command -v sbatch)" ]
then
	# Idiomatic parameter and option handling in sh
	# Adapted from https://superuser.com/questions/186272/check-if-any-of-the-parameters-to-a-bash-script-match-a-string
	# And advanced version is here https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash/7069755#7069755
	while test $# -gt 0
	do
		case "$1" in
			--depend)
				;&
			-W)
				shift
				depend="--$1"
				;;
			--range)
				;&
			-J)
				shift
				range="--array=$1"
				;;
			--hold)
				;&
			-h)
				hold="--hold"
				;;
			--export)
				;&
			-v)
				shift
				export="$1"
				exportFlag="--export="
				;;
			-*)
				;&
			--*)
				echo "Bad option $1 is ignored" >&2
				;;
			*)
				# The first string without an option string is the script to run
				if [ -z $script ]
				then
					script=$1
				# Everything further is ignored
				else
					echo "Bad option $1 is ignored" >&2
				fi
				;;
		esac
		shift
	done

	sbatch $hold $depend $range $exportFlag "$export" $script
else
	echo "No known scheduler present!" >&2
	exit 1
fi
