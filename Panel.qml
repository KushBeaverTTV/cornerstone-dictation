import QtQuick
import qs.Commons
import qs.Ui

// Cornerstone dictation — bar mark is the Cornerstone keystone.
// Built once per monitor; all watchers, commands and IPC live in Service.qml.
Panel {
  id: root
  moduleName: "cornerstone"
  ipcTarget: "cornerstone"
  manageIpc: false

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("cornerstone.panel") : null
  readonly property string iconPath: Qt.resolvedUrl("assets/cornerstone.png")

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Cornerstone status accents
  readonly property color brandBlue: "#FFD400"
  readonly property color brandOrange: "#FF4D00"
  readonly property color recordColor: brandOrange
  readonly property color workColor: brandBlue
  readonly property color errorColor: Color.urgent

  readonly property string state: service ? service.state : "idle"
  readonly property string lastText: service ? service.lastText : ""
  readonly property bool polishOn: service ? service.polishOn : true
  readonly property bool soundsOn: service ? service.soundsOn : true
  readonly property string styleName: service ? service.styleName : "natural"
  readonly property string engineName: service ? service.engineName : "local"
  readonly property string micLabel: service ? service.micLabel : ""

  readonly property bool recording: state === "recording"
  readonly property bool processing: state === "processing"
  readonly property bool broken: state === "error" || state === "nokey"
  readonly property bool live: recording || processing

  readonly property string engineText: service ? service.engineLabel() : "Whisper only"

  readonly property string statusText: {
    if (state === "recording") return "Listening…"
    if (state === "processing") return polishOn ? "Transcribing + polish…" : "Transcribing locally…"
    if (state === "error") return "Last run failed — audio kept, tap Retry"
    if (state === "nokey") return "API key missing"
    return "Idle — hold Right Option (or Right Ctrl)"
  }

  readonly property string statusDetail: {
    if (state === "nokey")
      return "Put your Mistral key in ~/.config/omarchy/dictation-cornerstone/api_key"
    if (lastText.length > 0)
      return "Last: " + lastText
    return "Alt+Space or Super+Shift+Space toggles · click starts/stops"
  }

  readonly property string barTooltip: {
    if (recording) return "Cornerstone · Listening…"
    if (processing) return "Cornerstone · Transcribing…"
    if (state === "error") return "Cornerstone · Last run failed"
    if (state === "nokey") return "Cornerstone · API key missing"
    return "Cornerstone · " + engineText
  }

  readonly property var actionRows: {
    var rows = []
    if (recording) rows.push({ id: "stop", label: "Stop listening" })
    else if (processing) rows.push({ id: "busy", label: "Working… (wait)" })
    else rows.push({ id: "start", label: "Start dictation" })
    rows.push({ id: "polish", label: polishOn ? "Polish: ON (tap to disable)" : "Polish: OFF (tap to enable)" })
    rows.push({ id: "style", label: "Style: " + styleName + " (tap to cycle)" })
    rows.push({ id: "engine", label: "Engine: " + engineText + " (tap to cycle)" })
    rows.push({ id: "sounds", label: soundsOn ? "Sounds: ON (tap to disable)" : "Sounds: OFF (tap to enable)" })
    if (micLabel.length > 0) rows.push({ id: "mic", label: "Mic: " + micLabel + " (tap for config)" })
    if (lastText.length > 0) rows.push({ id: "copy", label: "Copy last transcript" })
    if (state === "error") rows.push({ id: "retry", label: "Retry last recording" })
    if (state === "nokey") rows.push({ id: "key", label: "Open API key file" })
    rows.push({ id: "cfg", label: "Open config / vocab files" })
    rows.push({ id: "log", label: "Open last log" })
    return rows
  }

  property int cursor: -1
  onOpenedChanged: {
    cursor = -1
    if (opened && service) {
      service.probeStatus()
      service.refreshConfig()
    }
  }

  function runAction(id) {
    if (!service || id === "busy") return
    if (id === "start") { service.dictateStart(); root.close() }
    else if (id === "stop") service.dictateStop()
    else if (id === "polish") service.polishToggle()
    else if (id === "style") service.cycleStyle()
    else if (id === "engine") service.cycleEngine()
    else if (id === "sounds") service.soundsToggle()
    else if (id === "mic") { service.openConfig(); root.close() }
    else if (id === "copy") { service.copyLast(); root.close() }
    else if (id === "retry") { service.retryLast(); root.close() }
    else if (id === "key") { service.openKeyFile(); root.close() }
    else if (id === "cfg") { service.openConfig(); root.close() }
    else if (id === "log") { service.openLog(); root.close() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.service) root.service.dictateToggle()
      else if (buttonCode === Qt.MiddleButton && root.service) root.service.emergencyStop()
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
          sourceSize.width: 64
          sourceSize.height: 64
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          asynchronous: true
          opacity: root.state === "nokey" ? 0.4 : 1.0
          Behavior on opacity {
            NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
          }
          // Pulse while listening / processing (respects reduceMotion)
          SequentialAnimation on opacity {
            running: root.live && Style.duration(320) > 0
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: Style.duration(320); easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: Style.duration(320); easing.type: Easing.InOutQuad }
            onStopped: mark.opacity = root.state === "nokey" ? 0.4 : 1.0
          }
        }

        // Accent ring while live (orange listen / yellow process)
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.width: root.live ? 1.5 : 0
          border.color: root.recording ? root.recordColor : root.workColor
          opacity: root.live ? 0.9 : 0
          Behavior on opacity {
            NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
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
      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        var n = root.actionRows.length
        if (n <= 0) return
        root.cursor = root.cursor < 0 ? (dy > 0 ? 0 : n - 1) : (root.cursor + dy + n) % n
      }
      onActivateRequested: {
        if (root.cursor >= 0 && root.cursor < root.actionRows.length)
          root.runAction(root.actionRows[root.cursor].id)
      }
      onTextKey: function(t) {
        if (!root.service) return
        if (t === "d" || t === "D") root.service.dictateToggle()
        else if (t === "l" || t === "L") { root.service.openLog(); root.close() }
        else if (t === "k" || t === "K") { root.service.openKeyFile(); root.close() }
        else if (t === "c" || t === "C") { root.service.copyLast(); root.close() }
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
            smooth: true
            mipmap: true
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
          color: Util.alpha(root.errorColor, stopArea.containsMouse ? 0.95 : 0.78)
          Behavior on color { ColorAnimation { duration: Style.duration(120) } }
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
            onClicked: { if (root.service) root.service.emergencyStop(); root.close() }
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
            model: root.actionRows
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool busy: modelData.id === "busy"
              readonly property bool focused: root.cursor === index
              width: parent.width
              height: Style.space(30)
              radius: Style.space(6)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                             busy ? 0.08 : (rowArea.containsMouse || focused ? 0.2 : 0.12))
              border.width: focused ? 1 : 0
              border.color: Color.accent
              opacity: busy ? 0.55 : 1.0
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
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
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: !busy
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: root.cursor = index
                onClicked: root.runAction(modelData.id)
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
          text: "Hold Right Alt = talk · Alt+Space = toggle · j/k + Enter navigate · Emergency stop: middle-click or Super+Ctrl+Esc"
          wrapMode: Text.WordWrap
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
