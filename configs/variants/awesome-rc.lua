-- PocketCHIP desktop: awesome with a flat wibar.
--
-- The bar layout and palette follow the darkblue theme from 4ban/awesome-ban.
-- The full awesome-ban config is too heavy for the R8 (Lain, rofi, compton,
-- scratchpads), so only its look is reused here.  Earlier images ran a
-- fullscreen pygame launcher; it started slowly and needed a patch for every
-- pygame release, so the wibar menu is the launcher now.

local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local wibox = require("wibox")

beautiful.init(gears.filesystem.get_themes_dir() .. "default/theme.lua")

local bg_normal = "#32302f"
local fg_normal = "#ebdbb2"
local fg_dark = "#232323"
local accent = "#4e9699"
local block_violet = "#8c8ccd"
local block_gray = "#5e5e5e"

beautiful.font = "Terminus 9"
beautiful.bg_normal = bg_normal
beautiful.fg_normal = fg_normal
beautiful.bg_focus = bg_normal
beautiful.fg_focus = accent
beautiful.border_width = 0
beautiful.border_color = bg_normal
beautiful.tasklist_font = "Terminus 9"
beautiful.tasklist_bg_normal = bg_normal
beautiful.tasklist_fg_normal = fg_normal
beautiful.tasklist_bg_focus = bg_normal
beautiful.tasklist_fg_focus = accent
beautiful.menu_bg_normal = bg_normal
beautiful.menu_fg_normal = fg_normal
beautiful.menu_bg_focus = accent
beautiful.menu_fg_focus = fg_dark
beautiful.menu_border_color = bg_normal
beautiful.menu_border_width = 0
beautiful.menu_height = 18
beautiful.menu_width = 150
beautiful.notification_bg = bg_normal
beautiful.notification_fg = fg_normal
beautiful.notification_border_width = 0

local bar_height = 20

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

local mainmenu = awful.menu({ items = {
  { "Terminal", "pocketchip-terminal" },
  { "Files", "pcmanfm" },
  { "Write", "mousepad" },
  { "Browser", "pocketchip-browser" },
  { "PICO-8", "pico-8" },
  { "SunVox", "sunvox" },
  { "Wi-Fi", "nm-connection-editor" },
  { "Bluetooth", "blueman-manager" },
  { "Brightness / volume", "pocketchip-terminal -e pocketchip-control menu" },
  { "Touch calibration", "pocketchip-touch-calibrate" },
  { "Lock screen", "i3lock -c 32302f" },
  { "Reboot", "sudo -n pocketchip-power-root reboot" },
  { "Power off", "sudo -n pocketchip-power-root poweroff" },
} })

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
    c.minimized = all_minimized
  end
end

local modkey = "Mod1"

-- max (not max.fullscreen) keeps the work area below the wibar.
awful.layout.layouts = {
    awful.layout.suit.max
}

local tasklist_buttons = gears.table.join(
  awful.button({ }, 1, function(c)
    if c then
      c:activate { context = "tasklist", action = "toggle_minimization" }
    end
  end),
  awful.button({ }, 3, function(c)
    if c then
      c:kill()
    end
  end)
)

local function colored_block(widget, color)
  return wibox.container.background(
    wibox.container.margin(widget, 5, 5, 0, 0), color)
end

local launcher = colored_block(
  wibox.widget.textbox('<span foreground="' .. fg_dark .. '"> Menu </span>'),
  accent)

local battery_text = wibox.widget.textbox()
local function update_battery()
  local f = io.open("/sys/class/power_supply/axp20x-battery/capacity")
  local capacity = f and f:read("*l")
  if f then
    f:close()
  end
  battery_text:set_markup('<span foreground="' .. fg_dark .. '">' ..
    (capacity and (capacity .. "%") or "--") .. '</span>')
end
gears.timer({ timeout = 30, autostart = true, call_now = true,
              callback = update_battery })
local battery_block = colored_block(battery_text, block_gray)

local clock = wibox.widget.textclock(
  '<span foreground="' .. fg_dark .. '">%H:%M</span>')
local clock_block = colored_block(clock, block_violet)

awful.screen.connect_for_each_screen(function(s)
  awful.tag({ "1" }, s, awful.layout.layouts[1])

  launcher:buttons(gears.table.join(
    awful.button({ }, 1, function() mainmenu:toggle() end)))
  battery_block:buttons(gears.table.join(
    awful.button({ }, 1, function() awful.spawn("pocketchip-terminal -e pocketchip-control status") end)))
  clock_block:buttons(gears.table.join(
    awful.button({ }, 1, function() awful.spawn("pocketchip-terminal -e pocketchip-status") end)))

  local tasklist = awful.widget.tasklist {
    screen = s,
    filter = awful.widget.tasklist.filter.currenttags,
    buttons = tasklist_buttons,
    widget_template = {
      {
        id = "text_role",
        widget = wibox.widget.textbox,
      },
      layout = wibox.layout.fixed.horizontal,
    },
  }

  s.mywibox = awful.wibar({
    position = "top",
    screen = s,
    height = bar_height,
    bg = bg_normal,
    fg = fg_normal,
  })
  s.mywibox:setup {
    layout = wibox.layout.align.horizontal,
    { layout = wibox.layout.fixed.horizontal, launcher },
    tasklist,
    { layout = wibox.layout.fixed.horizontal,
      wibox.widget.systray(),
      battery_block,
      clock_block },
  }
end)

gears.wallpaper.set(gears.color(bg_normal))

root.buttons(gears.table.join(
  awful.button({ }, 4, awful.tag.viewnext),
  awful.button({ }, 5, awful.tag.viewprev)
))

local globalkeys = gears.table.join(
  awful.key({ }, "XF86PowerOff", toggle_minimize_all),
  awful.key({ modkey }, "Tab", focus_next_client),
  awful.key({ "Control" }, "Tab", focus_next_client),
  awful.key({ modkey }, "Return", function () awful.spawn("pocketchip-terminal") end),
  awful.key({ modkey }, "p", function () awful.spawn("dmenu_run") end),
  awful.key({ modkey }, "f", function () awful.spawn("pcmanfm") end),
  awful.key({ modkey }, "e", function () awful.spawn("mousepad") end),
  awful.key({ modkey }, "h", function () mainmenu:toggle() end),
  awful.key({ }, "XF86MonBrightnessUp", function () awful.spawn("pocketchip-control brightness-up") end),
  awful.key({ }, "XF86MonBrightnessDown", function () awful.spawn("pocketchip-control brightness-down") end),
  awful.key({ }, "XF86AudioRaiseVolume", function () awful.spawn("pocketchip-control volume-up") end),
  awful.key({ }, "XF86AudioLowerVolume", function () awful.spawn("pocketchip-control volume-down") end),
  awful.key({ }, "XF86AudioMute", function () awful.spawn("pocketchip-control volume-mute") end),
  awful.key({ modkey }, "equal", function () awful.spawn("pocketchip-control brightness-up") end),
  awful.key({ modkey }, "minus", function () awful.spawn("pocketchip-control brightness-down") end)
)

local clientkeys = gears.table.join(
  awful.key({ "Control" }, "q", function (c)
    c:kill()
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
  if not startup then
    local hints = c.size_hints or {}
    if not hints.user_position and not hints.program_position then
      awful.placement.no_overlap(c)
      awful.placement.no_offscreen(c)
    end
  end
end)
