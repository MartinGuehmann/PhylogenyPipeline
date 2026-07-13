# The Phylogeny Pipeline

This is the phylogeny pipeline, which builds single gene pyhlogenies for given bait sequences. With the bait sequences, the pipeline extracts matching sequences with BLAST from the protein sequence databases of NCBI and Uniprot. It extracts the sequences from NCBI remotely and from the Uniprot databases from local copies.

## Prerequisites

The pipeline requires to run:

	- Standard Linux tools such as Bash
	- SeqKit (user path)
	- IQ-Tree2 (module load)
	- Custom ete3 (installed locally from git clone) with Python 3  
	  (ete3 requires QT5 with a running x-server; on a headless cluster  
	  node run this step under a virtual framebuffer, e.g. xvfb-run,  
	  or run it separately on a machine with a real X session)
	- raxml-ng (user path)
	- cd-hit (user path)
	- efetch (user path)
	- blastp (module load)
	- TrimAl (base folder)
	- RogueNaRok-parallel (base folder)
	- TreeShrink (user path) with Python 2.7 (module load)

Steps 0 and 3 query NCBI remotely (BLAST and efetch). If the cluster's
compute nodes have no internet access, these two steps need to run
somewhere that does, e.g. a login node, instead of via the scheduler.

Supported aligners are:

	- T-Coffee (module load)
	- PASTA (user path)
	- MUSCLE (module load)
	- MUSCLE5 (module load)
	- SUPER5 (module load, ships with MUSCLE5)
	- MAFFT (module load)
	- LINSI (module load, ships with MAFFT)
	- FAMSA (user path)
	- Clustal-Omega (module load)
	- MAGUS (module load Python 3 + dendropy installed for that Python:
	  `python3 -m pip install --user -U dendropy`)
	- vcMSA (module load Python 3 + a conda environment named `vcmsa_env`)

Optional, however if not installed will generate an error:

	- pdf2png (user path installed on a local laptop with apt)

The needed programms are installed in mainly three different ways, depending on the original needs.

	- base folder is the folder where you clone this repository into.
	- user path is where bash checks for programs installed,  
	  this could be a system folder, but also a folder in your  
	  home directory that was added to your search path.
	- module load is the command used to load modules on a  
	  cluster node into the environment. These are specified  
	  in the ./Scheduler/XX_* files. And need to be modified  
	  for the cluster they are supposed to run on.

The pipeline is designed to run on a cluster computer, either with PBS Pro or Slurm as scheduler. In principle, more schedulers could be added. Another possibility would to install a scheduler such as PBS-Pro or Slurm on a local computer.

## Databases

The phylogeny pipeline downloads the uniprot protein databases sprot and trembl in fasta format and builds from them blast databases, which requires about 210 GB as of August 2021.

If you want to use newer versions you have to delete them. The databases are in ./PhylogenyPipeline/ProteinDatabase/. There, just delete the folders uniprot_trembl and uniprot_sprot.

The phylogeny pipeline also downloads the taxon database from NCBI. If you want to use a newer version just delete it. The files are in ./PhylogenyPipeline/SpeciesDatabase/.

## User Account Information

If you need to supply account information, when you start a job then go to file ./Scheduler/Account.sh and follow the comments given there. Note this is only implemented for Slurm, since no PBS-Pro is available for testing.

## Scheduler Setup

`Scheduler-Sub.sh` picks the scheduler to submit to at runtime:

	- If a `qsub` command is on the path, it is used, with PBS/Torque-style
	  options (`-W depend=`, `-J`, `-h`, `-v`).
	- Otherwise, if `sbatch` is on the path, it is used with translated
	  Slurm options.

The cpu/mem/walltime resources for each job script are not hardcoded in
the script itself. They are looked up by script name in
./Scheduler/Resources.cfg and passed on the command line
(`-l select=...`/`-l walltime=...` for qsub, `--cpus-per-task`/`--mem`/
`--time` for sbatch). This means tuning resources for a cluster, or for
a particular gene that needs more memory, is a matter of editing one
table instead of every job script.

Note that some Slurm installations that migrated from PBS/Torque provide
a `qsub` compatibility wrapper (e.g. Slurm's contribs/torque `qsub.pl`)
that would also read `#PBS` directives directly out of a script. This
pipeline no longer relies on that: `Resources.cfg` is the single source
of truth regardless of which branch `Scheduler-Sub.sh` takes.

## Moving to a new cluster

Checklist for getting the pipeline running on a cluster it hasn't run on before:

	- Adjust ./Scheduler/Resources.cfg if the new cluster's node sizes or
	  usual walltime limits differ from what is currently in there.
	- Update every `module load ...` line in ./Scheduler/*.sh to module
	  names/versions that exist on the new cluster.
	- Recreate the `vcmsa_env` conda environment used by
	  09_Scheduler-AlignWithVCMSA.sh, and pip-install dendropy for the
	  Python module used by 09_Scheduler-AlignWithMAGUS.sh.
	- Set the account string in ./Scheduler/Account.sh, if the cluster
	  requires one.
	- Install the "user path" and "base folder" tools listed under
	  Prerequisites; they are not covered by module load.
	- Make sure compute nodes have internet access for steps 0 and 3, or
	  plan to run those steps outside the scheduler.
	- Provision storage for the ~210 GB Uniprot BLAST databases and the
	  NCBI taxon database (see Databases above).
