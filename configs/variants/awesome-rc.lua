-- PocketCHIP home screen: pocketchip-menu runs fullscreen under awesome.
--
-- Ported from the awesome 3.5 config shipped by omgmog/pocketchip-menu to the
-- awesome 4.x API that Debian trixie packages. "Menu" is the pygame window's
-- WM_NAME; it is kept fullscreen, borderless and focused, and every other
-- window opens on top of it.

local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")

beautiful.init(gears.filesystem.get_themes_dir() .. "default/theme.lua")

-- Replaced with the real home directory when the image is built.
local home_shell = "@HOME@/pocketchip-menu/load.sh"

if awesome.startup_errors then
  naughty.notify({ preset = naughty.config.presets.critical,
                   title = "Oops, there were errors during startup!",
                   text = awesome.startup_errors })
end

do
  local in_error = false
  awesome.connect_signal("debug::error", function (err)
    if in_error then return end
    in_error = true
    naughty.notify({ preset = naughty.config.presets.critical,
                     title = "Oops, an error happened!",
                     text = tostring(err) })
    in_error = false
  end)
end

local home_screen = {}

local function adopt_home(c)
  if c.name ~= "Menu" then
    return
  end
  home_screen.client = c
  c.floating = true
  c.fullscreen = true
  c.border_width = 0
  c.skip_taskbar = true
  client.focus = c
  c:raise()
end

local function launch_home_screen()
  if home_screen.client then
    local old = home_screen.client
    home_screen = {}
    pcall(function() old:kill() end)
  end
  -- with_shell() has no sn_rules argument; adopt_home() applies the window
  -- properties once the pygame client appears.
  awful.spawn.with_shell(home_shell)
end

local function focus_next_client()
  awful.client.focus.byidx(1)
  if client.focus then
    client.focus:raise()
  end
end

local all_minimized = false
local function toggle_minimize_all()
  all_minimized = not all_minimized
  local s = mouse.screen
  if not s then
    return
  end
  for _, c in ipairs(s.selected_tag:clients()) do
    if c ~= home_screen.client then
      c.minimized = all_minimized
    end
  end
end

local modkey = "Mod1"

awful.layout.layouts = {
    awful.layout.suit.max.fullscreen
}

for s in screen do
  awful.tag({ "1" }, s, awful.layout.layouts[1])
end

root.buttons(gears.table.join(
  awful.button({ }, 4, awful.tag.viewnext),
  awful.button({ }, 5, awful.tag.viewprev)
))

local globalkeys = gears.table.join(
  awful.key({ }, "XF86PowerOff", toggle_minimize_all),
  awful.key({ modkey }, "Tab", focus_next_client),
  awful.key({ "Control" }, "Tab", focus_next_client),
  awful.key({ modkey }, "Return", function () awful.spawn("dmenu_run") end),
  awful.key({ modkey }, "h", launch_home_screen)
)

local clientkeys = gears.table.join(
  awful.key({ "Control" }, "q", function (c)
    if c ~= home_screen.client then
      c:kill()
    end
  end)
)

local clientbuttons = gears.table.join(
  awful.button({ }, 1, function (c) client.focus = c; c:raise() end),
  awful.button({ modkey }, 1, awful.mouse.client.move),
  awful.button({ "Control" }, 1, function () awful.spawn("xdotool click 3") end)
)

root.keys(globalkeys)

awful.rules.rules = {
  { rule = { },
    properties = { border_width = 0,
      border_color = beautiful.border_normal,
      focus = awful.client.focus.filter,
      keys = clientkeys,
      buttons = clientbuttons } }
}

client.connect_signal("manage", function (c, startup)
  adopt_home(c)

  if not startup and c ~= home_screen.client then
    local hints = c.size_hints or {}
    if not hints.user_position and not hints.program_position then
      awful.placement.no_overlap(c)
      awful.placement.no_offscreen(c)
    end
  end
end)

client.connect_signal("property::name", adopt_home)

client.connect_signal("unmanage", function (c)
  if c == home_screen.client then
    home_screen = {}
  end
end)

launch_home_screen()
