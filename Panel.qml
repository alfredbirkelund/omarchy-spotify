import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property string currentTab: "home"
  property bool openedForLogin: false

  property string searchText: ""
  property string searchType: "track"
  property string libraryType: "tracks"
  property string homeType: "recent"
  property string libraryFilter: ""
  property string librarySort: "default"
  property string playlistFilter: ""
  property string playlistSort: "default"
  property string detailFilter: ""
  property string detailSort: "default"
  property string artistSearchText: ""
  property var scrollPositions: ({})
  property var navigationStack: []
  property string restoredPlaylistId: ""

  property string draftDeviceName: "Omarchy Spotify"
  property string draftIdleMinutes: "15"
  property bool draftShowTitle: true
  property string draftAudioQuality: "320 kbps"
  property var contextItem: null
  property var contextSourceItems: []
  property string contextSourceUri: ""
  property int contextSourceIndex: -1
  property var contextPlaylist: null
  property var pendingPlaylistItem: null
  property string newPlaylistName: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "quickshell.spotify"
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property bool fullyConnected: service && service.fullyConnected
  readonly property bool compactHeight: window.height < Style.space(620)
  readonly property bool compactWidth: window.width < Style.space(760)
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 28
  }

  function syncDraftSettings() {
    if (!service) return
    draftDeviceName = service.deviceName
    draftIdleMinutes = String(service.idleShutdownMinutes)
    draftShowTitle = service.showTrackTitle
    draftAudioQuality = service.audioQuality
  }

  function saveSettings() {
    if (!service) return
    var values = {
      deviceName: String(draftDeviceName || "").trim() || "Omarchy Spotify",
      idleShutdownMinutes: Math.max(0, Math.min(1440,
        Math.floor(Number(draftIdleMinutes) || 0))),
      showTrackTitle: draftShowTitle ? "On" : "Off",
      audioQuality: draftAudioQuality
    }
    service.persistSettings(values)
    syncDraftSettings()
    service.succeed("Settings saved")
  }

  function cycleAudioQuality() {
    draftAudioQuality = draftAudioQuality === "96 kbps" ? "160 kbps"
      : (draftAudioQuality === "160 kbps" ? "320 kbps" : "96 kbps")
  }

  function audioQualityLabel() {
    if (draftAudioQuality === "96 kbps") return "Standard · 96 kbps"
    if (draftAudioQuality === "320 kbps") return "Very high · 320 kbps"
    return "High · 160 kbps"
  }

  function connectionButtonText() {
    if (!service) return "Spotify unavailable"
    if (service.loginBusy) return service.loginProgress + "…"
    if (fullyConnected) return "Connected"
    if (!service.daemon.playbackReady) return "Set up and continue"
    return "Continue with Spotify"
  }

  function connectionHeadline() {
    if (!service) return "Spotify is unavailable"
    if (service.daemon.setupBusy) return "Setting up playback"
    if (fullyConnected) return "You're connected"
    if (!service.daemon.playbackReady) return "One quick setup, then Spotify"
    return "Continue with Spotify"
  }

  function connectionErrorText() {
    if (!service) return "Music for Spotify is unavailable"
    return service.lastError || service.auth.lastError || service.daemon.lastError
  }

  function playbackStatusText() {
    if (!service) return "Playback is unavailable"
    if (!service.daemon.requirementsChecked) return "Checking playback support…"
    if (service.daemon.setupBusy) return "Preparing playback on this computer…"
    if (!service.daemon.playbackReady) return "A quick one-time setup is needed"
    if (!service.daemon.credentialsChecked) return "Checking your Spotify connection…"
    if (!service.daemon.credentialsAvailable) return "Ready for Spotify sign-in"
    if (service.daemon.running) return "Active on this computer"
    return "Ready — starts automatically when you play music"
  }

  function openMediaContext(item, sceneX, sceneY, sourceItems, contextUri, index) {
    if (!item) return
    contextItem = item
    contextSourceItems = Array.isArray(sourceItems) ? sourceItems : []
    contextSourceUri = String(contextUri || "")
    contextSourceIndex = index === undefined ? -1 : Math.floor(Number(index))
    contextPlaylist = playlistForContext(contextSourceUri)
    mediaContextMenu.x = Math.max(Style.space(6), Math.min(
      window.width - mediaContextMenu.width - Style.space(6), Number(sceneX) || 0))
    mediaContextMenu.y = Math.max(Style.space(6), Math.min(
      window.height - mediaContextMenu.height - Style.space(6), Number(sceneY) || 0))
    mediaContextMenu.open()
  }

  function dismissTransientPopup() {
    if (mediaContextMenu.opened) {
      mediaContextMenu.close()
      return true
    }
    if (playlistPicker.opened) {
      playlistPicker.close()
      return true
    }
    if (sleepPopup.opened) {
      sleepPopup.close()
      return true
    }
    return false
  }

  function turnPlaylistIntoOwn(playlist) {
    if (!service || !playlist) return
    service.makePlaylistYourOwn(playlist, function(copy) {
      if (!copy) return
      root.chooseTab("playlists")
      root.service.openPlaylist(copy)
    })
  }

  function playlistForContext(uri) {
    var value = String(uri || "")
    if (!service || !value) return null
    if (service.selectedPlaylist && service.selectedPlaylist.uri === value)
      return service.selectedPlaylist
    if (service.detailItem && service.detailItem.type === "playlist"
        && service.detailItem.uri === value) return service.detailItem
    return null
  }

  function rememberScroll(key, value) {
    var next = ({})
    for (var existing in scrollPositions) next[existing] = scrollPositions[existing]
    next[String(key || currentTab)] = Math.max(0, Number(value) || 0)
    scrollPositions = next
  }

  function scrollFor(key) {
    return Math.max(0, Number(scrollPositions[String(key || currentTab)]) || 0)
  }

  function restoreUiState() {
    if (!service) return
    var state = service.sessionState || ({})
    service.restoreLastRadioPlaylist(state.lastRadioPlaylist)
    searchText = String(state.searchText || service.searchQuery || "")
    searchType = Api.SEARCH_TYPES.indexOf(String(state.searchType || "")) >= 0
      ? String(state.searchType) : "track"
    libraryType = ["tracks", "albums", "artists", "shows", "episodes", "audiobooks"]
      .indexOf(String(state.libraryType || "")) >= 0 ? String(state.libraryType) : "tracks"
    homeType = ["recent", "tracks", "artists"].indexOf(String(state.homeType || "")) >= 0
      ? String(state.homeType) : "recent"
    libraryFilter = String(state.libraryFilter || "")
    librarySort = String(state.librarySort || "default")
    playlistFilter = String(state.playlistFilter || "")
    playlistSort = String(state.playlistSort || "default")
    detailFilter = String(state.detailFilter || "")
    detailSort = String(state.detailSort || "default")
    artistSearchText = String(state.artistSearchText || "")
    scrollPositions = state.scrollPositions && typeof state.scrollPositions === "object"
      ? state.scrollPositions : ({})
    restoredPlaylistId = String(state.selectedPlaylistId || "")
    var restoredTab = String(state.tab || "home")
    if (["home", "discover", "search", "library", "playlists", "detail", "queue", "devices", "setup"]
        .indexOf(restoredTab) >= 0) currentTab = restoredTab
    if (currentTab === "detail" && state.detailItem)
      service.openDetail(state.detailItem, artistSearchText)
  }

  function persistUiState() {
    if (!service) return
    service.persistSession({
      tab: currentTab === "login" ? "home" : currentTab,
      searchText: searchText,
      searchType: searchType,
      libraryType: libraryType,
      homeType: homeType,
      libraryFilter: libraryFilter,
      librarySort: librarySort,
      playlistFilter: playlistFilter,
      playlistSort: playlistSort,
      detailFilter: detailFilter,
      detailSort: detailSort,
      artistSearchText: currentTab === "detail" && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      scrollPositions: scrollPositions,
      detailItem: currentTab === "detail" && service.detailItem ? service.detailItem : null,
      selectedPlaylistId: service.selectedPlaylist ? service.selectedPlaylist.id : restoredPlaylistId,
      lastRadioPlaylist: service.lastRadioPlaylist
    })
  }

  function restorePlaylistSelection() {
    if (!service || !restoredPlaylistId || service.selectedPlaylist) return
    var playlist = service.playlistById(restoredPlaylistId)
    if (playlist) service.openPlaylist(playlist)
  }

  function openItem(item) {
    if (!item) return
    if (item.kind !== "context") {
      if (service) service.playItem(item, [item], "")
      return
    }
    var stack = navigationStack.slice()
    stack.push({
      tab: currentTab,
      item: currentTab === "detail" && service ? service.detailItem : null,
      artistSearchText: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : ""
    })
    navigationStack = stack
    currentTab = "detail"
    if (item.type === "artist") artistSearchText = ""
    if (service) service.openDetail(item)
  }

  function goBack() {
    if (!navigationStack.length) {
      chooseTab("search")
      return
    }
    var stack = navigationStack.slice()
    var destination = stack.pop()
    navigationStack = stack
    currentTab = destination.tab || "search"
    if (currentTab === "detail" && destination.item && service) {
      artistSearchText = destination.item.type === "artist"
        ? String(destination.artistSearchText || "") : ""
      service.openDetail(destination.item, artistSearchText)
    }
    else if (service) service.openView(currentTab, false)
  }

  function activateMedia(item, sourceItems, contextUri) {
    if (!item || !service) return
    service.playItem(item, sourceItems, contextUri)
  }

  function textInputFocused() {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }

  function focusSearch() {
    chooseTab("search")
    Qt.callLater(function() {
      if (pageLoader.item && typeof pageLoader.item.focusSearch === "function")
        pageLoader.item.focusSearch()
    })
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    var requestedTab = String(payload.tab || "")
    restoreUiState()
    if (["home", "discover", "search", "library", "playlists", "queue", "devices", "setup"].indexOf(requestedTab) >= 0)
      currentTab = requestedTab
    if (!fullyConnected) {
      currentTab = "login"
      openedForLogin = true
    } else {
      openedForLogin = false
    }
    closingFromHost = false
    opened = true
    syncDraftSettings()
    if (service) {
      service.setUiVisible("full-panel", true)
      service.activate(currentTab)
      if (currentTab === "search" && searchText && service.searchQuery !== searchText)
        service.search(searchText)
    }
    Qt.callLater(function() {
      focusScope.forceActiveFocus()
    })
  }

  function close() {
    persistUiState()
    closingFromHost = true
    opened = false
    if (service) {
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function chooseTab(tab) {
    if (!fullyConnected) {
      currentTab = "login"
      openedForLogin = true
      return
    }
    if (currentTab === "search" && tab !== "search" && service) service.cancelSearch(false)
    currentTab = tab
    if (tab !== "detail") navigationStack = []
    openedForLogin = false
    if (service) service.openView(tab, false)
  }

  function openLastRadio() {
    if (!service || !service.lastRadioPlaylist) return
    chooseTab("playlists")
    service.openPlaylist(service.lastRadioPlaylist)
  }

  function primaryNavigationItems() {
    var items = [
      { id: "home", label: "For you", icon: "󰎆" },
      { id: "discover", label: "Discover", icon: "󰲸" }
    ]
    if (service && service.lastRadioPlaylist) items.push({
      id: "radio",
      label: service.lastRadioPlaying ? "Current radio" : "Last radio",
      icon: "󰎆"
    })
    items.push(
      { id: "search", label: "Search", icon: "󰍉" },
      { id: "queue", label: "Queue", icon: "󰐕" },
      { id: "devices", label: "Devices", icon: "󰋋" })
    return items
  }

  function radioNavigationSelected() {
    return currentTab === "playlists" && service && service.lastRadioPlaylist
      && service.selectedPlaylist
      && String(service.selectedPlaylist.id) === String(service.lastRadioPlaylist.id)
  }

  function updateLoginGate() {
    if (!opened) return
    if (!fullyConnected) {
      currentTab = "login"
      openedForLogin = true
      return
    }
    if (openedForLogin || currentTab === "login") {
      openedForLogin = false
      currentTab = "home"
      if (service) service.openView("home", false)
    }
  }

  // Track the combined service state directly. During the first login, the
  // Web API token and spotifyd credential finish in separate event turns;
  // listening only to those nested objects can miss the final combined edge
  // while the panel loader is being remapped by the browser.
  onFullyConnectedChanged: Qt.callLater(function() { root.updateLoginGate() })
  onServiceChanged: Qt.callLater(function() { root.updateLoginGate() })

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPlaylistsChanged() { root.restorePlaylistSelection() }
    function onRadioPlaylistReady(playlist) {
      if (!playlist || !root.service) return
      root.openLastRadio()
    }
  }

  function pageComponent() {
    if (currentTab === "login") return loginPage
    if (currentTab === "setup") return setupPage
    if (currentTab === "home") return homePage
    if (currentTab === "discover") return discoverPage
    if (currentTab === "library") return libraryPage
    if (currentTab === "playlists") return playlistsPage
    if (currentTab === "detail") return detailPage
    if (currentTab === "queue") return queuePage
    if (currentTab === "devices") return devicesPage
    return searchPage
  }

  function pageTitle() {
    if (currentTab === "login") return "Log in to Spotify"
    if (currentTab === "home") return "For you"
    if (currentTab === "discover") return "Discover"
    if (currentTab === "library") return "Your Library"
    if (currentTab === "playlists") return "Playlists"
    if (currentTab === "queue") return "Queue"
    if (currentTab === "devices") return "Spotify Connect"
    if (currentTab === "setup") return "Settings"
    if (currentTab === "detail") return service && service.detailItem
      ? service.detailItem.name : "Loading…"
    return "Search"
  }

  function pageSubtitle() {
    if (currentTab === "login") return "Connect your Spotify account to get started"
    if (currentTab === "home") return "Recently played and your personal favorites"
    if (currentTab === "discover") return "Personal mixes and fresh music from Spotify"
    if (currentTab === "library") return "Songs, albums, artists, podcasts and audiobooks"
    if (currentTab === "playlists") return "Your Spotify playlists"
    if (currentTab === "queue") return "What plays next"
    if (currentTab === "devices") return "Speakers and players"
    if (currentTab === "setup") return "Account, playback and app preferences"
    if (currentTab === "detail") return service && service.detailItem
      ? String(service.detailItem.type || "Spotify item") : "Spotify item"
    return "Songs, artists, albums, playlists, podcasts and audiobooks"
  }

  function sidebarPlaylistName(item) {
    var name = item && item.name ? String(item.name) : "Playlist"
    return name.length > 22 ? name.substring(0, 21) + "…" : name
  }

  function playlistOptions() {
    var playlists = service ? service.sidebarPlaylists() : []
    var options = []
    for (var i = 0; i < playlists.length; i++) {
      var playlist = playlists[i]
      if (!playlist || !playlist.id) continue
      options.push({
        value: String(playlist.id),
        label: String(playlist.name || "Playlist"),
        description: String(playlist.ownerName || "")
      })
    }
    return options
  }

  function openExternal(item) {
    if (item && item.externalUrl) Qt.openUrlExternally(item.externalUrl)
  }

  function copyExternal(item) {
    if (!item || !item.externalUrl) return
    Quickshell.execDetached(["wl-copy", String(item.externalUrl)])
    if (service) service.succeed("Spotify link copied")
  }

  function playlistPosition(item) {
    if (!service || !item || !contextPlaylist) return -1
    var source = service.selectedPlaylist && service.selectedPlaylist.id === contextPlaylist.id
      ? service.playlistItems : service.detailItems
    var occurrence = 0
    for (var shown = 0; shown < contextSourceIndex; shown++)
      if (contextSourceItems[shown] && contextSourceItems[shown].uri === item.uri) occurrence++
    for (var i = 0; i < source.length; i++) {
      if (source[i] && source[i].uri === item.uri) {
        if (occurrence === 0) return i
        occurrence--
      }
    }
    return -1
  }

  function openPlaylistPicker(item) {
    if (!item || item.kind !== "item") return
    pendingPlaylistItem = item
    playlistPicker.open()
  }

  Component.onDestruction: {
    if (service) {
      persistUiState()
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
  }

  Popup {
    id: mediaContextMenu
    parent: window.contentItem
    width: Style.space(270)
    height: contextMenuContent.implicitHeight + padding * 2
    padding: Style.space(6)
    modal: true
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Keys.onEscapePressed: function(event) {
      mediaContextMenu.close()
      event.accepted = true
    }

    background: BorderSurface {
      color: root.background
      radius: Style.cornerRadius
      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    }

    contentItem: Column {
      id: contextMenuContent
      spacing: Style.space(3)

      Text {
        width: parent.width
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        topPadding: Style.space(4)
        bottomPadding: Style.space(4)
        text: root.contextItem ? String(root.contextItem.name || "Spotify item") : "Spotify item"
        color: Qt.darker(root.foreground, 1.25)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        text: "Press Esc to close"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width; foreground: root.foreground }

      Button {
        width: parent.width
        visible: root.contextItem
          && ["show", "audiobook"].indexOf(root.contextItem.type) < 0
        text: "Play"
        iconText: "󰐊"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.playItem(root.contextItem,
            root.contextSourceItems, root.contextSourceUri)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
        text: "Start track radio"
        iconText: "󰎆"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.startRadio(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem
          && ["track", "episode"].indexOf(root.contextItem.type) >= 0
        text: "Add to queue"
        iconText: "󰐕"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.addToQueue(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem
          && ["track", "episode"].indexOf(root.contextItem.type) >= 0
        text: "Add to playlist…"
        iconText: "󱁐"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openPlaylistPicker(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.kind === "context"
        text: "Open details"
        iconText: "󰋼"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openItem(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "playlist"
          && root.service && root.service.currentUserId !== ""
          && !root.service.playlistOwned(root.contextItem)
        text: root.service && root.service.playlistConversionBusy
          ? "Making your copy…" : "Turn into your own playlist"
        iconText: "󰒍"
        foreground: root.foreground
        leftAlign: true
        enabled: root.service && !root.service.playlistActionBusy
        onClicked: {
          var playlist = root.contextItem
          mediaContextMenu.close()
          root.turnPlaylistIntoOwn(playlist)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
          && root.contextItem.artists && root.contextItem.artists.length
        text: "Go to artist"
        iconText: "󰠃"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openItem(root.contextItem.artists[0])
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && !!root.contextItem.albumItem
        text: "Go to album"
        iconText: "󰀥"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openItem(root.contextItem.albumItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && !!root.contextItem.uri
          && root.contextItem.type !== "chapter"
        text: root.service && root.service.isSaved(root.contextItem)
          ? "Remove from library" : "Save to library"
        iconText: root.service && root.service.isSaved(root.contextItem) ? "󰓎" : "󰋑"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          if (root.service) root.service.toggleSaved(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextPlaylist && root.service
          && root.service.playlistEditable(root.contextPlaylist)
          && root.contextItem && root.contextItem.kind === "item"
        text: "Move up"
        iconText: "󰁝"
        foreground: root.foreground
        leftAlign: true
        enabled: root.playlistPosition(root.contextItem) > 0
        onClicked: {
          var position = root.playlistPosition(root.contextItem)
          mediaContextMenu.close()
          root.service.movePlaylistItem(position, -1, root.contextPlaylist,
            root.contextPlaylist === root.service.selectedPlaylist
              ? root.service.playlistItems.length : root.service.detailItems.length)
        }
      }

      Button {
        width: parent.width
        visible: root.contextPlaylist && root.service
          && root.service.playlistEditable(root.contextPlaylist)
          && root.contextItem && root.contextItem.kind === "item"
        text: "Move down"
        iconText: "󰁅"
        foreground: root.foreground
        leftAlign: true
        enabled: root.playlistPosition(root.contextItem) >= 0
          && root.playlistPosition(root.contextItem) < (root.contextPlaylist
            === (root.service ? root.service.selectedPlaylist : null)
              ? root.service.playlistItems.length - 1
              : (root.service ? root.service.detailItems.length - 1 : -1))
        onClicked: {
          var position = root.playlistPosition(root.contextItem)
          mediaContextMenu.close()
          root.service.movePlaylistItem(position, 1, root.contextPlaylist,
            root.contextPlaylist === root.service.selectedPlaylist
              ? root.service.playlistItems.length : root.service.detailItems.length)
        }
      }

      Button {
        width: parent.width
        visible: root.contextPlaylist && root.service
          && root.service.playlistEditable(root.contextPlaylist)
          && root.contextItem && root.contextItem.kind === "item"
        text: "Remove from playlist"
        iconText: "󰅖"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          var position = root.playlistPosition(root.contextItem)
          mediaContextMenu.close()
          root.service.removePlaylistItem(root.contextItem, position, root.contextPlaylist)
        }
      }

      PanelSeparator {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        foreground: root.foreground
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        text: "Copy Spotify link"
        iconText: "󰌷"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.copyExternal(root.contextItem)
        }
      }

      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        text: "Open in Spotify"
        iconText: "󰏌"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          mediaContextMenu.close()
          root.openExternal(root.contextItem)
        }
      }
    }
  }

  Popup {
    id: playlistPicker
    parent: window.contentItem
    x: Math.max(Style.space(8), (window.width - width) / 2)
    y: Math.max(Style.space(8), (window.height - height) / 2)
    width: Style.space(360)
    height: Math.min(Style.space(520), pickerContent.implicitHeight + padding * 2)
    padding: Style.space(8)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: BorderSurface {
      color: root.background
      radius: Style.cornerRadius
      borderSpec: Border.controlSpec("selected", root.foreground, root.accent)
    }

    contentItem: Column {
      id: pickerContent
      spacing: Style.space(7)

      Text {
        width: parent.width
        text: root.pendingPlaylistItem
          ? "Add “" + String(root.pendingPlaylistItem.name || "song") + "” to a playlist"
          : "Add to playlist"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Choose one of your playlists, or create a new private playlist."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: newPlaylistField
          width: Math.max(80, parent.width - createPlaylistButton.width - parent.spacing)
          foreground: root.foreground
          placeholderText: "Name a new playlist"
          text: root.newPlaylistName
          onTextEdited: root.newPlaylistName = text
          onAccepted: createPlaylistButton.clicked()
        }

        Button {
          id: createPlaylistButton
          text: "Create"
          iconText: "󰐕"
          foreground: root.foreground
          enabled: root.service && root.newPlaylistName.trim() !== ""
            && !root.service.playlistActionBusy
          onClicked: {
            if (!root.service) return
            root.service.createPlaylist(root.newPlaylistName, function(playlist) {
              if (root.pendingPlaylistItem) root.service.addItemToPlaylist(
                root.pendingPlaylistItem, playlist)
              root.newPlaylistName = ""
              playlistPicker.close()
            })
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.foreground }

      ListView {
        id: playlistPickerList
        width: parent.width
        height: Math.min(Style.space(340), Math.max(Style.space(80), contentHeight))
        model: root.service ? root.service.editablePlaylists() : []
        clip: true
        spacing: Style.space(2)
        ScrollBar.vertical: ScrollBar { }

        FastScrollHandler { parent: playlistPickerList; flickable: playlistPickerList }

        delegate: Button {
          required property var modelData
          width: ListView.view.width
          text: modelData.name || "Playlist"
          iconText: "󰲸"
          foreground: root.foreground
          leftAlign: true
          onClicked: {
            if (root.service && root.pendingPlaylistItem)
              root.service.addItemToPlaylist(root.pendingPlaylistItem, modelData)
            playlistPicker.close()
          }
        }
      }
    }
  }

  Popup {
    id: sleepPopup
    parent: window.contentItem
    x: Math.max(Style.space(8), window.width - width - Style.space(24))
    y: Math.max(Style.space(8), window.height - height - Style.space(130))
    width: Style.space(245)
    height: sleepContent.implicitHeight + padding * 2
    padding: Style.space(7)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: BorderSurface {
      color: root.background
      radius: Style.cornerRadius
      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    }

    contentItem: Column {
      id: sleepContent
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.service ? root.service.sleepStatusText() : "Sleep timer"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        leftPadding: Style.space(7)
      }
      PanelSeparator { width: parent.width; foreground: root.foreground }
      Repeater {
        model: [15, 30, 60, 120]
        Button {
          required property int modelData
          width: sleepContent.width
          text: modelData + " minutes"
          iconText: "󰔛"
          foreground: root.foreground
          leftAlign: true
          onClicked: {
            if (root.service) root.service.setSleepMinutes(modelData)
            sleepPopup.close()
          }
        }
      }
      Button {
        width: parent.width
        text: "After this item"
        iconText: "󰐾"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          if (root.service) root.service.sleepAfterTrack()
          sleepPopup.close()
        }
      }
      Button {
        width: parent.width
        text: "After this context"
        iconText: "󰓛"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          if (root.service) root.service.sleepAfterContext()
          sleepPopup.close()
        }
      }
      Button {
        width: parent.width
        visible: root.service && root.service.sleepActive
        text: "Cancel timer"
        iconText: "󰅖"
        foreground: root.foreground
        leftAlign: true
        onClicked: {
          root.service.cancelSleepTimer(true)
          sleepPopup.close()
        }
      }
    }
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Music for Spotify"
    color: root.background
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(700, 560)

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }
    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) {
        if (root.dismissTransientPopup()) {
          event.accepted = true
          return
        }
        if (root.currentTab === "detail" || root.navigationStack.length) root.goBack()
        else root.requestClose()
        event.accepted = true
      }

      Shortcut {
        sequence: "Ctrl+K"
        onActivated: root.focusSearch()
      }
      Shortcut {
        sequence: "/"
        enabled: !root.textInputFocused()
        onActivated: root.focusSearch()
      }
      Shortcut {
        sequence: "Space"
        enabled: !root.textInputFocused()
        onActivated: if (root.service) root.service.togglePlayback()
      }
      Shortcut {
        sequence: "Ctrl+Right"
        onActivated: if (root.service) root.service.next()
      }
      Shortcut {
        sequence: "Ctrl+Left"
        onActivated: if (root.service) root.service.previous()
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(14)

        Row {
          id: workspace
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footerSeparator.top
          anchors.bottomMargin: Style.space(10)
          spacing: sidebar.visible ? Style.space(10) : 0

          BorderSurface {
            id: sidebar
            visible: root.currentTab !== "login"
            width: visible
              ? (root.compactWidth ? Style.space(54)
                : Math.min(Style.space(214), Math.max(Style.space(176), workspace.width * 0.225)))
              : 0
            height: parent.height
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

            Row {
              id: brandRow
              visible: !root.compactHeight
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: visible ? Style.space(11) : 0
              height: visible ? Style.space(42) : 0
              spacing: Style.space(9)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                visible: !root.compactWidth
                width: Math.max(40, parent.width - Style.space(38))
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  width: parent.width
                  text: "Music"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: "for Spotify"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Column {
              id: primaryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: brandRow.visible ? brandRow.bottom : parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }

              Repeater {
                model: root.primaryNavigationItems()

                Button {
                  required property var modelData
                  readonly property bool radioEntry: modelData.id === "radio"
                  width: primaryNavigation.width
                  text: root.compactWidth ? "" : modelData.label
                  iconText: modelData.icon
                  foreground: root.foreground
                  selected: radioEntry ? root.radioNavigationSelected()
                    : root.currentTab === modelData.id
                  leftAlign: !root.compactWidth
                  focusable: true
                  tooltipText: radioEntry && root.service && root.service.lastRadioPlaylist
                    ? modelData.label + " · " + root.service.lastRadioPlaylist.name
                    : modelData.label
                  onClicked: {
                    if (radioEntry) root.openLastRadio()
                    else root.chooseTab(modelData.id)
                  }
                }
              }

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }
            }

            Text {
              id: playlistShortcutsHeading
              visible: !root.compactWidth
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: primaryNavigation.bottom
              anchors.leftMargin: Style.space(13)
              anchors.rightMargin: Style.space(13)
              anchors.topMargin: Style.space(9)
              height: visible ? implicitHeight : 0
              text: "YOUR LIBRARY"
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Column {
              id: libraryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: playlistShortcutsHeading.visible
                ? playlistShortcutsHeading.bottom : primaryNavigation.bottom
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.topMargin: Style.space(6)
              spacing: Style.space(2)

              Button {
                width: parent.width
                text: root.compactWidth ? "" : "Liked Songs"
                iconText: "󰋑"
                foreground: root.foreground
                selected: root.currentTab === "library"
                leftAlign: !root.compactWidth
                focusable: true
                tooltipText: "Liked Songs"
                onClicked: root.chooseTab("library")
              }

              Button {
                width: parent.width
                text: root.compactWidth ? "" : "Playlists"
                iconText: "󱁐"
                foreground: root.foreground
                selected: root.currentTab === "playlists"
                leftAlign: !root.compactWidth
                focusable: true
                tooltipText: "Playlists"
                onClicked: root.chooseTab("playlists")
              }
            }

            ListView {
              id: playlistShortcuts
              visible: !root.compactWidth
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryNavigation.bottom
              anchors.bottom: setupNavButton.top
              anchors.margins: Style.space(8)
              model: root.service ? root.service.sidebarPlaylists() : []
              clip: true
              spacing: Style.space(1)
              reuseItems: true

              FastScrollHandler {
                parent: playlistShortcuts
                flickable: playlistShortcuts
                onScrolled: {
                  if (playlistShortcuts.atYEnd && root.service
                      && root.service.playlistsNext
                      && !root.service.playlistsLoading)
                    root.service.loadMorePlaylists()
                }
              }

              onMovementEnded: {
                if (atYEnd && root.service && root.service.playlistsNext
                    && !root.service.playlistsLoading) root.service.loadMorePlaylists()
              }

              delegate: Button {
                required property var modelData
                width: ListView.view.width
                text: root.sidebarPlaylistName(modelData)
                iconText: "󰲸"
                foreground: root.foreground
                leftAlign: true
                focusable: true
                selected: root.currentTab === "playlists" && root.service
                  && root.service.selectedPlaylist
                  && root.service.selectedPlaylist.id === modelData.id
                tooltipText: modelData.name || "Playlist"
                onClicked: {
                  root.chooseTab("playlists")
                  if (root.service) root.service.openPlaylist(modelData)
                }
              }
            }

            Button {
              id: setupNavButton
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(8)
              text: root.compactWidth ? "" : "Settings"
              iconText: root.service && root.service.auth.loggedIn ? "󰀄" : "󰒓"
              foreground: root.foreground
              selected: root.currentTab === "setup"
              leftAlign: !root.compactWidth
              focusable: true
              tooltipText: "Settings"
              onClicked: root.chooseTab("setup")
            }
          }

          Item {
            id: contentPane
            width: Math.max(220, parent.width - sidebar.width - workspace.spacing)
            height: parent.height

            Row {
              id: pageHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(52)
              spacing: Style.space(5)

              Button {
                id: backButton
                visible: root.currentTab === "detail" || root.navigationStack.length > 0
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰁍"
                foreground: root.foreground
                tooltipText: "Back"
                focusable: true
                onClicked: root.goBack()
              }

              Column {
                width: Math.max(80, parent.width
                  - (backButton.visible ? backButton.width + parent.spacing : 0)
                  - refreshButton.width - closeButton.width - parent.spacing * 2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: root.pageTitle()
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.pageSubtitle()
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                id: refreshButton
                visible: root.currentTab !== "login" && root.currentTab !== "setup"
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                foreground: root.foreground
                tooltipText: "Refresh"
                focusable: true
                onClicked: {
                  if (!root.service) return
                  if (root.currentTab === "detail" && root.service.detailItem)
                    root.service.openDetail(root.service.detailItem)
                  else if (root.currentTab === "library")
                    root.service.loadLibrary(root.libraryType, false, true)
                  else root.service.refreshView(root.currentTab)
                }
              }

              Button {
                id: closeButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                foreground: root.foreground
                tooltipText: "Close"
                focusable: true
                onClicked: root.requestClose()
              }
            }

            BorderSurface {
              id: statusBanner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: pageHeader.bottom
              anchors.topMargin: visible ? Style.space(6) : 0
              implicitHeight: visible ? messageText.implicitHeight + Style.space(12) : 0
              height: implicitHeight
              visible: root.service && (root.service.lastError !== "" || root.service.statusMessage !== "")
              color: root.service && root.service.lastError !== ""
                ? Style.selectedFillFor(root.foreground, Color.urgent)
                : Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground,
                root.service && root.service.lastError !== "" ? Color.urgent : root.accent)
              radius: Style.cornerRadius

              Text {
                id: messageText
                anchors.fill: parent
                anchors.margins: Style.space(6)
                text: !root.service ? "" : (root.service.lastError || root.service.statusMessage)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Loader {
              id: pageLoader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: statusBanner.visible ? statusBanner.bottom : pageHeader.bottom
              anchors.topMargin: Style.space(8)
              anchors.bottom: parent.bottom
              sourceComponent: root.pageComponent()
            }
          }
        }

        PanelSeparator {
          id: footerSeparator
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: playerFooter.top
          anchors.bottomMargin: Style.space(10)
          foreground: root.foreground
        }

        BorderSurface {
          id: playerFooter
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? Style.space(root.compactHeight ? 88 : 104) : 0
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

          Row {
            id: playerRow
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)

            Row {
              id: nowPlaying
              width: Math.max(Style.space(170), Math.min(Style.space(240), playerRow.width * 0.29))
              height: parent.height
              spacing: Style.space(9)

              BorderSurface {
                width: Math.min(parent.height, Style.space(68))
                height: width
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.cornerRadius
                color: Style.selectedFillFor(root.foreground, root.accent)
                borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  source: root.service ? root.service.artUrl : ""
                  sourceSize.width: 136
                  sourceSize.height: 136
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  cache: true
                  visible: status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !root.service || root.service.artUrl === ""
                  text: "󰎈"
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }

              }

              Column {
                width: Math.max(40, parent.width - parent.height - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  width: parent.width
                  text: root.service && root.service.title ? root.service.title : "Nothing playing"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.service && root.service.artist
                    ? root.service.artist : "Choose something to play"
                  color: root.service && root.service.artist ? root.accent
                    : Qt.darker(root.foreground, 1.38)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight

                  MouseArea {
                    anchors.fill: parent
                    enabled: root.service && root.service.artist !== ""
                      && root.service.currentTrackId() !== ""
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.service.currentContext("artist", function(item) {
                      root.openItem(item)
                    })
                  }
                }

                Text {
                  width: parent.width
                  visible: root.service && root.service.album !== ""
                    && root.service.currentTrackId() !== ""
                  text: root.service ? root.service.album : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.service.currentContext("album", function(item) {
                      root.openItem(item)
                    })
                  }
                }
              }
            }

            Column {
              id: transport
              width: Math.max(120, parent.width - nowPlaying.width - outputControls.width - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)

                Button {
                  iconText: "󰒟"
                  foreground: root.foreground
                  selected: root.service && root.service.shuffle
                  tooltipText: "Shuffle"
                  onClicked: if (root.service) root.service.setShuffle(!root.service.shuffle)
                }
                Button {
                  iconText: "󰒮"
                  foreground: root.foreground
                  tooltipText: "Previous"
                  onClicked: if (root.service) root.service.previous()
                }
                Button {
                  iconText: root.service && root.service.playing ? "󰏤" : "󰐊"
                  iconSize: Style.font.iconLarge
                  foreground: root.foreground
                  tooltipText: root.service && root.service.playing ? "Pause" : "Play"
                  onClicked: if (root.service) root.service.togglePlayback()
                }
                Button {
                  iconText: "󰒭"
                  foreground: root.foreground
                  tooltipText: "Next"
                  onClicked: if (root.service) root.service.next()
                }
                Button {
                  iconText: root.service && root.service.repeatMode === "track" ? "󰑘" : "󰑖"
                  foreground: root.foreground
                  selected: root.service && root.service.repeatMode !== "off"
                  tooltipText: "Repeat: " + (root.service ? root.service.repeatMode : "off")
                  onClicked: if (root.service) root.service.cycleRepeat()
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  id: positionFooterTime
                  anchors.verticalCenter: parent.verticalCenter
                  text: Api.millisecondsToClock((root.service ? root.service.positionSeconds : 0) * 1000)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelSlider {
                  width: Math.max(30, parent.width - positionFooterTime.implicitWidth
                    - durationFooterTime.implicitWidth - Style.space(12))
                  anchors.verticalCenter: parent.verticalCenter
                  bar: root.panelBar
                  minimum: 0
                  maximum: Math.max(1, root.service ? root.service.lengthSeconds : 1)
                  step: 5
                  value: root.service ? root.service.positionSeconds : 0
                  onReleased: function(value) {
                    if (root.service) root.service.seekSeconds(value)
                  }
                }

                Text {
                  id: durationFooterTime
                  anchors.verticalCenter: parent.verticalCenter
                  text: Api.millisecondsToClock((root.service ? root.service.lengthSeconds : 0) * 1000)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Column {
              id: outputControls
              width: Math.max(Style.space(128), Math.min(Style.space(170), playerRow.width * 0.22))
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Row {
                width: parent.width
                spacing: Style.space(5)

                Button {
                  iconText: "󰋋"
                  foreground: root.foreground
                  tooltipText: "Devices"
                  onClicked: root.chooseTab("devices")
                }

                Button {
                  iconText: "󰔛"
                  foreground: root.foreground
                  selected: root.service && root.service.sleepActive
                  tooltipText: root.service ? root.service.sleepStatusText() : "Sleep timer"
                  onClicked: sleepPopup.open()
                }

                PanelSlider {
                  width: Math.max(35, parent.width - Style.space(74))
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: root.service && root.service.hasPlayer
                  bar: root.panelBar
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.service ? root.service.volume : 0
                  onReleased: function(value) {
                    if (root.service) root.service.setVolume(value)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.service && root.service.playing
    onTriggered: root.service.refreshPosition()
  }

  Component {
    id: homePage

    Item {
      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Row {
          id: homeTypes
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { type: "recent", label: "Recently played", icon: "󰋚" },
              { type: "tracks", label: "Top songs", icon: "󰎈" },
              { type: "artists", label: "Top artists", icon: "󰠃" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              foreground: root.foreground
              selected: root.homeType === modelData.type
              onClicked: root.homeType = modelData.type
            }
          }
        }

        MediaCollection {
          width: parent.width
          height: Math.max(40, parent.height - homeTypes.height - parent.spacing)
          service: root.service
          sourceItems: root.service ? root.service.homeItems(root.homeType) : []
          showFilter: false
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.homeLoading
          hasMore: false
          restoredContentY: root.scrollFor("home:" + root.homeType)
          stateKey: "home:" + root.homeType
          emptyMessage: root.service && root.service.homeLoading
            ? "Loading your listening history…" : "No listening history is available yet."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onViewStateChanged: function(filter, sort, y) {
            root.rememberScroll("home:" + root.homeType, y)
          }
        }
      }
    }
  }

  Component {
    id: discoverPage

    Item {
      MediaCollection {
        anchors.fill: parent
        service: root.service
        sourceItems: root.service ? root.service.discoverPlaylists : []
        showFilter: false
        showQueue: false
        showPlaylist: false
        showSave: true
        browseContexts: true
        loading: root.service && root.service.discoverLoading
        hasMore: false
        restoredContentY: root.scrollFor("discover")
        stateKey: "discover"
        emptyMessage: root.service && root.service.discoverLoading
          ? "Finding playlists picked for you…"
          : (root.service && root.service.discoverMessage
            ? root.service.discoverMessage : "No discovery playlists are available yet.")
        onActivated: function(item, items, uri) {
          root.activateMedia(item, items, uri)
        }
        onOpened: function(item) { root.openItem(item) }
        onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
        onContextRequested: function(item, x, y, index, items, uri) {
          root.openMediaContext(item, x, y, items, uri, index)
        }
        onViewStateChanged: function(filter, sort, y) {
          root.rememberScroll("discover", y)
        }
      }
    }
  }

  Component {
    id: detailPage

    Item {
      id: detailRoot
      readonly property bool isArtist: root.service && root.service.detailItem
        && root.service.detailItem.type === "artist"

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        BorderSurface {
          id: detailHero
          width: parent.width
          height: Style.space(132)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)

            BorderSurface {
              width: parent.height
              height: width
              radius: Style.cornerRadius
              color: Style.selectedFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Image {
                id: detailArtwork
                anchors.fill: parent
                anchors.margins: Style.space(2)
                source: root.service && root.service.detailItem
                  ? root.service.detailItem.imageUrl : ""
                sourceSize.width: 256
                sourceSize.height: 256
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                visible: status === Image.Ready
              }
              Text {
                anchors.centerIn: parent
                visible: detailArtwork.status !== Image.Ready
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: Math.max(80, parent.width - parent.height - detailActions.width
                - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                width: parent.width
                text: root.service && root.service.detailItem
                  ? root.service.detailItem.name : "Loading…"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.service && root.service.detailItem
                  ? root.service.detailItem.subtitle : ""
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.service && root.service.detailItem
                  ? String(root.service.detailItem.description
                    || root.service.detailItem.releaseDate || "") : ""
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                maximumLineCount: 2
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
              }
            }

            Column {
              id: detailActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: "Play"
                iconText: "󰐊"
                foreground: root.foreground
                selected: true
                enabled: root.service && root.service.detailItem
                  && (["show", "audiobook"].indexOf(root.service.detailItem.type) < 0
                    || root.service.detailItems.length > 0)
                onClicked: {
                  if (["show", "audiobook"].indexOf(root.service.detailItem.type) >= 0)
                    root.service.playItem(root.service.detailItems[0],
                      root.service.detailItems, "")
                  else root.service.playItem(root.service.detailItem)
                }
              }
              Button {
                text: root.service && root.service.isSaved(root.service.detailItem)
                  ? "Saved" : "Save"
                iconText: root.service && root.service.isSaved(root.service.detailItem)
                  ? "󰓎" : "󰋑"
                foreground: root.foreground
                selected: root.service && root.service.isSaved(root.service.detailItem)
                enabled: root.service && root.service.detailItem
                  && !root.service.isSaved(root.service.detailItem)
                onClicked: if (root.service && !root.service.isSaved(root.service.detailItem))
                  root.service.toggleSaved(root.service.detailItem)
              }
              Button {
                id: detailMoreActions
                visible: root.service && root.service.detailItem
                iconText: "󰇙"
                foreground: root.foreground
                tooltipText: "More actions"
                onClicked: {
                  var point = detailMoreActions.mapToItem(window.contentItem,
                    detailMoreActions.width, 0)
                  root.openMediaContext(root.service.detailItem, point.x, point.y,
                    root.service.detailItems, root.service.detailItem.uri, -1)
                }
              }
            }
          }
        }

        Text {
          id: detailNotice
          width: parent.width
          height: visible ? implicitHeight : 0
          visible: root.service && root.service.detailMessage !== ""
          text: root.service ? root.service.detailMessage : ""
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          id: artistCatalog
          width: parent.width
          height: Math.max(40, parent.height - detailHero.height - detailNotice.height
            - parent.spacing * 2)
          visible: detailRoot.isArtist
          spacing: Style.space(7)

          Row {
            id: artistSearchRow
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: artistSearchField
              width: Math.max(80, parent.width - clearArtistSearch.width - parent.spacing)
              foreground: root.foreground
              placeholderText: "Find any album, EP, or song by this artist"
              text: root.artistSearchText
              onTextEdited: {
                root.artistSearchText = text
                artistSearchDelay.restart()
              }
              onAccepted: {
                artistSearchDelay.stop()
                if (root.service) root.service.findArtistMusic(text)
              }
            }

            Button {
              id: clearArtistSearch
              iconText: "󰅖"
              foreground: root.foreground
              tooltipText: "Show top music"
              enabled: root.artistSearchText !== ""
              onClicked: {
                artistSearchDelay.stop()
                root.artistSearchText = ""
                artistSearchField.text = ""
                if (root.service) root.service.findArtistMusic("")
                artistSearchField.forceActiveFocus()
              }
            }
          }

          Row {
            id: artistLists
            width: parent.width
            height: Math.max(40, parent.height - artistSearchRow.height - parent.spacing)
            spacing: Style.space(10)

            Column {
              width: Math.max(80, (parent.width - parent.spacing) / 2)
              height: parent.height
              spacing: Style.space(5)

              MediaRow {
                id: artistThisIsRow
                width: parent.width
                height: visible ? implicitHeight : 0
                visible: root.service && root.service.artistThisIsPlaylist
                itemData: root.service ? root.service.artistThisIsPlaylist : null
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                browseOnActivate: true
                showQueue: false
                showPlaylist: false
                showSave: true
                saved: root.service && root.service.isSaved(itemData)
                onActivated: function(item) { root.activateMedia(item, [item], item.uri) }
                onOpenRequested: function(item) { root.openItem(item) }
                onSaveRequested: function(item) {
                  if (root.service) root.service.toggleSaved(item)
                }
                onContextRequested: function(item, sceneX, sceneY) {
                  root.openMediaContext(item, sceneX, sceneY, [item], item.uri, 0)
                }
              }

              Text {
                id: artistAlbumsHeading
                width: parent.width
                text: root.artistSearchText.trim() ? "ALBUMS & EPS" : "TOP ALBUMS & EPS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MediaCollection {
                width: parent.width
                height: Math.max(30, parent.height - artistThisIsRow.height
                  - artistAlbumsHeading.height - parent.spacing
                  * (artistThisIsRow.visible ? 2 : 1))
                service: root.service
                sourceItems: root.service ? root.service.artistAlbums : []
                showFilter: false
                showQueue: false
                showSave: true
                browseContexts: true
                loading: root.service && root.service.artistAlbumsLoading
                hasMore: root.service && root.service.artistAlbumsNext !== ""
                emptyMessage: root.service && root.service.artistAlbumsLoading
                  ? "Finding releases…" : "No matching albums or EPs."
                onActivated: function(item, items, uri) {
                  root.activateMedia(item, items, uri)
                }
                onOpened: function(item) { root.openItem(item) }
                onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
                onContextRequested: function(item, x, y, index, items, uri) {
                  root.openMediaContext(item, x, y, items, uri, index)
                }
                onLoadMoreRequested: if (root.service) root.service.loadMoreArtistAlbums()
              }
            }

            Column {
              width: Math.max(80, parent.width - parent.spacing
                - Math.max(80, (parent.width - parent.spacing) / 2))
              height: parent.height
              spacing: Style.space(5)

              Text {
                id: artistSongsHeading
                width: parent.width
                text: root.artistSearchText.trim() ? "SONGS" : "TOP 10 SONGS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MediaCollection {
                width: parent.width
                height: Math.max(30, parent.height - artistSongsHeading.height - parent.spacing)
                service: root.service
                sourceItems: root.service ? root.service.artistSongs : []
                showFilter: false
                showQueue: true
                showSave: true
                browseContexts: false
                loading: root.service && root.service.artistSongsLoading
                hasMore: root.service && root.service.artistSongsNext !== ""
                emptyMessage: root.service && root.service.artistSongsLoading
                  ? "Finding songs…" : "No matching songs."
                onActivated: function(item, items, uri) {
                  root.activateMedia(item, items, uri)
                }
                onOpened: function(item) { root.openItem(item) }
                onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
                onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
                onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
                onContextRequested: function(item, x, y, index, items, uri) {
                  root.openMediaContext(item, x, y, items, uri, index)
                }
                onLoadMoreRequested: if (root.service) root.service.loadMoreArtistSongs()
              }
            }
          }

          Timer {
            id: artistSearchDelay
            interval: 300
            repeat: false
            onTriggered: if (root.service)
              root.service.findArtistMusic(root.artistSearchText)
          }
        }

        MediaCollection {
          id: detailCollection
          width: parent.width
          height: Math.max(40, parent.height - detailHero.height - detailNotice.height
            - parent.spacing * 2)
          visible: !detailRoot.isArtist
          service: root.service
          sourceItems: root.service ? root.service.detailItems : []
          filterText: root.detailFilter
          sortKey: root.detailSort
          contextUri: root.service && root.service.detailItem
            ? root.service.detailItem.uri : ""
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.detailLoading
          hasMore: root.service && root.service.detailNext !== ""
          restoredContentY: root.scrollFor("detail:" + (root.service && root.service.detailItem
            ? root.service.detailItem.uri : ""))
          stateKey: "detail:" + (root.service && root.service.detailItem
            ? root.service.detailItem.uri : "")
          emptyMessage: root.service && root.service.detailMessage
            ? root.service.detailMessage : "No items are available for this selection."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onLoadMoreRequested: if (root.service) root.service.loadMoreDetail()
          onViewStateChanged: function(filter, sort, y) {
            root.detailFilter = filter
            root.detailSort = sort
            root.rememberScroll("detail:" + (root.service && root.service.detailItem
              ? root.service.detailItem.uri : ""), y)
          }
        }
      }
    }
  }

  Component {
    id: searchPage

    Item {
      id: searchRoot

      function focusSearch() {
        searchField.selectAll()
        searchField.forceActiveFocus()
      }

      Component.onDestruction: {
        if (root.service) root.service.cancelSearch(false)
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: searchField
            width: Math.max(80, parent.width - clearSearchButton.width - parent.spacing)
            foreground: root.foreground
            placeholderText: "Search Spotify"
            text: root.searchText
            enabled: root.service && root.service.auth.loggedIn
            onTextEdited: {
              root.searchText = text
              if (!root.service) return
              if (String(text).trim() === "") {
                searchDelay.stop()
                root.service.clearSearch()
              } else searchDelay.restart()
            }
            onAccepted: {
              searchDelay.stop()
              root.searchText = text
              if (root.service) root.service.search(text)
            }
          }

          Button {
            id: clearSearchButton
            iconText: "󰅖"
            foreground: root.foreground
            tooltipText: "Clear search"
            enabled: root.searchText !== ""
            onClicked: {
              root.searchText = ""
              searchField.text = ""
              if (root.service) root.service.clearSearch()
              searchField.forceActiveFocus()
            }
          }
        }

        Row {
          id: searchTypes
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: [
              { type: "track", label: "Songs" },
              { type: "artist", label: "Artists" },
              { type: "album", label: "Albums" },
              { type: "playlist", label: "Playlists" },
              { type: "show", label: "Podcasts" },
              { type: "episode", label: "Episodes" },
              { type: "audiobook", label: "Books" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.foreground
              selected: root.searchType === modelData.type
              horizontalPadding: Style.space(7)
              onClicked: root.searchType = modelData.type
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(7)
          visible: root.searchText.trim() === ""

          Row {
            width: parent.width

            Text {
              text: "RECENT SEARCHES"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Item { width: Math.max(0, parent.width - clearHistory.width - Style.space(120)); height: 1 }
            Button {
              id: clearHistory
              text: "Clear"
              foreground: root.foreground
              visible: root.service && root.service.searchHistory.length > 0
              onClicked: root.service.clearSearchHistory()
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(5)

            Repeater {
              model: root.service ? root.service.searchHistory : []
              Button {
                required property string modelData
                text: modelData
                iconText: "󰍉"
                foreground: root.foreground
                onClicked: {
                  root.searchText = modelData
                  searchField.text = modelData
                  root.service.search(modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.service || root.service.searchHistory.length === 0
            text: "Type a title, artist, album, playlist, podcast, episode, or audiobook."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        MediaCollection {
          id: resultsView
          width: parent.width
          height: Math.max(40, parent.height - searchField.height - searchTypes.height
            - Style.space(20))
          visible: root.searchText.trim() !== ""
          service: root.service
          sourceItems: root.service ? root.service.searchItems(root.searchType) : []
          showFilter: false
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.searchLoading
          hasMore: root.service && root.service.searchNext(root.searchType) !== ""
          restoredContentY: root.scrollFor("search:" + root.searchType)
          stateKey: "search:" + root.searchType
          emptyMessage: root.service && root.service.searchLoading
            ? "Searching…" : "No " + root.searchType + " results."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onLoadMoreRequested: if (root.service) root.service.loadMoreSearch(root.searchType)
          onViewStateChanged: function(filter, sort, y) {
            root.rememberScroll("search:" + root.searchType, y)
          }
        }
      }

      Timer {
        id: searchDelay
        interval: 300
        repeat: false
        onTriggered: if (root.service && root.service.searchQuery !== root.searchText.trim())
          root.service.search(root.searchText)
      }
    }
  }

  Component {
    id: libraryPage

    Item {
      Component.onCompleted: if (root.service) root.service.loadLibrary(root.libraryType, false)

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Row {
          id: libraryTypes
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { type: "tracks", label: "Songs", icon: "󰎈" },
              { type: "albums", label: "Albums", icon: "󰀥" },
              { type: "artists", label: "Artists", icon: "󰠃" },
              { type: "shows", label: "Podcasts", icon: "󰦔" },
              { type: "episodes", label: "Episodes", icon: "󰐾" },
              { type: "audiobooks", label: "Books", icon: "󰂺" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              foreground: root.foreground
              selected: root.libraryType === modelData.type
              onClicked: {
                root.libraryType = modelData.type
                if (root.service) root.service.loadLibrary(modelData.type, false)
              }
            }
          }
        }

        MediaCollection {
          id: libraryCollection
          width: parent.width
          height: Math.max(40, parent.height - libraryTypes.height - parent.spacing)
          service: root.service
          sourceItems: root.service ? root.service.libraryItems(root.libraryType) : []
          filterText: root.libraryFilter
          sortKey: root.librarySort
          showQueue: true
          showSave: true
          browseContexts: true
          loading: root.service && root.service.libraryLoading(root.libraryType)
          hasMore: root.service && root.service.libraryNext(root.libraryType) !== ""
          restoredContentY: root.scrollFor("library:" + root.libraryType)
          stateKey: "library:" + root.libraryType
          emptyMessage: "No saved items in this section."
          onActivated: function(item, items, uri) {
            root.activateMedia(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onLoadMoreRequested: if (root.service) root.service.loadLibrary(root.libraryType, true)
          onViewStateChanged: function(filter, sort, y) {
            root.libraryFilter = filter
            root.librarySort = sort
            root.rememberScroll("library:" + root.libraryType, y)
          }
        }
      }
    }
  }

  Component {
    id: playlistsPage

    Item {
      Column {
        anchors.fill: parent
        spacing: Style.space(6)

        Column {
          id: selectedPlaylistHeader
          width: parent.width
          spacing: Style.space(6)

          SearchableDropdown {
            visible: root.compactWidth
            width: parent.width
            height: visible ? implicitHeight : 0
            showLabel: false
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            placeholderText: "Choose a playlist…"
            emptyText: root.service && root.service.playlistsLoading
              ? "Loading playlists…" : "No playlists found"
            options: root.playlistOptions()
            value: root.service && root.service.selectedPlaylist
              ? String(root.service.selectedPlaylist.id) : ""
            onChanged: function(value) {
              var playlist = root.service ? root.service.playlistById(value) : null
              if (playlist) root.service.openPlaylist(playlist)
            }
          }

          Button {
            visible: root.compactWidth && root.service
              && root.service.playlistsNext !== ""
            width: parent.width
            text: root.service && root.service.playlistsLoading
              ? "Loading more playlists…" : "Load more playlists"
            iconText: "󰑐"
            foreground: root.foreground
            enabled: root.service && !root.service.playlistsLoading
            onClicked: root.service.loadMorePlaylists()
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: Math.max(40, parent.width
                - (playPlaylist.visible ? playPlaylist.width + parent.spacing : 0)
                - (playlistMoreActions.visible
                  ? playlistMoreActions.width + parent.spacing : 0))
              text: root.service && root.service.selectedPlaylist
                ? root.service.selectedPlaylist.name : "Select a playlist"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Button {
              id: playPlaylist
              visible: root.service && root.service.selectedPlaylist
              iconText: "󰐊"
              text: "Play"
              foreground: root.foreground
              onClicked: root.service.playItem(root.service.selectedPlaylist)
            }

            Button {
              id: playlistMoreActions
              visible: root.service && root.service.selectedPlaylist
              iconText: "󰇙"
              foreground: root.foreground
              tooltipText: "More actions"
              onClicked: {
                var point = playlistMoreActions.mapToItem(window.contentItem,
                  playlistMoreActions.width, 0)
                root.openMediaContext(root.service.selectedPlaylist, point.x, point.y,
                  [], root.service.selectedPlaylist.uri, -1)
              }
            }
          }

          Row {
            id: createPlaylistRow
            width: Math.min(parent.width, Style.space(390))
            spacing: Style.space(5)

            TextField {
              id: inlinePlaylistName
              width: Math.max(70, parent.width - inlineCreateButton.width - parent.spacing)
              foreground: root.foreground
              placeholderText: "Name a new playlist"
              onAccepted: inlineCreateButton.clicked()
            }
            Button {
              id: inlineCreateButton
              text: "Create"
              iconText: "󰐕"
              foreground: root.foreground
              tooltipText: "Create playlist"
              enabled: root.service && inlinePlaylistName.text.trim() !== ""
                && !root.service.playlistActionBusy
              onClicked: root.service.createPlaylist(inlinePlaylistName.text, function(playlist) {
                inlinePlaylistName.text = ""
                root.service.openPlaylist(playlist)
              })
            }
          }

          Button {
            width: parent.width
            visible: root.service && root.service.selectedPlaylist
              && root.service.currentUserId !== ""
              && !root.service.playlistOwned(root.service.selectedPlaylist)
            text: root.service && root.service.playlistConversionBusy
              ? "Making your copy…" : "Turn into your own playlist"
            iconText: "󰒍"
            foreground: root.foreground
            selected: true
            enabled: root.service && !root.service.playlistActionBusy
            tooltipText: "Copy every available item, then remove the followed original"
            onClicked: root.turnPlaylistIntoOwn(root.service.selectedPlaylist)
          }
        }

        MediaCollection {
          id: playlistItemsCollection
          width: parent.width
          height: Math.max(40, parent.height - selectedPlaylistHeader.height - parent.spacing)
          service: root.service
          sourceItems: root.service ? root.service.playlistItems : []
          filterText: root.playlistFilter
          sortKey: root.playlistSort
          contextUri: root.service && root.service.selectedPlaylist
            ? root.service.selectedPlaylist.uri : ""
          showQueue: true
          showSave: true
          browseContexts: false
          loading: root.service && root.service.playlistItemsLoading
          hasMore: root.service && root.service.playlistItemsNext !== ""
          emptyMessage: root.service && root.service.selectedPlaylist
            ? "This playlist has no visible items."
            : (root.compactWidth ? "Choose a playlist above."
              : "Choose a playlist from the sidebar.")
          restoredContentY: root.scrollFor("playlist:" + (root.service
            && root.service.selectedPlaylist ? root.service.selectedPlaylist.id : ""))
          stateKey: "playlist:" + (root.service && root.service.selectedPlaylist
            ? root.service.selectedPlaylist.id : "")
          onActivated: function(item, items, uri) {
            if (root.service) root.service.playItem(item, items, uri)
          }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.addToQueue(item) }
          onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri) {
            root.openMediaContext(item, x, y, items, uri, index)
          }
          onLoadMoreRequested: if (root.service) root.service.loadMorePlaylistItems()
          onViewStateChanged: function(filter, sort, y) {
            root.playlistFilter = filter
            root.playlistSort = sort
            root.rememberScroll("playlist:" + (root.service
              && root.service.selectedPlaylist ? root.service.selectedPlaylist.id : ""), y)
          }
        }
      }
    }
  }

  Component {
    id: queuePage

    Item {
      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        Row {
          width: parent.width

          Text {
            text: "UP NEXT"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item { width: Math.max(0, parent.width - queueRefresh.width - Style.space(80)); height: 1 }

          Button {
            id: queueRefresh
            text: root.service && root.service.queueLoading ? "Loading…" : "Refresh"
            iconText: "󰑐"
            foreground: root.foreground
            enabled: root.service && !root.service.queueLoading
            onClicked: root.service.loadQueue()
          }
        }

        ListView {
          id: queueList
          width: parent.width
          height: Math.max(60, parent.height - Style.space(44))
          model: root.service ? root.service.queue : []
          clip: true
          spacing: Style.space(3)
          reuseItems: true
          cacheBuffer: Style.space(140)
          ScrollBar.vertical: ScrollBar { }

          FastScrollHandler { parent: queueList; flickable: queueList }

          delegate: MediaRow {
            required property var modelData
            required property int index
            itemData: modelData
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            showQueue: false
            showSave: true
            saved: root.service && root.service.isSaved(modelData)
            onActivated: function(item) {
              if (root.service) root.service.playItem(item, root.service.queue, "")
            }
            onArtistRequested: function(item) { root.openItem(item) }
            onAlbumRequested: function(item) { root.openItem(item) }
            onOpenRequested: function(item) { root.openItem(item) }
            onPlaylistRequested: function(item) { root.openPlaylistPicker(item) }
            onSaveRequested: function(item) { if (root.service) root.service.toggleSaved(item) }
            onContextRequested: function(item, sceneX, sceneY) {
              root.openMediaContext(item, sceneX, sceneY,
                root.service ? root.service.queue : [], "", index)
            }
          }
        }
      }
    }
  }

  Component {
    id: devicesPage

    Item {
      ScrollView {
        id: devicesScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: devicesScroll.availableWidth
          spacing: Style.space(9)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: Math.max(80, parent.width - deviceRefresh.width - parent.spacing)
              text: "Choose where your music plays. This computer and nearby Spotify Connect devices appear here."
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              id: deviceRefresh
              text: root.service && root.service.devicesLoading ? "Loading…" : "Refresh"
              iconText: "󰑐"
              foreground: root.foreground
              enabled: root.service && !root.service.devicesLoading
                && !root.service.deviceActivationBusy
              onClicked: root.service.loadDevices(null, undefined, true)
            }
          }

          Text {
            text: "AVAILABLE DEVICES"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            text: "A nearby speaker may take a moment to connect the first time you choose it."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.service ? root.service.devices : []

            delegate: BorderSurface {
            id: deviceRow
            required property var modelData
            width: devicesScroll.availableWidth
            implicitHeight: Style.space(58)
            height: implicitHeight
            radius: Style.cornerRadius
            color: modelData.id === (root.service ? root.service.selectedDeviceId : "")
              ? Style.selectedFillFor(root.foreground, root.accent)
              : (deviceHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
            borderSpec: modelData.active
              ? Border.controlSpec("selected", root.foreground, root.accent) : Border.none()

            HoverHandler { id: deviceHover }
            MouseArea {
              anchors.fill: parent
              enabled: !deviceRow.modelData.restricted && root.service
                && !root.service.deviceActivationBusy
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
              onClicked: if (root.service) root.service.selectDevice(deviceRow.modelData.id, true)
            }

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(9)
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: deviceRow.modelData.type.toLowerCase() === "computer" ? "󰟀" : "󰋋"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                width: Math.max(40, parent.width - Style.space(150))
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: deviceRow.modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: deviceRow.modelData.active
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: deviceRow.modelData.type
                    + (deviceRow.modelData.description ? " · " + deviceRow.modelData.description : "")
                    + (deviceRow.modelData.local ? " · this computer" : "")
                    + (deviceRow.modelData.localDiscovery ? " · nearby" : "")
                    + (deviceRow.modelData.restricted ? " · unavailable" : "")
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.service && root.service.deviceActivationBusy
                    && deviceRow.modelData.id === root.service.selectedDeviceId ? "Connecting"
                  : (deviceRow.modelData.active ? "Active"
                    : (deviceRow.modelData.activationRequired ? "Available"
                      : Math.round(deviceRow.modelData.volumePercent) + "%"))
                color: deviceRow.modelData.active ? root.accent : Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
          }

          Text {
            width: parent.width
            visible: root.service && root.service.devicesLoaded
              && root.service.devices.length === 0
            text: "No Spotify Connect devices are available right now. Make sure the device is online, then refresh."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Item { width: 1; height: Style.space(4) }
        }
      }

      FastScrollHandler {
        parent: devicesScroll.contentItem
        flickable: devicesScroll.contentItem
      }
    }
  }

  Component {
    id: loginPage

    Item {
      ScrollView {
        id: loginScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: Math.min(Style.space(620), loginScroll.availableWidth)
          x: Math.max(0, (loginScroll.availableWidth - width) / 2)
          spacing: Style.space(14)

          Item { width: 1; height: Style.space(4) }

          Column {
            width: parent.width
            spacing: Style.space(5)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: ""
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Music for Spotify"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Your music, library, playlists, and Spotify Connect devices — at home in Omarchy."
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          BorderSurface {
            width: parent.width
            implicitHeight: loginContent.implicitHeight + Style.space(28)
            color: Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
            radius: Style.cornerRadius

            Column {
              id: loginContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(14)
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(10)

                BorderSurface {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: root.fullyConnected
                    ? Style.selectedFillFor(root.foreground, root.accent)
                    : Style.normalFillFor(root.foreground, root.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                  Text {
                    anchors.centerIn: parent
                    text: root.fullyConnected ? "󰄬" : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    font.bold: true
                  }
                }

                Column {
                  width: Math.max(40, parent.width - Style.space(44))
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    text: root.connectionHeadline()
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }
                  Text {
                    text: root.service ? root.service.loginProgress : "Spotify is unavailable"
                    color: root.fullyConnected
                      ? root.accent : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                width: parent.width
                text: "Spotify may open two approval pages the first time. Finish both and Music for Spotify will bring you back here automatically."
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Column {
                width: parent.width
                spacing: Style.space(7)

                Row {
                  spacing: Style.space(7)
                  Text {
                    text: root.service && root.service.auth.loggedIn ? "󰄬" : "󰋼"
                    color: root.service && root.service.auth.loggedIn
                      ? root.accent : Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.service && root.service.auth.loggedIn
                      ? "Your Spotify account is connected"
                      : (root.service && root.service.auth.loginBusy
                        ? "Connecting your Spotify account…"
                        : "Your Spotify account and library")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Row {
                  spacing: Style.space(7)
                  Text {
                    text: root.service && root.service.daemon.credentialsAvailable ? "󰄬" : "󰓃"
                    color: root.service && root.service.daemon.credentialsAvailable
                      ? root.accent : Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.service && root.service.daemon.credentialsAvailable
                      ? "Playback on this computer is connected"
                      : (root.service && root.service.daemon.authenticationBusy
                        ? "Connecting playback on this computer…"
                        : "Playback on this computer")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              Button {
                width: parent.width
                text: root.connectionButtonText()
                iconText: "󰍂"
                foreground: root.foreground
                selected: root.fullyConnected
                enabled: root.service && !root.fullyConnected && !root.service.loginBusy
                onClicked: if (root.service) root.service.login()
              }

              Text {
                width: parent.width
                text: !root.service || root.service.daemon.playbackReady
                  || root.service.daemon.setupBusy ? ""
                  : (root.service.daemon.binaryAvailable
                    ? "This prepares private, on-demand playback for your account."
                    : "Omarchy may ask for your computer password to install its small playback component.")
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                visible: text !== ""
              }

              Text {
                width: parent.width
                text: root.connectionErrorText()
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                visible: text !== ""
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Your password is entered only on Spotify's own page. Music for Spotify never sees it."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Item { width: 1; height: Style.space(4) }
        }
      }

      FastScrollHandler {
        parent: loginScroll.contentItem
        flickable: loginScroll.contentItem
      }
    }
  }

  Component {
    id: setupPage

    Item {
      ScrollView {
        id: setupScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: setupScroll.availableWidth
          spacing: Style.space(16)

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "SPOTIFY ACCOUNT"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Connect Spotify to search, browse your library, manage playlists, and listen on this computer or another Spotify Connect device."
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: accountStatus.implicitHeight + Style.space(16)
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Text {
                id: accountStatus
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: !root.service ? "Spotify is unavailable"
                  : (root.service.loginBusy ? root.service.loginProgress + "…"
                  : (root.fullyConnected ? "Connected and ready to play"
                  : (root.service.auth.loggedIn
                    ? "Spotify is connected · playback needs approval"
                    : (root.service.daemon.credentialsAvailable
                      ? "Playback is ready · Spotify needs approval"
                      : "Not connected"))))
                color: root.fullyConnected ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            Row {
              spacing: Style.space(7)

              Button {
                text: root.connectionButtonText()
                iconText: "󰍂"
                foreground: root.foreground
                selected: root.fullyConnected
                visible: !root.fullyConnected
                enabled: root.service && !root.service.loginBusy
                onClicked: if (root.service) root.service.login()
              }
              Button {
                text: "Reconnect Spotify"
                iconText: "󰑐"
                foreground: root.foreground
                visible: root.service && root.service.auth.loggedIn
                enabled: root.service && !root.service.loginBusy
                tooltipText: "Reconnect if library or playlist features are not working"
                onClicked: root.service.reconnectAccount()
              }
              Button {
                text: "Log out"
                iconText: "󰍃"
                foreground: root.foreground
                visible: root.service && (root.service.auth.loggedIn
                  || root.service.daemon.credentialsAvailable)
                enabled: root.service && !root.service.loginBusy
                  && !root.service.daemon.busy
                onClicked: root.service.logout()
              }
            }

            Text {
              width: parent.width
              text: root.connectionErrorText()
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              visible: text !== ""
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "PLAYBACK ON THIS COMPUTER"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width
              text: "A lightweight background player starts only when you need it, works with Omarchy's media controls, and appears in Spotify Connect as this computer."
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: engineStatus.implicitHeight + Style.space(16)
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Text {
                id: engineStatus
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: root.playbackStatusText()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            Row {
              spacing: Style.space(7)

              Button {
                text: root.service && root.service.daemon.setupBusy
                  ? "Setting up playback…" : "Set up playback"
                iconText: "󰓃"
                foreground: root.foreground
                visible: root.service && !root.service.daemon.playbackReady
                enabled: root.service && !root.service.loginBusy
                onClicked: root.service.login()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "PREFERENCES"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: Math.round(parent.width * 0.58)
                spacing: Style.space(4)

                Text {
                  text: "THIS COMPUTER APPEARS AS"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "Omarchy Spotify"
                  text: root.draftDeviceName
                  onTextEdited: root.draftDeviceName = text
                }
              }
              Column {
                width: Math.max(Style.space(150), parent.width - Math.round(parent.width * 0.58)
                  - parent.spacing)
                spacing: Style.space(4)

                Text {
                  text: "STOP WHEN IDLE · MINUTES"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "15"
                  text: root.draftIdleMinutes
                  validator: IntValidator { bottom: 0; top: 1440 }
                  onTextEdited: root.draftIdleMinutes = text
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: root.draftShowTitle ? "Song title in bar · On" : "Song title in bar · Off"
                foreground: root.foreground
                selected: root.draftShowTitle
                onClicked: root.draftShowTitle = !root.draftShowTitle
              }
              Button {
                text: "Audio quality · " + root.audioQualityLabel()
                iconText: "󰎈"
                foreground: root.foreground
                tooltipText: "Change streaming quality"
                onClicked: root.cycleAudioQuality()
              }
              Button {
                text: "Save changes"
                iconText: "󰆓"
                foreground: root.foreground
                selected: true
                onClicked: root.saveSettings()
              }
            }

            Text {
              width: parent.width
              text: "Use 0 idle minutes to keep this computer visible in Spotify Connect. Otherwise playback support sleeps when it is not in use. Device name and audio quality changes apply to Spotify Connect the next time music starts."
              color: Qt.darker(root.foreground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      FastScrollHandler {
        parent: setupScroll.contentItem
        flickable: setupScroll.contentItem
      }
    }
  }
}
