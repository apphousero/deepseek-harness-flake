# `DeepSeek Harness` flake

Packages [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`, a plugin-composed agent
harness by DeepSeek AI) as a Nix package, an overlay, and a Home Manager module. The binary is installed as `dsh`.

Built from the published `@deepseek-ai/dsh` npm release with a committed pnpm lock — hash-pinned, no network at
build time, and no checkout of the upstream monorepo.

## Try it

```console
$ nix run github:apphousero/deepseek-harness-flake -- web
```

That serves the Web UI on <http://127.0.0.1:3080>; pass `--no-open` to keep it from opening a browser. See the
[Web UI guide](https://deepseek-harness.github.io/deepseek-harness/en/guide/quickstart).

## Flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    dsh = {
      url = "github:apphousero/deepseek-harness-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

The `follows` line is optional: the Home Manager module and the overlay build against your own `pkgs`, so this
flake's `nixpkgs` pin only affects `nix build`/`nix run`/`nix develop` on this repo directly.

## Home Manager module

```nix
{ inputs, ... }:
{
  imports = [ inputs.dsh.homeManagerModules.default ];

  programs.deepseek-harness.enable = true;
}
```

### Declarative patch layer

`dsh` boots a *profile* — an ordered stack of plugin-bundle patch layers under your own overrides. Profiles live
in `~/.dsh/profiles/<name>` and are initialized on first use; `programs.deepseek-harness.patches` writes the
home-level layer `~/.dsh/cordis.patch.yml`, which applies over every profile's own layer.

```nix
{
  programs.deepseek-harness = {
    enable = true;
    patches = [
      {
        id = "agent-instructions";
        config.maxBytes = 32768;
      }
      {
        id = "tool-web";
        disabled = true;
      }
      {
        insert = [
          {
            id = "my-plugin";
            name = "dsh-plugin-example";
          }
        ];
      }
    ];
  };
}
```

A patch entry addresses a composed row by `id`: given keys replace that row's (`config` is replaced whole, never
merged), and `{ insert = [ … ]; }` appends rows. Entries that match nothing are warned about and skipped.

Leave `patches` unset and the file stays unmanaged. Set it and the file becomes a read-only store symlink, so the
Settings UI can no longer persist machine-local preferences there — that is the trade for declarative config, not
a bug. A profile's own `~/.dsh/profiles/<name>/cordis.patch.yml` stays writable and is applied first.

`programs.deepseek-harness.package` overrides the derivation.

## Without the module

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.dsh.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
```

## Overlay

An overlay adds `pkgs.deepseek-harness` — it is not a module, so it goes in `nixpkgs.overlays`, not `imports`.
This is also the NixOS path; there is no NixOS module, because `dsh` keeps all of its state under `~/.dsh` and a
system-wide install is one line.

```nix
{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.dsh.overlays.default ];

  environment.systemPackages = [ pkgs.deepseek-harness ]; # or home.packages under Home Manager
}
```

With Home Manager as a NixOS module and `home-manager.useGlobalPkgs = true`, set the overlay on the system
`nixpkgs.overlays`.

## Plugins

`dsh plugin --profile <name> add <package>` installs out-of-tree plugins into the profile directory by forwarding
to pnpm. The wrapper puts pnpm on `PATH` for that; `git` comes from your environment, so git-hosted plugin specs
need it installed. In-box plugins always resolve from the store closure, never from the profile.

## Updating the pinned release

`update.sh` rewrites `version` in `package.nix`, the dependency in `npm/package.json`, `npm/pnpm-lock.yaml`, and
the pnpm store hash:

```console
$ nix run .#update                    # the newest published release
$ nix run .#update -- dsh-v0.1.2-rc.1 # a specific version; a `dsh-v` tag prefix is fine
```

With no argument it takes the newest upstream release — prereleases included, since upstream publishes nothing
else — and pins the version off its `dsh-v*` tag. npm `dist-tags` are ignored: `latest` trails by weeks.

It is idempotent: an already-current tree keeps its hash and refetches nothing. A version or lock change fetches
the pnpm store once to resolve the new hash.

A scheduled workflow runs it daily, builds the result on every supported system, and only then opens a PR.

## Checks

`nix flake check` builds the package (its `installCheck` asserts `dsh --version`, composes the `web` profile
tree offline, and loads every native addon), evaluates the Home Manager module against a stub, and verifies
formatting. `nix fmt` formats the tree; `nix develop` provides the Nix and Node toolchain.

CI runs the same `nix flake check` on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. `x86_64-darwin` is
not supported — nixpkgs is retiring the platform; use Rosetta.
