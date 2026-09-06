#!/usr/bin/env bash
# Rewrites version, the pnpm lock, and the pnpm store hash for the newest published
# npm release. Run from the repository root, or via `nix run .#update`.
set -euo pipefail

registry="${DSH_REGISTRY:-https://registry.npmjs.org}"
package="@deepseek-ai/dsh"
target="${DSH_PACKAGE_NIX:-package.nix}"
root="${DSH_NPM_ROOT:-npm}"
attr="${DSH_FLAKE_ATTR:-.#deepseek-harness.pnpmDeps}"

if [ ! -f "$target" ] || [ ! -f "$root/package.json" ]; then
  echo "update: $target or $root/package.json not found; run from the repository root" >&2
  exit 1
fi

trap 'rm -f "$target.tmp" "$root/package.json.tmp"' EXIT

version="${1:-}"
if [ -z "$version" ]; then
  version=$(curl -fsSL "$registry/$package" |
    jq -r --arg package "$package" \
      '.time as $t
       | (.versions // {} | keys_unsorted)
       | if length == 0 then error("update: \($package) publishes no versions") else . end
       | max_by($t[.])')
fi
version="${version#dsh-}"
version="${version#v}"

if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "update: '$version' is not a release version like 0.1.2-rc.1" >&2
  exit 1
fi

current=$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$target")
currentLock=$(sha256sum "$root/pnpm-lock.yaml" | cut -d' ' -f1)
currentHash=$(sed -n 's/^    hash = "\(sha256-[^"]*\)";$/\1/p' "$target")

jq --arg package "$package" --arg version "$version" \
  'if .dependencies[$package] then .dependencies[$package] = $version else error("update: \($package) is not a dependency of the install root") end' \
  "$root/package.json" >"$root/package.json.tmp"
mv "$root/package.json.tmp" "$root/package.json"

(cd "$root" && pnpm install --lockfile-only --ignore-scripts)

if ! grep -q "^  '${package}@${version}':" "$root/pnpm-lock.yaml"; then
  echo "update: pnpm resolved no ${package}@${version}; the release may be unpublished" >&2
  exit 1
fi

awk -v ver="$version" '
  /^  version = "/ { sub(/"[^"]*"/, "\"" ver "\""); print; vers++; next }
  /^    hash = "/ { sub(/"[^"]*"/, "\"\""); print; hashes++; next }
  { print }
  END {
    if (vers != 1) { print "update: rewrote " vers + 0 " version lines, expected 1" > "/dev/stderr"; exit 1 }
    if (hashes != 1) { print "update: rewrote " hashes + 0 " hash lines, expected 1; package.nix layout changed" > "/dev/stderr"; exit 1 }
  }
' "$target" >"$target.tmp"
mv "$target.tmp" "$target"

newLock=$(sha256sum "$root/pnpm-lock.yaml" | cut -d' ' -f1)

hash=""
if [ "$current" = "$version" ] && [ "$currentLock" = "$newLock" ]; then
  hash="$currentHash"
fi

if [ -z "$hash" ]; then
  echo "update: fetching the pnpm store to resolve its hash" >&2
  out=$(nix build "$attr" --no-link 2>&1 || true)
  hash=$(printf '%s\n' "$out" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | tail -1)
  if [ -z "$hash" ]; then
    printf '%s\n' "$out" >&2
    echo "update: could not resolve the pnpm store hash from the build above" >&2
    exit 1
  fi
fi

sed -i "s|^    hash = \"\";\$|    hash = \"$hash\";|" "$target"

if ! grep -q "^    hash = \"$hash\";\$" "$target"; then
  echo "update: failed to write the pnpm store hash into $target" >&2
  exit 1
fi

if [ "$current" = "$version" ]; then
  echo "update: already at $version (lock and hash refreshed)"
else
  echo "update: $current -> $version"
fi
