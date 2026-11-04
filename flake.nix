{
  description = "Avunu's Odoo standards profile for odoo-nix: the odoo-nix this profile is validated against";

  # This repository is data (profile.toml, fleet.json), not a flake repositories consume: they
  # read it as a `flake = false` input named standards-profile. The flake only pins the
  # odoo-nix whose `odoo-nix profile validate` and fixtures (standards-project,
  # standards-addons) the CI uses, so every validate run is reproducible and Dependabot's
  # `nix` entry moves the pin in a PR.
  #
  # It pins the release named by profile.toml's `requires-odoo-nix` lower bound, and the
  # validate workflow's `latest` job covers the newest release the range allows.
  inputs = {
    # v2.3.0, the first odoo-nix release that ships the standards engine, is not tagged yet,
    # so this flake can't be locked and no flake.lock is committed. Until then
    # scripts/check.sh runs against a development build (ODOO_NIX, ODOO_NIX_SRC; README.md).
    # Once the tag exists, run `nix flake lock` and commit flake.lock (if the release is
    # another minor, move this pin, profile.toml's `extends` and `requires-odoo-nix` with it).
    odoo-nix.url = "github:Avunu/odoo-nix/v2.3.0";
    nixpkgs.follows = "odoo-nix/nixpkgs";
  };

  outputs =
    { odoo-nix, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);
    in
    {
      # The pinned odoo-nix source tree: its fixtures are what resolved.project.snapshot.json
      # and resolved.addons.snapshot.json are computed from (`nix eval --raw .#lib.odoo-nix-src`).
      lib.odoo-nix-src = "${odoo-nix}";

      packages = forAllSystems (
        _: system: {
          inherit (odoo-nix.packages.${system}) odoo-nix;
          default = odoo-nix.packages.${system}.odoo-nix;
        }
      );

      # `nix develop`: the pinned odoo-nix CLI, plus the tools the validate workflow uses.
      devShells = forAllSystems (
        pkgs: system: {
          default = pkgs.mkShell {
            packages = [
              odoo-nix.packages.${system}.odoo-nix
              pkgs.actionlint
              pkgs.jq
              pkgs.nixfmt-rs
              pkgs.ruff
              pkgs.shellcheck
              pkgs.zizmor
            ];
          };
        }
      );

      formatter = forAllSystems (pkgs: _: pkgs.nixfmt-rs);
    };
}
