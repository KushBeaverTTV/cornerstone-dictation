import QtQuick
import Quickshell
import Quickshell.Io

// Single session-wide service for Cornerstone Dictation: watches the status,
// pid, transcript, and config files with FileView (zero idle shell polling)
// and owns the single `cornerstone` IPC target across all monitors.
Item {
  id: service

  property var shell: null
  readonly property string pluginId: "cornerstone.panel"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state"))
    + "/omarchy-dictation-cornerstone"
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config"))
    + "/omarchy/dictation-cornerstone"
  readonly property string statusScript: Qt.resolvedUrl("cornerstone-status.sh").toString().replace(/^file:\/\//, "")

  // idle | recording | processing | error | nokey
  property string state: "idle"
  property string lastText: ""
  property bool polishOn: true
  property bool soundsOn: true
  property string styleName: "natural"
  property string engineName: "local"
  property string micLabel: ""

  readonly property bool recording: state === "recording"
  readonly property bool processing: state === "processing"
  readonly property bool broken: state === "error" || state === "nokey"
  readonly property bool live: recording || processing

  property bool probePending: false

  function probeStatus() {
    if (statusProc.running) {
      probePending = true
      return
    }
    probePending = false
    statusProc.running = true
  }

  function refreshConfig() {
    if (!configProc.running) configProc.running = true
  }

  function engineLabel() {
    if (engineName === "qwen") return "Qwen + Whisper check"
    if (engineName === "cpu") return "CPU local"
    if (engineName === "mistral") return "Mistral cloud"
    return "Whisper only"
  }

  // ---- event-driven file watchers (no idle polling)
  FileView {
    id: statusFile
    path: service.stateDir + "/status"
    watchChanges: true
    printErrors: false
    onLoaded: service.probeStatus()
    onFileChanged: { reload(); service.probeStatus() }
    onLoadFailed: service.probeStatus()
  }

  FileView {
    id: pidFile
    path: service.stateDir + "/record.pid"
    watchChanges: true
    printErrors: false
    onLoaded: service.probeStatus()
    onFileChanged: { reload(); service.probeStatus() }
    onLoadFailed: service.probeStatus()
  }

  FileView {
    id: lastTextView
    path: service.stateDir + "/last_text"
    watchChanges: true
    printErrors: false
    onLoaded: service.lastText = String(text() || "").trim()
    onFileChanged: reload()
  }

  FileView {
    id: configFile
    path: service.configDir + "/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: { service.refreshConfig(); service.probeStatus() }
    onFileChanged: { reload(); service.refreshConfig(); service.probeStatus() }
  }

  // Safety-net liveness check only while recording or processing, so a dead
  // recorder PID cannot leave the widget stuck active.
  Timer {
    interval: 4000
    running: service.live
    repeat: true
    onTriggered: service.probeStatus()
  }

  Timer {
    id: configRefreshSoon
    interval: 400
    onTriggered: { service.refreshConfig(); service.probeStatus() }
  }

  Process {
    id: statusProc
    command: ["bash", service.statusScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = String(this.text || "").trim()
        if (s === "idle" || s === "recording" || s === "processing" || s === "error" || s === "nokey")
          service.state = s
      }
    }
    onExited: if (service.probePending) Qt.callLater(service.probeStatus)
  }

  Process {
    id: configProc
    command: ["omarchy-dictation-cornerstone", "config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(this.text || ""))
          service.polishOn = d.polish !== false
          service.soundsOn = d.sounds !== false
          service.styleName = String(d.style || "natural").slice(0, 32)
          service.engineName = String(d.stt_engine || "local").slice(0, 32)
          service.micLabel = String(d.mic_label || "").slice(0, 80)
        } catch (e) {}
      }
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    probeStatus()
    refreshConfig()
  })

  // ---- actions
  function exec(argv, refreshAfter) {
    Quickshell.execDetached(argv)
    if (refreshAfter) configRefreshSoon.restart()
  }

  function dictateStart() { exec(["omarchy-dictation", "start"], true) }
  function dictateStop() { exec(["omarchy-dictation", "stop"], true) }
  function dictateToggle() { exec(["omarchy-dictation", "toggle"], true) }
  function emergencyStop() { exec(["omarchy-dictation-cornerstone", "panic"], true) }
  function retryLast() { exec(["omarchy-dictation-cornerstone", "retry"], true) }
  function copyLast() { if (lastText.length > 0) exec(["omarchy-dictation-cornerstone", "copy-last"], false) }
  function openKeyFile() { exec(["xdg-open", configDir + "/api_key"], false) }
  function openConfig() { exec(["xdg-open", configDir + "/config.json"], false) }
  function openLog() {
    exec(["omarchy-launch-tui", "sh", "-c", 'less +G "$1"', "sh", stateDir + "/last.log"], false)
  }

  function polishToggle() {
    exec(["omarchy-dictation-cornerstone", polishOn ? "polish-off" : "polish-on"], true)
  }

  function soundsToggle() {
    exec(["omarchy-dictation-cornerstone", soundsOn ? "sounds-off" : "sounds-on"], true)
  }

  function cycleStyle() {
    var order = ["natural", "chat", "email", "code"]
    var i = order.indexOf(styleName)
    var next = order[(i < 0 ? 0 : i + 1) % order.length]
    exec(["omarchy-dictation-cornerstone", "style", next], true)
  }

  function cycleEngine() {
    var order = ["qwen", "local", "cpu", "mistral"]
    var i = order.indexOf(engineName)
    var next = order[(i < 0 ? 0 : i + 1) % order.length]
    exec(["omarchy-dictation-cornerstone", "engine", next], true)
  }

  // ---- single IPC handler per session
  IpcHandler {
    target: "cornerstone"

    function open(): string { if (service.shell) service.shell.summon(service.pluginId); return "open" }
    function toggle(): string { if (service.shell) service.shell.toggle(service.pluginId); return "ok" }
    function status(): string { return service.state }
    function dictate(): string { service.dictateToggle(); return "toggled" }
    function start(): string { service.dictateStart(); return "starting" }
    function stop(): string { service.dictateStop(); return "stopping" }
    function panic(): string { service.emergencyStop(); return "emergency stop" }
    function refresh(): string { service.probeStatus(); service.refreshConfig(); return "ok" }
  }
}
