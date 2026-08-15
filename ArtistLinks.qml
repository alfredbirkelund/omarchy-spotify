import QtQuick

import "Api.js" as Api

Item {
  id: root

  property var artists: []
  property string fallbackText: ""
  property string suffixText: ""
  property bool fallbackClickable: false
  property alias color: label.color
  property alias font: label.font
  property alias maximumLineCount: label.maximumLineCount
  property alias elide: label.elide
  property color accent: color

  signal artistRequested(var artist)
  signal fallbackRequested(string name)

  function escaped(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  function artistValues() {
    var source = Api.arrayValues(artists)
    var result = []
    for (var i = 0; i < source.length; i++)
      if (source[i] && source[i].name) result.push(source[i])
    return result
  }

  function markup() {
    var values = artistValues()
    var parts = []
    for (var i = 0; i < values.length; i++)
      parts.push("<a href=\"artist:" + i + "\">"
        + escaped(values[i].name) + "</a>")
    var main = parts.length ? parts.join(", ") : escaped(fallbackText)
    if (!parts.length && fallbackClickable && main)
      main = "<a href=\"fallback\">" + main + "</a>"
    return main + escaped(suffixText)
  }

  function activateLink(link) {
    var value = String(link || "")
    if (value === "fallback") {
      fallbackRequested(fallbackText)
      return
    }
    var match = value.match(/^artist:([0-9]+)$/)
    var values = artistValues()
    var index = match ? Number(match[1]) : -1
    if (index >= 0 && index < values.length) artistRequested(values[index])
  }

  function linkAt(x, y) { return label.linkAt(x, y) }

  implicitWidth: label.implicitWidth
  implicitHeight: label.implicitHeight
  height: implicitHeight
  clip: true

  Text {
    id: label
    anchors.fill: parent
    text: root.markup()
    textFormat: Text.StyledText
    linkColor: root.accent
    maximumLineCount: 1
    elide: Text.ElideRight
  }

  MouseArea {
    anchors.fill: parent
    z: 1
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    propagateComposedEvents: true
    cursorShape: containsMouse && root.linkAt(mouseX, mouseY) !== ""
      ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      var link = root.linkAt(mouse.x, mouse.y)
      if (link) root.activateLink(link)
      else mouse.accepted = false
    }
  }
}
