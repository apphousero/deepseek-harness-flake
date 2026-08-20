{
  lib,
  pkgs,
  runCommand,
  hello,
  hmModule,
}:

let
  stubHomeManager = {
    options.home = {
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
      file = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.source = lib.mkOption { type = lib.types.path; };
          }
        );
        default = { };
      };
    };
    config._module.args.pkgs = pkgs;
  };

  eval =
    module:
    (lib.evalModules {
      modules = [
        stubHomeManager
        hmModule
        module
      ];
    }).config;

  disabled = eval { programs.deepseek-harness.package = hello; };

  bare = eval {
    programs.deepseek-harness = {
      enable = true;
      package = hello;
    };
  };

  configured = eval {
    programs.deepseek-harness = {
      enable = true;
      package = hello;
      patches = [
        {
          id = "agent-instructions";
          config.maxBytes = 32768;
        }
        {
          id = "tool-web";
          disabled = true;
        }
      ];
    };
  };

  patchFile = configured.home.file.".dsh/cordis.patch.yml".source;
in
runCommand "deepseek-harness-module-test"
  {
    inherit patchFile;
    disabledPackages = builtins.length disabled.home.packages;
    disabledFiles = builtins.length (builtins.attrNames disabled.home.file);
    barePackage = lib.getExe' (builtins.head bare.home.packages) "hello";
    bareFiles = builtins.length (builtins.attrNames bare.home.file);
  }
  ''
    [ "$disabledPackages" = 0 ] || { echo "disabled module still installs packages"; exit 1; }
    [ "$disabledFiles" = 0 ] || { echo "disabled module still manages files"; exit 1; }

    [ "$barePackage" = "${lib.getExe' hello "hello"}" ] || { echo "wrong package installed"; exit 1; }
    [ "$bareFiles" = 0 ] || { echo "empty patches must leave cordis.patch.yml unmanaged"; exit 1; }

    grep -q '^- ' "$patchFile" || { echo "patch layer is not a top-level list"; cat "$patchFile"; exit 1; }
    grep -q '^    maxBytes: 32768$' "$patchFile" || { echo "nested config not rendered"; cat "$patchFile"; exit 1; }
    grep -q '^- disabled: true$' "$patchFile" || { echo "row disable not rendered"; cat "$patchFile"; exit 1; }

    touch $out
  ''
