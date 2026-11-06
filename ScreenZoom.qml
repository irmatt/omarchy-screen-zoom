import QtQuick
import Quickshell
import Quickshell.Io

// Screen Zoom
//
// Hyprland 0.56 has a native cursor zoom: when `cursor:zoom_factor` is above
// 1, the monitor under the pointer is magnified around the cursor. The
// `cursor:zoom_detached_camera` option selects the macOS "Zoomed image moves"
// behaviour: false follows the pointer continuously, true only moves the image
// when the pointer reaches an edge. This plugin owns the user-facing settings
// and manual controls; a small Lua bridge in bridge.lua handles the triggers
// without a process round-trip.
//
// The bridge only zooms while this plugin is loaded. The marker file below is
// a heartbeat carrying this shell's PID and a timestamp, so a disabled or
// crashed shell stops the gestures without needing a Hyprland reload.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null

  property bool pinch: true
  property string pinchModifier: "super" // "super" or "none"
  property bool hold: false              // hold-Super-to-zoom mode
  property real factor: 2.0              // hold-mode magnification
  property int holdMs: 200
  property string follow: "pointer"      // "pointer" (continuous) or "edge"
  property bool resetOnRelease: false
  property bool manualZoomed: false

  readonly property string settingsPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/screen-zoom.json"
  readonly property string markerPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-screen-zoom.enabled"

  function clampFactor(value) {
    var n = Number(value)
    if (!isFinite(n) || n <= 0) return root.factor
    return Math.round(Math.max(1.1, Math.min(10, n)) * 10) / 10
  }

  function clampHold(value) {
    var n = Number(value)
    if (!isFinite(n)) return root.holdMs
    return Math.round(Math.max(40, Math.min(2000, n)))
  }

  function evalHypr(code) {
    Quickshell.execDetached(["hyprctl", "eval", code])
  }

  function applyCamera() {
    root.evalHypr("hl.config({cursor={zoom_detached_camera=" + (root.follow === "edge") + ",zoom_rigid=false}})")
  }

  function unregisterPinch() {
    root.evalHypr('hl.gesture({fingers=2,direction="pinch",action="unset",mods="SUPER"})')
    root.evalHypr('hl.gesture({fingers=2,direction="pinch",action="unset"})')
  }

  function applyPinch() {
    root.unregisterPinch()
    if (!root.pinch) return
    var mods = root.pinchModifier === "super" ? ',mods="SUPER"' : ""
    root.evalHypr('hl.gesture({fingers=2,direction="pinch",action="cursor_zoom",mode="live",zoom_level="2.0"' + mods + '})')
  }

  function setNativeZoom(value) {
    var next = root.clampFactor(value)
    root.manualZoomed = true
    root.evalHypr("hl.config({cursor={zoom_detached_camera=" + (root.follow === "edge") + ",zoom_rigid=false,zoom_factor=" + next + "}})")
    return next
  }

  function clearNativeZoom() {
    root.manualZoomed = false
    root.evalHypr("hl.config({cursor={zoom_factor=1.0}})")
  }

  function applySettings(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return

    if (typeof parsed.pinch === "boolean") root.pinch = parsed.pinch
    if (parsed.pinchModifier === "super" || parsed.pinchModifier === "none") root.pinchModifier = parsed.pinchModifier
    if (typeof parsed.hold === "boolean") root.hold = parsed.hold
    if (typeof parsed.factor === "number") root.factor = root.clampFactor(parsed.factor)
    if (typeof parsed.holdMs === "number") root.holdMs = root.clampHold(parsed.holdMs)
    if (parsed.follow === "pointer" || parsed.follow === "edge") root.follow = parsed.follow
    if (typeof parsed.resetOnRelease === "boolean") root.resetOnRelease = parsed.resetOnRelease

    root.applyCamera()
    root.applyPinch()
  }

  function saveSettings() {
    settingsFile.setText(JSON.stringify({
      pinch: root.pinch,
      pinchModifier: root.pinchModifier,
      hold: root.hold,
      factor: root.factor,
      holdMs: root.holdMs,
      follow: root.follow,
      resetOnRelease: root.resetOnRelease
    }, null, 2) + "\n")
  }

  // The bridge requires a fresh heartbeat, so a plugin unload or a shell crash
  // turns the gestures off within one expiry window.
  function writeMarker() {
    markerFile.setText(String(Quickshell.processId) + ":" + Math.floor(Date.now() / 1000))
  }

  Component.onCompleted: {
    root.writeMarker()
    root.applyCamera()
    root.applyPinch()
  }

  Component.onDestruction: {
    root.unregisterPinch()
    root.clearNativeZoom()
    Quickshell.execDetached(["rm", "-f", root.markerPath])
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettings(text())
    onLoadFailed: root.saveSettings()
  }

  FileView {
    id: markerFile
    path: root.markerPath
    atomicWrites: true
    printErrors: false
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.writeMarker()
  }

  IpcHandler {
    target: "screen-zoom"

    function zoom(factor: string): string {
      return String(root.setNativeZoom(factor))
    }

    function unzoom(): string {
      root.clearNativeZoom()
      return "ok"
    }

    function toggle(): string {
      if (root.manualZoomed) {
        root.clearNativeZoom()
        return "off"
      }
      return String(root.setNativeZoom(root.factor))
    }

    function set_pinch(value: string): string {
      root.pinch = value === "true"
      root.saveSettings()
      root.applyPinch()
      return String(root.pinch)
    }

    function set_pinch_modifier(value: string): string {
      if (value === "super" || value === "none") root.pinchModifier = value
      root.saveSettings()
      root.applyPinch()
      return root.pinchModifier
    }

    function set_hold_mode(value: string): string {
      root.hold = value === "true"
      root.saveSettings()
      return String(root.hold)
    }

    function set_factor(factor: string): string {
      root.factor = root.clampFactor(factor)
      root.saveSettings()
      if (root.manualZoomed) root.setNativeZoom(root.factor)
      return String(root.factor)
    }

    function set_hold_ms(ms: string): string {
      root.holdMs = root.clampHold(ms)
      root.saveSettings()
      return String(root.holdMs)
    }

    function set_follow(value: string): string {
      if (value === "pointer" || value === "edge") root.follow = value
      root.saveSettings()
      root.applyCamera()
      return root.follow
    }

    function set_reset_on_release(value: string): string {
      root.resetOnRelease = value === "true"
      root.saveSettings()
      return String(root.resetOnRelease)
    }

    function reload(): string {
      settingsFile.reload()
      return "ok"
    }
  }
}
