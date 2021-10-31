#!/bin/bash

# Wrapper for calling qrls from PBS-Pro or scontrol from Slurm
# Checks whether qrls or scontrol and passes all the arguments
# to these programs.

if [ -x "$(command -v qrls)" ]
then
	grls "$@"
elif [ -x "$(command -v scontrol)" ]
else
	scontrol release "$@"
fi

