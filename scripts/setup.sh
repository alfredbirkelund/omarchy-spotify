#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install_spotifyd=0
force_config=0
device_name="Omarchy Spotify"

usage() {
  cat <<'EOF'
Usage: scripts/setup.sh [--install-spotifyd] [--force-config] [--device-name NAME]

Install the user-level spotifyd configuration and static systemd user unit.
The unit is deliberately not enabled; the Omarchy plugin starts it on demand.
EOF
}

while (( $# > 0 )); do
  case $1 in
    --install-spotifyd)
      install_spotifyd=1
      shift
      ;;
    --force-config)
      force_config=1
      shift
      ;;
    --device-name)
      [[ $# -ge 2 ]] || { echo "setup.sh: --device-name requires a value" >&2; exit 2; }
      device_name=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "setup.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v spotifyd >/dev/null 2>&1; then
  if (( install_spotifyd )); then
    command -v pacman >/dev/null 2>&1 || {
      echo "setup.sh: --install-spotifyd is supported only on pacman-based Omarchy systems" >&2
      exit 1
    }
    sudo pacman -S --needed spotifyd
  else
    echo "setup.sh: spotifyd is missing" >&2
    echo "Install it with: sudo pacman -S --needed spotifyd" >&2
    echo "Or rerun: scripts/setup.sh --install-spotifyd" >&2
    exit 1
  fi
fi

for command_name in secret-tool openssl socat xdg-open systemctl awk install python3 avahi-browse; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "setup.sh: required Omarchy base command is missing: $command_name" >&2
    exit 1
  }
done

"$source_root/scripts/spotify-connect-device.py" self-test >/dev/null || {
  echo "setup.sh: the local Spotify Connect encryption helper failed its self-test" >&2
  exit 1
}

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
config_dir="$config_root/omarchy-spotify"
config_file="$config_dir/spotifyd.conf"
unit_dir="$config_root/systemd/user"
unit_file="$unit_dir/omarchy-spotifyd.service"

install -d -m 700 -- "$config_dir"
install -d -m 700 -- "$unit_dir"

if [[ -f $config_file && $force_config -eq 0 ]]; then
  echo "Keeping existing configuration: $config_file"
else
  if [[ -f $config_file ]]; then
    backup="${config_file}.bak.$(date -u +%Y%m%d%H%M%S)"
    cp -p -- "$config_file" "$backup"
    echo "Backed up previous configuration to: $backup"
  fi
  install -m 600 -- "$source_root/config/spotifyd.conf" "$config_file"
fi

printf '%s\n' "$device_name" | "$source_root/scripts/configure-spotifyd.sh"
install -m 644 -- "$source_root/systemd/omarchy-spotifyd.service" "$unit_file"
systemctl --user daemon-reload

unit_state=$(systemctl --user is-enabled omarchy-spotifyd.service 2>/dev/null || true)
if [[ $unit_state == "enabled" || $unit_state == "enabled-runtime" ]]; then
  echo "Warning: omarchy-spotifyd.service was already enabled at login." >&2
  echo "For on-demand behavior, run: systemctl --user disable omarchy-spotifyd.service" >&2
fi

echo "Installed static user unit: $unit_file"
echo "Installed private config: $config_file"
echo "spotifyd remains stopped and will be started on demand by the plugin."
