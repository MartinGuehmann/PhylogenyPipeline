#!/bin/bash

# Wrapper getting the array index from PBS-Pro, Slurm, or Torque/Moab,
# depending on what is installed.

# PBS-Pro
if [ ! -z ${PBS_ARRAY_INDEX} ]
then
	echo ${PBS_ARRAY_INDEX}
# Slurm
elif [ ! -z ${SLURM_ARRAY_TASK_ID} ]
then
	echo ${SLURM_ARRAY_TASK_ID}
# Torque/Moab
elif [ ! -z ${PBS_ARRAYID} ]
then
	echo ${PBS_ARRAYID}
else
	echo "No known scheduler present!" >&2
	exit 1
fi
