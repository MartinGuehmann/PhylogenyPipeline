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
              hash = pkgs.lib.fakeHash;
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
              hash = pkgs.lib.fakeHash;
            };
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
              hash = pkgs.lib.fakeHash;
            };
            nativeBuildInputs = [ pkgs.gnumake ];
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
              hash = pkgs.lib.fakeHash;
            };
            doCheck = false;
          };

          treeshrink = py.buildPythonApplication rec {
            pname = "TreeShrink";
            version = "1.4.0"; # github.com/uym2/TreeShrink, tag v1.4.0
            src = pkgs.fetchFromGitHub {
              owner = "uym2";
              repo = "TreeShrink";
              rev = "v${version}";
              hash = pkgs.lib.fakeHash;
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
              hash = pkgs.lib.fakeHash;
            };
            build-system = [ py.setuptools ];
            propagatedBuildInputs = [ py.dendropy ];
            doCheck = false;
            # Provides the `magus` command on PATH (magus.main:main).
            # Bundles precompiled Linux MAFFT/MCL/FastTree/Clustal-Omega,
            # so this replaces the separate MAGUS dendropy pip-install
            # note further down in the README.
          };
          entrez-direct = pkgs.stdenv.mkDerivation rec {
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
            nativeBuildInputs = [ pkgs.go ];
            buildInputs = [ pkgs.wget ];
            # Biggest unverified risk of this whole flake: cmd/build.sh
            # (bundled in the tarball) builds xtract/rchive/transmute/etc.
            # from Go source. If EDirect's Go modules aren't vendored in
            # the tarball, this `go build` will try to fetch them over the
            # network, which Nix's sandboxed build phase blocks. If that
            # happens, this needs converting to `pkgs.buildGoModule` with
            # a real `vendorHash` instead of plain `go` here.
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR"
              export GOCACHE="$TMPDIR/go-cache"
              export GOPATH="$TMPDIR/go-path"
              mkdir -p bin nobin
              mv xy-* nobin 2>/dev/null || true
              mv $(find * -type d -prune -o -print | sed '/^[A-Z]/d;/[.]pdf$/d;/[.]pem$/d;/[.]py$/d;/conda/d;/build/d') bin
              mkdir -p "$out/bin"
              (cd cmd && sh -ex ./build.sh "$out/bin")
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin/data" "$out/bin/help"
              install -m 644 data/* "$out/bin/data"
              install -m 644 help/* "$out/bin/help"
              install -m 755 bin/* "$out/bin"
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

          clustalw = pkgs.stdenv.mkDerivation rec {
            pname = "clustalw";
            version = "2.1"; # matches bioconda's pin
            src = pkgs.fetchurl {
              url = "http://www.clustal.org/download/current/clustalw-${version}.tar.gz";
              sha256 = "e052059b87abfd8c9e695c280bfba86a65899138c82abccd5b00478a80f49486";
            };
            nativeBuildInputs = [ pkgs.autoreconfHook ];
            postInstall = ''
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
              sha256 = "db5f0d2d1e2b9099193a3a68a5c44f71166a870a7a4269398b9258b1e3478e12";
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
              sha256 = "992eb5980f3c8c331b2860093756b98491f501999d4d09fc4d16ea89d849a105";
            };
            buildPhase = ''
              runHook preBuild
              mkdir -p $out/bin
              make -C src CC="$CC" CXX="$CXX" LINK="$CXX" TARGET="$out/bin/prank" -j"$NIX_BUILD_CORES"
              runHook postBuild
            '';
            dontInstall = true;
          };

          # Classic MUSCLE v3 (PASTA needs its command-line syntax; v5 in
          # the devShell above is not a substitute - see the PASTA
          # requirements below). No source build: drive5.com only ever
          # published static binaries for this series, and no aarch64
          # build exists, so this is x86_64-linux only.
          muscle3 = assert pkgs.lib.assertMsg pkgs.stdenv.hostPlatform.isx86_64
            "muscle3 is only published as an x86_64 Linux static binary";
          pkgs.stdenv.mkDerivation {
            pname = "muscle3";
            version = "3.8.31";
            src = pkgs.fetchurl {
              url = "https://drive5.com/muscle/downloads3.8.31/muscle3.8.31_i86linux64.tar.gz";
              hash = pkgs.lib.fakeHash;
            };
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/bin
              install -m755 muscle3.8.31_i86linux64 $out/bin/muscle3
            '';
          };

          # A single small file, not the whole sate-tools-linux repo.
          opalJar = pkgs.fetchurl {
            url = "https://github.com/smirarab/sate-tools-linux/raw/master/opal.jar";
            hash = pkgs.lib.fakeHash;
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
              ln -sf ${muscle3}/bin/muscle3 $out/bin/muscle
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
              sha256 = "4bbd77b148c7a0954e1103d0b6e834e3a507c3ada9ba556e2731109beb3d92fe";
            };
            format = "setuptools";
            # PASTA imports the long-removed stdlib `imp` module for an
            # old frozen-executable check that's dead code either way;
            # importing it at all crashes outright on Python 3.12+, where
            # `imp` was deleted. Same fix bioconda applies.
            postPatch = ''
              sed -i 's/^\(.*import imp\)/#\1/' pasta/__init__.py
              sed -i 's/^\(.*imp\.is_frozen.*\)/#\1/' pasta/__init__.py
            '';
            propagatedBuildInputs = [ py.dendropy py.pymongo ];
            doCheck = false;
            makeWrapperArgs = [ "--set" "PASTA_TOOLS_RUNDIR" "${pastaToolsDir}/bin" ];
            # Provides run_pasta.py on PATH.
          };

          # A custom AddFaceFloatRight branch, pinned to its tip commit
          # as of 2026-07-14 - deliberately from *before* rebasing onto
          # upstream ete's major version bump, to keep the
          # rebase/API-adjustment work separate and later. Re-pin the rev
          # (and probably restructure this derivation - the new major
          # version likely packages very differently) once that's done.
          ete3 = py.buildPythonApplication rec {
            pname = "ete3";
            version = "3-addfacefloatright-7b6ef8d";
            src = pkgs.fetchFromGitHub {
              owner = "MartinGuehmann";
              repo = "ete";
              rev = "7b6ef8dc2ee06e1919616b7b961281e2cb75fe21"; # tip of AddFaceFloatRight
              hash = pkgs.lib.fakeHash;
            };
            format = "setuptools";
            # This old setup.py phones home to etetoolkit.org on install
            # (an `urlopen()` call) unless "--donottrackinstall" is in
            # argv, which nothing here passes, and which wouldn't be
            # straightforward to plumb through buildPythonApplication's
            # own build invocation anyway. A network call would fail in
            # Nix's sandboxed build regardless, so disable the whole
            # thing outright by short-circuiting the condition that
            # guards it, rather than relying on argv.
            postPatch = ''
              sed -i 's/if TRACKINSTALL is not None and (wanted & seen) and not (notwanted & seen):/if False:/' setup.py
            '';
            # setup.py's own install_requires is empty (it only *checks*
            # for these and warns if missing); they're genuinely needed
            # at runtime, so propagate them for real here.
            propagatedBuildInputs = [ py.numpy py.pyqt5 py.lxml py.six ];
            doCheck = false;
            # Provides the `ete3` command and importable package. Still
            # needs a real or virtual X server at runtime (e.g.
            # xvfb-run) - packaging doesn't remove that requirement.
          };
        in
        {
          packages = {
            inherit raxml-ng roguenarok famsa treeshrink magus entrez-direct
              t-coffee clustalw fasttree prank muscle3 pasta ete3;
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
              iqtree # IQ-Tree2
              cd-hit
              trimal
              blast # blastp, makeblastdb, etc., in case module load isn't available
              muscle # nixpkgs' muscle is v5.1.0: covers MUSCLE5 and SUPER5 (muscle -super5 ...)
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
              pasta
              ete3
            ];
          };
        });
    in
    {
      packages = forAllSystems (system: perSystem.${system}.packages);
      devShells = forAllSystems (system: { default = perSystem.${system}.devShell; });
    };
}
