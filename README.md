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
	- TrimAl (user path)
	- RogueNaRok-parallel (user path)
	- TreeShrink (user path) with Python 2.7 (module load)
	- newick_utils: nw_reroot, nw_clade, nw_labels (user path)

Steps 5-7 build a tree via CLANS clustering and neighbor-joining
(rapidNJ) - an abandoned, experimental alternative to the main
alignment/tree-building pipeline (steps 9+). Only needed if you run
those steps specifically (all base folder):

	- ClansTools (https://github.com/MartinGuehmann/ClansTools, distinct
	  from the public CLANS-Tools Python repo)
	- CLANS (https://github.com/proteinevolution/clans)
	- rapidNJ (https://github.com/somme89/rapidNJ)

Steps 0 and 3 query NCBI remotely (BLAST and efetch). This needs a
machine with a genuinely working round trip to NCBI - not just "a
machine with internet access" via some proxy. See "Remote NCBI access"
below for what that distinction means in practice and how to test it.

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
	- vcMSA (module load Python 3 + a conda environment named `vcmsa_env`) -
	  currently disabled pipeline-wide via `Scheduler/SkippedAligners.cfg`
	  (see that file's own header comment to re-enable). Confirmed
	  2026-08-07 on real Mas1 production data that its embedding step's
	  memory use scales with input size badly enough that even a whole
	  compute node (96 CPUs/248GB, the largest single-job request this
	  cluster allows) still OOM-killed - root-caused to vcMSA's own
	  padding-to-longest-sequence embedding storage and multiple
	  redundant in-memory copies during clustering, not a
	  configuration/environment issue on this end.

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

If Nix (or nix-portable) is on PATH, run `./BuildNixDependencies.sh` once
after cloning, and again whenever flake.nix changes, before submitting
any jobs - not just to pre-build everything, but because it's the only
thing that actually protects the built environment from
`nix-collect-garbage`. It roots every derivation it builds under
`.nix-gcroots/`; without that, store paths are only *realized*, not
*rooted*, and the next garbage collection (yours, another user's, or a
cron job, on a shared store) can remove one out from under an
already-built derivation that references it - confirmed 2026-07-29, when
a `raxml` symlink baked into PASTA's tool directory went dangling this
way and failed an entire 26-task array. `Scheduler/Scheduler-Call.sh`
checks these roots exist and aren't broken before submitting any job, and
refuses to submit (with a pointer back to this script) if they're
missing or stale.

The devShell's binary *names* were audited against what the pipeline
scripts actually call, not assumed from each tool's usual name:

- **MUSCLE**: `09_AlignWithMUSCLE.sh` calls a plain `muscle` expecting
  classic v3's `-in`/`-out` syntax, and `09_AlignWithMUSCLE5.sh`/
  `SUPER5.sh` call `muscle5` expecting v5's `-align`/`-super5` syntax.
  nixpkgs' own `muscle` package is v5.1.0 but installs its binary as
  plain `muscle` - so the flake exposes classic MUSCLE v3 (built from a
  drive5.com static binary) as `muscle`, and re-exposes nixpkgs' v5
  package under the name `muscle5` instead, matching both scripts.
- **IQ-Tree**: nixpkgs' `iqtree` package builds IQ-TREE 3 (binary
  `iqtree3`), a major version ahead of the `iqtree2` that
  `10_MakeTreeWithIQ-Tree.sh` calls. Decided to upgrade rather than pin
  an IQ-TREE2 build from source: IQ-TREE3's own release notes describe it
  as an additive release (mixture models, concordance factors,
  DecentTree, a `piqtree` Python interface), and none of the flags this
  pipeline uses (`-s`, `-B`, `--abayes`, `--alrt`, `-m TEST`,
  `-nt`/`-ntmax`, `--boot-trees`) turned up as renamed or removed
  anywhere in IQ-TREE's docs. So `iqtree3` is aliased to the command name
  `iqtree2` in the devShell rather than changing the script - same
  pattern as MUSCLE above, same command the script already calls, a
  different implementation behind it (`iqtree2 --version` will report
  3.x; that's expected). This hasn't been run against a real cluster
  workload yet - worth a smoke-test comparison against a known IQ-TREE2
  result before trusting it for production, since a major-version jump
  can shift numerical results even with identical flags. `module load`
  (Scheduler/Modules.cfg) still gives the cluster's real IQ-TREE2 module
  if you need to fall back to it.

The shell also builds raxml-ng, RogueNaRok-parallel (plus its rnr-prune/
rnr-lsi/rnr-tii/rnr-mast helpers), FAMSA, TreeShrink, MAGUS, and
newick_utils (nw_reroot/nw_clade/nw_labels/etc.) straight from source
(nixpkgs' own `raxml` package is the older, classic RAxML, not
raxml-ng - do not substitute it), since none of those are packaged
in nixpkgs either. These have since been build-tested successfully
(`./BuildNixDependencies.sh` builds every derivation in the flake and
reports OK for all of them), so the `fakeHash` placeholders described in
that script's own comments are already resolved to real hashes - a fresh
`nix build .#<name>` shouldn't need that step repeated unless flake.nix
changes again. A successful build only confirms each derivation compiles
and installs, though, not that its binary behaves correctly at runtime:
the flake's TreeShrink is v1.4.0, which needs Python 3.8+, not the
Python 2.7 in the Prerequisites list above - check it still behaves the
same before relying on it for a production run.

entrez-direct (efetch, esearch, esummary, elink, epost, einfo) has no
public source repo of its own - NCBI only distributes it via FTP - so
that derivation is instead modeled on
[bioconda's build recipe](https://github.com/bioconda/bioconda-recipes/tree/master/recipes/entrez-direct)
and uses its pinned version and hash directly (no `fakeHash` there).
Unlike the tools above, this one has been build-tested end to end
(`nix build .#entrez-direct`, `efetch -version` reporting `25.3`, and a
live NCBI fetch all confirmed working): `efetch`/`esearch`/`esummary`/
`elink`/`epost`/`einfo` are plain shell scripts shipped at the EDirect
tarball's root, separate from the `xtract`/`rchive`/`transmute` Go
binaries this derivation builds from bundled Go source (`cmd/*.go`) - an
earlier version of this flake only ever built the latter, so `efetch`
was silently missing from the devShell entirely and every script calling
it (`03_ExtractSequences.sh`) was actually depending on whatever `efetch`
happened to be on the system outside Nix. The installPhase now installs
the scripts and their real runtime dependencies (`ecommon.sh`, `nquire`,
`cacert.pem`) as real file copies rather than symlinks, since each
resolves a sibling file via `dirname "$0"` at runtime, and that does not
follow symlinks. `nquire` (efetch's actual HTTP transport) shells out to
whatever `curl`/`wget` it finds on `PATH` at runtime instead of bundling
its own, so the devShell lists `curl`/`wget` directly in its `packages`
- not as an entrez-direct `buildInput`, since `buildInputs`/
`propagatedBuildInputs` only propagate to other derivations building
against this one, not to a plain `nix develop`/`nix shell`'s PATH. The
Go build itself still carries the same vendoring risk as the tools
above: if EDirect's Go modules aren't vendored in the tarball, `go
build` will try to reach the network, which Nix's sandboxed build
blocks - see the comment in flake.nix for the `pkgs.buildGoModule`
fallback if that happens.

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

`09_AlignWithFAMSA.sh`, `11_RemoveRogues.sh`, `09_AlignWithMAGUS.sh`, and
`08_/16_ExtractSequencesOfInterest.sh` call `famsa`, `RogueNaRok-parallel`,
`magus`, and `nw_reroot`/`nw_clade`/`nw_labels` by bare command name, so
they resolve through the Nix devShell (or `module load`/base-folder
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
versus pipeline-generated output, or start a new one from
[GeneFamilyTemplate](https://github.com/MartinGuehmann/GeneFamilyTemplate).

One subdirectory has its own `README.md`, since its contents need more
than a one-line explanation: `SequencesOfInterest/`, where the
rogue-removal loop (step 11) keeps each round's working sequence set.
That sub-readme covers the `RogueIter_N/` directory layout and,
notably, why a round's output has *three* files per part
(`part_NNN.fasta`, `part_NNN.dropped.fasta`, `part_NNN.old.fasta`) with
no continuity between the plain one and the other two once shuffling
is on.

## Databases

The phylogeny pipeline downloads the uniprot protein databases sprot and trembl in fasta format and builds from them blast databases, which requires about 210 GB as of August 2021.

If you want to use newer versions you have to delete them. The databases are in ./PhylogenyPipeline/ProteinDatabase/. There, just delete the folders uniprot_trembl and uniprot_sprot.

The phylogeny pipeline also downloads the taxon database from NCBI. If you want to use a newer version just delete it. The files are in ./PhylogenyPipeline/SpeciesDatabase/.

`nr`, `refseq_protein`, and `tsa_nr` are normally searched remotely
(`Databases.sh`'s `RemoteDataBases`) - `nr`'s sheer breadth of homology in
particular can make NCBI kill a broad-homology gene's remote search
outright (`CPU usage limit exceeded`, SIGXCPU), no matter how the search
itself is tuned. If that's a problem, pass `--localNr`/`-L`,
`--localRefseqProtein`/`-R`, and/or `--localTsaNr`/`-T` (`RunAll.sh`,
`Scheduler-Call.sh`, `Scheduler-00-ExtractSequences.sh`/
`Scheduler-01-PrepareSequences.sh`) to search a local copy of whichever
one(s) you name instead - independently settable, so you can opt into
just `tsa_nr` (~6GB) without also committing to `nr`'s ~730GB, for
example. Each is fetched/built automatically the first time it's needed,
via NCBI's own `update_blastdb.pl` (`ProteinDatabase/get_ncbi_blastdb.sh`)
- pre-formatted volumes, not a separate FASTA + `makeblastdb` step like
the uniprot databases above - and reused across runs after that, into
`./PhylogenyPipeline/ProteinDatabase/<name>/<name>` (e.g. `nr/nr`,
`refseq_protein/refseq_protein`). Without the corresponding flag, or if a
database that was opted in couldn't be fetched/built, it stays remote
exactly as before - these flags only ever narrow what's searched
remotely, never widen it.

The three flags combine into one `localDatabases` variable (a
colon-separated list of `Databases.sh`'s `RemoteDataBases` names, e.g.
`nr:refseq_protein` - colon-, not comma-separated, since this reaches the
job scripts via Slurm's `--export=Var1=Val1,Var2=Val2`, which already
uses comma to separate different variables, the same reason `$holdJobs`
is colon-joined too) at `Scheduler-Call.sh`, which is what actually
reaches the two job scripts (set it directly there, e.g.
`localDatabases=nr`, if calling them without going through
`Scheduler-Call.sh`). It needs to reach both step 0 (the search) and step
3 (the actual sequence extraction) - a gene's hits from one of these
databases are otherwise still fetched remotely via `efetch` in step 3
regardless of how the search that found them ran, so it's threaded
through `Scheduler-Call.sh`'s step 0 *and* step 3 cases (the latter
reached via `Scheduler-01-PrepareSequences.sh`'s step 1→2→3→4 chain, not
directly from step 0). Step 3 extracts a locally-opted-in database's hits
with `blastdbcmd` instead of `efetch`, falling back to `efetch` for any
individual accession `blastdbcmd` can't find locally (e.g. one added to
NCBI's real database after this local copy was last updated).

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

`00_GetGenesFromAllDataBases.sh`, `01_CombineHitsForEachDatabase.sh`, and
`03_ExtractSequences.sh` all call `ProteinDatabase/get_uniprot_databases.sh`,
which downloads and `makeblastdb`-builds the local Uniprot sprot/trembl
BLAST databases if they don't already exist yet (see Databases below).
`makeblastdb` ignores whatever CPU count it's actually assigned and just
tries to use everything on the node it lands on, so if that build is ever
triggered, the job needs the whole node to itself to avoid starving
whatever else is sharing it.

Rather than permanently sizing those three scripts' `Resources.cfg` lines
to the whole node just in case, `Scheduler-Call.sh` checks
`ProteinDatabase/NeedsBuilding.sh` before submitting steps 0, 1, and 3 (it
exits 0 if either database is still missing its `.pdb` index). If a build
is needed, it passes `--resources`/`-R AskForWholeNode` to
`Scheduler-Sub.sh`, which looks up the named `AskForWholeNode` entry in
`Resources.cfg` instead of the script's own line for that one submission.
Otherwise the script's own line applies as normal. `AskForWholeNode` still
just holds the old cluster's biggest node size (24 CPUs / 187 GB / 72h);
resize that one entry for a new cluster's node rather than the old
per-script lines.

Step 0's own line (used whenever the databases already exist, the common
case) was lowered from that same whole-node size to 8 CPUs / 32 GB / 72h.
`nproc`-based CPU limits are honestly respected on this cluster, so 8 CPUs
genuinely constrains the local `blastp` searches `00_GetGenesFromAllDataBases.sh`
runs — but the actual memory/walltime those searches need isn't known
precisely, so treat this as a starting estimate to retune from observed
job behavior, not an authoritative figure.

`Resources.cfg`'s 5th column is a comma-separated list of Slurm
partitions the job may run in (`--partition=a,b,c`); Slurm places it
into whichever listed partition can start it soonest, skipping any
whose own time limit is shorter than the job's requested walltime.
Leaving it blank submits into the cluster's own default partition
instead. This matters because a job's `--time` exceeding every listed
partition's own limit gets rejected at submission outright, not just
queued longer - and a cluster's default partition (the one `sinfo`
marks with a `*`) is not guaranteed to be a generous one; it can be the
most restrictive partition on the whole cluster. PBS Pro has no
equivalent of a multi-partition candidate list (`-q` only takes one
queue name), so a comma-separated value here is simply not passed to
`qsub` at all, falling back to PBS's own default/routing queue - PBS
routing queues (if the cluster has them configured) already do real
automatic queue selection from the resource request server-side, which
Slurm has no equivalent of without cluster-admin-level configuration
(a `job_submit` plugin); the multi-partition list is the closest
approximation achievable from this repo alone.

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

Every job script also sources `Enter-NixDevShell.sh` first, before
`Load-Module.sh`. Job scripts run as freshly submitted `qsub`/`sbatch`
jobs, not inside whatever interactive shell you happened to submit them
from, so they can't just inherit a `nix develop` shell you entered by
hand beforehand - `Enter-NixDevShell.sh` re-execs the job script inside
`nix develop` itself if Nix (or nix-portable) is available and it isn't
already running inside one, so the flake's tools end up on PATH either
way. If a cluster has no Nix install at all, it does nothing and the
script falls back to `module load`/whatever's already on PATH, same as
before this existed - Nix is only ever a fallback, never a requirement,
for users who install every prerequisite by hand or get everything from
`module load`.

Because `Enter-NixDevShell.sh` always runs *before* `Load-Module.sh`,
and environment-modules/Lmod prepend a loaded module's `bin/` directory
to the front of PATH rather than appending it, a real module configured
in Modules.cfg still shadows the Nix version of the same tool (e.g.
`blastp`) whenever both are present - `module load` simply runs later
and wins. Blanking the Modules.cfg key is the only way to guarantee the
Nix version is used instead.

## Remote NCBI access

Steps 0 and 3 (the remote databases in `00_GetGenesFromAllDataBases.sh`,
`efetch` in `03_ExtractSequences.sh`) need a genuinely working round
trip to NCBI, not just "a machine with internet access." Confirmed on
this cluster (Uni Jena, 2026-07-21):

	- Compute nodes have no direct internet access at all - a direct,
	  non-proxied `curl` gets an immediate connection-refused on IPv4
	  and network-unreachable on IPv6. Everything has to go through the
	  cluster's HTTP(S) proxy (`internet4nzm.rz.uni-jena.de:3128` here).
	- Plain HTTPS through that proxy works fine - `curl`/`wget` need no
	  special config beyond the `http_proxy`/`https_proxy` env vars the
	  cluster already sets.
	- `blastp`/`entrez-direct`'s NCBI C++ toolkit does *not* honor those
	  generic `http_proxy`/`https_proxy` env vars, nor the
	  `NCBI_CONFIG__CONN__*` env var override convention (tried, no
	  effect). It only reads an actual `~/.ncbirc` file:
	  	[CONN]
	  	FIREWALL = TRUE
	  	HTTP_PROXY_HOST = internet4nzm.rz.uni-jena.de
	  	HTTP_PROXY_PORT = 3128
	  Without `FIREWALL = TRUE`, the proxy host/port lines are silently
	  ignored.
	- Even with that file in place, `blastp -remote` (2.17.0, the current
	  `blast` package) still doesn't work anywhere on this cluster -
	  tried on both a compute node and the login node, identical result
	  both times. `strace` shows the proxy `CONNECT` and a full TLS 1.3
	  handshake to `www.ncbi.nlm.nih.gov` both succeeding, but the
	  actual NCBI Blast4 RPC request never gets sent/answered - the
	  connection just goes quiet for ~5s and then the peer closes it.
	  Root cause: BLAST+ 2.10.0 introduced a network-service
	  "dispatcher" (`Service/dispd.cgi`) for `-remote` that does not
	  work behind an HTTP CONNECT-tunneled proxy - see
	  [wurmlab/sequenceserver#458](https://github.com/wurmlab/sequenceserver/issues/458),
	  which reports the same failure and found no working fix for any
	  version >= 2.10.0. Since the transport underneath is proven
	  working here, this isn't a config problem on our end.
	- Fix: `flake.nix`'s devShell also provides `blastp_2_9_0`, a pinned
	  prebuilt BLAST+ 2.9.0 (predates the dispatcher), confirmed working
	  `-remote` through this cluster's proxy on 2026-07-21 with the
	  same `~/.ncbirc` above. `00a_GetGenes.sh` (step 0's per-database
	  worker) uses it automatically for remote databases if it's on
	  PATH, falling back to plain `blastp` otherwise. It's used for
	  nothing else - local searches and `makeblastdb` are unaffected
	  (no network involved) and keep using the current `blast` package.
	- `efetch`/`entrez-direct` (step 3) hits the same dispatcher
	  mechanism and has *not* been confirmed fixable the same way - no
	  working version/config combination found yet. Until it is, run
	  step 3's `efetch` calls from a machine with its own direct,
	  unshared internet connection instead (e.g. a laptop).

**Required one-time setup on any cluster that only has proxied internet
access:** create `~/.ncbirc` as shown above (with that cluster's own
proxy host/port) before running steps 0 or 3 - it isn't created
automatically by anything in this repo, since it lives outside the repo
in `$HOME` and the proxy details are cluster-specific, the same reason
`Scheduler/Account.sh` is a manual one-time edit rather than something
the flake sets up.

If this comes up on a different cluster, don't assume "the login node
has internet" settles it - test an actual `blastp -remote` round trip
(as above) before trusting steps 0/3 to run anywhere on that cluster at
all.

## Moving to a new cluster

Checklist for getting the pipeline running on a cluster it hasn't run on before:

	- Adjust ./Scheduler/Resources.cfg if the new cluster's node sizes or
	  usual walltime limits differ from what is currently in there,
	  including the `AskForWholeNode` entry and step 0's own line (see
	  "Scheduler Setup" above). Also check each partition's own time
	  limit (`sinfo`) against the walltime column: a job's `--time`
	  exceeding every one of its listed partitions' limits gets rejected
	  at submission, not just queued longer, and the cluster's default
	  partition (the one `sinfo` marks with a `*`) may have a much
	  shorter limit than the partitions actually meant for real work -
	  update the comma-separated partition column accordingly (blank
	  stays on the default; see "Scheduler Setup" above for how Slurm
	  picks among several listed partitions automatically).
	- Update ./Scheduler/Modules.cfg to module names/versions that exist
	  on the new cluster, or blank an entry out to fall back to Nix
	  instead (see "Scheduler Setup" above).
	- Nothing to do for the `vcmsa_env` conda environment used by
	  09_Scheduler-AlignWithVCMSA.sh - get_vcmsa_env.sh creates it
	  itself (once per cluster) the first time a VCMSA job runs, per
	  [vcMSA's own install instructions](https://github.com/clairemcwhite/vcmsa).
	  It uses `-n`, not vcMSA's own suggested `--prefix vcmsa_env` -
	  09_Scheduler-AlignWithVCMSA.sh activates the env by bare name
	  (`conda activate vcmsa_env`) from whatever directory the job runs
	  in, so it needs to resolve the same way regardless of the job's
	  working directory, which only a named env (registered in conda's
	  envs_dirs) guarantees; a `--prefix` env only activates by that
	  name when the current directory happens to be its parent.
	  MAGUS just needs a `magus` command on PATH
	  (`pip install --user magus-msa`, or the flake's `magus` package).
	- Set the account string in ./Scheduler/Account.sh, if the cluster
	  requires one.
	- Install the "user path" and "base folder" tools listed under
	  Prerequisites; they are not covered by module load. `nix develop`
	  (see "Installing prerequisites with Nix" above) covers a subset of
	  these.
	- Confirm steps 0 and 3 can actually complete a real round trip to
	  NCBI somewhere on the new cluster (see "Remote NCBI access"
	  above) - "has internet access" is not sufficient on its own to
	  assume this works. Plan to run those steps entirely off-cluster
	  if it doesn't.
	- Provision storage for the ~210 GB Uniprot BLAST databases and the
	  NCBI taxon database (see Databases above).
