import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root

  required property var service
  property var sourceItems: []
  property string filterText: ""
  property string sortKey: "default"
  property string contextUri: ""
  property bool showFilter: true
  property bool showQueue: true
  property bool showPlaylist: true
  property bool showSave: true
  property bool browseContexts: true
  property bool loading: false
  property bool hasMore: false
  property string emptyMessage: "Nothing here yet."
  property real restoredContentY: 0
  property string stateKey: ""
  property bool restoreApplied: false

  readonly property var visibleItems: Api.filteredSorted(sourceItems, filterText, sortKey)
  readonly property var sortKeys: ["default", "name", "artist", "album", "duration", "date"]

  signal activated(var item, var sourceItems, string contextUri)
  signal opened(var item)
  signal queued(var item)
  signal playlistRequested(var item)
  signal saveToggled(var item)
  signal contextRequested(var item, real sceneX, real sceneY, int index,
    var sourceItems, string contextUri)
  signal loadMoreRequested()
  signal viewStateChanged(string filterText, string sortKey, real contentY)

  function sortLabel() {
    if (sortKey === "name") return "Title"
    if (sortKey === "artist") return "Artist"
    if (sortKey === "album") return "Album"
    if (sortKey === "duration") return "Duration"
    if (sortKey === "date") return "Date"
    return "Original"
  }

  function cycleSort() {
    var index = sortKeys.indexOf(sortKey)
    sortKey = sortKeys[(index + 1) % sortKeys.length]
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }

  function focusList() {
    mediaList.forceActiveFocus()
    if (mediaList.currentIndex < 0 && mediaList.count > 0) mediaList.currentIndex = 0
  }

  function rememberView() {
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }

  function restoreView() {
    if (restoreApplied || restoredContentY <= 0 || mediaList.count <= 0) return
    Qt.callLater(function() {
      if (root.restoreApplied || mediaList.count <= 0) return
      var maximum = Math.max(mediaList.originY,
        mediaList.contentHeight - mediaList.height + mediaList.originY)
      mediaList.contentY = Math.max(mediaList.originY,
        Math.min(maximum, root.restoredContentY))
      root.restoreApplied = true
    })
  }

  function resetRestore() {
    restoreApplied = false
    Qt.callLater(function() {
      if (root.restoredContentY <= 0) {
        mediaList.contentY = mediaList.originY
        root.restoreApplied = true
      } else {
        root.restoreView()
      }
    })
  }

  Component.onCompleted: restoreView()
  onRestoredContentYChanged: resetRestore()
  onStateKeyChanged: resetRestore()
  Component.onDestruction: rememberView()

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      id: tools
      width: parent.width
      height: root.showFilter ? Style.space(38) : 0
      visible: root.showFilter
      spacing: Style.space(7)

      TextField {
        id: filterField
        width: Math.max(80, parent.width - sortButton.width - countLabel.width
          - parent.spacing * 2)
        foreground: Color.foreground
        placeholderText: "Filter this list"
        text: root.filterText
        onTextEdited: {
          root.filterText = text
          root.viewStateChanged(root.filterText, root.sortKey, mediaList.contentY)
        }
        Keys.onDownPressed: root.focusList()
      }

      Button {
        id: sortButton
        text: root.sortLabel()
        iconText: "󰒺"
        foreground: Color.foreground
        tooltipText: "Change sort order"
        onClicked: root.cycleSort()
      }

      Text {
        id: countLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.visibleItems.length
          + (root.filterText ? (root.visibleItems.length === 1 ? " match" : " matches")
            : (root.visibleItems.length === 1 ? " item" : " items"))
        color: Qt.darker(Color.foreground, 1.42)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    ListView {
      id: mediaList
      width: parent.width
      height: Math.max(30, parent.height - tools.height - moreButton.height
        - emptyLabel.height - parent.spacing * 3)
      model: root.visibleItems
      clip: true
      spacing: Style.space(3)
      reuseItems: true
      cacheBuffer: Style.space(160)
      activeFocusOnTab: true
      keyNavigationEnabled: true
      highlightFollowsCurrentItem: true
      ScrollBar.vertical: ScrollBar { }
      onMovementEnded: root.rememberView()
      onCountChanged: root.restoreView()

      Keys.onReturnPressed: if (currentItem) currentItem.triggerPrimary()
      Keys.onEnterPressed: if (currentItem) currentItem.triggerPrimary()

      delegate: MediaRow {
        required property var modelData
        required property int index
        itemData: modelData
        foreground: Color.foreground
        accent: Color.accent
        fontFamily: Style.font.family
        selected: ListView.isCurrentItem
        browseOnActivate: root.browseContexts && modelData.kind === "context"
        showQueue: root.showQueue
        showPlaylist: root.showPlaylist
        showSave: root.showSave
        saved: root.service ? root.service.isSaved(modelData) : false
        onActivated: function(item) {
          root.activated(item, root.visibleItems, root.contextUri)
        }
        onOpenRequested: function(item) { root.opened(item) }
        onArtistRequested: function(item) { root.opened(item) }
        onAlbumRequested: function(item) { root.opened(item) }
        onQueueRequested: function(item) { root.queued(item) }
        onPlaylistRequested: function(item) { root.playlistRequested(item) }
        onSaveRequested: function(item) { root.saveToggled(item) }
        onContextRequested: function(item, sceneX, sceneY) {
          root.contextRequested(item, sceneX, sceneY, index,
            root.visibleItems, root.contextUri)
        }
      }
    }

    Text {
      id: emptyLabel
      width: parent.width
      height: visible ? implicitHeight : 0
      visible: !root.loading && root.visibleItems.length === 0
      text: root.emptyMessage
      color: Qt.darker(Color.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Button {
      id: moreButton
      anchors.horizontalCenter: parent.horizontalCenter
      height: visible ? implicitHeight : 0
      visible: root.loading || root.hasMore
      text: root.loading ? "Loading…" : "Load more"
      foreground: Color.foreground
      enabled: root.hasMore && !root.loading
      onClicked: root.loadMoreRequested()
    }
  }
}
