# Technical notes

This document keeps implementation, development, and deep troubleshooting
details out of the user-facing README.

## Architecture

Omarchy Spotify runs as a plugin inside Omarchy's existing `omarchy-shell`
Quickshell process. It provides a shared service, a bar widget, and a lazy-loaded
panel. There is no embedded website, browser engine, second shell process, or
resident helper process.

Local playback state and ordinary controls use MPRIS. Active playback on another
Spotify Connect device comes from the Spotify Web API, refreshed while a UI is
visible and at a slower rate while that device is playing. Spotify data and user
actions also use the Web API. Local audio uses `spotifyd` 0.4.2 or newer,
supervised by a static systemd user unit that is never enabled at login. The app
starts it only when playback needs this computer and stops it after the
configured idle period.

## Runtime requirements

- Omarchy 4 with the Quickshell shell enabled
- Spotify Premium
- `spotifyd` 0.4.2 or newer
- Omarchy base tools: `secret-tool`, `openssl`, `socat`, `xdg-open`, `wl-copy`,
  `avahi-browse`, `systemctl`, and Python 3

Omarchy's plugin installer deliberately clones and validates plugins without
running install hooks or privileged code. `scripts/setup-playback.sh` therefore
finishes setup only after the user clicks the first-run button. It uses Polkit to
install the official Arch `spotifyd` package only when missing, then installs the
private config and static user unit without privilege.

## Authentication

Web API access uses Spotify's Authorization Code with PKCE flow and the public
application identity also used by `spotify-player` and ncspot. The fixed callback
is `http://127.0.0.1:8989/login`. `spotifyd` performs its independent browser
authorization on loopback port `8000`. Receivers that advertise the
`authorization_code` token type use a separate, on-demand, streaming-only PKCE
grant on port `8990`.

No client secret or Spotify password enters the plugin. OAuth refresh tokens
are written to GNOME Keyring over stdin and separated by client identity.
Short-lived access tokens and PKCE values remain in the shell process. OAuth
state is checked, callback listeners bind explicitly to IPv4 loopback, API URLs
are restricted to
`https://api.spotify.com/v1`, and sensitive credential patterns are redacted
before an error can reach the interface.

The app requests only the library, follow, listening-history, playlist,
playback-position, and playback-control permissions used by visible features.
It does not request profile or email permissions.

## Local Spotify Connect

The app prefers its own local device unless the user explicitly chooses another
Spotify Connect device. It can perform a one-shot `_spotify-connect._tcp` lookup
for nearby receivers omitted from Spotify's device response. For ordinary
receivers, the helper re-encrypts `spotifyd`'s owner-only reusable credential for
the receiver's ephemeral ZeroConf key. For authorization-code receivers such as
Sonos, it exchanges the short-lived streaming token for a receiver-scoped code
and sends that code to the receiver. It then waits for Spotify to report the
genuine device before transferring playback when needed. It never asks for or
stores the user's password.

Once a restricted Sonos is active, the Web API rejects its player commands.
The app therefore resolves that same receiver on the LAN and sends fixed UPnP
AVTransport or RenderingControl actions for play, pause, previous, next, seek,
shuffle/repeat mode, and volume. Targets still come only from validated local
Spotify Connect discovery. When playback has moved elsewhere, a local Play wake
is attempted first; the OAuth activation flow remains the fallback for a Sonos
that has actually lost its Spotify session. Receiver discovery and requests are
retried briefly because Sonos can sleep its endpoint during a handoff.

The current-playback response is also merged into the device list. This matters
for models that Spotify omits from `/me/player/devices`, or whose active device
id is null. A matching nearby receiver is recognized by name and type in that
case. Restricted devices remain visible with their current item. Controls stay
disabled unless the app has a supported local-control path such as Sonos.

Spotify changed development-mode endpoints and fields in 2026. This client uses
`/playlists/{id}/items`, `/me/library`, and search limits of 10. Some non-owned
playlist contents are no longer returned. Artist pages use artist-scoped catalog
search for the two ranked release/song columns because Spotify removed the
artist-top-tracks endpoint. Followed-playlist conversion fetches every available
page before creating a private copy, writes items in batches of 100, and removes
the original from the library only after all writes succeed.

## Local development

From a checkout on Omarchy 4:

```bash
./scripts/install-local.sh --install-spotifyd
```

The command validates the manifest, installs the user-level playback files,
links the checkout at
`~/.config/omarchy/plugins/quickshell.spotify`, and enables the bar widget. It
refuses to replace an existing plugin.

To install only the playback integration:

```bash
./scripts/setup.sh --install-spotifyd
```

Neither path enables or starts `spotifyd` at login.

## Verification

```bash
./scripts/test.sh
```

The suite runs Omarchy manifest validation, Qt 6 QML lint, offline Qt tests with
mocked authentication responses, shell-script tests, configuration checks, and a
forbidden-heavyweight-dependency scan.

Resource sampling:

```bash
./scripts/benchmark.sh idle 10
```

See [Benchmark](BENCHMARK.md) for methodology and recorded results.

## Complete removal

Log out in the app first, then remove the plugin. Before deleting the checkout,
run:

```bash
./scripts/remove-runtime.sh --purge
omarchy plugin remove quickshell.spotify --yes
```

This stops and removes the static user unit, deletes the app's private playback
config, removes `spotifyd`'s cached credential, and clears matching Music for
Spotify keyring entries. The `spotifyd` package remains installed because another
client may use it.

Remove that package separately only when it was installed solely for this app:

```bash
sudo pacman -Rns spotifyd
```

## Upstream projects

- [Omarchy](https://github.com/basecamp/omarchy)
- [spotifyd](https://github.com/Spotifyd/spotifyd)
- [spotify-player](https://github.com/aome510/spotify-player)
- [ncspot](https://github.com/hrkfdn/ncspot)
- [Spotify Web API](https://developer.spotify.com/documentation/web-api)
