import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar widget + popup. Pick a display in the list, edit it below. Display
// state and the keep/revert flow live in DisplayStore, shared with the
// arrangement window (Arrange.qml). Brightness and text size are local.
Panel {
  id: root
  moduleName: DisplayStore.pluginId
  ipcTarget: DisplayStore.pluginId
  manageIpc: false

  property string hoveredName: ""

  property bool brightnessAvailable: false
  property int brightnessPercent: 0
  property bool brightnessSetQueued: false
  property real wheelAccumulator: 0

  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1

  readonly property var scaleOptions: DisplayStore.current
    ? Model.availableScales(DisplayStore.scalePresets, DisplayStore.current.width, DisplayStore.current.height).map(function(s) { return { value: s, label: s + "x" } })
    : []
  readonly property var resolutionOptions: DisplayStore.selected ? Model.resolutions(DisplayStore.selected.modes) : []
  readonly property var refreshOptions: DisplayStore.current
    ? Model.refreshRates(DisplayStore.selected.modes, DisplayStore.current.width, DisplayStore.current.height)
    : []
  readonly property var mirrorOptions: {
    var options = [{ value: "", label: "Extend" }]
    var displays = DisplayStore.displays
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (!DisplayStore.selected || d.name === DisplayStore.selected.name || !d.enabled) continue
      options.push({ value: d.name, label: "Mirror " + d.model })
    }
    return options
  }

  function openArrange() {
    root.close()
    if (root.bar && root.bar.shell) root.bar.shell.summon(DisplayStore.pluginId, "{}")
  }

  function readBrightness() {
    if (!DisplayStore.selected) return
    brightnessReadProc.command = ["omarchy-brightness-display", "--monitor", DisplayStore.selected.name]
    brightnessReadProc.running = true
  }

  function setBrightness(value) {
    var percent = Math.max(1, Math.min(100, Math.round(value)))
    brightnessPercent = percent
    if (brightnessSetProc.running) { brightnessSetQueued = true; return }
    brightnessSetQueued = false
    brightnessSetProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", DisplayStore.selected.name, percent + "%"]
    brightnessSetProc.running = true
  }

  function nearestTextStop(px) {
    var best = 0
    for (var i = 0; i < textSizeStops.length; i++)
      if (Math.abs(textSizeStops[i] - px) < Math.abs(textSizeStops[best] - px)) best = i
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  function setTextSize(index) {
    textSizePreviewIndex = index
    textSizeProc.command = ["omarchy-display-text-size", String(textSizeStops[index])]
    textSizeProc.running = true
  }

  function modeSummary(d) {
    if (!d.enabled) return "Off"
    var text = d.width + "×" + d.height + " @ " + Math.round(d.hz) + " Hz · " + d.scale + "x"
    if (d.transform) text += " · " + Model.transformLabel(d.transform)
    if (d.mirrorOf) text += " · mirrors " + d.mirrorOf
    return text
  }

  // omarchy-shell io.github.fluffet.display <method> [arg]
  IpcHandler {
    target: DisplayStore.pluginId

    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function arrange() { root.openArrange() }
    function state(): string { return JSON.stringify({ selected: DisplayStore.selectedName, pending: DisplayStore.pending, displays: DisplayStore.displays }) }
    function select(name: string) { DisplayStore.select(name) }
    function change(patchJson: string) { DisplayStore.change(JSON.parse(patchJson)) }
    function keep() { DisplayStore.keep() }
    function revert() { DisplayStore.revert() }
    function forget() { DisplayStore.forgetSaved() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: readBrightness()

  onOpenedChanged: if (opened) { DisplayStore.refresh(); readBrightness() }

  Connections {
    target: DisplayStore
    function onSelectedNameChanged() { root.readBrightness() }
  }

  Timer {
    interval: 5000
    running: root.opened && !DisplayStore.hasPending
    repeat: true
    onTriggered: DisplayStore.refresh()
  }

  Process {
    id: brightnessReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text).trim(), 10)
        root.brightnessAvailable = isFinite(value)
        root.brightnessPercent = isFinite(value) ? value : 0
      }
    }
  }

  Process {
    id: brightnessSetProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running && root.brightnessSetQueued) root.setBrightness(root.brightnessPercent)
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: textSizeProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      if (root.textSizePreviewIndex >= 0 && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: DisplayStore.displays.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.setBrightness(root.brightnessPercent + wheel.steps * 5)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: DisplayStore.selected ? DisplayStore.selected.model : "Display"
            meta: DisplayStore.selected ? DisplayStore.selected.name + " · " + root.modeSummary(DisplayStore.selected) : ""
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Component {
              Text {
                text: DisplayStore.displays.length > 1 ? "󰍺" : "󰍹"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Display list ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(displaysHeader.implicitHeight, arrangeButton.implicitHeight)

              PanelSectionHeader {
                id: displaysHeader
                text: "DISPLAYS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: arrangeButton
                visible: DisplayStore.layoutRects.length > 1
                text: "Arrange…"
                bordered: true
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.openArrange()
              }
            }

            Repeater {
              model: DisplayStore.displays

              CursorSurface {
                id: displayRow
                required property var modelData
                width: panelColumn.width
                implicitHeight: rowInner.implicitHeight + Style.spacing.xl
                current: modelData.name === DisplayStore.selectedName
                hasCursor: modelData.name === root.hoveredName
                foreground: root.bar.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: root.hoveredName = containsMouse ? displayRow.modelData.name : (root.hoveredName === displayRow.modelData.name ? "" : root.hoveredName)
                  onClicked: DisplayStore.select(displayRow.modelData.name)
                }

                Row {
                  id: rowInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)

                  Text {
                    text: displayRow.modelData.internal ? "󰌢" : "󰍹"
                    color: root.bar.foreground
                    opacity: displayRow.modelData.enabled ? 1 : 0.45
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.title
                    width: Style.space(22)
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    width: parent.width - Style.space(22) - enableSwitch.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: displayRow.modelData.model + (displayRow.modelData.focused ? " · focused" : "")
                      color: root.bar.foreground
                      opacity: displayRow.modelData.enabled ? 1 : 0.45
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: displayRow.modelData.name + " · " + root.modeSummary(displayRow.modelData)
                      color: Qt.darker(root.bar.foreground, 1.4)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  ToggleSwitch {
                    id: enableSwitch
                    checked: displayRow.modelData.enabled
                    interactive: !displayRow.modelData.enabled || DisplayStore.enabledCount > 1
                    foreground: root.bar.foreground
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: DisplayStore.setEnabled(displayRow.modelData, !displayRow.modelData.enabled)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Selected display ----------
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: DisplayStore.current !== null && !DisplayStore.current.disabled

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.brightnessAvailable

              Item {
                width: parent.width
                implicitHeight: brightnessHeader.implicitHeight

                PanelSectionHeader {
                  id: brightnessHeader
                  text: "BRIGHTNESS"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  anchors.left: parent.left
                }

                Text {
                  text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "% · " + Model.brightnessName(root.brightnessPercent).toUpperCase()
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                }
              }

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                width: parent.width - Style.space(12)
                anchors.horizontalCenter: parent.horizontalCenter
                minimum: 1
                maximum: 100
                step: 1
                integer: true
                value: root.brightnessPercent
                onMoved: function(v) { root.brightnessPercent = Math.round(v); brightnessDebounce.restart() }
                onReleased: function(v) { brightnessDebounce.stop(); root.setBrightness(v) }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Dropdown {
                width: (parent.width - parent.spacing) / 2
                label: "RESOLUTION"
                options: root.resolutionOptions
                value: DisplayStore.current ? DisplayStore.current.width + "x" + DisplayStore.current.height : ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { DisplayStore.setResolution(v) }
              }

              Dropdown {
                width: (parent.width - parent.spacing) / 2
                label: "REFRESH RATE"
                options: root.refreshOptions
                value: DisplayStore.current ? Number(DisplayStore.current.hz).toFixed(2) : ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { DisplayStore.change({ hz: Number(v) }) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              PanelSectionHeader { text: "SCALE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

              ButtonGroup {
                options: root.scaleOptions
                value: DisplayStore.current ? DisplayStore.current.scale : ""
                focusable: false
                foreground: root.bar.foreground
                background: root.bar.background
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.caption
                onChanged: function(v) { DisplayStore.change({ scale: v }) }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap

                PanelSectionHeader { text: "ROTATION"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

                ButtonGroup {
                  options: [0, 1, 2, 3].map(function(t) { return { value: String(t), label: Model.transformLabel(t) } })
                  value: DisplayStore.current ? String(DisplayStore.current.transform) : "0"
                  focusable: false
                  foreground: root.bar.foreground
                  background: root.bar.background
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onChanged: function(v) { DisplayStore.change({ transform: Number(v) }) }
                }
              }

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap

                PanelSectionHeader {
                  text: "VRR" + (DisplayStore.selectedEdid.range ? " · " + DisplayStore.selectedEdid.range + " HZ" : "")
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                }

                ButtonGroup {
                  options: [{ value: "0", label: "Off" }, { value: "1", label: "On" }, { value: "2", label: "Fullscreen" }]
                  value: DisplayStore.current ? String(DisplayStore.current.vrr) : "0"
                  focusable: false
                  foreground: root.bar.foreground
                  background: root.bar.background
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.caption
                  onChanged: function(v) { DisplayStore.change({ vrr: Number(v) }) }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Dropdown {
                width: (parent.width - parent.spacing) / 2
                label: "MIRROR"
                options: root.mirrorOptions
                value: DisplayStore.current ? DisplayStore.current.mirror : ""
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { DisplayStore.change({ mirror: v }) }
              }

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.spacing.labelGap
                visible: DisplayStore.selectedEdid.hdr

                PanelSectionHeader { text: "HDR"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

                Item {
                  width: parent.width
                  height: Style.spacing.controlHeight

                  ToggleSwitch {
                    checked: DisplayStore.current ? DisplayStore.current.hdr : false
                    foreground: root.bar.foreground
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: DisplayStore.change({ hdr: !DisplayStore.current.hdr })
                  }

                  Text {
                    text: "10-bit HDR"
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Text size (global) ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: textHeader.implicitHeight

              PanelSectionHeader {
                id: textHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
              }

              Text {
                text: root.textSizeStops[textSizeSlider.dragging ? Math.round(textSizeSlider.liveValue) : root.currentTextIndex()] + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
              }
            }

            PanelSlider {
              id: textSizeSlider
              bar: root.bar
              width: parent.width - Style.space(12)
              anchors.horizontalCenter: parent.horizontalCenter
              minimum: 0
              maximum: root.textSizeStops.length - 1
              step: 1
              integer: true
              tickCount: root.textSizeStops.length
              value: root.currentTextIndex()
              onReleased: function(v) { root.setTextSize(Math.round(v)) }
            }
          }

          // ---------- Pending change bar ----------
          Rectangle {
            width: parent.width
            visible: DisplayStore.hasPending
            implicitHeight: pendingRow.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Style.selectedFillFor(root.bar.foreground, Color.accent)

            Row {
              id: pendingRow
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              spacing: Style.space(8)

              Text {
                width: parent.width - keepButton.width - revertButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: "Keep these settings? Reverting in " + DisplayStore.secondsLeft + "s"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Button {
                id: keepButton
                text: "Keep"
                bordered: true
                selected: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: DisplayStore.keep()
              }

              Button {
                id: revertButton
                text: "Revert"
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: DisplayStore.revert()
              }
            }
          }

          Item {
            width: parent.width
            height: forgetButton.implicitHeight
            visible: !DisplayStore.hasPending

            Button {
              id: forgetButton
              text: "Forget saved layout"
              tooltipText: "Remove this panel's block from monitors.lua and reload Hyprland"
              fontSize: Style.font.caption
              foreground: Qt.darker(root.bar.foreground, 1.4)
              fontFamily: root.bar.fontFamily
              anchors.right: parent.right
              onClicked: DisplayStore.forgetSaved()
            }
          }
        }
      }
    }
  }
}
