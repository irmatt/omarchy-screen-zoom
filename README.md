# Screen Zoom

A macOS-style screen magnifier for the [Omarchy](https://omarchy.org) shell.

It builds on Hyprland 0.56's native cursor zoom, so the screen stays live (no
frozen screenshot), the magnification follows the pointer, and multi-monitor
setups zoom the display under the pointer.

## Features

- **Super + two-finger pinch** zooms in and out on the trackpad. Spread your
  fingers to zoom in, pinch them together to zoom out.
  - Uses Hyprland's native live pinch gesture: smooth, no screenshots, no
    swallowed clicks, and app scrolling keeps working.
  - The zoomed image follows the pointer continuously after the pinch
    (macOS "Continuously with Pointer").
  - The zoom stays where you leave it, like macOS. Reset with
    `SUPER + CTRL + ALT + Z` or `omarchy-shell screen-zoom unzoom`.
- **Plain two-finger pinch without Super does nothing**, so pinch gestures in
  apps (photos, maps, browsers) are left alone.
- **Optional hold mode:** hold Super for a moment to zoom to a fixed factor,
  move the pointer to pan, release to restore. Enable it with
  `"hold": true` (see below).

### Why not Super + two-finger scroll?

Hyprland only exposes **mouse-wheel** scroll to keybinds; trackpad finger scroll
goes straight to the focused app. Capturing it would need a full-screen input
overlay that also swallows Super+click/drag. This plugin uses the native pinch
gesture instead and leaves the stock Super+scroll workspace bindings untouched.

## Requirements

- Omarchy with the Lua Hyprland config (`configProvider: lua`).
- Hyprland 0.56 or newer, which has the native cursor zoom
  (`cursor:zoom_factor`), the `zoom_detached_camera` option, the native
  `cursor_zoom` trackpad gesture, and the `input.keyboard.key` Lua event.
- The Omarchy shell plugin loader.

## Install

From the marketplace entry, or directly:

```bash
omarchy plugin add https://github.com/irmatt/omarchy-screen-zoom.git --enable
```

Or manually copy this folder to
`~/.config/omarchy/plugins/irmatt.screen-zoom/`, then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable irmatt.screen-zoom
```

Pinch zoom works immediately. No Hyprland config edit is needed.

### Optional: hold-to-zoom

Hold mode needs a small Lua bridge because Hyprland cannot express a reliable
press/release for a modifier key with an ordinary bind. Add this line to
`~/.config/hypr/hyprland.lua`:

```lua
-- Optional hold-to-zoom bridge for irmatt.screen-zoom.
pcall(dofile, (os.getenv("HOME") or "") .. "/.config/omarchy/plugins/irmatt.screen-zoom/bridge.lua")
```

Then reload Hyprland and turn the mode on:

```bash
hyprctl reload
omarchy-shell screen-zoom set_hold_mode true
```

The `pcall` keeps Hyprland loading if the plugin folder is ever removed.

## Settings

Edit `~/.config/omarchy/screen-zoom.json`. The plugin creates the file with
these defaults if it is missing, watches it for changes, and applies them
immediately.

```json
{
  "pinch": true,
  "pinchModifier": "super",
  "hold": false,
  "factor": 2.0,
  "holdMs": 200,
  "follow": "pointer",
  "resetOnRelease": false
}
```

| Key | Meaning |
| --- | --- |
| `pinch` | Enable the two-finger pinch gesture. |
| `pinchModifier` | `super` = pinch only while Super is held, keeping app pinch gestures intact; `none` = plain two-finger pinch always zooms. |
| `hold` | Enable hold-Super-to-zoom (requires the optional bridge). |
| `factor` | Zoom level for hold mode and manual zoom. 1.1–10. |
| `holdMs` | How long Super must be held in hold mode. 40–2000 ms. |
| `follow` | `pointer` = macOS "Continuously with Pointer"; `edge` = macOS "When Pointer Reaches Edge". |
| `resetOnRelease` | Reset to 1× when Super is released (requires the optional bridge). Off by default, like macOS. |

### macOS options

| macOS Zoom option | This plugin |
| --- | --- |
| Use scroll gesture with modifier keys to zoom | Not possible for trackpad scroll; use Super+pinch. |
| Zoomed image moves | `follow`: `pointer` / `edge`. |
| Restore zoom factor on startup | Not implemented; the zoom persists until reset, but the factor is not re-applied on login. |
| Set range for rapid zooming | `factor` covers hold mode; Hyprland's native pinch range is 1–100. |
| Zoom style: Full Screen / Split / Picture-in-Picture | Full screen only. |

## Manual control

The plugin exposes an IPC target for scripts and keybindings:

```bash
omarchy-shell screen-zoom zoom 2.5
omarchy-shell screen-zoom unzoom
omarchy-shell screen-zoom toggle
omarchy-shell screen-zoom set_pinch true
omarchy-shell screen-zoom set_pinch false
omarchy-shell screen-zoom set_pinch_modifier super
omarchy-shell screen-zoom set_pinch_modifier none
omarchy-shell screen-zoom set_hold_mode true
omarchy-shell screen-zoom set_hold_mode false
omarchy-shell screen-zoom set_factor 2.5
omarchy-shell screen-zoom set_hold_ms 250
omarchy-shell screen-zoom set_follow pointer
omarchy-shell screen-zoom set_follow edge
omarchy-shell screen-zoom set_reset_on_release true
omarchy-shell screen-zoom reload
```

For example, a manual reset keybinding:

```lua
o.bind("SUPER + SHIFT + Z", "Screen zoom off", "omarchy-shell screen-zoom unzoom")
```

Omarchy already binds `SUPER + CTRL + Z` to step the native zoom in and
`SUPER + CTRL + ALT + Z` to reset it; those continue to work alongside this
plugin.

## How it works

Hyprland 0.56 renders a monitor at `cursor:zoom_factor` around the cursor.
`cursor:zoom_detached_camera` selects between following the pointer
continuously (`false`) and only panning when the pointer reaches an edge
(`true`). This plugin sets those options and resets `zoom_factor` to 1 on
request.

- **Pinch:** the shell plugin registers Hyprland's native `cursor_zoom`
  trackpad gesture with `mode = "live"` through `hyprctl eval`, and
  unregisters it when the plugin unloads or `pinch` is turned off. It requires
  Super by default so it does not take pinch gestures from apps.
- **Hold:** the optional Lua bridge listens to the raw `input.keyboard.key`
  event, which sees both the press and release of Super even after a chord.
  It only zooms while the plugin's heartbeat file in `$XDG_RUNTIME_DIR` is
  fresh, so disabling the plugin turns the mode off without a Hyprland reload.

## Uninstall

```bash
omarchy plugin disable irmatt.screen-zoom
omarchy plugin remove irmatt.screen-zoom
rm -f ~/.config/omarchy/screen-zoom.json
```

If you added the optional hold bridge, remove its `dofile` line from
`~/.config/hypr/hyprland.lua` and run `hyprctl reload`.

## Caveats

- This uses Hyprland's native zoom, so it magnifies the monitor under the
  pointer. Moving the pointer to another monitor pans across displays.
- With `pinchModifier = "none"`, the pinch gesture applies everywhere and will
  take two-finger pinch away from apps. Super is the default for this reason.
- Hold mode and Super+pinch both use Super. Enabling both means a slow hold can
  start the hold zoom before the pinch begins. Enable one, use a longer
  `holdMs`, or set `pinchModifier = "none"`.
- If the shell process crashes while the plugin is loaded, the native pinch
  gesture can remain registered until the shell starts again or you run
  `hyprctl reload`.
- Run the bridge unit tests without touching Hyprland:

  ```bash
  lua5.4 tests/bridge_test.lua
  ```

## License

MIT. See [LICENSE](LICENSE).
