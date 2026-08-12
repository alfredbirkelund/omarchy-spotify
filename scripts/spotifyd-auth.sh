#!/bin/sh
set -eu

# spotifyd owns a credential separate from the Web API refresh token. Force a
# private creation mode even when omarchy-shell itself inherited umask 0022.
umask 077

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
exec /usr/bin/spotifyd authenticate \
  --config-path "$config_root/omarchy-spotify/spotifyd.conf" \
  --oauth-port 8000
