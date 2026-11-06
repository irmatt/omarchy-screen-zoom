-- Screen Zoom: optional hold-mode bridge for the irmatt.screen-zoom plugin.
--
-- The default Super+pinch gesture and all manual controls are registered by the
-- shell plugin itself. Only hold-Super-to-zoom needs this file, because
-- Hyprland cannot express a reliable press/release for a modifier key with an
-- ordinary bind: its global shortcut protocol does not send a release for
-- modifiers, and a bindr on Super_L is skipped once Super was part of a chord.
-- `input.keyboard.key` sees both events.
--
-- Loaded from ~/.config/hypr/hyprland.lua:
--   pcall(dofile, (os.getenv("HOME") or "") .. "/.config/omarchy/plugins/irmatt.screen-zoom/bridge.lua")

local HOME = os.getenv("HOME") or ""
local SETTINGS = HOME .. "/.config/omarchy/screen-zoom.json"
local MARKER = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-screen-zoom.enabled"

local SUPER_L = 133 -- evdev 125 + 8, the keycode Hyprland hands to Lua
local SUPER_R = 134
local MARKER_MAX_AGE = 20 -- seconds; the plugin refreshes every 5

local DEFAULTS = {
  hold = false,
  factor = 2.0,
  holdMs = 200,
  follow = "pointer",
  resetOnRelease = false,
}

local holding = hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
local pending = nil
local holdZoomed = false
local previousFactor = 1.0
local activeCache = false
local activeCheckedAt = 0

local function pluginActive()
  local now = os.time()
  if now == activeCheckedAt then return activeCache end
  activeCheckedAt = now
  activeCache = false

  local f = io.open(MARKER, "r")
  if not f then return false end
  local raw = f:read("*a") or ""
  f:close()

  local pid, stamp = raw:match("^(%d+):(%d+)")
  if not pid or not stamp then return false end
  if math.abs(now - tonumber(stamp)) > MARKER_MAX_AGE then return false end

  local proc = io.open("/proc/" .. pid .. "/comm", "r")
  if not proc then return false end
  proc:close()
  activeCache = true
  return true
end

local function readString(raw, key, fallback)
  return raw:match('"' .. key .. '"%s*:%s*"([%w_-]+)"') or fallback
end

local function readNumber(raw, key, fallback)
  return tonumber(raw:match('"' .. key .. '"%s*:%s*([%d%.]+)')) or fallback
end

local function readBool(raw, key, fallback)
  local value = raw:match('"' .. key .. '"%s*:%s*(%a+)')
  if value == "true" then return true end
  if value == "false" then return false end
  return fallback
end

local function readSettings()
  local raw = ""
  local f = io.open(SETTINGS, "r")
  if f then
    raw = f:read("*a") or ""
    f:close()
  end

  local s = {
    hold = readBool(raw, "hold", DEFAULTS.hold),
    factor = readNumber(raw, "factor", DEFAULTS.factor),
    holdMs = readNumber(raw, "holdMs", DEFAULTS.holdMs),
    follow = readString(raw, "follow", DEFAULTS.follow),
    resetOnRelease = readBool(raw, "resetOnRelease", DEFAULTS.resetOnRelease),
  }

  if s.follow ~= "pointer" and s.follow ~= "edge" then s.follow = DEFAULTS.follow end
  s.factor = math.min(10, math.max(1.1, s.factor))
  s.holdMs = math.min(2000, math.max(40, s.holdMs))
  return s
end

local function applyZoom(factor, follow)
  hl.config({ cursor = {
    zoom_detached_camera = follow == "edge",
    zoom_rigid = false,
    zoom_factor = factor,
  } })
end

local function currentZoom()
  return tonumber(hl.get_config("cursor:zoom_factor")) or 1.0
end

local function stopHoldZoom()
  if pending then
    pending:set_enabled(false)
    pending = nil
  end
  if holdZoomed then
    holdZoomed = false
    applyZoom(previousFactor > 1.005 and previousFactor or 1.0, readSettings().follow)
  end
end

local function beginHoldZoom(factor, follow)
  pending = nil
  if holdZoomed or not holding then return end
  if not pluginActive() then return end
  holdZoomed = true
  applyZoom(factor, follow)
end

hl.on("input.keyboard.key", function(keycode, _timeMs, state)
  local superKey = keycode == SUPER_L or keycode == SUPER_R

  if state == 1 then
    if superKey then
      if not holding then
        holding = true
        local s = readSettings()
        if s.hold then
          previousFactor = currentZoom()
          pending = hl.timer(function() beginHoldZoom(s.factor, s.follow) end, { timeout = s.holdMs, type = "oneshot" })
        end
      end
    else
      -- Another key while Super is down means this is a chord, not a zoom
      -- gesture; cancel a hold zoom that has not started yet.
      if pending then
        pending:set_enabled(false)
        pending = nil
      end
      holding = hl.is_key_down("Super_L") or hl.is_key_down("Super_R")
    end
  elseif superKey then
    holding = false
    local s = readSettings()
    if s.hold then
      stopHoldZoom()
    elseif s.resetOnRelease then
      applyZoom(1.0, s.follow)
    end
  end
end)
