#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$source_root/backend/Cargo.toml"
runtime_dir=${OMARCHY_SPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omarchy-spotify"}
destination="$runtime_dir/omarchy-spotify-backend"
architecture=$(uname -m)
prebuilt="$source_root/backend/dist/$architecture/omarchy-spotify-backend"

# Build outside the plugin directory: Omarchy hot-reloads a plugin whenever any
# file inside it changes, so an in-place backend/target/ makes its recursive
# watcher unload and reload the plugin for every Cargo write, killing the build.
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
target_dir=${CARGO_TARGET_DIR:-"$cache_root/omarchy-spotify/target"}

if [[ -x $prebuilt ]]; then
  install -d -m 700 -- "$runtime_dir"
  install -m 755 -- "$prebuilt" "$destination"
  printf 'Installed bundled playback backend: %s\n' "$destination"
  exit 0
fi

command -v cargo >/dev/null 2>&1 || {
  echo "build-backend.sh: no bundled backend is available and cargo is missing" >&2
  exit 30
}

CARGO_TARGET_DIR="$target_dir" cargo build --locked --release --manifest-path "$manifest"
install -d -m 700 -- "$runtime_dir"
install -m 755 -- "$target_dir/release/omarchy-spotify-backend" \
  "$destination"
printf 'Built and installed playback backend: %s\n' "$destination"
