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
	- RogueNaRok-parallel (user path)
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
	- MAGUS (user path: a `magus` command, e.g. via
	  `pip install --user magus-msa`, or the flake's `magus` package)
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

### Installing prerequisites with Nix

`./flake.nix` provides a `nix develop` shell with the "user path" tools that
are packaged in nixpkgs: SeqKit, cd-hit, TrimAl, blastp, Clustal-Omega, and
MAFFT/LINSI. This turns those installs into a single reproducible
environment instead of one recipe per tool, and is a fallback for tools
such as blastp if they are not available via `module load` on a given
cluster.

If Nix itself isn't installed on the cluster and you have no root access,
use [nix-portable](https://github.com/DavHau/nix-portable) instead of the
regular installer; it runs Nix entirely out of your home directory via a
user namespace/bubblewrap trick, e.g. `nix-portable nix develop`.

IQ-Tree is deliberately *not* in the devShell yet: nixpkgs' `iqtree`
package currently builds IQ-TREE 3 (`iqtree3`), a major version ahead of
the `iqtree2` that `10_MakeTreeWithIQ-Tree.sh` expects - still deciding
whether to upgrade the pipeline to match, or pin an IQ-TREE2 build in the
flake instead. Until that's settled, `module load` (Scheduler/Modules.cfg)
is the only way to get IQ-Tree2 in this setup.

The devShell's binary *names* were audited against what the pipeline
scripts actually call, not assumed from each tool's usual name:

- **MUSCLE**: `09_AlignWithMUSCLE.sh` calls a plain `muscle` expecting
  classic v3's `-in`/`-out` syntax, and `09_AlignWithMUSCLE5.sh`/
  `SUPER5.sh` call `muscle5` expecting v5's `-align`/`-super5` syntax.
  nixpkgs' own `muscle` package is v5.1.0 but installs its binary as
  plain `muscle` - so the flake exposes classic MUSCLE v3 (built from a
  drive5.com static binary) as `muscle`, and re-exposes nixpkgs' v5
  package under the name `muscle5` instead, matching both scripts.

The shell also builds raxml-ng, RogueNaRok-parallel (plus its rnr-prune/
rnr-lsi/rnr-tii/rnr-mast helpers), FAMSA, TreeShrink, MAGUS, and
entrez-direct (efetch, esearch, etc.) straight from source (nixpkgs' own
`raxml` package is the older, classic RAxML, not raxml-ng - do not
substitute it), since none of those are packaged in nixpkgs either. These
derivations are unverified - built from each project's documented build
commands, not build-tested against a real Nix install - so the first
`nix build .#<name>` (e.g. `nix build .#raxml-ng`) will likely need its
`fakeHash` placeholder replaced with the real hash Nix reports, and
possibly a small installPhase fix if a binary ends up somewhere other
than guessed. Also note the flake's TreeShrink is v1.4.0, which needs
Python 3.8+, not the Python 2.7 in the Prerequisites list above - check
it still behaves the same before relying on it for a production run.

entrez-direct has no public source repo of its own - NCBI only
distributes it via FTP - so that derivation is instead modeled on
[bioconda's build recipe](https://github.com/bioconda/bioconda-recipes/tree/master/recipes/entrez-direct)
and uses its pinned version and hash directly (no `fakeHash` there). Its
own biggest risk: it builds the `xtract`/`rchive`/`transmute` helpers
from bundled Go source at build time, and if EDirect's Go modules aren't
vendored in the tarball, that `go build` will try to reach the network,
which Nix's sandboxed build blocks - see the comment in flake.nix for
the `pkgs.buildGoModule` fallback if that happens.

T-Coffee and PASTA are now also built, likewise modeled on their
[bioconda](https://github.com/bioconda/bioconda-recipes) recipes rather
than each project's own install docs, since bioconda's CI actually builds
and tests them and gives pinned versions/hashes to match. Both needed
real compromises versus the bioconda recipe, so treat them as the least
trustworthy derivations in this flake:

- **T-Coffee**: only the core `t_coffee`/`TMalign` compile step is
  replicated (`cd t_coffee_source && make all`), not bioconda's full
  install, which also runs T-Coffee's own installer to fetch its bundled
  meta-aligner plugins over the network - not usable in a sandboxed Nix
  build, and not needed since this pipeline only calls the base
  `t_coffee` binary anyway. A small upstream patch bioconda applies
  (`coredump.patch`, fixing `set_nproc`'s signature in util.c) was
  skipped since only its two changed lines were available, not full
  context; if the build fails around `set_nproc`, that's the fix needed.
- **PASTA**: needs several more tools at *specific old versions*, now
  also built from source and bundled alongside it: classic MUSCLE v3
  (PASTA's own code expects v3's CLI flags, not v5's - published only as
  an x86_64 static binary, so this piece doesn't exist on aarch64),
  ClustalW 2.1, FastTree 2.2.0, and PRANK, plus `pkgs.raxml` and
  `pkgs.hmmer` from nixpkgs and a single `opal.jar` fetched directly
  (not the whole `sate-tools-linux` bundle it comes from). These are
  handed to PASTA via its own `PASTA_TOOLS_RUNDIR` environment variable
  rather than bioconda's approach of patching PASTA's source to look at
  `$CONDA_PREFIX/bin` - this is the least certain part of the whole
  flake: bioconda's choice to patch instead of using that variable hints
  it may not cover every tool lookup in PASTA's code. If PASTA can't find
  a tool at runtime despite it being available, patching
  `pasta/__init__.py`'s tool-directory functions the way bioconda's
  `fix_tooldir.patch` does is the documented fallback (see the comment
  above the `pastaToolsDir` derivation in flake.nix).

The shell also builds a custom ete3 fork
([MartinGuehmann/ete](https://github.com/MartinGuehmann/ete), branch
`AddFaceFloatRight`), pinned to that branch's tip commit
(`7b6ef8d`) as of 2026-07-14 - deliberately from *before* rebasing onto
upstream ete's major version bump, since that rebase and the API
adjustments it needs are being kept as separate, later work rather than
entangled with this packaging. Re-pin the `rev` (and likely rework this
derivation - a major version bump probably changes how ete3 packages
itself) once that rebase happens. Its old setup.py also "phones home" to
etetoolkit.org on install unless told not to; disabled outright here
since that network call would fail in Nix's sandboxed build anyway. It
still needs a real or virtual X server at runtime (e.g. `xvfb-run`) -
packaging it doesn't remove that requirement.

`12_ConvertTreesToFigures.py` isn't a standalone `ete3` command, though -
it's run as plain `python3 12_ConvertTreesToFigures.py` and does
`from ete3 import ...` internally. A wrapped, isolated `ete3` console
script wouldn't help there, since a *separate* `python3` on PATH
wouldn't have ete3 importable. So ete3 is instead built as a plain
importable package and merged into its own `python3` via
`pkgs.python3.withPackages`, and it's *that* interpreter (not a bare
`ete3` command) that the devShell puts on PATH as `python3`.

FAMSA, RogueNaRok, and MAGUS needed a different kind of fix: the pipeline
called them via hardcoded sibling-directory paths
(`$DIR/../FAMSA/famsa`, `$DIR/../RogueNaRok/RogueNaRok-parallel`,
`python3 $DIR/../MAGUS/magus.py`) rather than a PATH lookup, so the
devShell's versions were never reached no matter what was on PATH.
`09_AlignWithFAMSA.sh`, `11_RemoveRogues.sh`, and `09_AlignWithMAGUS.sh`
now call `famsa`, `RogueNaRok-parallel`, and `magus` directly instead,
so they resolve through the Nix devShell (or `module load`/base-folder
installs, if you're not using the flake).

## Gene Data Repositories

The pipeline scripts build paths as `$DIR/$gene/...`, where `$DIR` is this
repository's own directory and `$gene` is whatever is passed via `-g`. The
gene-specific data itself (bait sequences, clade definitions, orchestration
scripts, and the pipeline's generated output for that gene) is kept in a
separate, per-gene-family repository rather than inside this one.

The convention is to check that gene repository out as a sibling of this
one, under the same parent directory, and have its orchestration scripts
pass `-g "../<GeneRepoName>"` so that `$DIR/$gene/...` resolves back up
into it. See [Opsins](https://github.com/MartinGuehmann/Opsins) for a
worked example, including which subdirectories are hand-curated inputs
versus pipeline-generated output.

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

Likewise, the `module load ...` lines are not hardcoded in each job
script either. Each script instead sources `Load-Module.sh` and calls
`load_module MODULE_KEY`, which looks `MODULE_KEY` up in
./Scheduler/Modules.cfg and runs `module load` with whatever value it
finds there. If a key is missing or blank in Modules.cfg, or the
`module` command doesn't exist on the cluster at all, `load_module` does
nothing and the script falls back to whatever is already on PATH - e.g.
tools from the Nix devShell (see "Installing prerequisites with Nix"
above). So adjusting module names/versions for a new cluster, or
dropping a module entirely in favor of Nix, is a matter of editing one
table instead of every job script.

## Moving to a new cluster

Checklist for getting the pipeline running on a cluster it hasn't run on before:

	- Adjust ./Scheduler/Resources.cfg if the new cluster's node sizes or
	  usual walltime limits differ from what is currently in there.
	- Update ./Scheduler/Modules.cfg to module names/versions that exist
	  on the new cluster, or blank an entry out to fall back to Nix
	  instead (see "Scheduler Setup" above).
	- Recreate the `vcmsa_env` conda environment used by
	  09_Scheduler-AlignWithVCMSA.sh. MAGUS just needs a `magus` command
	  on PATH (`pip install --user magus-msa`, or the flake's `magus`
	  package).
	- Set the account string in ./Scheduler/Account.sh, if the cluster
	  requires one.
	- Install the "user path" and "base folder" tools listed under
	  Prerequisites; they are not covered by module load. `nix develop`
	  (see "Installing prerequisites with Nix" above) covers a subset of
	  these.
	- Make sure compute nodes have internet access for steps 0 and 3, or
	  plan to run those steps outside the scheduler.
	- Provision storage for the ~210 GB Uniprot BLAST databases and the
	  NCBI taxon database (see Databases above).
