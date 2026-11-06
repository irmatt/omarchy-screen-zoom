#!/usr/bin/env lua
-- Unit tests for the optional hold-mode bridge. No Hyprland needed:
--   lua5.4 tests/bridge_test.lua
--
-- The default Super+pinch gesture lives in ScreenZoom.qml; this covers the
-- hold-to-zoom state machine, settings, and the plugin heartbeat.

local script = arg[0] or ""
local pluginDir = script:match("^(.*)/tests/[^/]+$") or "."
local bridgePath = pluginDir .. "/bridge.lua"

local tmp = os.getenv("TMPDIR") or "/tmp"
local home = tmp .. "/screen-zoom-test-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000))
local runtime = home .. "/runtime"
local configDir = home .. "/.config/omarchy"
local marker = runtime .. "/omarchy-screen-zoom.enabled"
local settings = configDir .. "/screen-zoom.json"

os.execute("mkdir -p '" .. configDir .. "' '" .. runtime .. "'")

-- Lua has no os.setenv; the bridge reads these through os.getenv.
local realGetenv = os.getenv
os.getenv = function(name)
  if name == "HOME" then return home end
  if name == "XDG_RUNTIME_DIR" then return runtime end
  return realGetenv(name)
end

local function writeFile(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function markerFor(pid, age)
  writeFile(marker, tostring(pid) .. ":" .. tostring(os.time() - (age or 0)))
end

-- Marker has to name a live process. Use this test's PID: the shell that
-- io.popen starts reports its parent, which is this Lua process.
local pid = nil
do
  local handle = io.popen("echo $PPID")
  if handle then pid = handle:read("*l"); handle:close() end
end
assert(pid and pid:match("^%d+$"), "could not determine test pid")

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
end

local function newState(configOverride)
  local state = {
    configs = {},
    timers = {},
    onKey = nil,
    store = {
      cursor = { zoom_factor = 1.0, zoom_detached_camera = false, zoom_rigid = false },
    },
  }

  if configOverride then merge(state.store, configOverride) end

  hl = {
    is_key_down = function(_name) return false end,
    on = function(name, cb)
      assert(name == "input.keyboard.key", "unexpected event: " .. tostring(name))
      state.onKey = cb
    end,
    timer = function(cb, opts)
      local timer = { cb = cb, enabled = true, timeout = opts.timeout }
      function timer:set_enabled(value) self.enabled = value end
      table.insert(state.timers, timer)
      return timer
    end,
    config = function(tbl)
      table.insert(state.configs, tbl)
      merge(state.store, tbl)
    end,
    get_config = function(key)
      local node = state.store
      for part in key:gmatch("[^:.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
      end
      return node
    end,
  }

  dofile(bridgePath)
  assert(state.onKey, "bridge did not register input.keyboard.key")
  return state
end

local function zoom(state)
  return state.store.cursor.zoom_factor
end

local function pressSuper(state, code)
  state.onKey(code or 133, 0, 1)
end

local function releaseSuper(state, code)
  state.onKey(code or 133, 0, 0)
end

local function fire(state)
  local timer = state.timers[#state.timers]
  assert(timer, "no timer registered")
  assert(timer.enabled, "timer should still be enabled")
  timer.cb()
end

local function defaults(extra)
  local s = {
    pinch = true,
    pinchModifier = "super",
    hold = false,
    factor = 2.0,
    holdMs = 200,
    follow = "pointer",
    resetOnRelease = false,
  }
  if extra then merge(s, extra) end
  return s
end

local function writeSettings(extra)
  writeFile(settings, (function()
    local s = defaults(extra)
    return string.format(
      '{"pinch":%s,"pinchModifier":"%s","hold":%s,"factor":%s,"holdMs":%s,"follow":"%s","resetOnRelease":%s}',
      tostring(s.pinch), s.pinchModifier, tostring(s.hold), s.factor, s.holdMs, s.follow,
      tostring(s.resetOnRelease))
  end)())
end

local checks = 0
local function check(condition, message)
  checks = checks + 1
  if not condition then error("FAIL: " .. message, 2) end
end

-- 1. With hold mode off, a Super press arms nothing and does not zoom.
do
  writeSettings()
  markerFor(pid, 0)
  local state = newState()
  pressSuper(state)
  check(#state.timers == 0, "hold mode off should not arm a timer")
  check(zoom(state) == 1.0, "plain Super should not zoom when hold is off")
  releaseSuper(state)
  check(zoom(state) == 1.0, "release should leave the zoom alone")
end

-- 2. Hold mode arms a timer, zooms at the configured factor, and restores the
--    previous zoom on release.
do
  writeSettings({ hold = true, follow = "edge", factor = 2.0, holdMs = 150 })
  markerFor(pid, 0)
  local state = newState({ cursor = { zoom_factor = 1.5 } })
  pressSuper(state)
  check(#state.timers == 1, "hold mode should arm a timer")
  check(state.timers[1].timeout == 150, "hold timeout should come from settings")
  fire(state)
  check(zoom(state) == 2.0, "hold should zoom to the configured factor")
  check(state.store.cursor.zoom_detached_camera == true, "edge mode should detach the camera")
  releaseSuper(state)
  check(zoom(state) == 1.5, "hold release should restore the previous zoom")
end

-- 3. A chord before the hold elapses cancels it.
do
  writeSettings({ hold = true })
  markerFor(pid, 0)
  local state = newState()
  pressSuper(state)
  state.onKey(38, 0, 1) -- 'a'
  check(state.timers[1].enabled == false, "chord should cancel the pending hold")
  releaseSuper(state)
  check(zoom(state) == 1.0, "a chord must not zoom")
end

-- 4. A chord after the hold started keeps the zoom until Super is released.
do
  writeSettings({ hold = true })
  markerFor(pid, 0)
  local state = newState()
  pressSuper(state)
  fire(state)
  check(zoom(state) == 2.0, "hold should zoom")
  state.onKey(38, 0, 1)
  check(zoom(state) == 2.0, "chord while zoomed should keep the zoom")
  releaseSuper(state)
  check(zoom(state) == 1.0, "Super release should stop a zoomed chord")
end

-- 5. resetOnRelease can make an existing zoom temporary even with hold off.
do
  writeSettings({ resetOnRelease = true })
  markerFor(pid, 0)
  local state = newState({ cursor = { zoom_factor = 2.0 } })
  pressSuper(state)
  releaseSuper(state)
  check(zoom(state) == 1.0, "resetOnRelease should restore 1x")
end

-- 6. The plugin heartbeat must be fresh and name a live process.
do
  writeSettings({ hold = true })
  markerFor(pid, 60)
  local state = newState()
  pressSuper(state)
  fire(state)
  check(zoom(state) == 1.0, "stale heartbeat must not hold-zoom")
  releaseSuper(state)

  writeSettings({ hold = true })
  markerFor(999999, 0)
  state = newState()
  pressSuper(state)
  fire(state)
  check(zoom(state) == 1.0, "dead shell pid must not hold-zoom")
  releaseSuper(state)

  writeSettings({ hold = true })
  os.remove(marker)
  state = newState()
  pressSuper(state)
  fire(state)
  check(zoom(state) == 1.0, "missing marker must not hold-zoom")
  releaseSuper(state)
end

-- 7. Invalid settings are clamped, not trusted.
do
  writeSettings({ factor = 99, holdMs = 1, hold = true })
  markerFor(pid, 0)
  local state = newState()
  pressSuper(state)
  check(state.timers[1].timeout == 40, "holdMs should clamp to 40")
  fire(state)
  check(zoom(state) == 10, "factor should clamp to 10x")
  releaseSuper(state)
end

-- 8. Pointer follow is the default; edge mode is opt-in.
do
  writeSettings({ hold = true, follow = "pointer" })
  markerFor(pid, 0)
  local state = newState()
  pressSuper(state)
  fire(state)
  check(state.store.cursor.zoom_detached_camera == false, "pointer mode should attach the camera")
  releaseSuper(state)
end

os.execute("rm -rf '" .. home .. "'")

print(string.format("ok - %d checks", checks))
