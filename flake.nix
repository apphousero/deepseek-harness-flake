{
  description = "DeepSeek Harness (dsh), a plugin-composed agent harness: package, overlay, and Home Manager module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        deepseek-harness = pkgs.callPackage ./package.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness;
      });

      checks = forAllSystems (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness;

        module = pkgs.callPackage ./tests/module.nix {
          hmModule = self.homeManagerModules.default;
        };

        formatting =
          pkgs.runCommand "check-formatting"
            {
              nativeBuildInputs = [ pkgs.nixfmt ];
            }
            ''
              nixfmt --check $(find ${self} -name '*.nix')
              touch $out
            '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      apps = forAllSystems (pkgs: rec {
        update = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "deepseek-harness-update";
              runtimeInputs = with pkgs; [
                bash
                cacert
                coreutils
                curl
                gnused
                jq
                nodejs
                pnpm
              ];
              text = ''exec ${./update.sh} "$@"'';
            }
          );
          meta.description = "Rewrite package.nix and the pnpm lock for the latest upstream release";
        };
        default = update;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            deadnix
            jq
            nil
            nixfmt
            nodejs
            pnpm
            shellcheck
            statix
          ];
        };
      });

      homeManagerModules.default = import ./module.nix;

      overlays.default = final: _prev: {
        deepseek-harness = final.callPackage ./package.nix { };
      };
    };
}
