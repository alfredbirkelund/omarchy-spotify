#!/usr/bin/env bash
set -euo pipefail

purge=0
if [[ ${1:-} == "--purge" ]]; then
  purge=1
  shift
fi
if (( $# > 0 )); then
  echo "Usage: scripts/remove-runtime.sh [--purge]" >&2
  exit 2
fi

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
backend_unit_file="$config_root/systemd/user/omarchy-spotify.service"
fallback_unit_file="$config_root/systemd/user/omarchy-spotifyd.service"
config_dir="$config_root/omarchy-spotify"
cache_dir="$cache_root/spotifyd"
state_dir="$state_root/omarchy-spotify"
runtime_dir=${OMARCHY_SPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omarchy-spotify"}
backend_binary="$runtime_dir/omarchy-spotify-backend"
backend_source_id_file="$runtime_dir/backend-source.sha256"
backend_binary_hash_file="$runtime_dir/backend-binary.sha256"
backend_origin_file="$runtime_dir/backend-origin"

systemctl --user stop omarchy-spotify.service 2>/dev/null || true
systemctl --user stop omarchy-spotifyd.service 2>/dev/null || true
rm -f -- "$backend_unit_file" "$fallback_unit_file" "$backend_binary" \
  "$backend_source_id_file" "$backend_binary_hash_file" "$backend_origin_file"
systemctl --user daemon-reload

if [[ -d $config_dir ]]; then
  if (( purge )); then
    [[ $config_dir == "$config_root/omarchy-spotify" ]] || exit 3
    rm -rf -- "$config_dir"
    echo "Removed spotifyd configuration."
  else
    backup="${config_dir}.bak.$(date -u +%Y%m%d%H%M%S)"
    mv -- "$config_dir" "$backup"
    echo "Moved configuration to: $backup"
  fi
fi

if (( purge )); then
  [[ $state_root == /* && $state_root != / ]] || {
    echo "remove-runtime.sh: refusing an unsafe state path" >&2
    exit 3
  }
  if [[ -d $cache_dir ]]; then
    [[ $cache_dir == "$cache_root/spotifyd" ]] || exit 3
    rm -rf -- "$cache_dir"
    echo "Removed spotifyd cached credentials and audio."
  fi
  if [[ -d $state_dir ]]; then
    [[ $state_dir == "$state_root/omarchy-spotify" ]] || exit 3
    rm -rf -- "$state_dir"
    echo "Removed durable playback authorization and session state."
  fi
  if command -v secret-tool >/dev/null 2>&1; then
    for _ in {1..20}; do
      secret-tool clear service quickshell-spotify kind refresh-token >/dev/null 2>&1 || break
    done
    echo "Cleared matching Omarchy Spotify keyring entries."
  fi
fi

echo "Runtime integration removed. The spotifyd package was left installed."
