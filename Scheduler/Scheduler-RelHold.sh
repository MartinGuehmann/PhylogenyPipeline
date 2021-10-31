#!/bin/bash

# Wrapper for calling qrls from PBS-Pro or scontrol from Slurm
# Checks whether qrls or scontrol and passes all the arguments
# to these programs.

if [ -x "$(command -v qrls)" ]
then
	qrls "$@"
elif [ -x "$(command -v scontrol)" ]
then
	scontrol release "$@"
else
	echo "No known scheduler present!" >&2
fi

