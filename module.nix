{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.deepseek-harness;
  yaml = pkgs.formats.yaml { };
in
{
  options.programs.deepseek-harness = {
    enable = lib.mkEnableOption "DeepSeek Harness, a plugin-composed agent harness";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.deepseek-harness or (pkgs.callPackage ./package.nix { });
      defaultText = lib.literalExpression "pkgs.deepseek-harness, or this flake's package when the overlay is not applied";
      description = "The DeepSeek Harness package to install. Provides the `dsh` binary.";
    };

    patches = lib.mkOption {
      type = lib.types.listOf yaml.type;
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            id = "agent-instructions";
            config.maxBytes = 32768;
          }
          {
            id = "tool-web";
            disabled = true;
          }
        ]
      '';
      description = ''
        The home-level loader patch layer, written to {file}`~/.dsh/cordis.patch.yml`.

        A top-level list of patch entries applied over every profile's own
        layer: `{ id, config }` replaces a row's configuration, `disabled`
        turns a row off, and `{ insert = [ … ]; }` appends rows. `!!js`
        expressions cannot be expressed here, since YAML tags have no Nix
        representation; keep those in a profile's own layer.

        Left empty, the file is not managed and `dsh` owns it. Set it, and the
        file becomes a read-only store symlink: the Settings UI can no longer
        persist machine-local preferences to it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file = lib.mkIf (cfg.patches != [ ]) {
      ".dsh/cordis.patch.yml".source = yaml.generate "dsh-cordis.patch.yml" cfg.patches;
    };
  };
}
