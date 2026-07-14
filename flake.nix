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
        in
        {
          packages = {
            inherit raxml-ng roguenarok famsa treeshrink magus entrez-direct;
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
            ]) ++ [ raxml-ng roguenarok famsa treeshrink magus entrez-direct ];
          };
        });
    in
    {
      packages = forAllSystems (system: perSystem.${system}.packages);
      devShells = forAllSystems (system: { default = perSystem.${system}.devShell; });
    };

  # Deliberately not packaged here - see the reasoning below rather than
  # forcing a derivation that's likely to fail in a network-sandboxed
  # Nix build:
  #   - T-Coffee: its build depends on g77, a Fortran compiler dropped
  #     from GCC long ago in favor of gfortran; unclear if the Makefile
  #     tolerates the substitution without patching.
  #   - PASTA: needs a whole separate sate-tools-linux repo bundling
  #     MAFFT, OPAL, Muscle, FastTree, RAxML, HMMER, Contralign and
  #     ProbCons as prebuilt binaries - packaging PASTA properly means
  #     packaging that whole bundle too.
  #   - ete3: left for later per your note; also still needs a real or
  #     virtual X server regardless of how it's installed.
}
