import QtQuick
import Quickshell.Io

import "Api.js" as Api

// Runs one-shot local discovery and activation commands. There is no resident
// network scanner: discovery happens only when the Devices page is opened or
// explicitly refreshed.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property string pluginDir: ""
  property var devices: []
  property bool loading: false
  property bool activating: false
  property string activatingDeviceId: ""
  property string activationInput: ""
  property string discoveryResult: ""
  property string activationResult: ""
  property string lastError: ""

  signal refreshed()
  signal refreshFailed(string reason)
  signal activated(string deviceId)
  signal activationFailed(string reason)

  function safeError(value) {
    return Api.redact(String(value || ""))
  }

  function refresh() {
    if (loading || discoveryCommand.running || !pluginDir) return
    loading = true
    lastError = ""
    discoveryResult = ""
    discoveryCommand.command = [pluginDir + "/scripts/spotify-connect-device.py", "discover"]
    discoveryCommand.running = true
  }

  function activate(deviceId) {
    var requested = String(deviceId || "")
    if (activating || activationCommand.running || !pluginDir
        || !/^[A-Za-z0-9_.:-]{8,160}$/.test(requested)) return
    activating = true
    activatingDeviceId = requested
    activationInput = requested
    activationResult = ""
    lastError = ""
    activationCommand.command = [pluginDir + "/scripts/spotify-connect-device.py", "activate"]
    activationCommand.running = true
  }

  function applyDiscovery(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      if (payload.schemaVersion !== 1 || !Array.isArray(payload.devices)) throw new Error("schema")
      var next = []
      for (var i = 0; i < payload.devices.length && next.length < 32; i++) {
        var item = payload.devices[i] || {}
        var id = String(item.id || "")
        if (!/^[A-Za-z0-9_.:-]{8,160}$/.test(id)) continue
        next.push({
          id: id,
          name: String(item.name || "Spotify Connect device").slice(0, 160),
          type: String(item.type || "Speaker").slice(0, 80),
          description: String(item.description || "").slice(0, 260),
          localDiscovery: true,
          activationRequired: true,
          activeUser: item.activeUser === true
        })
      }
      devices = next
    } catch (e) {
      devices = []
    }
  }

  Process {
    id: discoveryCommand
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.discoveryResult = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) {
        root.applyDiscovery(root.discoveryResult)
        root.discoveryResult = ""
        root.lastError = ""
        root.refreshed()
      } else {
        root.discoveryResult = ""
        root.lastError = "Could not find Spotify Connect devices on this network"
        root.refreshFailed(root.lastError)
      }
    }
  }

  Process {
    id: activationCommand
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.activationResult = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(root.activationInput + "\n")
      root.activationInput = ""
    }
    onExited: function(exitCode) {
      var requested = root.activatingDeviceId
      root.activating = false
      root.activatingDeviceId = ""
      root.activationInput = ""
      root.activationResult = ""
      if (exitCode === 0) {
        root.lastError = ""
        root.activated(requested)
      } else {
        root.lastError = "Could not connect to this Spotify Connect device"
        root.activationFailed(root.lastError)
      }
    }
  }
}
