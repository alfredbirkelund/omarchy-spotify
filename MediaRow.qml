import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

BorderSurface {
  id: root

  required property var itemData
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool selected: false
  property bool showPlay: true
  property bool showQueue: false
  property bool showPlaylist: true
  property bool showSave: false
  property bool saved: false
  property bool browseOnActivate: false
  property bool hovered: hoverHandler.hovered

  signal activated(var item)
  signal openRequested(var item)
  signal queueRequested(var item)
  signal playlistRequested(var item)
  signal saveRequested(var item)
  signal artistRequested(var item)
  signal albumRequested(var item)
  signal contextRequested(var item, real sceneX, real sceneY)

  readonly property var leadingContext: {
    if (!itemData) return null
    if (itemData.type === "track" && Array.isArray(itemData.artists)
        && itemData.artists.length) return itemData.artists[0]
    return itemData.parentContext || null
  }
  readonly property var secondaryContext: itemData && itemData.type === "track"
    ? itemData.albumItem : null

  function triggerPrimary() {
    if (browseOnActivate) openRequested(itemData)
    else activated(itemData)
  }

  function triggerPlay() { activated(itemData) }

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(420)
  implicitHeight: Style.space(66)
  height: implicitHeight
  radius: Style.cornerRadius
  color: selected ? Style.selectedFillFor(foreground, accent)
    : (hovered ? Style.hoverFillFor(foreground, accent) : "transparent")
  borderSpec: selected
    ? Border.controlSpec("selected", foreground, accent)
    : Border.none()
  clip: true

  HoverHandler { id: hoverHandler }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
        root.contextRequested(root.itemData, scenePoint.x, scenePoint.y)
      } else {
        root.triggerPrimary()
      }
    }
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(9)

    BorderSurface {
      width: parent.height
      height: width
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(root.foreground, root.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

      Image {
        id: rowArtwork
        anchors.fill: parent
        anchors.margins: Style.space(2)
        source: root.itemData && root.itemData.imageUrl ? root.itemData.imageUrl : ""
        sourceSize.width: 112
        sourceSize.height: 112
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // List delegates are recycled; do not retain every scrolled artwork
        // pixmap in the process. The current-track artwork is the only image
        // intentionally kept in Qt's shared cache.
        cache: false
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: rowArtwork.status !== Image.Ready
        text: !root.itemData ? "󰝚"
          : (root.itemData.type === "playlist" ? "󰲸"
          : (root.itemData.type === "artist" ? "󰠃"
          : (root.itemData.type === "album" ? "󰀥"
          : (root.itemData.type === "show" || root.itemData.type === "episode" ? "󰦔"
          : (root.itemData.type === "audiobook" || root.itemData.type === "chapter" ? "󰂺" : "󰝚")))))
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    Column {
      width: Math.max(20, parent.width - parent.height - actionRow.width - Style.space(20))
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.selected
        elide: Text.ElideRight
      }

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          id: subtitleText
          width: root.secondaryContext
            ? Math.min(implicitWidth, Math.max(20, Math.round(parent.width * 0.48)))
            : parent.width
          text: root.itemData ? String(root.itemData.subtitle || "") : ""
          color: root.leadingContext ? root.accent : Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          visible: text !== ""

          MouseArea {
            anchors.fill: parent
            enabled: !!root.leadingContext
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              if (!root.leadingContext) return
              if (root.leadingContext.type === "artist")
                root.artistRequested(root.leadingContext)
              else root.openRequested(root.leadingContext)
            }
          }
        }

        Text {
          id: albumText
          visible: !!root.secondaryContext
          width: visible ? Math.max(20, parent.width - subtitleText.width - parent.spacing) : 0
          text: root.secondaryContext ? "· " + String(root.secondaryContext.name || "Album") : ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.secondaryContext) root.albumRequested(root.secondaryContext)
          }
        }
      }
    }

    Row {
      id: actionRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        visible: root.itemData && root.itemData.kind === "item"
          && Number(root.itemData.durationMs) > 0
        anchors.verticalCenter: parent.verticalCenter
        text: Api.millisecondsToClock(root.itemData ? root.itemData.durationMs : 0)
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        visible: root.showSave && !root.saved && root.itemData && !!root.itemData.uri
          && root.itemData.type !== "chapter"
        iconText: "󰋑"
        foreground: root.foreground
        tooltipText: "Save to library"
        horizontalPadding: Style.space(7)
        onClicked: root.saveRequested(root.itemData)
      }

      Button {
        visible: root.showPlaylist && root.itemData
          && ["track", "episode"].indexOf(root.itemData.type) >= 0
        iconText: "󱁐"
        foreground: root.foreground
        tooltipText: "Add to playlist"
        horizontalPadding: Style.space(7)
        onClicked: root.playlistRequested(root.itemData)
      }

      Button {
        visible: root.showQueue && root.itemData
          && ["track", "episode"].indexOf(root.itemData.type) >= 0
        iconText: "󰐕"
        foreground: root.foreground
        tooltipText: "Add to queue"
        horizontalPadding: Style.space(7)
        onClicked: root.queueRequested(root.itemData)
      }

      Button {
        visible: root.showPlay && root.itemData
          && ["show", "audiobook"].indexOf(root.itemData.type) < 0
        iconText: "󰐊"
        foreground: root.foreground
        tooltipText: "Play"
        horizontalPadding: Style.space(7)
        onClicked: root.triggerPlay()
      }
    }
  }
}
