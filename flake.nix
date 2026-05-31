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
            # Adding zmk-dongle-screen changes the fetched west deps, so this
            # hash WILL change. Build once with fakeHash, then paste the correct
            # hash from the error. (Alternatively: `nix run .#update`.)
            zephyrDepsHash = lib.fakeHash;
            meta = {
              description = "ZMK firmware";
              license = lib.licenses.mit;
              platforms = lib.platforms.all;
            };
          };

          # Both halves are now peripherals — role is set in redox_left.conf and
          # redox_right.conf. Studio lives on the central (the dongle), so
          # enableZmkStudio is intentionally gone from here.
          firmware = zmkLib.buildSplitKeyboard (
            common
            // {
              name = "firmware";
              shield = "redox_%PART%";
            }
          );

          # The dongle: central role (via its shield's Kconfig.defconfig) + the
          # YADS screen, on the XIAO. Phase 1 = no light sensor, no Studio.
          dongle = zmkLib.buildKeyboard (
            common
            // {
              name = "dongle";
              board = "xiao_ble//zmk";
              shield = "redox_dongle dongle_screen";
              # snippets = [ "zmk-usb-logging" ]; # optional, debugging only
            }
          );

          # Reset images — one per board family.
          resetfw = zmkLib.buildKeyboard (
            common
            // {
              name = "resetfw";
              shield = "settings_reset";
            }
          );
          resetfw-dongle = zmkLib.buildKeyboard (
            common
            // {
              name = "resetfw-dongle";
              board = "xiao_ble//zmk";
              shield = "settings_reset";
            }
          );

          flash = zmk-nix.packages.${system}.flash.override { inherit firmware; };
          flash-dongle = zmk-nix.packages.${system}.flash.override { firmware = dongle; };
          flash-reset-dongle = zmk-nix.packages.${system}.flash.override { firmware = resetfw-dongle; };

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
            dongle
            resetfw
            resetfw-dongle
            flash
            flash-dongle
            flash-reset
            flash-reset-dongle
            ;
          update = zmk-nix.packages.${system}.update;
        }
      );
      devShells = forAllSystems (system: {
        default = zmk-nix.devShells.${system}.default;
      });
    };
}
