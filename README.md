# Omarchy Spotify

**The Spotify app built for Omarchy.**

Designed to feel like the original Spotify client, with the familiar sidebar,
browsing views, playlists and persistent player—just way snappier and dramatically
less resource-heavy.

It talks directly to Spotify's API instead of controlling or embedding the official
client, so the Spotify desktop app does not need to be installed or running. The
entire interface automatically follows your active Omarchy theme, including light
themes.

A populated Omarchy Spotify window used **54.8 MiB PSS**, compared with **912.2 MiB**
across the official Spotify client's processes: **94% less memory**. With its window
closed, the plugin adds only **1.6 MiB PSS** to the existing Omarchy shell.

![Omarchy Spotify playlists](docs/pr-assets/matte-black-playlists.png)

![Omarchy Spotify search](docs/pr-assets/matte-black-search.png)

![Omarchy Spotify discover](docs/pr-assets/matte-black-discover.png)

> Requires Omarchy 4 and a personal Spotify Premium account.

## Add to Omarchy

```bash
omarchy plugin add https://github.com/stappmus/Omarchy-Spotify.git --enable
```

After installation, click the Spotify icon in the bar and follow the setup shown
in the app.

## Highlights

- Search from one bar across the app. It filters the artist, album, playlist,
  library section, or other area you have open; uncheck **In …** for a full
  Spotify search instead.
- Discover Weekly, Release Radar, Daily Mixes, daylist, and fresh Spotify picks
  in a dedicated Discover tab when they are available for your account.
- Browse Liked Songs, saved albums, followed artists, podcasts, and books.
- Open an artist for their **This Is** playlist, top albums and EPs, and top 10
  songs, then search within that artist's catalog.
- Create and edit playlists, manage the queue, and start track radio.
- Turn a followed playlist into your own editable private copy when Spotify
  makes its contents available.
- Play on this computer or switch to another Spotify Connect device.
- Control shuffle, repeat, position, volume, and a flexible sleep timer.
- Match every Omarchy theme automatically, including light themes.
- Stay lightweight: no embedded browser, Electron app, or always-on background
  worker.

## First-run setup

On first launch:

1. Click the Spotify icon in the bar.
2. Choose **Set up and continue**. If the small playback component is missing,
   Omarchy asks for your computer password before installing it.
3. Finish the Spotify approval pages in your browser. Spotify may show two pages
   the first time; complete both and the app brings you back automatically.

That is the whole setup. Playback on this computer starts when the mini player
or full app opens, or when local playback is needed. It stays available in
Spotify Connect while either view is open and stops automatically after it has
been idle with both views closed.

### Why setup may request administrator access

The `omarchy plugin add` command only clones, validates, installs, and enables
the plugin. It does not run setup hooks or privileged code.

After you explicitly choose **Set up and continue**, Omarchy Spotify checks for
the local `spotifyd` playback component. If it is missing, Polkit shows the
system authorization prompt before the plugin runs this fixed command:

```bash
pkexec /usr/bin/pacman -S --needed --noconfirm spotifyd
```

The package name and command are not assembled from remote input, and the setup
does not download or pipe a remote script into a shell. Everything after that
runs without administrator privileges: the plugin writes a private config and
a static systemd user unit under your user configuration directory. The unit is
not enabled at login; Omarchy Spotify starts it only when local playback is
needed and stops it again after the configured idle period.

## Everyday controls

- Left-click the bar widget for now playing and quick controls.
- Middle-click to play or pause.
- Right-click to open the full app.
- Scroll over the widget for previous or next.
- Use the playlist button on any song or episode to add it to one of your
  playlists or create a new playlist for it.
- Right-click a song or other media row for more actions. Removing something
  from your library is intentionally kept in this menu.
- Click any artist name—in a media row, album header, or either player—to open
  that artist directly.
- Use the lyrics button in either player to open the current song directly in
  Omasing Lyrics with its title, artist, album, duration, artwork, and current
  playback position. Omasing opens slightly before the estimated current line.
  If the optional plugin is missing or disabled, Spotify asks before installing
  or enabling it and explains that Omarchy plugins run unsandboxed.
- Use **Devices** to move playback between this computer and Spotify Connect
  speakers or players.

Keyboard shortcuts:

- `Ctrl+K` or `/` — Focus the unified search bar
- `Ctrl+F` / `Ctrl+L` — Search in the open area / search all of Spotify
- `Alt+Left` — Go back
- `Ctrl+,` — Open Settings
- `Alt+Shift+H` / `Alt+Shift+Q` / `Alt+Shift+D` — Open For You, Queue,
  or Devices
- `Space` — Play or pause
- `Ctrl+Left` / `Ctrl+Right` — Previous or next
- `M` — Mute or restore the previous volume
- `Ctrl+S` / `Ctrl+R` — Toggle shuffle / cycle repeat
- `Shift+Left` / `Shift+Right` — Seek backward / forward 10 seconds
- `Ctrl+Up` / `Ctrl+Down` — Raise / lower volume by 5%
- `Ctrl+/` — Open the keyboard-shortcut reference
- Arrow keys and `Enter` — Move through and open lists
- `Escape` — Close an open menu, clear search, or go back; from a top-level
  view, press twice to close the window

Playback shortcuts are suspended while typing. Hover a matching control to see
its shortcut without opening the reference.

## Playlists

Choose the **+** beside **Playlists**, enter a name in the popup, and choose
**Create**. To add music, use the playlist button on any song or podcast episode
and choose the destination. The same picker can create a new private playlist
and add the item in one step. In a playlist you own, keep sorting set to
**Original**, then drag a song card to place it anywhere in the loaded list.

When a playlist belongs to someone else, choose **Turn into your own playlist**.
The app creates a private copy, copies every song or episode Spotify provides,
and removes the followed original only after the copy succeeds. If Spotify does
not expose that playlist's contents, nothing is removed.

## Settings

Open **Settings** in the app to:

- reconnect Spotify or log out;
- rename how this computer appears in Spotify Connect;
- choose when local playback goes to sleep;
- show or hide the song title in the bar; and
- choose standard, high, or very high audio quality. New installs default to
  very high (320 kbps).

Set idle minutes to `0` only if you want this computer to remain available as a
Spotify Connect target all the time.

## Privacy and security

Your Spotify password is entered only on Spotify's own page. Omarchy Spotify
never sees it.

The saved Spotify session is stored in GNOME Keyring. Short-lived access data
stays in the Omarchy shell process, sign-in listens only on this computer, and
sensitive values are removed from any error shown in the app. Logging out stops
local playback and clears all saved Spotify sessions.

Like every Omarchy shell plugin, this code runs inside `omarchy-shell` rather
than a sandbox. Install plugins only from sources you trust.

## Troubleshooting

- **A Spotify feature stopped working:** open **Settings** and choose
  **Reconnect Spotify**.
- **Music will not start on this computer:** open **Settings** and check the
  playback status. If offered, choose **Set up playback**.
- **Sign-in did not return to the app:** close any old Spotify approval tabs and
  try again. Another local sign-in already in progress can block the return.
- **A speaker is missing:** make sure it is awake and on the same network, then
  open **Devices** and choose **Refresh**.
- **A Sonos speaker will not connect:** choose it while it is awake. The app
  first wakes its existing session and asks for an extra Spotify approval only
  when the speaker has actually signed out. If it is already playing, the app
  recognizes its current track without reconnecting it.
- **Spotify reports a temporary limit:** wait for the time shown in the app,
  then try again.

## Remove

Log out from **Settings** first, then remove the plugin from Omarchy's plugin
manager. The small playback package is kept because another Spotify client may
also use it; inactive local setup files are harmless.

For complete runtime cleanup, see the [technical notes](docs/TECHNICAL.md#complete-removal).

## Known limits

- Spotify requires Premium for playback control and Spotify Connect transfers.
- Some playlists that you do not own may not expose their contents, but can
  still be played as a playlist. Spotify must expose the contents before the
  app can turn one into your own copy.
- Speaker availability is ultimately controlled by Spotify and the device.
- Spotify marks some players, including Sonos in some states, as restricted.
  For a locally discovered Sonos, the app uses its LAN controls for transport,
  seeking, playback mode, and volume. Other restricted-device actions remain
  subject to Spotify and the speaker.
- The local playback component is community-maintained and is not an official
  Spotify desktop client.

Omarchy Spotify is an independent project and is not affiliated with Spotify.
Spotify is a trademark of Spotify AB.

Technical architecture, development setup, and verification are documented in
[Technical notes](docs/TECHNICAL.md). Resource measurements are in
[Benchmark](docs/BENCHMARK.md).

Licensed under the [MIT License](LICENSE).
