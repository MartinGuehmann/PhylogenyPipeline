{
  description = "User-space dev shell for the PhylogenyPipeline's non-cluster-provided tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      perSystem = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          py = pkgs.python3Packages;

          # --- Tools built from source, not in nixpkgs ------------------
          #
          # None of these have been build-tested (no Linux/Nix available
          # in the environment they were written in). `hash` fields are
          # left as `pkgs.lib.fakeHash`: run `nix build .#<name>`, Nix
          # will refuse and print the real hash of what it downloaded,
          # paste that in place of fakeHash, and re-run. That's the
          # normal Nix workflow for a first-time packaging, not a sign
          # something is broken. installPhase paths are best-effort
          # guesses from each project's README/Makefile and may need a
          # tweak once you see the actual build output.

          raxml-ng = pkgs.stdenv.mkDerivation rec {
            pname = "raxml-ng";
            version = "2.0.2"; # github.com/amkozlov/raxml-ng, tag 2.0.2
            src = pkgs.fetchFromGitHub {
              owner = "amkozlov";
              repo = "raxml-ng";
              rev = version;
              fetchSubmodules = true; # pulls bundled coraxlib/terraphast
              hash = "sha256-Yd5IaeE8wT3cgGev39QmZ9qWqp0tvH+I91Ew5k5jTYo=";
            };
            nativeBuildInputs = [ pkgs.cmake ];
            buildInputs = [ pkgs.gmp pkgs.htslib pkgs.zlib pkgs.bzip2 pkgs.xz ];
            installPhase = ''
              mkdir -p $out/bin
              for candidate in bin/raxml-ng ../bin/raxml-ng raxml-ng; do
                if [ -f "$candidate" ]; then
                  cp "$candidate" $out/bin/
                  break
                fi
              done
            '';
          };

          roguenarok = pkgs.stdenv.mkDerivation rec {
            pname = "roguenarok";
            version = "1.0.1"; # github.com/aberer/RogueNaRok, tag v1.0.1
            src = pkgs.fetchFromGitHub {
              owner = "aberer";
              repo = "RogueNaRok";
              rev = "v${version}";
              hash = "sha256-ubPF/wFF0k7XcBvfgFxQKPf6GHkXvQRrdGyvyrcv6M0=";
            };
            # RogueNaRok's C code (2013) tentatively declares globals like
            # processID/bits_in_16bits in headers without extern, relying
            # on GCC's old -fcommon default to merge those tentative
            # definitions across translation units. GCC 10 switched the
            # default to -fno-common, turning that into a hard "multiple
            # definition" link error - confirmed on 2026-07-17. Restoring
            # -fcommon is the standard fix for this exact, common
            # legacy-C-on-modern-GCC regression.
            #
            # Separately, rnr-lsi.c calls printHelpFile(FALSE) against a
            # `void printHelpFile()` declaration - old-style K&R/ANSI-C
            # "unspecified arguments", not accepting zero arguments the
            # way `(void)` would. GCC 14 switched its default C standard
            # from gnu17 to gnu23, and C23 gives empty parens the `(void)`
            # meaning instead, turning this into a hard "too many
            # arguments" error - confirmed on 2026-07-17, same class of
            # regression as -fcommon above, just a different GCC-version
            # default change. -std=gnu17 restores the old, looser
            # semantics this code relies on.
            env.NIX_CFLAGS_COMPILE = "-fcommon -std=gnu17";
            buildPhase = ''
              make mode=parallel
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp RogueNaRok-parallel rnr-prune rnr-lsi rnr-tii rnr-mast $out/bin/
            '';
          };

          famsa = pkgs.stdenv.mkDerivation rec {
            pname = "famsa";
            version = "2.5.2"; # github.com/refresh-bio/FAMSA, tag v2.5.2
            src = pkgs.fetchFromGitHub {
              owner = "refresh-bio";
              repo = "FAMSA";
              rev = "v${version}";
              fetchSubmodules = true; # pulls bundled mimalloc etc.
              hash = "sha256-X3jK46XCLfjIQd+4k/1YbNLNq4Fd6E+0pr9JYPb4o3s=";
            };
            # FAMSA's Makefile shells out to both at build time (for its
            # bundled submodule dependencies like zlib-ng/isa-l) -
            # confirmed missing on 2026-07-17 ("make: git: No such file
            # or directory" and cmake's own "required software ... not
            # installed" check). Neither was declared before.
            nativeBuildInputs = [ pkgs.gnumake pkgs.git pkgs.cmake ];
            # cmake ships a setup hook that auto-takes-over configurePhase
            # for any derivation that has it as a build input, assuming a
            # top-level CMake project - but FAMSA is a plain Makefile
            # project that only shells out to cmake internally for a
            # couple of bundled submodules, so that hook fails outright
            # ("does not appear to contain CMakeLists.txt", confirmed on
            # 2026-07-17). Disabling it leaves cmake on PATH without
            # letting it hijack the phase.
            dontUseCmakeConfigure = true;
            # refresh.mk's cmake invocation for the bundled zlib-ng
            # submodule doesn't disable zlib-ng's own test suite, which
            # defaults to on (ZLIB_ENABLE_TESTS/WITH_GTEST, both ON by
            # default in libs/zlib-ng/CMakeLists.txt) and fetches
            # googletest from GitHub mid-build via CMake's
            # FetchContent_Populate - confirmed failing on 2026-07-17
            # ("Failed to clone repository"), the same class of
            # sandboxed-network-access issue as entrez-direct's Go
            # modules, just via CMake instead. We only need zlib-ng's
            # compiled library, not its tests, so disabling both avoids
            # the fetch entirely.
            postPatch = ''
              sed -i 's/-DWITH_GZFILEOP=ON/-DWITH_GZFILEOP=ON -DZLIB_ENABLE_TESTS=OFF -DWITH_GTEST=OFF/' refresh.mk
            '';
            # avx2 is FAMSA's own documented default: broad x86-64 coverage
            # without needing to know every cluster node's CPU generation.
            # Override to PLATFORM=native for a single known machine, or
            # PLATFORM=none for maximum compatibility.
            buildPhase = ''
              make PLATFORM=avx2
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp bin/famsa $out/bin/
            '';
          };

          treeswift = py.buildPythonPackage rec {
            pname = "treeswift";
            version = "1.1.45"; # not in nixpkgs; pulled straight from PyPI
            format = "setuptools";
            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-O9HbOkXb1EMFGk+eyvyZqOOLI7R6KDM4eMHu9uj2fn4=";
            };
            doCheck = false;
          };

          treeshrink = py.buildPythonApplication rec {
            pname = "TreeShrink";
            version = "1.4.0"; # github.com/uym2/TreeShrink, tag v1.4.0
            src = pkgs.fetchFromGitHub {
              owner = "uym2";
              repo = "TreeShrink";
              # The tag name "v1.4.0" is ambiguous in this repo - GitHub's
              # own archive endpoint refused it outright on 2026-07-17
              # ("the given path has multiple possibilities"), a tag and
              # some other ref (likely a branch) apparently share that
              # exact name. Pinned to the tag's actual commit instead,
              # which sidesteps the ambiguity entirely.
              rev = "a31070dbdf4c95165dc9943749cc199eb44ab6e2";
              hash = "sha256-Pocwz0qwil18WaOt+k3hNmAL+cXA9J45qZtRKLSW+vY=";
            };
            format = "setuptools";
            propagatedBuildInputs = [ treeswift py.numpy py.scipy ];
            doCheck = false;
            # Provides run_treeshrink.py on PATH.
          };

          magus = py.buildPythonApplication rec {
            pname = "magus-msa";
            version = "0.2.0"; # published to PyPI from vlasmirnov/MAGUS
            pyproject = true;
            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-raxaEQbojWBbYlxyZ6e0mjH2Nso4aDbFoUeIeVi6IoY=";
            };
            build-system = [ py.setuptools ];
            propagatedBuildInputs = [ py.dendropy ];
            doCheck = false;
            # Provides the `magus` command on PATH (magus.main:main).
            # Bundles precompiled Linux MAFFT/MCL/FastTree/Clustal-Omega,
            # so this replaces the separate MAGUS dendropy pip-install
            # note further down in the README.
          };
          entrez-direct = pkgs.buildGoModule rec {
            pname = "entrez-direct";
            # EDirect has no public source repo - NCBI ships it only via
            # FTP. This mirrors bioconda's recipes/entrez-direct/build.sh,
            # the most reliable ground truth available, including its
            # pinned version/hash (bioconda's CI actually builds this).
            version = "25.3.20260410";
            src = pkgs.fetchurl {
              url = "https://ftp.ncbi.nlm.nih.gov/entrez/entrezdirect/versions/${version}/edirect.tar.gz";
              sha256 = "189382f1fe4a1b43872855cd5b442ed25111192dd4b00330268c1cad6d7216bf";
            };
            # Confirmed by inspecting the real tarball (2026-07-17): cmd/
            # (Go module "edirect") and eutils/ (Go module "eutils", the
            # shared library cmd's *.go files import) are two separate
            # local Go modules, linked via a `replace eutils => ../eutils`
            # directive in cmd/go.mod. modRoot points buildGoModule at
            # cmd/; the relative replace path still resolves since both
            # directories travel together inside $src. This replaces the
            # plain `pkgs.go` + hand-rolled build.sh invocation this
            # derivation used before, which failed: build.sh's `go build`
            # needs network access to fetch Go module dependencies (none
            # are vendored in the tarball), which Nix's sandboxed build
            # phase blocks - buildGoModule instead fetches and verifies
            # them in their own dedicated, network-permitted fixed-output
            # step (vendorHash below).
            modRoot = "cmd";
            # cmd/edict.go imports github.com/gin-gonic/gin, which isn't
            # declared in cmd/go.mod or cmd/go.sum - confirmed on
            # 2026-07-17, Go's module resolution fails on it before
            # buildGoModule can even compute vendorHash, even though
            # build.sh (and buildPhase below) never builds edict.go at
            # all, only xtract/rchive/transmute. Removing it sidesteps
            # that resolution failure entirely. This runs before
            # buildGoModule's own separate vendor-fetching derivation
            # too, since that reuses this same postPatch.
            postPatch = ''
              rm cmd/edict.go
            '';
            vendorHash = "sha256-9Ys43yzO8AXSCIQJ2XnitkoIivDfQ8b6z3H8LUdvaT0=";
            buildInputs = [ pkgs.wget ];
            # buildGoModule's default checkPhase assumes a normal package
            # layout it can discover and test - confirmed on 2026-07-17
            # ("getGoDirs: command not found") that doesn't apply cleanly
            # here, given modRoot plus the nonstandard one-file-at-a-time
            # buildPhase below. Not needed anyway: this only builds three
            # binaries, it doesn't run edirect's own Go test suite.
            doCheck = false;
            # Force using nixpkgs' own `go` rather than whatever toolchain
            # version cmd/go.mod's `go 1.26.1` directive requests - newer
            # Go versions auto-download a matching toolchain over the
            # network by default (GOTOOLCHAIN=auto) if the one available
            # doesn't satisfy that directive, which would hit the same
            # sandboxed-network wall vendorHash exists to avoid.
            env.GOTOOLCHAIN = "local";
            # xtract/rchive/transmute are three separate `main`s that
            # coexist as individual .go files in one directory (cmd/)
            # rather than three package directories - confirmed in
            # cmd/build.sh, which builds them the same way: one named
            # file at a time, not buildGoModule's normal ./... package
            # build. modRoot puts the working directory at cmd/ for both
            # phases below, so ../data and ../help reach the sibling
            # directories from the top of the extracted source tree.
            buildPhase = ''
              runHook preBuild
              for exc in xtract rchive transmute; do
                go build -o "$exc" "$exc.go"
              done
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin/data" "$out/bin/help"
              install -m 755 xtract rchive transmute "$out/bin"
              install -m 644 ../data/* "$out/bin/data"
              install -m 644 ../help/* "$out/bin/help"
              runHook postInstall
            '';
            # wget is a buildInput only so it's pulled into the devShell
            # below; the scripts shell out to it at runtime, not build time.
          };

          # --- T-Coffee and PASTA -----------------------------------------
          #
          # Both were initially left out as too risky to blind-package (see
          # git history), then attempted anyway. They turned out to have
          # real bioconda recipes (bioconda/bioconda-recipes on GitHub),
          # which is the ground truth these derivations are modeled on
          # instead of each project's own install docs - bioconda actually
          # builds and tests these on their CI, so their pinned
          # versions/hashes are used directly (no fakeHash) where bioconda
          # provided one.

          t-coffee = pkgs.stdenv.mkDerivation rec {
            pname = "t-coffee";
            version = "13.46.2.7c9e712d"; # matches bioconda's pin
            src = pkgs.fetchurl {
              url = "https://s3.eu-central-1.amazonaws.com/tcoffee-packages/Archives/T-COFFEE_distribution_Version_${version}.tar.gz";
              sha256 = "84f9b4076767d39dec6619c5eb91c9538a7c58c68a3731a92ebbf2e1f914296f";
            };
            nativeBuildInputs = [ pkgs.gfortran pkgs.perl ];
            # bioconda's build.sh runs the source through T-Coffee's own
            # `install` perl script, which also tries to download plugin
            # binaries over the network - unusable in a sandboxed Nix
            # build. Instead this only replicates bioconda's *compile*
            # step (`cd t_coffee_source && make all`), which is enough for
            # a standalone t_coffee binary (the one this pipeline actually
            # needs, not T-Coffee's whole bundled meta-aligner ensemble).
            # Skipped: bioconda's own `coredump.patch` (a small upstream
            # fix to util.c's set_nproc signature) - not applied here
            # since only its two changed lines, not full context, were
            # available. If `make all` fails around `set_nproc`, that
            # patch is the fix.
            buildPhase = ''
              runHook preBuild
              sed -i 's|CC=g++|CC=$(CXX)|' t_coffee_source/makefile
              sed -i 's|$(FCC)|$(FC)|' t_coffee_source/makefile
              (cd t_coffee_source && make all -j"$NIX_BUILD_CORES")
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp t_coffee_source/t_coffee $out/bin/
              [ -f t_coffee_source/TMalign ] && cp t_coffee_source/TMalign $out/bin/
              runHook postInstall
            '';
          };

          clustalw = pkgs.stdenv.mkDerivation {
            pname = "clustalw";
            version = "2.1"; # matches bioconda's pin
            # clustal.org's own download started returning HTTP 403 from
            # the cluster's network (same symptom muscle3 below hit
            # against drive5.com - academic sites blocking the cluster's
            # proxy egress IP outright, confirmed on 2026-07-17 with a
            # retry that still 403'd), so this pulls bioconda's
            # precompiled binary from anaconda.org instead of building
            # from source. Dynamically linked against libstdc++/libm/
            # libgcc_s/libc (confirmed via `file`/`readelf -d`), which
            # resolve fine against a normal Linux distro's system
            # libraries - not patched for NixOS-style store-only linking,
            # matching how muscle3 below is handled too.
            src = pkgs.fetchurl {
              url = "https://conda.anaconda.org/bioconda/linux-64/clustalw-2.1-0.tar.bz2";
              hash = "sha256-4N9s1jPhRrosf03MiJsNGggLHP3fb4GjjXf145f9uD4=";
            };
            # Conda packages aren't wrapped in a single top-level
            # directory (bin/, info/, etc. sit directly at the archive
            # root), which the default unpackPhase can't auto-cd into -
            # confirmed on 2026-07-17 ("unpacker produced multiple
            # directories"). sourceRoot = "." keeps it at the top instead
            # of guessing.
            sourceRoot = ".";
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/bin
              install -m755 bin/clustalw2 $out/bin/
              ln -sf $out/bin/clustalw2 $out/bin/clustalw
            '';
          };

          fasttree = pkgs.stdenv.mkDerivation rec {
            pname = "fasttree";
            version = "2.2.0"; # matches bioconda's pin
            src = pkgs.fetchFromGitHub {
              owner = "morgannprice";
              repo = "fasttree";
              rev = "v${version}";
              sha256 = "sha256-vIi60XveGxYeMZpoGklTidqnl+ROBbxLyEsygB8Digg=";
            };
            dontConfigure = true;
            # bioconda passes CPU-specific -march flags here; dropped for
            # portability across unknown cluster node generations, same
            # reasoning as FAMSA's PLATFORM=avx2 choice above.
            buildPhase = ''
              runHook preBuild
              $CC -O3 -funsafe-math-optimizations -o FastTree FastTree.c -lm
              $CC -DOPENMP -O3 -fopenmp -funsafe-math-optimizations -o FastTreeMP FastTree.c -lm
              runHook postBuild
            '';
            installPhase = ''
              mkdir -p $out/bin
              install -m755 FastTree $out/bin/FastTree
              install -m755 FastTree $out/bin/fasttree
              install -m755 FastTreeMP $out/bin/FastTreeMP
            '';
          };

          prank = pkgs.stdenv.mkDerivation rec {
            pname = "prank";
            version = "251117"; # matches bioconda's pin
            src = pkgs.fetchFromGitHub {
              owner = "ariloytynoja";
              repo = "prank-msa";
              rev = "v.${version}"; # tag is literally "v.251117"
              sha256 = "sha256-ayBqHmjeQ5QNr2rv19cJYAR+HMbFdvtjzyJiWl3pdPI=";
            };
            buildPhase = ''
              runHook preBuild
              mkdir -p $out/bin
              make -C src CC="$CC" CXX="$CXX" LINK="$CXX" TARGET="$out/bin/prank" -j"$NIX_BUILD_CORES"
              runHook postBuild
            '';
            dontInstall = true;
          };

          # Classic MUSCLE v3. The pipeline's own 09_AlignWithMUSCLE.sh
          # calls a plain `muscle` command expecting v3's `-in`/`-out`
          # flags, which nixpkgs' own `muscle` (v5.1.0, `-align`/`-output`)
          # does not accept - so *this* is what devShell exposes as
          # `muscle`, and nixpkgs' v5 is exposed as `muscle5` instead (see
          # the muscle5 derivation below), matching what
          # 09_AlignWithMUSCLE5.sh/09_AlignWithSUPER5.sh actually call.
          # No source build: only ever published as a static binary for
          # this series, and no aarch64 build exists (confirmed against
          # bioconda's own release listing for 3.8.31 specifically, even
          # though bioconda's channel has aarch64 builds for newer MUSCLE
          # v5), so this is x86_64-linux only. Pulled from bioconda's
          # anaconda.org mirror rather than drive5.com directly: the
          # latter started returning HTTP 403 from the cluster's network
          # (confirmed on 2026-07-17 with a retry that still 403'd, same
          # symptom clustalw above hit against a different site) -
          # academic sites apparently blocking the cluster's proxy
          # egress IP outright. Statically linked (confirmed via `file`),
          # so no dynamic-linking concerns either way.
          muscle3 = assert pkgs.lib.assertMsg pkgs.stdenv.hostPlatform.isx86_64
            "muscle3 is only published as an x86_64 Linux static binary";
          pkgs.stdenv.mkDerivation {
            pname = "muscle3";
            version = "3.8.31";
            src = pkgs.fetchurl {
              url = "https://conda.anaconda.org/bioconda/linux-64/muscle-3.8.31-0.tar.bz2";
              hash = "sha256-xGsjT8X/3fythulpCK5Ya6cXOQqQs6SKZehi2OKJy6c=";
            };
            # Same reason as clustalw above: conda packages have no single
            # top-level wrapping directory, so the default unpackPhase
            # can't auto-cd into one.
            sourceRoot = ".";
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/bin
              install -m755 bin/muscle $out/bin/muscle
            '';
          };

          # nixpkgs' own muscle package (v5.1.0) installs its binary as
          # plain `muscle`, but 09_AlignWithMUSCLE5.sh/SUPER5.sh call it
          # as `muscle5` - so re-expose it under that name instead of
          # colliding with classic MUSCLE v3 above.
          muscle5 = pkgs.runCommand "muscle5" { } ''
            mkdir -p $out/bin
            ln -s ${pkgs.muscle}/bin/muscle $out/bin/muscle5
          '';

          # Decided to upgrade rather than pin IQ-TREE2 from source:
          # nixpkgs' `iqtree` builds IQ-TREE 3 (binary `iqtree3`), which
          # per IQ-TREE3's own release notes is an additive major release
          # (mixture models, concordance factors, DecentTree, piqtree) -
          # no evidence found of any flag used in 10_MakeTreeWithIQ-Tree.sh
          # (-s, -B, --abayes, --alrt, -m TEST, -nt/-ntmax, --boot-trees)
          # being renamed or removed. Not build-tested against a real
          # cluster run yet. Aliased to `iqtree2` (the script's own
          # `module load`-era command name) rather than changing the
          # script, matching how every other tool swap in this flake
          # works: same command the script already calls, different
          # implementation behind it. `iqtree2 --version` will report 3.x
          # - that's expected, not a packaging bug.
          iqtree2 = pkgs.runCommand "iqtree2" { } ''
            mkdir -p $out/bin
            ln -s ${pkgs.iqtree}/bin/iqtree3 $out/bin/iqtree2
          '';

          # A single small file, not the whole sate-tools-linux repo.
          opalJar = pkgs.fetchurl {
            url = "https://github.com/smirarab/sate-tools-linux/raw/master/opal.jar";
            hash = "sha256-VCOQIx2Yh59BX+H5MFJ0QHUDAQPmNOdXrtnH8+E9WNM=";
          };

          # Merged directory of PASTA's external tools, handed to it via
          # PASTA_TOOLS_RUNDIR (see the `pasta` derivation below). This is
          # the single riskiest guess in this whole flake: PASTA's own
          # code (pasta/__init__.py, pasta_tools_deploy_dir()) defaults to
          # a flat "../bin"-style directory of plainly-named executables
          # when PASTA_TOOLS_RUNDIR is unset, which is what's modeled
          # here - but bioconda's own recipe achieves the equivalent by
          # source-patching pasta/__init__.py to point at $CONDA_PREFIX/bin
          # instead of relying on this variable, which suggests the
          # variable alone may not be sufficient for every tool lookup in
          # the codebase. If tools "aren't found" at runtime despite being
          # in this join, patching pasta/__init__.py the way bioconda does
          # (its fix_tooldir.patch) is the documented working fallback.
          pastaToolsDir = pkgs.symlinkJoin {
            name = "pasta-tools-dir";
            paths = [
              pkgs.mafft
              muscle3
              clustalw
              pkgs.raxml
              pkgs.hmmer
              fasttree
              prank
            ];
            postBuild = ''
              ln -sf ${pkgs.raxml}/bin/raxmlHPC $out/bin/raxml
              cp ${opalJar} $out/bin/opal.jar
            '';
          };

          pasta = py.buildPythonApplication rec {
            pname = "pasta";
            version = "1.9.3"; # matches bioconda's pin
            src = pkgs.fetchFromGitHub {
              owner = "smirarab";
              repo = "pasta";
              rev = "v${version}";
              sha256 = "sha256-kU6kPNHB/uIvp2WQhuP+asVYNFArvSR0lW3ixzUHP9Y=";
            };
            format = "setuptools";
            # PASTA imports the long-removed stdlib `imp` module for an
            # old frozen-executable check that's dead code either way;
            # importing it at all crashes outright on Python 3.12+, where
            # `imp` was deleted. Same fix bioconda applies.
            postPatch = ''
              sed -i 's/^\(.*import imp\)/#\1/' pasta/__init__.py
              sed -i 's/^\(.*imp\.is_frozen.*\)/#\1/' pasta/__init__.py
              # setup.py also expects the legacy sate-tools-linux bundle's
              # nested mafftdir/{bin,libexec} layout on top of the flat
              # tools directory - confirmed failing on 2026-07-17
              # ("FileNotFoundError: .../pasta-tools-dir/bin/mafftdir/bin").
              # pastaToolsDir below is flat (nixpkgs' own mafft package
              # already puts everything MAFFT needs directly in one bin/
              # directory, unlike upstream's separate bin/libexec split,
              # confirmed by every mafft-* binary linking successfully
              # from the flat layer already), so both nested entries are
              # redundant and genuinely don't exist here.
              sed -i "s|, 'mafftdir/bin','mafftdir/libexec'||" setup.py
            '';
            propagatedBuildInputs = [ py.dendropy py.pymongo ];
            doCheck = false;
            # setup.py's own build step (separate from the runtime wrapper
            # below) also looks for a "SATe tools bundle directory" via
            # $PASTA_TOOLS_DEVDIR, defaulting to a hardcoded
            # /build/sate-tools-linux guess when unset - confirmed failing
            # on 2026-07-17 ("Could not find SATe tools bundle
            # directory"), exactly the "variable alone may not be
            # sufficient for every tool lookup" risk flagged above.
            # Pointing it at the same pastaToolsDir satisfies this
            # build-time lookup too, without needing to patch
            # pasta/__init__.py the way bioconda's own recipe does.
            env.PASTA_TOOLS_DEVDIR = "${pastaToolsDir}/bin";
            makeWrapperArgs = [ "--set" "PASTA_TOOLS_RUNDIR" "${pastaToolsDir}/bin" ];
            # Provides run_pasta.py on PATH.
          };

          # A custom AddFaceFloatRight branch, pinned to its tip commit
          # as of 2026-07-14 - deliberately from *before* rebasing onto
          # upstream ete's major version bump, to keep the
          # rebase/API-adjustment work separate and later. Re-pin the rev
          # (and probably restructure this derivation - the new major
          # version likely packages very differently) once that's done.
          #
          # This is a plain buildPythonPackage, not buildPythonApplication:
          # 12_ConvertTreesToFigures.py does `from ete3 import ...` and is
          # run via a bare `python3 12_ConvertTreesToFigures.py`, not an
          # `ete3` command - so what's actually needed on PATH is a
          # `python3` that has ete3 importable, not an isolated wrapper
          # that only exposes ete3's own console script. See
          # `pythonWithEte3` below, which is what goes into the devShell.
          ete3 = py.buildPythonPackage rec {
            pname = "ete3";
            version = "3-addfacefloatright-7b6ef8d";
            src = pkgs.fetchFromGitHub {
              owner = "MartinGuehmann";
              repo = "ete";
              rev = "7b6ef8dc2ee06e1919616b7b961281e2cb75fe21"; # tip of AddFaceFloatRight
              hash = "sha256-pzIdhZbZ4Lz0Nrc3pFupjiMFNExI3EWytWGH6NdaXoY=";
            };
            format = "setuptools";
            # This old setup.py phones home to etetoolkit.org on install
            # (an `urlopen()` call) unless "--donottrackinstall" is in
            # argv, which nothing here passes, and which wouldn't be
            # straightforward to plumb through the build invocation
            # anyway. A network call would fail in Nix's sandboxed build
            # regardless, so disable the whole thing outright by
            # short-circuiting the condition that guards it, rather than
            # relying on argv.
            postPatch = ''
              sed -i 's/if TRACKINSTALL is not None and (wanted & seen) and not (notwanted & seen):/if False:/' setup.py
            '';
            # setup.py's own install_requires is empty (it only *checks*
            # for these and warns if missing); they're genuinely needed
            # at runtime, so propagate them for real here.
            propagatedBuildInputs = [ py.numpy py.pyqt5 py.lxml py.six ];
            doCheck = false;
            # Still needs a real or virtual X server at runtime (e.g.
            # xvfb-run) - packaging it doesn't remove that requirement.
          };

          # A python3 with ete3 (and its deps) merged into its own
          # site-packages, so that a bare `python3 script.py` - not just
          # ete3's own console script - can `import ete3`. This, not the
          # `ete3` package above directly, is what goes into the devShell.
          pythonWithEte3 = pkgs.python3.withPackages (ps: [ ete3 ]);
        in
        {
          packages = {
            inherit raxml-ng roguenarok famsa treeshrink magus entrez-direct
              t-coffee clustalw fasttree prank muscle3 muscle5 iqtree2 pasta
              ete3 pythonWithEte3;
          };
          devShell = pkgs.mkShell {
            # Enter with `nix develop` (or `nix-portable nix develop` if
            # Nix itself isn't installed on the cluster). Everything in
            # here replaces a "user path" install from the README's
            # Prerequisites section. It does NOT replace anything marked
            # "module load" - those come from the cluster's own module
            # system on purpose, e.g. because the sysadmin's blastp build
            # is tied to the cluster's MPI/BLAST database setup.
            packages = (with pkgs; [
              seqkit
              cd-hit
              trimal
              blast # blastp, makeblastdb, etc., in case module load isn't available
              clustal-omega
              mafft # also provides linsi
              openjdk # needed by PASTA's bundled opal.jar merger at runtime
            ]) ++ [
              raxml-ng
              roguenarok
              famsa
              treeshrink
              magus
              entrez-direct
              t-coffee
              clustalw
              fasttree
              prank
              muscle3
              muscle5
              iqtree2
              pasta
              pythonWithEte3
            ];
          };
        });
    in
    {
      packages = forAllSystems (system: perSystem.${system}.packages);
      devShells = forAllSystems (system: { default = perSystem.${system}.devShell; });
    };
}
