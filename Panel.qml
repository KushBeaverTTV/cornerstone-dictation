import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cornerstone dictation — bar mark is the Cornerstone keystone.
// Live state from the status file written
// by omarchy-dictation-cornerstone.
Panel {
  id: root
  moduleName: "cornerstone"
  ipcTarget: "cornerstone"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: root.home + "/.config/omarchy/plugins/cornerstone.panel"
  readonly property string statusScript: root.pluginDir + "/cornerstone-status.sh"
  readonly property string iconPath: Qt.resolvedUrl("assets/cornerstone.png")
  readonly property string lastTextPath: root.home + "/.local/state/omarchy-dictation-cornerstone/last_text"
  readonly property string logPath: root.home + "/.local/state/omarchy-dictation-cornerstone/last.log"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Cornerstone palette — yellow / black / white
  readonly property color brandBlue: "#FFD400"
  readonly property color brandDeep: "#7A5C00"
  readonly property color brandLight: "#FFEC99"
  readonly property color brandOrange: "#FF4D00"
  readonly property color recordColor: brandOrange
  readonly property color workColor: brandBlue
  readonly property color errorColor: "#E11414"

  // idle | recording | processing | error | nokey
  property string state: "idle"
  property string lastText: ""

  readonly property bool recording: root.state === "recording"
  readonly property bool processing: root.state === "processing"
  readonly property bool broken: root.state === "error" || root.state === "nokey"
  readonly property bool live: root.recording || root.processing

  readonly property color barIconColor: {
    if (root.recording) return root.recordColor
    if (root.processing) return root.workColor
    if (root.state === "error") return root.errorColor
    if (root.state === "nokey") return root.muted
    return root.foreground
  }

  readonly property string statusText: {
    if (root.state === "recording") return "Listening…"
    if (root.state === "processing") return root.polishOn ? "Transcribing + polish…" : "Transcribing locally…"
    if (root.state === "error") return "Last run failed — audio kept, tap Retry"
    if (root.state === "nokey") return "API key missing"
    return "Idle — hold Right Option (or Right Ctrl)"
  }

  readonly property string statusDetail: {
    if (root.state === "nokey")
      return "Put your Mistral key in ~/.config/omarchy/dictation-cornerstone/api_key"
    if (root.lastText.length > 0)
      return "Last: " + root.lastText
    return "Alt+Space or Super+Shift+Space toggles · click starts/stops"
  }

  // ---------------------------------------------------------------- state

  Process {
    id: statusProc
    command: ["bash", root.statusScript]
    stdout: StdioCollector {
      onStreamFinished: {
        var s = String(this.text).trim()
        if (s === "idle" || s === "recording" || s === "processing" || s === "error" || s === "nokey")
          root.state = s
      }
    }
  }

  FileView {
    id: lastTextView
    path: root.lastTextPath
    watchChanges: true
    onLoaded: root.lastText = String(text()).trim()
    onFileChanged: reload()
  }

  // Poll fast while live so the bar feels instant; slow when idle.
  Timer {
    interval: root.live ? 250 : 900
    running: true
    repeat: true
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  function dictateStart() {
    if (root.bar) root.bar.run("omarchy-dictation start")
  }
  function dictateStop() {
    if (root.bar) root.bar.run("omarchy-dictation stop")
  }
  function dictateToggle() {
    if (root.bar) root.bar.run("omarchy-dictation toggle")
  }
  function openLog() {
    if (root.bar) root.bar.run("omarchy-launch-tui sh -c 'less +G ~/.local/state/omarchy-dictation-cornerstone/last.log'")
  }
  function openKeyFile() {
    if (root.bar) root.bar.run("xdg-open ~/.config/omarchy/dictation-cornerstone/api_key")
  }
  function openConfig() {
    if (root.bar) root.bar.run("xdg-open ~/.config/omarchy/dictation-cornerstone/config.json")
  }
  function copyLast() {
    if (root.lastText.length > 0 && root.bar)
      root.bar.run("omarchy-dictation-cornerstone copy-last")
  }
  function emergencyStop() {
    if (root.bar) root.bar.run("omarchy-dictation-cornerstone panic")
  }
  function retryLast() {
    if (root.bar) root.bar.run("omarchy-dictation-cornerstone retry")
  }
  function polishToggle() {
    if (!root.bar) return
    if (root.polishOn) root.bar.run("omarchy-dictation-cornerstone polish-off")
    else root.bar.run("omarchy-dictation-cornerstone polish-on")
    polishTimer.start()
  }
  function cycleStyle() {
    if (!root.bar) return
    var order = ["natural", "chat", "email", "code"]
    var i = order.indexOf(root.styleName)
    var next = order[(i < 0 ? 0 : i + 1) % order.length]
    root.bar.run("omarchy-dictation-cornerstone style " + next)
    polishTimer.start()
  }
  function soundsToggle() {
    if (!root.bar) return
    if (root.soundsOn) root.bar.run("omarchy-dictation-cornerstone sounds-off")
    else root.bar.run("omarchy-dictation-cornerstone sounds-on")
    polishTimer.start()
  }
  function cycleEngine() {
    if (!root.bar) return
    var order = ["qwen", "local", "cpu", "mistral"]
    var i = order.indexOf(root.engineName)
    var next = order[(i < 0 ? 0 : i + 1) % order.length]
    root.bar.run("omarchy-dictation-cornerstone engine " + next)
    polishTimer.start()
  }
  function engineLabel() {
    if (root.engineName === "qwen") return "Qwen + Whisper check"
    if (root.engineName === "cpu") return "CPU local"
    if (root.engineName === "mistral") return "Mistral cloud"
    return "Whisper only"
  }

  property bool polishOn: true
  property bool soundsOn: true
  property string styleName: "natural"
  property string engineName: "local"
  property string micLabel: ""

  Process {
    id: configProc
    command: ["omarchy-dictation-cornerstone", "config"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(String(this.text))
          root.polishOn = d.polish !== false
          root.soundsOn = d.sounds !== false
          root.styleName = d.style || "natural"
          root.engineName = d.stt_engine || "local"
          root.micLabel = d.mic_label || ""
        } catch (e) {}
      }
    }
  }
  Timer {
    id: polishTimer
    interval: 400
    onTriggered: { configProc.running = true }
  }
  Component.onCompleted: Qt.callLater(function() {
    statusProc.running = true
    lastTextView.reload()
    configProc.running = true
  })

  IpcHandler {
    id: ipc
    target: root.ipcTarget
    function open(): string { root.toggle(); return root.opened ? "open" : "closed" }
    function toggle(): string { root.toggle(); return root.opened ? "open" : "closed" }
    function status(): string { return root.state }
    function dictate(): string { root.dictateToggle(); return "toggled" }
    function start(): string { root.dictateStart(); return "starting" }
    function stop(): string { root.dictateStop(); return "stopping" }
    function panic(): string { root.emergencyStop(); return "emergency stop" }
    Component.onCompleted: IpcRegistry.register(ipc)
    Component.onDestruction: IpcRegistry.unregister(ipc)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: ""
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.dictateToggle()
      else if (buttonCode === Qt.MiddleButton) root.emergencyStop()
      else root.toggle()
    }

    iconComponent: Component {
      Item {
        width: 24
        height: 24
        clip: true

        // Cornerstone keystone mark
        Image {
          id: mark
          anchors.centerIn: parent
          width: 24
          height: 24
          source: root.iconPath
          sourceSize.width: 128
          sourceSize.height: 128
          fillMode: Image.PreserveAspectFit
          smooth: false
          mipmap: false
          asynchronous: false
          opacity: root.state === "nokey" ? 0.4 : 1.0
          Behavior on opacity {
            NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
          }
          // Pulse while listening / processing
          SequentialAnimation on opacity {
            running: root.live
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 320; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 320; easing.type: Easing.InOutQuad }
          }
        }

        // Accent ring while live (orange listen / blue process)
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.width: root.live ? 1.5 : 0
          border.color: root.recording ? root.recordColor : root.workColor
          opacity: root.live ? 0.9 : 0
          Behavior on opacity {
            NumberAnimation { duration: Style.duration(160) }
          }
        }

        // Tiny error pip
        Rectangle {
          visible: root.broken
          width: 6
          height: 6
          radius: 3
          anchors.right: parent.right
          anchors.top: parent.top
          color: root.state === "nokey" ? root.muted : root.errorColor
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "d" || t === "D") root.dictateToggle()
        else if (t === "l" || t === "L") root.openLog()
        else if (t === "k" || t === "K") root.openKeyFile()
        else if (t === "c" || t === "C") root.copyLast()
      }

      clip: true

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        Row {
          spacing: Style.space(10)
          Image {
            width: 36
            height: 36
            source: root.iconPath
            sourceSize.width: 72
            sourceSize.height: 72
            fillMode: Image.PreserveAspectFit
            smooth: false
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: "Cornerstone"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: root.engineName === "qwen" ? "Local Qwen · Whisper check" : "Local Whisper · Mistral fallback"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: root.statusText
          color: root.recording ? root.recordColor
               : root.processing ? root.workColor
               : root.broken ? root.errorColor
               : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: root.live
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.statusDetail.replace(/\s+/g, " ")
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Emergency stop: always here, kills recorder + jobs, frees memory.
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.space(6)
          color: stopArea.containsMouse ? Qt.rgba(0.88, 0.08, 0.08, 0.95) : Qt.rgba(0.88, 0.08, 0.08, 0.75)
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "■  Emergency stop (kill dictation, free memory)"
            color: "#FFFFFF"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          MouseArea {
            id: stopArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.emergencyStop(); root.close() }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.hairline
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: {
              var rows = []
              if (root.recording)
                rows.push({ id: "stop", label: "Stop listening" })
              else if (root.processing)
                rows.push({ id: "busy", label: "Working… (wait)" })
              else
                rows.push({ id: "start", label: "Start dictation" })
              rows.push({ id: "polish", label: root.polishOn ? "Polish: ON (tap to disable)" : "Polish: OFF (tap to enable)" })
              rows.push({ id: "style", label: "Style: " + root.styleName + " (tap to cycle)" })
              rows.push({ id: "engine", label: "Engine: " + root.engineLabel() + " (tap to cycle)" })
              rows.push({ id: "sounds", label: root.soundsOn ? "Sounds: ON (tap to disable)" : "Sounds: OFF (tap to enable)" })
              if (root.micLabel.length > 0)
                rows.push({ id: "mic", label: "Mic: " + root.micLabel + " (tap for config)" })
              if (root.lastText.length > 0)
                rows.push({ id: "copy", label: "Copy last transcript" })
              if (root.state === "error")
                rows.push({ id: "retry", label: "Retry last recording" })
              if (root.state === "nokey")
                rows.push({ id: "key", label: "Open API key file" })
              rows.push({ id: "cfg", label: "Open config / vocab files" })
              rows.push({ id: "log", label: "Open last log" })
              return rows
            }
            Rectangle {
              required property var modelData
              width: parent.width
              height: Style.space(30)
              radius: Style.space(6)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              opacity: modelData.id === "busy" ? 0.55 : 1.0
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width - Style.space(20)
              }
              MouseArea {
                anchors.fill: parent
                enabled: modelData.id !== "busy"
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (modelData.id === "start") { root.dictateStart(); root.close() }
                  else if (modelData.id === "stop") { root.dictateStop() }
                  else if (modelData.id === "polish") root.polishToggle()
                  else if (modelData.id === "style") root.cycleStyle()
                  else if (modelData.id === "engine") root.cycleEngine()
                  else if (modelData.id === "sounds") root.soundsToggle()
                  else if (modelData.id === "mic") { root.openConfig(); root.close() }
                  else if (modelData.id === "copy") { root.copyLast(); root.close() }
                  else if (modelData.id === "retry") { root.retryLast(); root.close() }
                  else if (modelData.id === "key") { root.openKeyFile(); root.close() }
                  else if (modelData.id === "cfg") { root.openConfig(); root.close() }
                  else if (modelData.id === "log") { root.openLog(); root.close() }
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.hairline
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Hold Right Alt = talk · Alt+Space = toggle · Emergency stop: middle-click icon or Super+Ctrl+Esc · auto-stops at 10 min"
          wrapMode: Text.WordWrap
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
