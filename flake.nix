{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      zmk-nix,
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs (nixpkgs.lib.attrNames zmk-nix.packages);
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = nixpkgs.lib;
          zmkLib = zmk-nix.legacyPackages.${system};

          # Attributes shared by every keyboard build
          common = {
            src = lib.sourceFilesBySuffices self [
              ".board"
              ".cmake"
              ".conf"
              ".defconfig"
              ".dts"
              ".dtsi"
              ".json"
              ".keymap"
              ".overlay"
              ".shield"
              ".yml"
              "_defconfig"
            ];
            board = "nice_nano//zmk";
            zephyrDepsHash = "sha256-lGjFEg5K+YRrJmnC9vLyyj46jWR3ys40ohzUT4G63G8=";
            meta = {
              description = "ZMK firmware";
              license = lib.licenses.mit;
              platforms = lib.platforms.all;
            };
          };

          # Normal split build.
          # Role (central/peripheral) is determined by redox_left.conf and
          # redox_right.conf — zmk-nix passes ZMK_CONFIG to west and ZMK
          # picks up the per-side conf file by shield name automatically.
          firmware = zmkLib.buildSplitKeyboard (
            common
            // {
              name = "firmware";
              shield = "redox_%PART%";
	      enableZmkStudio = true;
            }
          );

          # Single settings-reset image, identical for both sides.
          resetfw = zmkLib.buildKeyboard (
            common
            // {
              name = "resetfw";
              shield = "settings_reset";
            }
          );

          # flash.override { firmware = <drv>; } produces the upstream flash
          # script wired to a specific firmware derivation.
          flash = zmk-nix.packages.${system}.flash.override { inherit firmware; };

          # For resetfw we need to flash the same single image twice (one per
          # side) in sequence. The upstream flash script runs once when the
          # firmware derivation has no 'parts' attribute (buildKeyboard case),
          # so we wrap it in a script that simply calls it twice.
          flash-reset =
            let
              flashOnce = zmk-nix.packages.${system}.flash.override { firmware = resetfw; };
            in
            pkgs.writeShellApplication {
              name = "zmk-uf2-flash-reset";
              runtimeInputs = [ flashOnce ];
              text = ''
                echo "=== Flashing settings reset firmware ==="
                echo "You will be prompted twice, once for each half."
                echo ""
                echo "--- First half ---"
                zmk-uf2-flash
                echo ""
                echo "--- Second half ---"
                zmk-uf2-flash
              '';
            };

        in
        {
          default = firmware;
          inherit
            firmware
            resetfw
            flash
            flash-reset
            ;
          update = zmk-nix.packages.${system}.update;
        }
      );

      devShells = forAllSystems (system: {
        default = zmk-nix.devShells.${system}.default;
      });
    };
}
