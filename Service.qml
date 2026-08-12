import QtQuick
import Quickshell
import Quickshell.Services.Mpris

import "Api.js" as Api

// Shared state for the bar widget and the lazy full panel. There is no
// heartbeat: MPRIS supplies playback changes, Spotify requests happen only
// after a user action, and the idle timer runs only while spotifyd is active.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "quickshell.spotify"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""

  property var settings: ({
    deviceName: "Omarchy Spotify",
    idleShutdownMinutes: 15,
    showTrackTitle: "On",
    audioQuality: "320 kbps",
    searchHistory: "[]",
    sessionState: "{}"
  })

  readonly property string deviceName: String(settings.deviceName || "Omarchy Spotify").trim() || "Omarchy Spotify"
  readonly property int idleShutdownMinutes: Math.max(0, Math.min(1440,
    Math.floor(Number(settings.idleShutdownMinutes) || 0)))
  readonly property bool showTrackTitle: String(settings.showTrackTitle || "On") !== "Off"
  readonly property int bitrateKbps: String(settings.audioQuality || "320 kbps").indexOf("96") === 0
    ? 96 : (String(settings.audioQuality || "320 kbps").indexOf("160") === 0 ? 160 : 320)
  readonly property string audioQuality: bitrateKbps + " kbps"
  readonly property var searchHistory: Api.parseStringList(settings.searchHistory, 12)
  readonly property var sessionState: {
    var parsed = Api.parseJson(String(settings.sessionState || "{}"), ({}))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
  }

  readonly property alias auth: authManager
  readonly property alias api: spotifyApi
  readonly property alias daemon: daemonManager
  readonly property bool fullyConnected: daemonManager.playbackReady
    && authManager.loggedIn && daemonManager.credentialsAvailable
  readonly property bool loginBusy: daemonManager.setupBusy
    || authManager.loginBusy
    || authManager.sessionBusy || !authManager.sessionChecked
    || daemonManager.authenticationBusy || daemonManager.credentialsClearBusy
    || !daemonManager.credentialsChecked || !daemonManager.requirementsChecked
  readonly property string loginProgress: daemonManager.setupBusy
    ? "Preparing playback on this computer"
    : (daemonManager.credentialsClearBusy
    ? "Signing out"
    : (authManager.loginBusy
      ? "Approve Spotify access in your browser"
      : (authManager.sessionBusy || !authManager.sessionChecked
        ? "Checking your saved Spotify session"
        : (!daemonManager.requirementsChecked || !daemonManager.credentialsChecked
          ? "Checking local playback"
          : (daemonManager.authenticationBusy
            ? "Approve local playback in your browser"
            : (fullyConnected ? "Connected to Spotify" : "Ready to connect"))))))

  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: spotifydPlayer()
  readonly property bool hasPlayer: activePlayer !== null
  readonly property bool hasMedia: hasPlayer && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool playing: hasPlayer && activePlayer.isPlaying
  readonly property int playbackState: hasPlayer
    ? activePlayer.playbackState : MprisPlaybackState.Stopped
  readonly property string title: hasPlayer ? String(activePlayer.trackTitle || "") : ""
  readonly property string artist: hasPlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string album: hasPlayer ? String(activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: hasPlayer ? String(activePlayer.trackArtUrl || "") : ""
  readonly property real positionSeconds: hasPlayer && activePlayer.positionSupported
    ? Math.max(0, Number(activePlayer.position) || 0) : 0
  readonly property real lengthSeconds: hasPlayer && activePlayer.lengthSupported
    ? Math.max(0, Number(activePlayer.length) || 0) : 0
  readonly property real volume: hasPlayer && activePlayer.volumeSupported
    ? Math.max(0, Math.min(1, Number(activePlayer.volume) || 0)) : 0
  readonly property bool shuffle: hasPlayer && activePlayer.shuffleSupported
    ? activePlayer.shuffle === true : false
  readonly property string repeatMode: mprisRepeatMode()
  readonly property string currentUri: metadataString("xesam:url")
  readonly property string currentExternalUrl: spotifyWebUrl(currentUri)

  property var playlists: []
  property string playlistsNext: ""
  property var savedTracks: []
  property string savedTracksNext: ""
  property var savedAlbums: []
  property string savedAlbumsNext: ""
  property var followedArtists: []
  property string followedArtistsNext: ""
  property var savedShows: []
  property string savedShowsNext: ""
  property var savedEpisodes: []
  property string savedEpisodesNext: ""
  property var savedAudiobooks: []
  property string savedAudiobooksNext: ""
  property var playlistItems: []
  property string playlistItemsNext: ""
  property var selectedPlaylist: null
  property string currentUserId: ""
  property string currentUserName: ""
  property var queue: []
  property var devices: []
  property var apiDevices: []
  property var pendingDeviceLoadCallback: null
  property string pendingDeviceLoadError: ""
  property string selectedDeviceId: ""
  property bool selectedDeviceExplicit: false
  property string localDeviceId: ""
  property string localRuntimeDeviceName: "Omarchy Spotify"
  property string searchQuery: ""
  property var searchGroups: Api.searchGroups({}, 128)
  property var savedUris: ({})

  property var recentTracks: []
  property var topTracks: []
  property var topArtists: []
  property bool homeLoaded: false
  property int homeRequestsPending: 0
  readonly property bool homeLoading: homeRequestsPending > 0

  property var discoverPlaylists: []
  property var discoverCandidates: []
  property bool discoverLoaded: false
  property int discoverRequestsPending: 0
  property int discoverRequestsFailed: 0
  property int discoverSerial: 0
  property string discoverMessage: ""
  readonly property bool discoverLoading: discoverRequestsPending > 0

  property var detailItem: null
  property var detailItems: []
  property string detailNext: ""
  property bool detailLoading: false
  property string detailMessage: ""
  property int detailSerial: 0
  property var artistAlbums: []
  property string artistAlbumsNext: ""
  property bool artistAlbumsLoading: false
  property var artistSongs: []
  property string artistSongsNext: ""
  property bool artistSongsLoading: false
  property var artistThisIsPlaylist: null
  property bool artistThisIsLoading: false
  property string artistCatalogQuery: ""
  property int artistCatalogSerial: 0

  property bool playlistActionBusy: false
  property bool playlistConversionBusy: false
  property string pendingPlaylistName: ""

  property string sleepMode: "off"
  property double sleepEndsAt: 0
  property string sleepTrackUri: ""
  readonly property bool sleepActive: sleepMode !== "off"
  property int sleepRemainingSeconds: 0

  property string activeView: "search"
  property bool playlistsLoaded: false
  property bool savedTracksLoaded: false
  property bool savedAlbumsLoaded: false
  property bool followedArtistsLoaded: false
  property bool savedShowsLoaded: false
  property bool savedEpisodesLoaded: false
  property bool savedAudiobooksLoaded: false
  property bool queueLoaded: false
  property bool devicesLoaded: false
  property bool playlistsLoading: false
  property bool savedTracksLoading: false
  property bool savedAlbumsLoading: false
  property bool followedArtistsLoading: false
  property bool savedShowsLoading: false
  property bool savedEpisodesLoading: false
  property bool savedAudiobooksLoading: false
  property bool playlistItemsLoading: false
  property bool queueLoading: false
  property bool devicesLoading: false
  property bool searchLoading: false
  property string lastError: ""
  property string statusMessage: ""

  property int dataSerial: 0
  property var visibleSurfaces: ({})
  readonly property bool uiVisible: Object.keys(visibleSurfaces).length > 0
  property double lastActivityAt: Date.now()
  property var pendingPlayback: null
  property var pendingPlaybackBody: null
  property string pendingPlaybackMessage: ""
  property var pendingPlaybackRadio: null
  property int pendingPlaybackSerial: 0
  property int radioSerial: 0
  property var lastRadioPlaylist: null
  property bool radioContextSelected: false
  readonly property bool lastRadioPlaying: !!lastRadioPlaylist
    && radioContextSelected && playing
  property bool localActivationRequested: false
  property int deviceProbeAttempts: 0
  property bool loginFlowActive: false
  property string pendingConnectDeviceId: ""
  property int connectActivationAttempts: 0

  readonly property bool deviceActivationBusy: spotifyConnectManager.activating

  readonly property int cacheLimit: 200

  signal operationFailed(string reason)
  signal radioPlaylistReady(var playlist)

  function defaults() {
    var fallback = {
      deviceName: "Omarchy Spotify",
      idleShutdownMinutes: 15,
      showTrackTitle: "On",
      audioQuality: "320 kbps",
      searchHistory: "[]",
      sessionState: "{}"
    }
    var source = manifest && manifest.barWidget && manifest.barWidget.defaults
      ? manifest.barWidget.defaults : null
    if (!source) return fallback
    for (var key in source) fallback[key] = source[key]
    return fallback
  }

  function normalizedSettings(values) {
    var next = defaults()
    var source = values || {}
    if (source.deviceName !== undefined) next.deviceName = source.deviceName
    if (source.idleShutdownMinutes !== undefined)
      next.idleShutdownMinutes = source.idleShutdownMinutes
    if (source.showTrackTitle !== undefined) next.showTrackTitle = source.showTrackTitle
    if (source.audioQuality !== undefined) next.audioQuality = source.audioQuality
    if (source.searchHistory !== undefined)
      next.searchHistory = JSON.stringify(Api.parseStringList(source.searchHistory, 12))
    if (source.sessionState !== undefined) {
      var session = source.sessionState
      if (typeof session === "string") session = Api.parseJson(session, ({}))
      if (!session || typeof session !== "object" || Array.isArray(session)) session = ({})
      var encodedSession = JSON.stringify(session)
      next.sessionState = encodedSession.length <= 16000 ? encodedSession : "{}"
    }
    next.deviceName = String(next.deviceName || "Omarchy Spotify").trim() || "Omarchy Spotify"
    next.idleShutdownMinutes = Math.max(0, Math.min(1440,
      Math.floor(Number(next.idleShutdownMinutes) || 0)))
    next.showTrackTitle = String(next.showTrackTitle || "On") === "Off" ? "Off" : "On"
    var quality = String(next.audioQuality || "320 kbps")
    next.audioQuality = quality.indexOf("96") === 0 ? "96 kbps"
      : (quality.indexOf("160") === 0 ? "160 kbps" : "320 kbps")
    return next
  }

  function relabelLocalDevices(source, previousName, nextName) {
    var rows = Array.isArray(source) ? source : []
    var result = []
    for (var i = 0; i < rows.length; i++) {
      var item = rows[i]
      if (!item) continue
      var local = item.local === true || Api.isLocalPlaybackDevice(item,
        previousName, localRuntimeDeviceName, localDeviceId)
      if (!local) {
        result.push(item)
        continue
      }
      var copy = ({})
      for (var key in item) copy[key] = item[key]
      copy.name = nextName
      copy.local = true
      result.push(copy)
    }
    return result
  }

  function applySettings(values) {
    var previousDeviceName = deviceName
    var next = normalizedSettings(values)
    if (JSON.stringify(next) !== JSON.stringify(settings)) settings = next
    if (previousDeviceName !== next.deviceName) {
      if (daemonManager.running && !localRuntimeDeviceName)
        localRuntimeDeviceName = previousDeviceName
      apiDevices = relabelLocalDevices(apiDevices, previousDeviceName, next.deviceName)
      devices = relabelLocalDevices(devices, previousDeviceName, next.deviceName)
    }
  }

  function persistSettings(values) {
    var merged = ({})
    for (var existing in settings) merged[existing] = settings[existing]
    var source = values || {}
    for (var key in source) merged[key] = source[key]
    var next = normalizedSettings(merged)
    applySettings(next)
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(pluginId, next)
  }

  function persistSession(values) {
    persistSettings({ sessionState: values || ({}) })
  }

  function rememberSearch(term) {
    var next = Api.touchHistory(searchHistory, term, 12)
    if (JSON.stringify(next) !== JSON.stringify(searchHistory))
      persistSettings({ searchHistory: next })
  }

  function clearSearchHistory() {
    persistSettings({ searchHistory: [] })
  }

  function configuredEntry() {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    if (!config) return null
    var layout = config.bar && config.bar.layout ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var rows = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
        for (var i = 0; i < rows.length; i++)
          if (rows[i] && String(rows[i].id || "") === pluginId) return rows[i]
      }
    }
    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (var p = 0; p < plugins.length; p++)
      if (plugins[p] && String(plugins[p].id || "") === pluginId) return plugins[p]
    return null
  }

  function syncSettings() {
    applySettings(configuredEntry() || {})
  }

  function isSpotifyd(player) {
    if (!player) return false
    var identity = [player.dbusName, player.desktopEntry, player.identity]
      .join(" ").toLowerCase()
    return identity.indexOf("spotifyd") !== -1
      || identity.indexOf("librespot") !== -1
  }

  function spotifydPlayer() {
    var fallback = null
    for (var i = 0; i < mprisPlayers.length; i++) {
      var player = mprisPlayers[i]
      if (!isSpotifyd(player)) continue
      if (player.isPlaying) return player
      if (!fallback) fallback = player
    }
    return fallback
  }

  function metadataString(key) {
    var metadata = activePlayer && activePlayer.metadata ? activePlayer.metadata : null
    return metadata && metadata[key] !== undefined ? String(metadata[key]) : ""
  }

  function spotifyWebUrl(uri) {
    var value = String(uri || "")
    var match = value.match(/^spotify:(track|album|artist|playlist|episode|show|audiobook|chapter):([^:]+)$/)
    return match ? "https://open.spotify.com/" + match[1] + "/" + match[2]
      : (value.indexOf("https://open.spotify.com/") === 0 ? value : "")
  }

  function mprisRepeatMode() {
    if (!hasPlayer || !activePlayer.loopSupported) return "off"
    if (activePlayer.loopState === MprisLoopState.Track) return "track"
    if (activePlayer.loopState === MprisLoopState.Playlist) return "context"
    return "off"
  }

  function safeError(reason) {
    return Api.redact(String(reason || "Spotify operation failed"))
  }

  function fail(reason) {
    statusClearTimer.stop()
    lastError = safeError(reason)
    statusMessage = ""
    operationFailed(lastError)
  }

  function succeed(message) {
    lastError = ""
    statusMessage = String(message || "")
    if (statusMessage) statusClearTimer.restart()
    else statusClearTimer.stop()
  }

  function noteActivity() {
    lastActivityAt = Date.now()
  }

  function setUiVisible(key, value) {
    var name = String(key || "surface")
    var next = ({})
    for (var oldKey in visibleSurfaces)
      if (oldKey !== name && visibleSurfaces[oldKey]) next[oldKey] = true
    if (value) next[name] = true
    visibleSurfaces = next
    if (value) noteActivity()
  }

  function refreshPosition() {
    if (activePlayer && activePlayer.positionSupported) activePlayer.positionChanged()
  }

  function apiAction(method, path, query, body, successText, callback) {
    noteActivity()
    spotifyApi.request(method, path, query, body, function(status, payload, error) {
      if (error) {
        root.fail(error)
        if (typeof callback === "function") callback(false, payload)
        return
      }
      root.succeed(successText)
      if (typeof callback === "function") callback(true, payload)
    })
  }

  function normalizedView(view) {
    var value = String(view || "search")
    return ["home", "discover", "search", "library", "playlists", "detail", "queue", "devices", "setup"].indexOf(value) >= 0
      ? value : "search"
  }

  // Fetch only the dataset represented by the visible page. An empty but
  // successfully loaded list is tracked separately so revisiting it causes no
  // network request; the explicit refresh control can still force one.
  function openView(view, force) {
    activeView = normalizedView(view)
    if (!authManager.loggedIn && !authManager.tokenIsFresh()) return
    if (activeView === "home" && (force || !homeLoaded))
      loadHome()
    else if (activeView === "discover" && (force || !discoverLoaded))
      loadDiscover()
    else if (activeView === "search" && force && searchQuery)
      search(searchQuery)
    else if (activeView === "library" && (force || !savedTracksLoaded))
      loadSavedTracks(false)
    else if (activeView === "playlists" && (force || !playlistsLoaded))
      loadPlaylists(false)
    else if (activeView === "queue" && (force || !queueLoaded))
      loadQueue()
    else if (activeView === "devices") {
      loadDevices(null, undefined, true)
    }
  }

  function refreshView(view) {
    openView(view, true)
  }

  function loadSidebarPlaylists() {
    if (!playlistsLoaded && !playlistsLoading) loadPlaylists(false)
  }

  function loadProfile() {
    if (currentUserId) return
    spotifyApi.request("GET", "/me", null, null, function(status, payload, error) {
      if (error || !payload) return
      root.currentUserId = String(payload.id || "")
      root.currentUserName = String(payload.display_name || "")
    })
  }

  function playlistById(id) {
    var key = String(id || "")
    for (var i = 0; i < playlists.length; i++)
      if (String(playlists[i].id || "") === key) return playlists[i]
    return null
  }

  function playlistEditable(item) {
    if (!item || item.type !== "playlist") return false
    return item.collaborative === true
      || playlistOwned(item)
  }

  function playlistOwned(item) {
    return !!item && item.type === "playlist" && !!currentUserId
      && String(item.ownerId || "") === currentUserId
  }

  function playlistContentsAvailable(item) {
    return !!item && item.type === "playlist" && !!item.id
  }

  function editablePlaylists() {
    var result = []
    for (var i = 0; i < playlists.length; i++)
      if (playlistEditable(playlists[i])) result.push(playlists[i])
    return result
  }

  function updatePlaylistSnapshot(id, snapshotId) {
    var key = String(id || "")
    var snapshot = String(snapshotId || "")
    if (!key || !snapshot) return
    function updated(item) {
      if (!item || String(item.id || "") !== key) return item
      var copy = ({})
      for (var propertyName in item) copy[propertyName] = item[propertyName]
      copy.snapshotId = snapshot
      return copy
    }
    var next = []
    for (var i = 0; i < playlists.length; i++) next.push(updated(playlists[i]))
    playlists = next
    selectedPlaylist = updated(selectedPlaylist)
    if (detailItem && detailItem.type === "playlist") detailItem = updated(detailItem)
  }

  function sidebarPlaylists() {
    return playlists
  }

  function validRadioPlaylist(value) {
    return !!value && value.type === "playlist" && !!value.id && !!value.uri
  }

  function sameRadioPlaylist(left, right) {
    if (!validRadioPlaylist(left) || !validRadioPlaylist(right)) return false
    return String(left.id) === String(right.id)
      || String(left.uri) === String(right.uri)
  }

  function restoreLastRadioPlaylist(value) {
    if (!lastRadioPlaylist && validRadioPlaylist(value))
      lastRadioPlaylist = value
  }

  function rememberRadioPlaylist(value) {
    if (!validRadioPlaylist(value)) return
    lastRadioPlaylist = value
    radioContextSelected = false
    var state = ({})
    for (var key in sessionState) state[key] = sessionState[key]
    state.lastRadioPlaylist = value
    persistSession(state)
  }

  function radioPlaylistForPlayback(item, contextUri, explicitRadio) {
    if (validRadioPlaylist(explicitRadio)) return explicitRadio
    if (!validRadioPlaylist(lastRadioPlaylist)) return null
    if (sameRadioPlaylist(item, lastRadioPlaylist)
        || String(contextUri || "") === String(lastRadioPlaylist.uri))
      return lastRadioPlaylist
    return null
  }

  function verifyRadioPlaybackContext() {
    if (!validRadioPlaylist(lastRadioPlaylist)) {
      radioContextSelected = false
      return
    }
    var expectedSerial = radioSerial
    var expectedPlaylist = lastRadioPlaylist
    spotifyApi.request("GET", "/me/player", null, null,
      function(status, payload, error) {
        if (error || expectedSerial !== root.radioSerial
            || !root.sameRadioPlaylist(expectedPlaylist, root.lastRadioPlaylist)) return
        var context = payload && payload.context ? payload.context : null
        root.radioContextSelected = !!context
          && (String(context.uri || "") === String(expectedPlaylist.uri)
            || (context.type === "playlist"
              && String(context.href || "").indexOf("/playlists/" + expectedPlaylist.id) >= 0))
      })
  }

  // Restore the keyring-backed session only when a Spotify API surface is
  // actually opened. This avoids a network request when the widget is merely
  // sitting on the bar and local MPRIS controls are sufficient.
  function activate(view) {
    activeView = normalizedView(view)
    authManager.withAccessToken(function(token, error) {
      if (token) {
        root.loadProfile()
        root.loadSidebarPlaylists()
        root.verifyRadioPlaybackContext()
        root.openView(root.activeView, false)
      }
      else if (error && error !== "Log in to Spotify first") root.fail(error)
    })
  }

  function loadPlaylists(append, callback, serial) {
    if (playlistsLoading) {
      if (typeof callback === "function") callback()
      return
    }
    var path = append ? playlistsNext : "/me/playlists"
    if (!path) {
      if (typeof callback === "function") callback()
      return
    }
    var expected = serial === undefined ? dataSerial : serial
    playlistsLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 30 }, null,
      function(status, payload, error) {
        root.playlistsLoading = false
        if (expected !== root.dataSerial) return
        if (error) root.fail(error)
        else {
          var page = Api.normalizePage(payload, function(value) {
            return Api.normalizePlaylist(value, 96)
          })
          root.playlists = (append ? Api.mergeUnique(root.playlists, page.items) : page.items)
            .slice(0, root.cacheLimit)
          root.playlistsNext = root.playlists.length >= root.cacheLimit ? "" : page.next
          root.playlistsLoaded = true
          root.checkSavedItems(page.items)
          if (root.discoverLoaded || root.discoverLoading)
            root.mergeDiscoverCandidates(page.items)
        }
        if (typeof callback === "function") callback()
      })
  }

  function loadMorePlaylists() {
    loadPlaylists(true)
  }

  function loadSavedTracks(append, callback, serial) {
    if (savedTracksLoading) {
      if (typeof callback === "function") callback()
      return
    }
    var path = append ? savedTracksNext : "/me/tracks"
    if (!path) {
      if (typeof callback === "function") callback()
      return
    }
    var expected = serial === undefined ? dataSerial : serial
    savedTracksLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 30 }, null,
      function(status, payload, error) {
        root.savedTracksLoading = false
        if (expected !== root.dataSerial) return
        if (error) root.fail(error)
        else {
          var page = Api.normalizePage(payload, function(value) {
            return Api.normalizeTrack(value, 96)
          })
          root.savedTracks = (append ? Api.mergeUnique(root.savedTracks, page.items) : page.items)
            .slice(0, root.cacheLimit)
          root.savedTracksNext = root.savedTracks.length >= root.cacheLimit ? "" : page.next
          root.savedTracksLoaded = true
          root.markItemsSaved(page.items, true)
        }
        if (typeof callback === "function") callback()
      })
  }

  function loadMoreSavedTracks() {
    loadSavedTracks(true)
  }

  function setSavedState(uri, value) {
    var key = String(uri || "")
    if (!key) return
    var next = ({})
    for (var existing in savedUris) next[existing] = savedUris[existing]
    next[key] = value === true
    savedUris = next
  }

  function markItemsSaved(items, value) {
    var rows = Array.isArray(items) ? items : []
    var next = ({})
    for (var existing in savedUris) next[existing] = savedUris[existing]
    for (var i = 0; i < rows.length; i++)
      if (rows[i] && rows[i].uri) next[String(rows[i].uri)] = value !== false
    savedUris = next
  }

  function isSaved(item) {
    return !!item && !!item.uri && savedUris[String(item.uri)] === true
  }

  function checkSavedItems(items) {
    var rows = Array.isArray(items) ? items : []
    var uris = []
    var seen = ({})
    for (var i = 0; i < rows.length; i++) {
      var uri = String((rows[i] && rows[i].uri) || "")
      if (!uri || seen[uri]) continue
      seen[uri] = true
      uris.push(uri)
    }
    for (var start = 0; start < uris.length; start += 40) {
      (function(chunk) {
        spotifyApi.request("GET", "/me/library/contains", { uris: chunk }, null,
          function(status, payload, error) {
            if (error || !Array.isArray(payload)) return
            var next = ({})
            for (var old in root.savedUris) next[old] = root.savedUris[old]
            for (var p = 0; p < chunk.length; p++) next[chunk[p]] = payload[p] === true
            root.savedUris = next
          })
      })(uris.slice(start, start + 40))
    }
  }

  function toggleSaved(item) {
    if (!item || !item.uri || item.type === "chapter") return
    var removing = isSaved(item)
    apiAction(removing ? "DELETE" : "PUT", "/me/library", { uris: item.uri }, null,
      removing ? "Removed from your library" : "Saved to your library",
      function(ok) {
        if (!ok) return
        root.setSavedState(item.uri, !removing)
        if (item.type === "track" && root.savedTracksLoaded) root.loadSavedTracks(false)
        else if (item.type === "album" && root.savedAlbumsLoaded) root.loadSavedAlbums(false)
        else if (item.type === "artist" && root.followedArtistsLoaded) root.loadFollowedArtists(false)
        else if (item.type === "show" && root.savedShowsLoaded) root.loadSavedShows(false)
        else if (item.type === "episode" && root.savedEpisodesLoaded)
          root.loadSavedEpisodes(false)
        else if (item.type === "audiobook" && root.savedAudiobooksLoaded)
          root.loadSavedAudiobooks(false)
        if (item.type === "playlist" && root.playlistsLoaded) root.loadPlaylists(false)
      })
  }

  function loadSavedAlbums(append) {
    if (savedAlbumsLoading) return
    var path = append ? savedAlbumsNext : "/me/albums"
    if (!path) return
    savedAlbumsLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 30 }, null,
      function(status, payload, error) {
        root.savedAlbumsLoading = false
        if (error) { root.fail(error); return }
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeContext(value, 96)
        })
        root.savedAlbums = (append ? Api.mergeUnique(root.savedAlbums, page.items) : page.items)
          .slice(0, root.cacheLimit)
        root.savedAlbumsNext = root.savedAlbums.length >= root.cacheLimit ? "" : page.next
        root.savedAlbumsLoaded = true
        root.markItemsSaved(page.items, true)
      })
  }

  function loadFollowedArtists(append) {
    if (followedArtistsLoading) return
    var path = append ? followedArtistsNext : "/me/following"
    if (!path) return
    followedArtistsLoading = true
    spotifyApi.request("GET", path, append ? null : { type: "artist", limit: 30 }, null,
      function(status, payload, error) {
        root.followedArtistsLoading = false
        if (error) { root.fail(error); return }
        var page = Api.normalizeCursorPage(payload && payload.artists, function(value) {
          return Api.normalizeContext(value, 96)
        })
        root.followedArtists = (append
          ? Api.mergeUnique(root.followedArtists, page.items) : page.items).slice(0, root.cacheLimit)
        root.followedArtistsNext = root.followedArtists.length >= root.cacheLimit ? "" : page.next
        root.followedArtistsLoaded = true
        root.markItemsSaved(page.items, true)
      })
  }

  function loadSavedShows(append) {
    if (savedShowsLoading) return
    var path = append ? savedShowsNext : "/me/shows"
    if (!path) return
    savedShowsLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 30 }, null,
      function(status, payload, error) {
        root.savedShowsLoading = false
        if (error) { root.fail(error); return }
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeContext(value, 96)
        })
        root.savedShows = (append ? Api.mergeUnique(root.savedShows, page.items) : page.items)
          .slice(0, root.cacheLimit)
        root.savedShowsNext = root.savedShows.length >= root.cacheLimit ? "" : page.next
        root.savedShowsLoaded = true
        root.markItemsSaved(page.items, true)
      })
  }

  function loadSavedEpisodes(append) {
    if (savedEpisodesLoading) return
    var path = append ? savedEpisodesNext : "/me/episodes"
    if (!path) return
    savedEpisodesLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 30 }, null,
      function(status, payload, error) {
        root.savedEpisodesLoading = false
        if (error) { root.fail(error); return }
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeTrack(value, 96)
        })
        root.savedEpisodes = (append
          ? Api.mergeUnique(root.savedEpisodes, page.items) : page.items).slice(0, root.cacheLimit)
        root.savedEpisodesNext = root.savedEpisodes.length >= root.cacheLimit ? "" : page.next
        root.savedEpisodesLoaded = true
        root.markItemsSaved(page.items, true)
      })
  }

  function loadSavedAudiobooks(append) {
    if (savedAudiobooksLoading) return
    var path = append ? savedAudiobooksNext : "/me/audiobooks"
    if (!path) return
    savedAudiobooksLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 30 }, null,
      function(status, payload, error) {
        root.savedAudiobooksLoading = false
        if (error) { root.fail(error); return }
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeContext(value, 96)
        })
        root.savedAudiobooks = (append
          ? Api.mergeUnique(root.savedAudiobooks, page.items) : page.items).slice(0, root.cacheLimit)
        root.savedAudiobooksNext = root.savedAudiobooks.length >= root.cacheLimit ? "" : page.next
        root.savedAudiobooksLoaded = true
        root.markItemsSaved(page.items, true)
      })
  }

  function libraryItems(kind) {
    var value = String(kind || "tracks")
    if (value === "albums") return savedAlbums
    if (value === "artists") return followedArtists
    if (value === "shows") return savedShows
    if (value === "episodes") return savedEpisodes
    if (value === "audiobooks") return savedAudiobooks
    return savedTracks
  }

  function libraryNext(kind) {
    var value = String(kind || "tracks")
    if (value === "albums") return savedAlbumsNext
    if (value === "artists") return followedArtistsNext
    if (value === "shows") return savedShowsNext
    if (value === "episodes") return savedEpisodesNext
    if (value === "audiobooks") return savedAudiobooksNext
    return savedTracksNext
  }

  function libraryLoading(kind) {
    var value = String(kind || "tracks")
    if (value === "albums") return savedAlbumsLoading
    if (value === "artists") return followedArtistsLoading
    if (value === "shows") return savedShowsLoading
    if (value === "episodes") return savedEpisodesLoading
    if (value === "audiobooks") return savedAudiobooksLoading
    return savedTracksLoading
  }

  function libraryLoaded(kind) {
    var value = String(kind || "tracks")
    if (value === "albums") return savedAlbumsLoaded
    if (value === "artists") return followedArtistsLoaded
    if (value === "shows") return savedShowsLoaded
    if (value === "episodes") return savedEpisodesLoaded
    if (value === "audiobooks") return savedAudiobooksLoaded
    return savedTracksLoaded
  }

  function loadLibrary(kind, append, force) {
    var value = String(kind || "tracks")
    if (append !== true && force !== true && libraryLoaded(value)) return
    if (value === "albums") loadSavedAlbums(append === true)
    else if (value === "artists") loadFollowedArtists(append === true)
    else if (value === "shows") loadSavedShows(append === true)
    else if (value === "episodes") loadSavedEpisodes(append === true)
    else if (value === "audiobooks") loadSavedAudiobooks(append === true)
    else loadSavedTracks(append === true)
  }

  function openPlaylist(playlist) {
    if (!playlist || !playlist.id) return
    succeed("")
    selectedPlaylist = playlist
    playlistItems = []
    playlistItemsNext = ""
    loadPlaylistItems(false)
  }

  function loadPlaylistItems(append) {
    if (!selectedPlaylist || !selectedPlaylist.id || playlistItemsLoading) return
    var path = append ? playlistItemsNext
      : "/playlists/" + encodeURIComponent(String(selectedPlaylist.id)) + "/items"
    if (!path) return
    var playlistId = String(selectedPlaylist.id)
    playlistItemsLoading = true
    spotifyApi.request("GET", path, append ? null : { limit: 50 }, null,
      function(status, payload, error) {
        root.playlistItemsLoading = false
        if (!root.selectedPlaylist || String(root.selectedPlaylist.id) !== playlistId) return
        if (error) root.fail(error)
        else {
          var page = Api.normalizePage(payload, function(value) {
            return Api.normalizeTrack(value, 96)
          })
          root.playlistItems = (append ? Api.mergeUnique(root.playlistItems, page.items) : page.items)
            .slice(0, root.cacheLimit)
          root.playlistItemsNext = root.playlistItems.length >= root.cacheLimit ? "" : page.next
        }
      })
  }

  function loadMorePlaylistItems() {
    loadPlaylistItems(true)
  }

  function createPlaylist(name, callback) {
    var normalized = String(name || "").trim()
    if (!normalized || playlistActionBusy) return
    playlistActionBusy = true
    spotifyApi.request("POST", "/me/playlists", null, {
      name: normalized.slice(0, 100),
      "public": false,
      description: "Created with Music for Spotify on Omarchy"
    }, function(status, payload, error) {
      root.playlistActionBusy = false
      if (error) { root.fail(error); return }
      var playlist = Api.normalizePlaylist(payload, 96)
      if (playlist) {
        root.playlists = [playlist].concat(root.playlists)
        root.setSavedState(playlist.uri, true)
        root.succeed("Playlist created")
        if (typeof callback === "function") callback(playlist)
      }
    })
  }

  function addItemToPlaylist(item, playlist) {
    if (!item || ["track", "episode"].indexOf(item.type) < 0 || !item.uri
        || !playlist || !playlist.id
        || playlistActionBusy) return
    playlistActionBusy = true
    spotifyApi.request("POST", "/playlists/" + encodeURIComponent(String(playlist.id)) + "/items",
      null, { uris: [item.uri] }, function(status, payload, error) {
        root.playlistActionBusy = false
        if (error) { root.fail(error); return }
        root.updatePlaylistSnapshot(playlist.id, payload && payload.snapshot_id)
        root.succeed("Added to " + String(playlist.name || "playlist"))
        if (root.selectedPlaylist && root.selectedPlaylist.id === playlist.id)
          root.loadPlaylistItems(false)
        if (root.detailItem && root.detailItem.id === playlist.id) root.openDetail(root.detailItem)
      })
  }

  function registerPlaylistCopy(playlist) {
    if (!playlist) return
    var next = [playlist]
    for (var i = 0; i < playlists.length; i++)
      if (String(playlists[i].id || "") !== String(playlist.id || ""))
        next.push(playlists[i])
    playlists = next
    setSavedState(playlist.uri, true)
  }

  function finishPlaylistConversion(error) {
    playlistConversionBusy = false
    playlistActionBusy = false
    statusMessage = ""
    if (error) fail(error)
  }

  function collectPlaylistForCopy(playlist, path, collected, expected, callback) {
    var first = !path
    var requestPath = path || "/playlists/" + encodeURIComponent(String(playlist.id)) + "/items"
    spotifyApi.request("GET", requestPath, first ? { limit: 50 } : null, null,
      function(status, payload, error) {
        if (expected !== root.dataSerial) return
        if (error) { callback([], error); return }
        if (!payload || !Array.isArray(payload.items)) {
          callback([], "Spotify does not make this playlist's songs available to copy. The original was left untouched.")
          return
        }
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeTrack(value, 96)
        })
        var combined = collected.concat(page.items)
        if (page.next && combined.length < 10000) {
          root.collectPlaylistForCopy(playlist, page.next, combined, expected, callback)
          return
        }
        if (page.next) {
          callback([], "This playlist is too large to copy safely")
          return
        }
        callback(combined, "")
      })
  }

  function addPlaylistCopyBatches(playlist, uris, offset, expected, callback) {
    if (expected !== dataSerial) return
    if (offset >= uris.length) { callback(""); return }
    var batch = uris.slice(offset, Math.min(offset + 100, uris.length))
    spotifyApi.request("POST", "/playlists/" + encodeURIComponent(String(playlist.id)) + "/items",
      null, { uris: batch }, function(status, payload, error) {
        if (expected !== root.dataSerial) return
        if (error) { callback(error); return }
        root.updatePlaylistSnapshot(playlist.id, payload && payload.snapshot_id)
        root.addPlaylistCopyBatches(playlist, uris, offset + batch.length, expected, callback)
      })
  }

  function removeOriginalAfterCopy(original, copy, expected, callback) {
    spotifyApi.request("DELETE", "/me/library", { uris: original.uri }, null,
      function(status, payload, error) {
        if (expected !== root.dataSerial) return
        if (error) {
          root.finishPlaylistConversion("Your copy is ready, but Spotify could not remove the original from your library")
          return
        }
        var next = []
        for (var i = 0; i < root.playlists.length; i++) {
          var candidate = root.playlists[i]
          if (String(candidate.id || "") !== String(original.id || "")) next.push(candidate)
        }
        root.playlists = next
        root.setSavedState(original.uri, false)
        root.finishPlaylistConversion("")
        root.succeed("Your playlist is ready")
        if (typeof callback === "function") callback(copy)
      })
  }

  function makePlaylistYourOwn(playlist, callback) {
    if (!playlist || playlist.type !== "playlist" || !playlist.id || !playlist.uri
        || playlistOwned(playlist) || playlistActionBusy || !currentUserId) return
    var expected = dataSerial
    playlistActionBusy = true
    playlistConversionBusy = true
    lastError = ""
    statusClearTimer.stop()
    statusMessage = "Reading " + String(playlist.name || "playlist") + "…"
    collectPlaylistForCopy(playlist, "", [], expected, function(items, readError) {
      if (readError) { root.finishPlaylistConversion(readError); return }
      var uris = Api.playlistItemUris(items)
      if (Number(playlist.total || 0) > 0 && uris.length === 0) {
        root.finishPlaylistConversion("Spotify does not make this playlist's songs available to copy. The original was left untouched.")
        return
      }
      root.statusMessage = "Creating your playlist…"
      spotifyApi.request("POST", "/me/playlists", null, {
        name: String(playlist.name || "My playlist").slice(0, 100),
        "public": false,
        description: "Your copy, created with Music for Spotify on Omarchy"
      }, function(status, payload, createError) {
        if (expected !== root.dataSerial) return
        if (createError) { root.finishPlaylistConversion(createError); return }
        var copy = Api.normalizePlaylist(payload, 96)
        if (!copy) {
          root.finishPlaylistConversion("Spotify created the playlist, but it could not be opened")
          return
        }
        root.registerPlaylistCopy(copy)
        root.statusMessage = "Copying " + uris.length + (uris.length === 1 ? " item…" : " items…")
        root.addPlaylistCopyBatches(copy, uris, 0, expected, function(copyError) {
          if (copyError) {
            root.finishPlaylistConversion("The new playlist was created, but Spotify stopped before every item was copied. The original was kept.")
            return
          }
          root.statusMessage = "Removing the original from your library…"
          root.removeOriginalAfterCopy(playlist, copy, expected, callback)
        })
      })
    })
  }

  function reloadPlaylist(playlist) {
    if (!playlist) return
    if (selectedPlaylist && selectedPlaylist.id === playlist.id) {
      playlistItems = []
      playlistItemsNext = ""
      loadPlaylistItems(false)
    }
    if (detailItem && detailItem.type === "playlist" && detailItem.id === playlist.id)
      openDetail(detailItem)
  }

  function removePlaylistItem(item, index, playlist) {
    var target = playlist || selectedPlaylist
    if (!item || !item.uri || !playlistEditable(target) || playlistActionBusy) return
    playlistActionBusy = true
    var body = { items: [{ uri: item.uri }] }
    if (target.snapshotId) body.snapshot_id = target.snapshotId
    spotifyApi.request("DELETE", "/playlists/" + encodeURIComponent(String(target.id)) + "/items",
      null, body, function(status, payload, error) {
        root.playlistActionBusy = false
        if (error) { root.fail(error); return }
        root.updatePlaylistSnapshot(target.id, payload && payload.snapshot_id)
        root.succeed("Removed from playlist")
        root.reloadPlaylist(target)
      })
  }

  function movePlaylistItem(index, delta, playlist, count) {
    var target = playlist || selectedPlaylist
    var source = Math.max(0, Math.floor(Number(index) || 0))
    var direction = Number(delta || 0) < 0 ? -1 : 1
    var length = Math.max(0, Math.floor(Number(count) || playlistItems.length))
    if (!playlistEditable(target) || playlistActionBusy || length < 2
        || (direction < 0 && source === 0) || (direction > 0 && source >= length - 1)) return
    var insertBefore = direction < 0 ? source - 1 : source + 2
    playlistActionBusy = true
    var body = { range_start: source, insert_before: insertBefore, range_length: 1 }
    if (target.snapshotId) body.snapshot_id = target.snapshotId
    spotifyApi.request("PUT", "/playlists/" + encodeURIComponent(String(target.id)) + "/items",
      null, body, function(status, payload, error) {
        root.playlistActionBusy = false
        if (error) { root.fail(error); return }
        root.updatePlaylistSnapshot(target.id, payload && payload.snapshot_id)
        root.succeed("Playlist order updated")
        root.reloadPlaylist(target)
      })
  }

  function detailPageFromPayload(payload, type, parent) {
    var container = payload || {}
    if (type === "album") container = payload && payload.tracks ? payload.tracks : container
    else if (type === "playlist")
      container = payload && (payload.items || payload.tracks) ? (payload.items || payload.tracks) : container
    else if (type === "show") container = payload && payload.episodes ? payload.episodes : container
    else if (type === "audiobook")
      container = payload && payload.chapters ? payload.chapters : container
    return Api.normalizePage(container, function(value) {
      return type === "artist" ? Api.normalizeContext(value, 96)
        : Api.normalizeTrack(value, 96, parent)
    })
  }

  function openDetail(item, requestedArtistQuery) {
    if (!item || !item.id || item.kind !== "context") return
    var type = String(item.type || "")
    if (["artist", "album", "playlist", "show", "audiobook"].indexOf(type) < 0) return
    var serial = ++detailSerial
    detailItem = item
    detailItems = []
    detailNext = ""
    detailMessage = ""
    artistCatalogSerial++
    var initialArtistQuery = type === "artist" ? String(requestedArtistQuery || "") : ""
    artistCatalogQuery = initialArtistQuery
    artistAlbums = []
    artistAlbumsNext = ""
    artistAlbumsLoading = false
    artistSongs = []
    artistSongsNext = ""
    artistSongsLoading = false
    artistThisIsPlaylist = null
    artistThisIsLoading = false
    detailLoading = true
    activeView = "detail"
    checkSavedItems([item])

    var metadataPath = "/" + (type === "show" ? "shows" : type === "audiobook"
      ? "audiobooks" : type + "s") + "/" + encodeURIComponent(String(item.id))
    spotifyApi.request("GET", metadataPath, null, null, function(status, payload, error) {
      if (serial !== root.detailSerial) return
      if (error) {
        root.detailLoading = false
        root.fail(error)
        return
      }
      var normalized = Api.normalizeContext(payload, 256)
      if (normalized) root.detailItem = normalized
      var parent = root.detailItem || item
      if (type === "artist") {
        root.loadArtistThisIs(serial, parent)
        root.findArtistMusic(initialArtistQuery, serial, parent)
        return
      }
      var page = root.detailPageFromPayload(payload, type, parent)
      root.detailItems = page.items.slice(0, root.cacheLimit)
      root.detailNext = page.next
      root.detailLoading = false
      root.checkSavedItems(root.detailItems)
      if (type === "playlist" && !payload.items && !payload.tracks)
        root.detailMessage = "Spotify does not expose the contents of this playlist unless you own or collaborate on it. You can still play it as a Spotify context."
    })
  }

  function loadArtistThisIs(expectedDetail, artist) {
    if (!artist || artist.type !== "artist" || !artist.name) return
    artistThisIsPlaylist = null
    artistThisIsLoading = true
    spotifyApi.request("GET", "/search", {
      q: "This Is " + String(artist.name),
      type: "playlist",
      limit: 10
    }, null, function(status, payload, error) {
      if (expectedDetail !== root.detailSerial) return
      root.artistThisIsLoading = false
      if (error) return
      var page = Api.normalizeSearchPage(payload, "playlist", 128)
      root.artistThisIsPlaylist = Api.findThisIsPlaylist(page.items, artist.name)
      if (root.artistThisIsPlaylist) root.checkSavedItems([root.artistThisIsPlaylist])
    })
  }

  function findArtistMusic(query, serial, artist) {
    var parent = artist || detailItem
    if (!parent || parent.type !== "artist" || !parent.name) return
    var expectedDetail = serial === undefined ? detailSerial : serial
    var expectedCatalog = ++artistCatalogSerial
    artistCatalogQuery = String(query || "").trim()
    artistAlbums = []
    artistAlbumsNext = ""
    artistSongs = []
    artistSongsNext = ""
    detailMessage = ""
    detailLoading = true
    requestArtistCatalog("album", false, expectedDetail, expectedCatalog, parent)
    if (artistCatalogQuery) requestArtistCatalog("track", false,
      expectedDetail, expectedCatalog, parent)
    else requestArtistTopSongs(false, expectedDetail, expectedCatalog, parent, 0)
  }

  function requestArtistCatalog(type, append, expectedDetail, expectedCatalog, artist) {
    var albums = type === "album"
    var path = append ? (albums ? artistAlbumsNext : artistSongsNext) : "/search"
    if (!path) return
    if (albums) artistAlbumsLoading = true
    else artistSongsLoading = true
    var query = append ? null : {
      q: Api.catalogSearchText(artist.name, artistCatalogQuery),
      type: type,
      limit: 10
    }
    spotifyApi.request("GET", path, query, null, function(status, payload, error) {
      if (expectedDetail !== root.detailSerial || expectedCatalog !== root.artistCatalogSerial)
        return
      if (albums) root.artistAlbumsLoading = false
      else root.artistSongsLoading = false
      root.detailLoading = root.artistAlbumsLoading || root.artistSongsLoading
      if (error) { root.fail(error); return }
      var page = Api.normalizeSearchPage(payload, type, 96)
      if (albums) {
        root.artistAlbums = (append ? Api.mergeUnique(root.artistAlbums, page.items) : page.items)
          .slice(0, root.cacheLimit)
        root.artistAlbumsNext = root.artistAlbums.length >= root.cacheLimit ? "" : page.next
      } else {
        root.artistSongs = (append ? Api.mergeUnique(root.artistSongs, page.items) : page.items)
          .slice(0, root.cacheLimit)
        root.artistSongsNext = root.artistSongs.length >= root.cacheLimit ? "" : page.next
      }
      root.checkSavedItems(page.items)
    })
  }

  function requestArtistTopSongs(append, expectedDetail, expectedCatalog, artist,
      automaticPage) {
    var path = append ? artistSongsNext : "/search"
    if (!path) return
    var automaticDepth = Math.max(0, Number(automaticPage) || 0)
    artistSongsLoading = true
    var query = append ? null : {
      q: String(artist.name || ""),
      type: "track",
      limit: 10
    }
    spotifyApi.request("GET", path, query, null, function(status, payload, error) {
      if (expectedDetail !== root.detailSerial || expectedCatalog !== root.artistCatalogSerial)
        return
      if (error) {
        root.artistSongsLoading = false
        root.detailLoading = root.artistAlbumsLoading
        root.fail(error)
        return
      }
      var page = Api.normalizeSearchPage(payload, "track", 96)
      var matching = Api.tracksForArtist(page.items, artist)
      root.artistSongs = Api.mergeUnique(append ? root.artistSongs : [], matching).slice(0, 10)
      root.checkSavedItems(matching)
      if (root.artistSongs.length < 10 && page.next && automaticDepth < 5) {
        root.artistSongsNext = page.next
        root.requestArtistTopSongs(true, expectedDetail, expectedCatalog,
          artist, automaticDepth + 1)
        return
      }
      root.artistSongsNext = ""
      root.artistSongsLoading = false
      root.detailLoading = root.artistAlbumsLoading
    })
  }

  function loadMoreArtistAlbums() {
    if (!artistAlbumsNext || artistAlbumsLoading || !detailItem) return
    requestArtistCatalog("album", true, detailSerial, artistCatalogSerial, detailItem)
  }

  function loadMoreArtistSongs() {
    if (!artistSongsNext || artistSongsLoading || !detailItem) return
    requestArtistCatalog("track", true, detailSerial, artistCatalogSerial, detailItem)
  }

  function loadMoreDetail() {
    var path = detailNext
    var parent = detailItem
    if (!path || !parent || detailLoading) return
    var serial = detailSerial
    var type = String(parent.type || "")
    if (type === "artist") return
    detailLoading = true
    spotifyApi.request("GET", path, null, null, function(status, payload, error) {
      if (serial !== root.detailSerial) return
      root.detailLoading = false
      if (error) { root.fail(error); return }
      var page = root.detailPageFromPayload(payload, type, parent)
      root.detailItems = Api.mergeUnique(root.detailItems, page.items).slice(0, root.cacheLimit)
      root.detailNext = root.detailItems.length >= root.cacheLimit ? "" : page.next
      root.checkSavedItems(page.items)
    })
  }

  function currentTrackId() {
    var value = String(currentUri || "")
    var match = value.match(/(?:spotify:track:|open\.spotify\.com\/track\/)([A-Za-z0-9]+)/)
    return match ? match[1] : ""
  }

  function currentContext(kind, callback) {
    var id = currentTrackId()
    if (!id || typeof callback !== "function") return
    spotifyApi.request("GET", "/tracks/" + encodeURIComponent(id), null, null,
      function(status, payload, error) {
        if (error) { root.fail(error); return }
        var track = Api.normalizeTrack(payload, 128)
        if (!track) return
        if (kind === "album" && track.albumItem) callback(track.albumItem)
        else if (kind === "artist" && track.artists.length) callback(track.artists[0])
      })
  }

  function finishHomeRequest(error) {
    homeRequestsPending = Math.max(0, homeRequestsPending - 1)
    if (error) fail(error)
    if (homeRequestsPending === 0) {
      homeLoaded = true
      checkSavedItems(recentTracks.concat(topTracks).concat(topArtists))
    }
  }

  function loadHome() {
    if (homeLoading) return
    homeLoaded = false
    homeRequestsPending = 3
    spotifyApi.request("GET", "/me/player/recently-played", { limit: 30 }, null,
      function(status, payload, error) {
        if (!error) {
          var page = Api.normalizePage(payload, function(value) {
            return Api.normalizeTrack(value, 96)
          })
          root.recentTracks = page.items
        }
        root.finishHomeRequest(error)
      })
    spotifyApi.request("GET", "/me/top/tracks", {
      limit: 30, time_range: "medium_term"
    }, null, function(status, payload, error) {
      if (!error) {
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeTrack(value, 96)
          })
          root.topTracks = page.items
      }
      root.finishHomeRequest(error)
    })
    spotifyApi.request("GET", "/me/top/artists", {
      limit: 30, time_range: "medium_term"
    }, null, function(status, payload, error) {
      if (!error) {
        var page = Api.normalizePage(payload, function(value) {
          return Api.normalizeContext(value, 96)
          })
          root.topArtists = page.items
      }
      root.finishHomeRequest(error)
    })
  }

  function homeItems(kind) {
    var value = String(kind || "recent")
    if (value === "tracks") return topTracks
    if (value === "artists") return topArtists
    return recentTracks
  }

  function mergeDiscoverCandidates(items) {
    discoverCandidates = Api.mergeUnique(discoverCandidates, items)
    discoverPlaylists = Api.discoveryPlaylists(discoverCandidates, 24)
  }

  function finishDiscoverRequest(error) {
    if (error) discoverRequestsFailed++
    discoverRequestsPending = Math.max(0, discoverRequestsPending - 1)
    if (discoverRequestsPending > 0) return
    discoverLoaded = true
    checkSavedItems(discoverPlaylists)
    if (!discoverPlaylists.length) {
      discoverMessage = discoverRequestsFailed >= Api.DISCOVERY_SEARCHES.length
        ? "Spotify could not load discovery playlists. Try Refresh."
        : "Spotify did not return any personal discovery playlists yet. Try Refresh later."
    }
  }

  function requestDiscoverPlaylistSearch(term, expectedData, expectedDiscover) {
    spotifyApi.request("GET", "/search", {
      q: String(term || ""),
      type: "playlist",
      limit: 10
    }, null, function(status, payload, error) {
      if (expectedData !== root.dataSerial || expectedDiscover !== root.discoverSerial)
        return
      if (!error) {
        var page = Api.normalizeSearchPage(payload, "playlist", 128)
        root.mergeDiscoverCandidates(page.items)
      }
      root.finishDiscoverRequest(error)
    })
  }

  function loadDiscover() {
    if (discoverLoading) return
    var expectedData = dataSerial
    var expectedDiscover = ++discoverSerial
    discoverLoaded = false
    discoverMessage = ""
    discoverRequestsFailed = 0
    discoverCandidates = playlists.slice()
    discoverPlaylists = Api.discoveryPlaylists(discoverCandidates, 24)
    discoverRequestsPending = Api.DISCOVERY_SEARCHES.length
    if (!discoverRequestsPending) {
      discoverLoaded = true
      return
    }
    for (var i = 0; i < Api.DISCOVERY_SEARCHES.length; i++)
      requestDiscoverPlaylistSearch(Api.DISCOVERY_SEARCHES[i], expectedData, expectedDiscover)
  }

  function normalizeDevice(value) {
    var item = value || {}
    var rawName = String(item.name || "Spotify device")
    var id = String(item.id || "")
    var local = Api.isLocalPlaybackDevice({ id: id, name: rawName },
      deviceName, localRuntimeDeviceName, localDeviceId)
    if (local) {
      if (id) localDeviceId = id
      if (rawName === deviceName || !localRuntimeDeviceName)
        localRuntimeDeviceName = rawName
    }
    return {
      id: id,
      name: local ? deviceName : rawName,
      sourceName: rawName,
      type: String(item.type || "unknown"),
      active: item.is_active === true,
      restricted: item.is_restricted === true,
      volumePercent: Math.max(0, Math.min(100, Number(item.volume_percent) || 0)),
      local: local,
      localDiscovery: false,
      activationRequired: false,
      description: ""
    }
  }

  function mergeConnectDevices() {
    var local = spotifyConnectManager.devices || []
    var localById = ({})
    for (var i = 0; i < local.length; i++) localById[String(local[i].id || "")] = local[i]
    var next = []
    var present = ({})
    for (var j = 0; j < apiDevices.length && next.length < 32; j++) {
      var apiDevice = apiDevices[j]
      var discovered = localById[String(apiDevice.id || "")]
      if (discovered) {
        if (!apiDevice.local) apiDevice.name = discovered.name
        apiDevice.description = discovered.description
        apiDevice.localDiscovery = true
        apiDevice.activationRequired = false
      }
      present[String(apiDevice.id || "")] = true
      next.push(apiDevice)
    }
    for (var k = 0; k < local.length && next.length < 32; k++) {
      var item = local[k]
      if (present[String(item.id || "")]) continue
      var rawName = String(item.name || "Spotify Connect device")
      var isLocal = Api.isLocalPlaybackDevice({ id: item.id, name: rawName },
        deviceName, localRuntimeDeviceName, localDeviceId)
      if (isLocal) {
        localDeviceId = String(item.id || localDeviceId)
        if (rawName === deviceName || !localRuntimeDeviceName)
          localRuntimeDeviceName = rawName
      }
      next.push({
        id: String(item.id || ""),
        name: isLocal ? deviceName : rawName,
        sourceName: rawName,
        type: String(item.type || "Speaker"),
        active: false,
        restricted: false,
        volumePercent: 0,
        local: isLocal,
        localDiscovery: true,
        activationRequired: true,
        description: String(item.description || "")
      })
    }
    devices = next
    var preferred = Api.preferredPlaybackDevice(next, selectedDeviceId,
      selectedDeviceExplicit)
    if (selectedDeviceExplicit
        && (!preferred || preferred.id !== selectedDeviceId))
      selectedDeviceExplicit = false
    selectedDeviceId = preferred ? preferred.id : ""
    devicesLoaded = true
  }

  function finishDeviceLoad(callback, error) {
    mergeConnectDevices()
    devicesLoading = false
    if (error) fail(error)
    if (typeof callback === "function") callback()
  }

  function loadDevices(callback, serial, discoverLocal) {
    if (devicesLoading) {
      if (typeof callback === "function") callback()
      return
    }
    var expected = serial === undefined ? dataSerial : serial
    devicesLoading = true
    spotifyApi.request("GET", "/me/player/devices", null, null,
      function(status, payload, error) {
        if (expected !== root.dataSerial) {
          root.devicesLoading = false
          return
        }
        if (!error) {
          var source = payload && Array.isArray(payload.devices) ? payload.devices : []
          var next = []
          for (var i = 0; i < source.length; i++) next.push(root.normalizeDevice(source[i]))
          root.apiDevices = next.slice(0, 32)
        }
        if (discoverLocal === true) {
          root.pendingDeviceLoadCallback = callback
          root.pendingDeviceLoadError = error || ""
          if (spotifyConnectManager.loading) return
          spotifyConnectManager.refresh()
        } else {
          root.finishDeviceLoad(callback, error || "")
        }
      })
  }

  function loadQueue(callback, serial) {
    if (queueLoading) {
      if (typeof callback === "function") callback()
      return
    }
    var expected = serial === undefined ? dataSerial : serial
    queueLoading = true
    spotifyApi.request("GET", "/me/player/queue", null, null,
      function(status, payload, error) {
        root.queueLoading = false
        if (expected !== root.dataSerial) return
        if (error) root.fail(error)
        else {
          var source = payload && Array.isArray(payload.queue) ? payload.queue : []
          var next = []
          for (var i = 0; i < source.length && next.length < 100; i++) {
            var track = Api.normalizeTrack(source[i], 96)
            if (track) next.push(track)
          }
          root.queue = next
          root.queueLoaded = true
        }
        if (typeof callback === "function") callback()
      })
  }

  function search(term) {
    var normalized = String(term || "").trim()
    searchQuery = normalized
    searchLoading = normalized !== ""
    if (!normalized) {
      clearSearch()
      return
    }
    spotifyApi.search(normalized, function(groups, error) {
      root.searchLoading = false
      if (error) root.fail(error)
      else {
        root.searchGroups = groups
        root.rememberSearch(normalized)
        var allItems = []
        for (var i = 0; i < Api.SEARCH_TYPES.length; i++)
          allItems = allItems.concat(root.searchItems(Api.SEARCH_TYPES[i]))
        root.checkSavedItems(allItems)
      }
    })
  }

  function searchItems(type) {
    var page = searchGroups[String(type || "track")]
    return page && Array.isArray(page.items) ? page.items : []
  }

  function searchNext(type) {
    var page = searchGroups[String(type || "track")]
    return page ? String(page.next || "") : ""
  }

  function searchTotal(type) {
    var page = searchGroups[String(type || "track")]
    return page ? Number(page.total) || 0 : 0
  }

  function loadMoreSearch(type) {
    var value = String(type || "track")
    var path = searchNext(value)
    if (!path || searchLoading) return
    searchLoading = true
    spotifyApi.request("GET", path, null, null, function(status, payload, error) {
      root.searchLoading = false
      if (error) { root.fail(error); return }
      var incoming = ({})
      incoming[value] = Api.normalizeSearchPage(payload, value, 128)
      var merged = Api.mergeSearchGroups(root.searchGroups, incoming)
      if (merged[value].items.length >= root.cacheLimit) {
        merged[value].items = merged[value].items.slice(0, root.cacheLimit)
        merged[value].next = ""
      }
      root.searchGroups = merged
      root.checkSavedItems(root.searchItems(value))
    })
  }

  function clearSearch() {
    spotifyApi.cancelSearch()
    searchLoading = false
    searchQuery = ""
    searchGroups = Api.searchGroups({}, 128)
  }

  function cancelSearch(clearResults) {
    spotifyApi.cancelSearch()
    searchLoading = false
    if (clearResults === true) clearSearch()
  }

  function deviceForId(id) {
    var key = String(id || "")
    for (var i = 0; i < devices.length; i++)
      if (devices[i].id === key) return devices[i]
    return null
  }

  function activeDevice() {
    for (var i = 0; i < devices.length; i++) if (devices[i].active) return devices[i]
    return null
  }

  function localDevice() {
    for (var i = 0; i < devices.length; i++) if (devices[i].local) return devices[i]
    return null
  }

  function chooseDevice() {
    return Api.preferredPlaybackDevice(devices, selectedDeviceId,
      selectedDeviceExplicit)
  }

  function selectDevice(id, transferPlayback) {
    var device = deviceForId(id)
    if (!device || !device.id || device.restricted) return
    selectedDeviceId = device.id
    selectedDeviceExplicit = true
    noteActivity()
    if (device.activationRequired) {
      if (spotifyConnectManager.activating) return
      pendingConnectDeviceId = device.id
      connectActivationAttempts = 0
      statusClearTimer.stop()
      statusMessage = "Connecting to " + device.name
      lastError = ""
      spotifyConnectManager.activate(device.id)
      return
    }
    if (transferPlayback !== false) transferToConnectDevice(device.id)
  }

  function transferToConnectDevice(deviceId) {
    apiAction("PUT", "/me/player", null,
      { device_ids: [deviceId], play: playing }, "Playback device changed",
      function(ok) { if (ok) root.loadDevices() })
  }

  function checkActivatedConnectDevice() {
    var requested = pendingConnectDeviceId
    if (!requested) return
    var device = deviceForId(requested)
    if (device && !device.activationRequired) {
      pendingConnectDeviceId = ""
      connectActivationAttempts = 0
      transferToConnectDevice(requested)
      return
    }
    connectActivationAttempts++
    if (connectActivationAttempts < 8) connectActivationTimer.restart()
    else {
      pendingConnectDeviceId = ""
      fail("The speaker connected, but did not become available. Make sure it is awake and try again")
    }
  }

  function playItem(item, sourceItems, contextUri, successMessage, explicitRadio) {
    var playbackSerial = ++radioSerial
    var body = Api.playbackBody(item, sourceItems, contextUri)
    if (!body) {
      fail("This Spotify item cannot be played")
      return
    }
    pendingPlayback = item
    pendingPlaybackBody = body
    pendingPlaybackMessage = String(successMessage || "")
    pendingPlaybackRadio = radioPlaylistForPlayback(item, contextUri, explicitRadio)
    pendingPlaybackSerial = playbackSerial
    localActivationRequested = true
    deviceProbeAttempts = 0
    noteActivity()

    var target = chooseDevice()
    if (target && selectedDeviceExplicit && !target.local) {
      localActivationRequested = false
      sendPendingPlayback(target.id)
      return
    }
    if (target && target.local && daemonManager.running) {
      localActivationRequested = false
      sendPendingPlayback(target.id)
      return
    }
    if (!daemonManager.binaryAvailable || !daemonManager.unitAvailable) {
      fail("Playback on this computer needs to be set up in Settings")
      pendingPlayback = null
      pendingPlaybackBody = null
      pendingPlaybackMessage = ""
      pendingPlaybackRadio = null
      pendingPlaybackSerial = 0
      localActivationRequested = false
      return
    }
    daemonManager.start()
    deviceProbeTimer.restart()
  }

  function probeForLocalDevice() {
    if (!pendingPlayback && !localActivationRequested) return
    loadDevices(function() {
      if (!root.pendingPlayback && !root.localActivationRequested) return
      var explicitTarget = root.pendingPlayback && root.selectedDeviceExplicit
        ? root.deviceForId(root.selectedDeviceId) : null
      if (explicitTarget && !explicitTarget.local && !explicitTarget.restricted) {
        root.localActivationRequested = false
        root.sendPendingPlayback(explicitTarget.id)
        return
      }
      var local = root.localDevice()
      if (local && local.id && !local.restricted) {
        root.selectedDeviceId = local.id
        root.selectedDeviceExplicit = false
        if (root.pendingPlayback) {
          root.localActivationRequested = false
          root.sendPendingPlayback(local.id)
        } else {
          root.activateLocalDevice(local.id)
        }
        return
      }
      root.deviceProbeAttempts++
      if (root.deviceProbeAttempts < 8) deviceProbeTimer.restart()
      else {
        root.pendingPlayback = null
        root.pendingPlaybackBody = null
        root.pendingPlaybackMessage = ""
        root.pendingPlaybackRadio = null
        root.pendingPlaybackSerial = 0
        root.localActivationRequested = false
        root.fail("Playback on this computer did not become available. Reconnect Spotify in Settings, then try again")
      }
    })
  }

  function activateLocalDevice(deviceId) {
    var id = String(deviceId || "")
    if (!id) return
    localActivationRequested = false
    apiAction("PUT", "/me/player", null,
      { device_ids: [id], play: false }, "Omarchy Spotify is ready",
      function(ok) {
        if (ok) {
          root.selectedDeviceId = id
          root.selectedDeviceExplicit = false
          root.loadDevices()
        }
      })
  }

  function sendPendingPlayback(deviceId) {
    var body = pendingPlaybackBody
    var successMessage = pendingPlaybackMessage
    var radioPlaylist = pendingPlaybackRadio
    var playbackSerial = pendingPlaybackSerial
    if (!body) return
    pendingPlayback = null
    pendingPlaybackBody = null
    pendingPlaybackMessage = ""
    pendingPlaybackRadio = null
    pendingPlaybackSerial = 0
    apiAction("PUT", "/me/player/play", { device_id: deviceId }, body, successMessage,
      function(ok) {
        if (ok) {
          if (playbackSerial === root.radioSerial)
            root.radioContextSelected = !!radioPlaylist
          root.selectedDeviceId = String(deviceId || root.selectedDeviceId)
          root.loadDevices()
          root.loadQueue()
        }
      })
  }

  function startRadio(item) {
    if (!item || item.type !== "track" || !item.id || !item.uri) {
      fail("Track radio is available for Spotify songs")
      return
    }
    var expected = ++radioSerial
    noteActivity()
    succeed("Finding similar tracks…")
    // Development-mode recommendation requests can succeed with no payload.
    // Spotify's generated radio playlists provide a real playback context, so
    // prefer an exact Spotify-owned match and verify its first track is the seed.
    spotifyApi.request("GET", "/search", {
      q: String(item.name || "") + " Radio",
      type: "playlist",
      limit: 10
    }, null, function(status, payload, error) {
      if (expected !== root.radioSerial) return
      if (!error) {
        var page = Api.normalizeSearchPage(payload, "playlist", 96)
        var candidates = Api.trackRadioPlaylists(page.items, item.name)
        if (candidates.length) {
          root.tryRadioPlaylist(item, candidates, 0, expected)
          return
        }
      }
      root.requestRadioRecommendations(item, expected)
    })
  }

  function tryRadioPlaylist(item, candidates, index, expected) {
    if (expected !== radioSerial) return
    if (index >= candidates.length) {
      requestRadioRecommendations(item, expected)
      return
    }
    var candidate = candidates[index]
    spotifyApi.request("GET", "/playlists/"
      + encodeURIComponent(String(candidate.id)) + "/items", { limit: 1 }, null,
      function(status, payload, error) {
        if (expected !== root.radioSerial) return
        var source = payload && Array.isArray(payload.items) ? payload.items : []
        var first = !error && source.length ? Api.normalizeTrack(source[0], 96) : null
        if (first && Api.radioSeedMatches(first, item)) {
          root.rememberRadioPlaylist(candidate)
          root.playItem(candidate, null, "", "Track radio started", candidate)
          root.radioPlaylistReady(candidate)
          return
        }
        root.tryRadioPlaylist(item, candidates, index + 1, expected)
      })
  }

  function requestRadioRecommendations(item, expected) {
    if (expected !== radioSerial) return
    spotifyApi.request("GET", "/recommendations", {
      limit: 49,
      seed_tracks: item.id
    }, null, function(status, payload, error) {
      if (expected !== root.radioSerial) return
      var source = payload && Array.isArray(payload.tracks) ? payload.tracks : []
      var radio = [item]
      var seen = ({})
      seen[String(item.uri)] = true
      for (var i = 0; i < source.length; i++) {
        var track = Api.normalizeTrack(source[i], 96)
        var uri = String((track && track.uri) || "")
        if (uri && !seen[uri]) {
          seen[uri] = true
          radio.push(track)
        }
      }
      if (!error && radio.length > 1) {
        root.playItem(item, radio, "", "Track radio started")
        return
      }
      root.requestRadioArtistTracks(item, expected)
    })
  }

  function requestRadioArtistTracks(item, expected) {
    if (expected !== radioSerial) return
    var artist = item.artists && item.artists.length ? item.artists[0] : null
    if (!artist || !artist.name) {
      fail("Spotify could not find a radio mix for this song")
      return
    }
    spotifyApi.request("GET", "/search", {
      q: Api.catalogSearchText(artist.name, ""),
      type: "track",
      limit: 10
    }, null, function(status, payload, error) {
      if (expected !== root.radioSerial) return
      var page = error ? { items: [] }
        : Api.normalizeSearchPage(payload, "track", 96)
      var matching = Api.tracksForArtist(page.items, artist)
      var radio = [item]
      var seen = ({})
      seen[String(item.uri)] = true
      for (var i = 0; i < matching.length; i++) {
        var track = matching[i]
        var uri = String((track && track.uri) || "")
        if (uri && !seen[uri]) {
          seen[uri] = true
          radio.push(track)
        }
      }
      if (radio.length > 1) root.playItem(item, radio, "", "Track radio started")
      else root.fail("Spotify could not find a radio mix for this song")
    })
  }

  function togglePlayback() {
    noteActivity()
    if (hasPlayer && activePlayer.canTogglePlaying) {
      activePlayer.togglePlaying()
      return
    }
    apiAction("PUT", playing ? "/me/player/pause" : "/me/player/play",
      selectedDeviceId ? { device_id: selectedDeviceId } : null, null, "")
  }

  function next() {
    noteActivity()
    if (hasPlayer && activePlayer.canGoNext) activePlayer.next()
    else apiAction("POST", "/me/player/next",
      selectedDeviceId ? { device_id: selectedDeviceId } : null, null, "")
  }

  function previous() {
    noteActivity()
    if (hasPlayer && activePlayer.canGoPrevious) activePlayer.previous()
    else apiAction("POST", "/me/player/previous",
      selectedDeviceId ? { device_id: selectedDeviceId } : null, null, "")
  }

  function seekSeconds(seconds) {
    var value = Math.max(0, Math.min(lengthSeconds || Number.MAX_VALUE,
      Number(seconds) || 0))
    noteActivity()
    if (hasPlayer && activePlayer.canSeek && activePlayer.positionSupported)
      activePlayer.position = value
    else apiAction("PUT", "/me/player/seek", {
      position_ms: Math.round(value * 1000),
      device_id: selectedDeviceId || undefined
    }, null, "")
  }

  function setVolume(value) {
    var normalized = Math.max(0, Math.min(1, Number(value) || 0))
    noteActivity()
    if (hasPlayer && activePlayer.volumeSupported) activePlayer.volume = normalized
    else apiAction("PUT", "/me/player/volume", {
      volume_percent: Math.round(normalized * 100),
      device_id: selectedDeviceId || undefined
    }, null, "")
  }

  function setShuffle(value) {
    var enabled = value === true
    noteActivity()
    if (hasPlayer && activePlayer.shuffleSupported) activePlayer.shuffle = enabled
    else apiAction("PUT", "/me/player/shuffle", {
      state: enabled ? "true" : "false",
      device_id: selectedDeviceId || undefined
    }, null, "")
  }

  function cycleRepeat() {
    var nextMode = repeatMode === "off" ? "context" : (repeatMode === "context" ? "track" : "off")
    noteActivity()
    if (hasPlayer && activePlayer.loopSupported) {
      activePlayer.loopState = nextMode === "track" ? MprisLoopState.Track
        : (nextMode === "context" ? MprisLoopState.Playlist : MprisLoopState.None)
    } else {
      apiAction("PUT", "/me/player/repeat", {
        state: nextMode,
        device_id: selectedDeviceId || undefined
      }, null, "")
    }
  }

  function setSleepMinutes(minutes) {
    var value = Math.max(1, Math.min(720, Math.floor(Number(minutes) || 0)))
    sleepMode = "minutes"
    sleepEndsAt = Date.now() + value * 60000
    sleepRemainingSeconds = value * 60
    sleepTrackUri = ""
    succeed("Sleep timer set for " + value + " minutes")
  }

  function sleepAfterTrack() {
    if (!currentUri || !playing) {
      fail("Play something before setting an end-of-track timer")
      return
    }
    sleepMode = "track"
    sleepTrackUri = currentUri
    sleepEndsAt = 0
    sleepRemainingSeconds = 0
    succeed("Playback will pause after this item")
  }

  function sleepAfterContext() {
    if (!playing) {
      fail("Play something before setting an end-of-context timer")
      return
    }
    sleepMode = "context"
    sleepTrackUri = ""
    sleepEndsAt = 0
    sleepRemainingSeconds = 0
    succeed("Playback will stay asleep when this context ends")
  }

  function cancelSleepTimer(showStatus) {
    sleepMode = "off"
    sleepEndsAt = 0
    sleepTrackUri = ""
    sleepRemainingSeconds = 0
    sleepContextTimer.stop()
    if (showStatus !== false) succeed("Sleep timer cancelled")
  }

  function finishSleepTimer() {
    if (playing) togglePlayback()
    cancelSleepTimer(false)
    succeed("Sleep timer finished")
  }

  function sleepStatusText() {
    if (sleepMode === "minutes") {
      var minutes = Math.floor(sleepRemainingSeconds / 60)
      var seconds = sleepRemainingSeconds % 60
      return "Sleep in " + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    if (sleepMode === "track") return "Sleep after this item"
    if (sleepMode === "context") return "Sleep after this context"
    return "Sleep timer"
  }

  function addToQueue(item) {
    if (!item || ["track", "episode"].indexOf(item.type) < 0 || !item.uri) {
      fail("Only tracks and episodes can be added to the queue")
      return
    }
    apiAction("POST", "/me/player/queue", {
      uri: item.uri,
      device_id: selectedDeviceId || undefined
    }, null, "Added to queue", function(ok) { if (ok) root.loadQueue() })
  }

  function saveTrack(item) {
    if (!item || item.type !== "track" || !item.uri) return
    apiAction("PUT", "/me/library", { uris: item.uri }, null,
      "Saved to Liked Songs", function(ok) {
        if (ok) {
          root.setSavedState(item.uri, true)
          root.loadSavedTracks(false)
        }
      })
  }

  function startEngine() {
    noteActivity()
    localActivationRequested = true
    deviceProbeAttempts = 0
    daemonManager.start()
    deviceProbeTimer.restart()
  }

  function stopEngine() {
    pendingPlayback = null
    pendingPlaybackBody = null
    pendingPlaybackMessage = ""
    pendingPlaybackRadio = null
    pendingPlaybackSerial = 0
    localActivationRequested = false
    deviceProbeTimer.stop()
    daemonManager.stop()
  }

  function login() {
    if (loginBusy) return
    noteActivity()
    lastError = ""
    statusClearTimer.stop()
    statusMessage = ""
    loginFlowActive = true
    if (!daemonManager.playbackReady) {
      daemonManager.setupPlayback()
      return
    }
    if (!authManager.loggedIn) {
      authManager.beginLogin()
      return
    }
    if (!daemonManager.credentialsAvailable) {
      daemonManager.authenticate()
      return
    }
    finishLoginFlow()
  }

  function reconnectAccount() {
    if (loginBusy) return
    noteActivity()
    lastError = ""
    statusClearTimer.stop()
    statusMessage = ""
    loginFlowActive = true
    authManager.beginLogin()
  }

  function finishLoginFlow() {
    loginFlowActive = false
    succeed("Connected to Spotify")
    loadProfile()
    loadSidebarPlaylists()
    openView(activeView, true)
  }

  function logout() {
    if (loginBusy || daemonManager.busy) return
    loginFlowActive = false
    dataSerial++
    pendingPlayback = null
    pendingPlaybackBody = null
    pendingPlaybackMessage = ""
    pendingPlaybackRadio = null
    pendingPlaybackSerial = 0
    localActivationRequested = false
    deviceProbeTimer.stop()
    spotifyApi.cancelSearch()
    daemonManager.clearCredentials()
    authManager.logout()
    clearData()
  }

  function clearData() {
    radioSerial++
    pendingPlayback = null
    pendingPlaybackBody = null
    pendingPlaybackMessage = ""
    pendingPlaybackRadio = null
    pendingPlaybackSerial = 0
    radioContextSelected = false
    playlists = []
    playlistsLoaded = false
    playlistsNext = ""
    savedTracks = []
    savedTracksLoaded = false
    savedTracksNext = ""
    savedAlbums = []
    savedAlbumsLoaded = false
    savedAlbumsNext = ""
    followedArtists = []
    followedArtistsLoaded = false
    followedArtistsNext = ""
    savedShows = []
    savedShowsLoaded = false
    savedShowsNext = ""
    savedEpisodes = []
    savedEpisodesLoaded = false
    savedEpisodesNext = ""
    savedAudiobooks = []
    savedAudiobooksLoaded = false
    savedAudiobooksNext = ""
    playlistItems = []
    playlistItemsNext = ""
    selectedPlaylist = null
    currentUserId = ""
    currentUserName = ""
    queue = []
    queueLoaded = false
    devices = []
    apiDevices = []
    devicesLoaded = false
    selectedDeviceId = ""
    selectedDeviceExplicit = false
    localDeviceId = ""
    localRuntimeDeviceName = deviceName
    pendingConnectDeviceId = ""
    connectActivationAttempts = 0
    connectActivationTimer.stop()
    searchQuery = ""
    searchGroups = Api.searchGroups({}, 128)
    savedUris = ({})
    recentTracks = []
    topTracks = []
    topArtists = []
    homeLoaded = false
    homeRequestsPending = 0
    discoverSerial++
    discoverPlaylists = []
    discoverCandidates = []
    discoverLoaded = false
    discoverRequestsPending = 0
    discoverRequestsFailed = 0
    discoverMessage = ""
    detailSerial++
    detailItem = null
    detailItems = []
    detailNext = ""
    detailLoading = false
    detailMessage = ""
    artistCatalogSerial++
    artistCatalogQuery = ""
    artistAlbums = []
    artistAlbumsNext = ""
    artistAlbumsLoading = false
    artistSongs = []
    artistSongsNext = ""
    artistSongsLoading = false
    artistThisIsPlaylist = null
    artistThisIsLoading = false
    playlistsLoading = false
    savedTracksLoading = false
    savedAlbumsLoading = false
    followedArtistsLoading = false
    savedShowsLoading = false
    savedEpisodesLoading = false
    savedAudiobooksLoading = false
    playlistItemsLoading = false
    playlistActionBusy = false
    playlistConversionBusy = false
    queueLoading = false
    devicesLoading = false
    searchLoading = false
    cancelSleepTimer(false)
  }

  onPlayingChanged: noteActivity()
  onPlaybackStateChanged: {
    if ((sleepMode === "context" || sleepMode === "track")
        && playbackState === MprisPlaybackState.Stopped) sleepContextTimer.restart()
    else sleepContextTimer.stop()
  }
  onCurrentUriChanged: {
    if (sleepMode === "track" && sleepTrackUri && currentUri
        && currentUri !== sleepTrackUri) finishSleepTimer()
  }
  onShellChanged: settingsSync.restart()

  Component.onCompleted: {
    settingsSync.start()
    daemonManager.refreshStatus()
  }

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onShellConfigChanged() { root.syncSettings() }
  }

  Connections {
    target: authManager
    function onLoginSucceeded() {
      if (!root.loginFlowActive) {
        root.succeed("Spotify account connected")
        return
      }
      if (root.loginFlowActive && !root.daemon.credentialsAvailable) {
        root.succeed("Spotify connected · connecting playback on this computer")
        root.daemon.authenticate()
        return
      }
      root.finishLoginFlow()
      if (root.localActivationRequested) root.deviceProbeTimer.restart()
    }
    function onLoggedOut() { root.clearData() }
    function onSessionUnavailable(reason) {
      root.loginFlowActive = false
      if (reason) root.lastError = root.safeError(reason)
    }
  }

  Connections {
    target: daemonManager
    function onSetupSucceeded() {
      if (root.loginFlowActive) root.login()
      else root.succeed("Playback on this computer is ready")
    }
    function onSetupFailed(reason) {
      root.loginFlowActive = false
      root.fail(reason)
    }
    function onStarted() {
      root.localRuntimeDeviceName = root.deviceName
      root.localDeviceId = ""
      root.succeed("Playback started on this computer")
      if (root.pendingPlayback || root.localActivationRequested) deviceProbeTimer.restart()
    }
    function onStopped() { root.succeed("Playback stopped on this computer") }
    function onAuthenticationSucceeded() {
      if (root.loginFlowActive) root.finishLoginFlow()
      else root.succeed("Playback on this computer is connected")
      if (root.pendingPlayback || root.localActivationRequested) deviceProbeTimer.restart()
    }
    function onAuthenticationFailed(reason) {
      root.loginFlowActive = false
      root.fail(reason)
    }
    function onCredentialsCleared() { root.succeed("Signed out of Spotify") }
    function onCredentialsClearFailed(reason) { root.fail(reason) }
  }

  Connections {
    target: spotifyConnectManager
    function onRefreshed() {
      var callback = root.pendingDeviceLoadCallback
      var error = root.pendingDeviceLoadError
      root.pendingDeviceLoadCallback = null
      root.pendingDeviceLoadError = ""
      root.finishDeviceLoad(callback, error)
    }
    function onRefreshFailed(reason) {
      var callback = root.pendingDeviceLoadCallback
      var error = root.pendingDeviceLoadError || reason
      root.pendingDeviceLoadCallback = null
      root.pendingDeviceLoadError = ""
      root.finishDeviceLoad(callback, error)
    }
    function onActivated(deviceId) {
      statusClearTimer.stop()
      root.statusMessage = "Speaker connected · waiting for it to become available"
      root.connectActivationAttempts = 0
      connectActivationTimer.restart()
    }
    function onActivationFailed(reason) {
      root.pendingConnectDeviceId = ""
      root.connectActivationAttempts = 0
      root.fail(reason)
    }
  }

  Timer {
    id: settingsSync
    interval: 0
    onTriggered: root.syncSettings()
  }

  Timer {
    id: statusClearTimer
    interval: 4500
    onTriggered: if (!root.lastError) root.statusMessage = ""
  }

  Timer {
    id: deviceProbeTimer
    interval: 750
    repeat: false
    onTriggered: root.probeForLocalDevice()
  }

  Timer {
    id: connectActivationTimer
    interval: 650
    repeat: false
    onTriggered: root.loadDevices(function() { root.checkActivatedConnectDevice() })
  }

  Timer {
    id: idleTimer
    interval: 60000
    repeat: true
    running: root.daemon.running && !root.playing && !root.uiVisible
      && root.idleShutdownMinutes > 0
    onTriggered: {
      if (Date.now() - root.lastActivityAt >= root.idleShutdownMinutes * 60000)
        root.stopEngine()
    }
  }

  Timer {
    id: sleepCountdown
    interval: 1000
    repeat: true
    running: root.sleepMode === "minutes"
    onTriggered: {
      root.sleepRemainingSeconds = Math.max(0,
        Math.ceil((root.sleepEndsAt - Date.now()) / 1000))
      if (root.sleepRemainingSeconds <= 0) root.finishSleepTimer()
    }
  }

  Timer {
    id: sleepContextTimer
    interval: 1800
    repeat: false
    onTriggered: if ((root.sleepMode === "context" || root.sleepMode === "track")
        && root.playbackState === MprisPlaybackState.Stopped)
      root.finishSleepTimer()
  }

  AuthManager {
    id: authManager
    pluginDir: root.pluginDir
  }

  SpotifyApi {
    id: spotifyApi
    auth: authManager
  }

  SpotifyConnectManager {
    id: spotifyConnectManager
    pluginDir: root.pluginDir
  }

  DaemonManager {
    id: daemonManager
    pluginDir: root.pluginDir
    deviceName: root.deviceName
    bitrateKbps: root.bitrateKbps
    mprisPresent: root.hasPlayer
  }
}
