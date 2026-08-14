import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

import "Api.js" as Api

BarWidget {
  id: root

  moduleName: "quickshell.spotify"

  readonly property var spotify: bar && bar.shell
    ? bar.shell.serviceFor("quickshell.spotify") : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string surfaceKey: "spotify-popup-" + String(root)
  readonly property string barText: spotify
    ? Api.barTrackText(spotify.title, spotify.artist,
      spotify.showTrackTitle, spotify.showArtistName) : ""
  readonly property bool iconOnly: !spotify || vertical || !spotify.hasMedia
    || barText === ""
  property bool popupOpen: false
  readonly property bool opened: popupOpen

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  function openFullPanel() {
    close()
    if (bar && bar.shell) bar.shell.toggle("quickshell.spotify", "{}")
  }

  function syncSettings() {
    if (spotify) spotify.applySettings(settings)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onSettingsChanged: syncSettings()
  onSpotifyChanged: syncSettings()
  onPopupOpenChanged: if (spotify) spotify.setUiVisible(surfaceKey, popupOpen)
  Component.onCompleted: syncSettings()
  Component.onDestruction: if (spotify) spotify.setUiVisible(surfaceKey, false)

  TextMetrics {
    id: labelMetrics
    text: root.barText
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  TextMetrics {
    id: glyphMetrics
    text: ""
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: root.iconOnly
    hasVisualContent: true
    fontSize: root.iconOnly ? Style.font.bodySmall : Style.font.body
    active: root.spotify && root.spotify.playing
    // Keep the playing state legible on transparent bars. WidgetButton's
    // foreground follows bar.barForeground, which the shell derives from the
    // wallpaper underneath the bar.
    activeColor: button.foreground
    tooltipText: root.spotify && root.spotify.hasMedia
      ? root.spotify.title + (root.spotify.artist ? " — " + root.spotify.artist : "")
      : "Omarchy Spotify"
    fixedWidth: root.vertical ? root.barSize
      : (root.iconOnly ? Style.bar.statusSlot
        : Math.min(Style.space(240), Math.max(root.barSize,
          glyphMetrics.advanceWidth + labelMetrics.advanceWidth + Style.space(24))))
    fixedHeight: root.vertical && root.iconOnly ? Style.bar.statusSlot : -1
    clip: true

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(6)
      visible: !root.iconOnly
      enabled: false

      Text {
        id: barGlyph
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: button.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Item {
        id: scrollClip
        width: Math.max(0, button.width - barGlyph.implicitWidth
          - barContent.spacing - button.scaledHorizontalMargin * 2)
        height: barGlyph.implicitHeight
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        Text {
          id: barLabel
          anchors.verticalCenter: parent.verticalCenter
          text: root.barText
          color: button.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering

          readonly property bool needsScroll: labelMetrics.advanceWidth > scrollClip.width

          NumberAnimation on x {
            id: barScrollAnimation
            running: root.spotify && root.spotify.scrollBarText
              && barLabel.needsScroll && !root.popupOpen && !root.vertical
            loops: Animation.Infinite
            duration: Math.round(Math.max(6000, labelMetrics.advanceWidth * 25)
              / Math.max(0.25, root.spotify ? root.spotify.scrollSpeed : 1))
            from: scrollClip.width
            to: -labelMetrics.advanceWidth
            easing.type: Easing.Linear
            onStopped: barLabel.x = 0
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        if (root.spotify) root.spotify.togglePlayback()
      } else if (mouseButton === Qt.RightButton) {
        root.openFullPanel()
      } else if (!root.spotify || !root.spotify.fullyConnected) {
        root.openFullPanel()
      } else {
        root.toggle()
      }
    }
    onWheelMoved: function(delta) {
      if (!root.spotify) return
      if (delta > 0) root.spotify.previous()
      else if (delta < 0) root.spotify.next()
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: fittedContentWidth(Style.space(340))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight)

    Column {
      id: contentColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(12)

        BorderSurface {
          width: Style.space(78)
          height: width
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

          Image {
            id: popupArtwork
            anchors.fill: parent
            anchors.margins: Style.space(3)
            source: root.popupOpen && root.spotify ? root.spotify.artUrl : ""
            sourceSize.width: 156
            sourceSize.height: 156
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: popupArtwork.status !== Image.Ready
            text: ""
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.displayLarge
          }

        }

        Column {
          width: parent.width - Style.space(90)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            width: parent.width
            text: root.spotify && root.spotify.title ? root.spotify.title : "Nothing playing"
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.spotify ? root.spotify.artist : ""
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            visible: text !== ""
          }

          Text {
            width: parent.width
            text: root.spotify ? root.spotify.album : ""
            color: Qt.darker(root.foreground, 1.55)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            visible: text !== ""
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(3)
        visible: root.spotify && root.spotify.lengthSeconds > 0

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: Math.max(1, root.spotify ? root.spotify.lengthSeconds : 1)
          value: root.spotify ? root.spotify.positionSeconds : 0
          step: 5
          onReleased: function(value) {
            if (root.spotify) root.spotify.seekSeconds(value)
          }
        }

        Row {
          width: parent.width

          Text {
            id: positionTime
            text: Api.millisecondsToClock((root.spotify ? root.spotify.positionSeconds : 0) * 1000)
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Item { width: Math.max(0, parent.width - positionTime.implicitWidth - endTime.implicitWidth); height: 1 }

          Text {
            id: endTime
            text: Api.millisecondsToClock((root.spotify ? root.spotify.lengthSeconds : 0) * 1000)
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(5)

        Button {
          iconText: "󰒟"
          foreground: root.foreground
          selected: root.spotify && root.spotify.shuffle
          tooltipText: "Shuffle"
          enabled: root.spotify && root.spotify.playbackControllable
          onClicked: if (root.spotify) root.spotify.setShuffle(!root.spotify.shuffle)
        }

        Button {
          iconText: "󰒮"
          foreground: root.foreground
          tooltipText: "Previous"
          enabled: root.spotify && root.spotify.playbackControllable
          onClicked: if (root.spotify) root.spotify.previous()
        }

        Button {
          iconText: root.spotify && root.spotify.playing ? "󰏤" : "󰐊"
          iconSize: Style.font.iconLarge
          foreground: root.foreground
          tooltipText: root.spotify && root.spotify.playing ? "Pause" : "Play"
          enabled: root.spotify && root.spotify.playbackControllable
          onClicked: if (root.spotify) root.spotify.togglePlayback()
        }

        Button {
          iconText: "󰒭"
          foreground: root.foreground
          tooltipText: "Next"
          enabled: root.spotify && root.spotify.playbackControllable
          onClicked: if (root.spotify) root.spotify.next()
        }

        Button {
          iconText: root.spotify && root.spotify.repeatMode === "track" ? "󰑘" : "󰑖"
          foreground: root.foreground
          selected: root.spotify && root.spotify.repeatMode !== "off"
          tooltipText: "Repeat: " + (root.spotify ? root.spotify.repeatMode : "off")
          enabled: root.spotify && root.spotify.playbackControllable
          onClicked: if (root.spotify) root.spotify.cycleRepeat()
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        visible: root.spotify && root.spotify.hasPlayer

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰕾"
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
        }

        PanelSlider {
          width: parent.width - Style.space(34)
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.spotify ? root.spotify.volume : 0
          enabled: root.spotify && root.spotify.volumeSupported
          onReleased: function(value) {
            if (root.spotify) root.spotify.setVolume(value)
          }
        }
      }

      PanelSeparator { foreground: root.foreground }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          width: parent.width - openButton.width - Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: !root.spotify ? "Spotify is unavailable"
            : (!root.spotify.fullyConnected ? "Continue with Spotify"
            : (root.spotify.useRemotePlayback
              ? (root.spotify.playing ? "Playing on " : "Connected to ")
                + root.spotify.playbackDeviceName
              : (root.spotify.daemon.running ? "Playing on this computer" : "Ready when you press play")))
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Button {
          id: openButton
          text: "Open"
          iconText: "󰏋"
          foreground: root.foreground
          onClicked: root.openFullPanel()
        }
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.spotify && root.spotify.playing
    onTriggered: root.spotify.refreshPosition()
  }
}
