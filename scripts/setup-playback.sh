#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Plugin installs intentionally do not run hooks. Finish the small amount of
# local playback setup from the app instead, asking through Polkit only when
# the official Arch spotifyd package is not already installed.
if ! command -v spotifyd >/dev/null 2>&1; then
  command -v pkexec >/dev/null 2>&1 || exit 20
  if ! pkexec /usr/bin/pacman -S --needed --noconfirm spotifyd; then
    exit 21
  fi
fi

if ! "$source_root/scripts/setup.sh"; then
  exit 22
fi
