#!/bin/bash

# Wrapper for calling qsub from PBS-Pro or sbatch from Slurm
# The parameters mapped from qsub to sbatch are hold, range,
# dependency, and exported environment variables. Add if you
# need more. Call this script with these options as you would
# call qsub.
#
# The cpu/mem/walltime/partition resources for the submitted script are
# looked up by its basename in Resources.cfg and passed on the command
# line, so tuning resources for a cluster means editing that one file
# instead of every job script. Pass --resources/-R NAME to look up NAME
# instead of the script's own basename, e.g. to ask for a different
# named profile such as AskForWholeNode.

hold=""
depend=""
range=""
export=""
exportFlag=""
script=""
resourceName=""

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
			--resources)
				;&
			-R)
				shift
				resourceName="$1"
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

	profileName="${resourceName:-$(basename "$script")}"
	resourceLine=$(grep -m1 "^${profileName}[[:space:]]" "./Resources.cfg")
	resources=""
	if [ -n "$resourceLine" ]
	then
		read -r _ cpus mem walltime partition <<< "$resourceLine"
		resources="-l select=1:ncpus=$cpus:mem=${mem}gb -l walltime=$walltime"
		[ -n "$partition" ] && resources="$resources -q $partition"
		if [ "$profileName" == "AskForWholeNode" ]
		then
			# PBS Pro's exclusive-node flag, unlike Slurm's --exclusive
			# below, still needs the ncpus/mem above to size the select
			# statement - place=excl just additionally guarantees no
			# other job shares the node, which is the whole reason this
			# profile exists (makeblastdb ignores its assigned CPU count
			# and grabs everything on the node it lands on).
			resources="$resources -l place=excl"
		fi
	fi

	qsub $hold $depend $range $resources $exportFlag "$export" $script
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
				export="${export//, /,}"
				exportFlag="--export="
				;;
			--resources)
				;&
			-R)
				shift
				resourceName="$1"
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

	account=$("./Account.sh")

	profileName="${resourceName:-$(basename "$script")}"
	resourceLine=$(grep -m1 "^${profileName}[[:space:]]" "./Resources.cfg")
	resources=""
	if [ -n "$resourceLine" ]
	then
		read -r _ cpus mem walltime partition <<< "$resourceLine"
		if [ "$profileName" == "AskForWholeNode" ]
		then
			# --exclusive hands the whole node to this job regardless of
			# its actual size, so no --cpus-per-task/--mem here - unlike
			# the PBS branch above, Slurm doesn't need an explicit size
			# to grant the full node. This is also why this profile's
			# ncpus/mem in Resources.cfg no longer need resizing for a
			# new cluster on the Slurm side (PBS still uses them).
			resources="--exclusive --time=$walltime"
		else
			resources="--cpus-per-task=$cpus --mem=${mem}G --time=$walltime"
		fi
		[ -n "$partition" ] && resources="$resources --partition=$partition"
	fi

	jobID=$(sbatch --kill-on-invalid-dep=yes $hold $account $depend $range $resources $exportFlag"$export" $script)
	echo ${jobID##* }
else
	echo "No known scheduler present!" >&2
	exit 1
fi
