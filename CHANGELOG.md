# Changelog

## 1.0.1 — 2026-08-13

- Use Omarchy Spotify consistently as the product name.
- Document the user-initiated, narrowly scoped playback setup and its exact
  privileged package-install command.

- Show active playback from remote Spotify Connect devices, including Sonos
  players omitted from Spotify's available-device response or reported without
  a device id.
- Activate Sonos and other authorization-code receivers with their advertised
  OAuth flow instead of sending an incompatible reusable-credential blob.
- Mark restricted active devices clearly and avoid sending controls that the
  Spotify Web API will reject.
- Keep new song selections on the currently active Spotify Connect device,
  falling back to this computer only when no device is active.
- Control locally discovered Sonos playback, seeking, modes, and volume over
  its fixed LAN endpoints when Spotify marks the device restricted.
- Keep the remote volume slider visible when Spotify omits its nullable volume
  reading, including an authoritative local volume read for Sonos.
- Reconnect to a previously authorized Sonos by waking its retained session,
  with transient receiver retries and OAuth activation as fallback.
- Show locally advertised aliases for active speakers whose Spotify API name is
  only an opaque device id, and honor JBL-style access-token activation.

## 1.0.0 — 2026-08-12

First public release for Omarchy 4.

- Full Spotify home, search, library, playlist, queue, and detail views.
- Artist pages with Spotify's **This Is** playlist directly above releases,
  a full top 10 songs loaded across Spotify result pages, and artist-specific
  search.
- Dedicated Discover tab for official personal mixes and fresh Spotify playlists.
- Local on-demand playback plus Spotify Connect device switching.
- Guided first-run setup and browser sign-in from one user-facing flow.
- Playlist editing, track radio, saved items, recent searches, and sleep timers.
- One-click song-to-playlist picking and safe conversion of followed playlists.
- Playlist menus fit long actions cleanly; unused playlist pinning was removed.
- Escape/focus-loss menu dismissal and context-menu-only library removal.
- Very high (320 kbps) audio quality by default.
- Device-name changes update the Devices view immediately without losing the
  local playback target.
- Track artist and album labels stay together and truncate cleanly on artist pages.
- Theme-native bar popup and full app with compact tiled-window navigation.
- Keyring-backed sessions, PKCE sign-in, credential redaction, and loopback-only callbacks.
- Offline QML and script tests plus documented resource benchmarks.
