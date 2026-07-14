{
  description = "User-space dev shell for the PhylogenyPipeline's non-cluster-provided tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Enter with `nix develop` (or `nix-portable nix develop` if Nix
          # itself isn't installed on the cluster). Everything in here
          # replaces a "user path" install from the README's Prerequisites
          # section. It does NOT replace anything marked "module load" -
          # those come from the cluster's own module system on purpose,
          # e.g. because the sysadmin's blastp build is tied to the
          # cluster's MPI/BLAST database setup.
          default = pkgs.mkShell {
            packages = with pkgs; [
              seqkit
              iqtree # IQ-Tree2
              cd-hit
              trimal
              blast # blastp, makeblastdb, etc., in case module load isn't available
              muscle # nixpkgs' muscle is v5.1.0: covers MUSCLE5 and SUPER5 (muscle -super5 ...)
              clustal-omega
              mafft # also provides linsi
            ];
          };
        });
    };

  # Not packaged in nixpkgs as of 2026-07, so still need a manual/module
  # install as described in the README:
  #   - raxml-ng          (nixpkgs only has classic RAxML 8.2.13, a
  #                         different, older tool - do not substitute it)
  #   - T-Coffee
  #   - PASTA
  #   - FAMSA
  #   - TreeShrink (Python 2.7)
  #   - RogueNaRok-parallel
  #   - efetch / entrez-direct
  #   - ete3 (packageable via python3Packages.ete3, but that doesn't
  #     remove the X-server/xvfb requirement, only the install step)
  #   - MAGUS's dendropy (pip) and vcMSA's vcmsa_env (conda) are their
  #     own environments already and are left as-is
}
