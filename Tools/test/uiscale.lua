-- The whole interface can be made smaller or larger.
--
-- A scale is a multiplier on the frames, and a frame's anchor offsets are in its
-- own scale. So changing it moves a window unless the offsets change with it,
-- and a position saved at one scale means somewhere else at another. This checks
-- the things that go wrong in that: the window staying where it was, what is
-- saved, the screen-edge clamp, and every window and panel following -- not just
-- the main one.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL [uiscale] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function near(label, got, want, tolerance)
	check(label, got ~= nil and math.abs(got - want) <= (tolerance or 0.01),
		("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM, UI, L, W, Options = ns.ConversationManager, ns.UI, ns.L, ns.Widgets, ns.Options
ns.Options.Set("messages.openOnWhisper", false)

local line = 600
local function whisper(text, sender)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(1)
end
whisper("hallo", "Thrall")
whisper("hallo", "Jaina")
local thrallID = ns.Compat.NormalizeName("Thrall")
local jainaID = ns.Compat.NormalizeName("Jaina")

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

local spec
for _, category in ipairs(Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			if row.path == "appearance.uiScale" then spec = row end
		end
	end
end
check("Settings > Appearance offers an interface scale", spec ~= nil and spec.type == "slider")
if spec then
	near("down to 60 %", spec.minValue, 0.6)
	near("up to 150 %", spec.maxValue, 1.5)
end
near("it starts at 100 %", ns.Theme.UIScale(), 1)

Options.Set("appearance.uiScale", 5)
near("more than allowed is held to the most", ns.Theme.UIScale(), 1.5)
Options.Set("appearance.uiScale", 0.1)
near("less than allowed is held to the least", ns.Theme.UIScale(), 0.6)
Options.Set("appearance.uiScale", "kaputt")
near("something that is not a number is 100 %", ns.Theme.UIScale(), 1)
Options.Set("appearance.uiScale", 1)

--------------------------------------------------------------------------------
-- Every window follows
--------------------------------------------------------------------------------

UI.Show()
CM.Select(thrallID)
M.RunFrames(20)
local window = ns.MainWindow.Get()
ns.Popout.Open(jainaID)
M.RunFrames(10)
local popout = ns.Popout.Get(jainaID)
ns.SettingsUI.Show()
M.RunFrames(6)
local settings = ns.SettingsUI.Frame()
ns.Dialogs.QuickReplies()
M.RunFrames(4)
local dialog = ns.Dialogs.quickDialog
ns.EmojiPicker.Open(window.view.composer.emoji, window.view.composer)
M.RunFrames(4)
local picker = _G.WhatTheWhisperEmojiPicker
ns.Menu.Open({ { text = "x", onClick = function() end } }, { anchorTo = window })
local menu = _G.WhatTheWhisperContextMenu
ns.Menu.Close()
ns.EmojiPicker.Toggle(window.view.composer.emoji, window.view.composer)

local all = {
	["the messenger"] = window, ["a window of its own"] = popout, ["the settings"] = settings,
	["a dialog"] = dialog, ["the emoji picker"] = picker, ["a menu"] = menu,
}
for name, frame in pairs(all) do near(name .. " is at 100 % to begin with", frame:GetScale(), 1) end

-- Where the windows are, in screen terms, before.
local function anchor(frame)
	local point, _, relPoint, x, y = frame:GetPoint(1)
	return point, relPoint, x, y
end
window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 800)
window:SavePosition()
local before = { anchor(window) }
local storeBefore = ns.db.profile.layout.point
check("the position is saved at 100 %", storeBefore ~= nil and storeBefore.left == 300 and storeBefore.top == 800,
	storeBefore and (storeBefore.left .. "," .. storeBefore.top))

Options.Set("appearance.uiScale", 0.75)
M.RunFrames(4)
for name, frame in pairs(all) do near(name .. " follows to 75 %", frame:GetScale(), 0.75) end

local point, relPoint, x, y = anchor(window)
check("the messenger keeps its corner: same anchor point", point == before[1] and relPoint == before[2])
near("and the corner is where it was on screen (x)", x * 0.75, 300 * 1)
near("(y)", y * 0.75, 800 * 1)
local store = ns.db.profile.layout.point
near("what is saved is in the new scale (left)", store.left, 400, 0.5)
near("(top)", store.top, 800 / 0.75, 0.5)

-- And back.
Options.Set("appearance.uiScale", 1)
M.RunFrames(4)
local _, _, x1, y1 = anchor(window)
near("back at 100 %, the corner is exactly where it began (x)", x1, 300, 0.01)
near("(y)", y1, 800, 0.01)
near("and the saved position too", ns.db.profile.layout.point.top, 800, 0.01)

-- A centred window stays centred.
local cx0 = select(3, anchor(settings))
Options.Set("appearance.uiScale", 0.6)
M.RunFrames(4)
local csPoint, _, cx, cy = anchor(settings)
check("a window placed by its centre is still placed by it", csPoint == "CENTER", csPoint)
near("and its offset from the screen's centre shrinks in step", cx, cx0 / 0.6, 0.01)
Options.Set("appearance.uiScale", 1)
M.RunFrames(4)

--------------------------------------------------------------------------------
-- Windows made after the setting was changed
--------------------------------------------------------------------------------

Options.Set("appearance.uiScale", 0.8)
M.RunFrames(2)
ns.Popout.Open(thrallID)
M.RunFrames(10)
near("a window opened afterwards is already at the scale", ns.Popout.Get(thrallID):GetScale(), 0.8)
ns.Menu.Open({ { text = "y", onClick = function() end } }, { anchorTo = window })
near("so is a menu", menu:GetScale(), 0.8)
ns.Menu.Close()
ns.Popout.CloseAll()
Options.Set("appearance.uiScale", 1)
M.RunFrames(2)

--------------------------------------------------------------------------------
-- The screen edge
--------------------------------------------------------------------------------

-- 1920 pixels across. At 50 % a window's own units are twice as many as the
-- screen has pixels, so a window at left = 1500 is on screen and one at 2500 is
-- not, where at 100 % both would be clamped to 1920 - margin.
local left100 = W.ClampToScreen(2500, 900, 400, 300, 1)
local left50 = W.ClampToScreen(2500, 900, 400, 300, 0.5)
check("at 100 %, a window far to the right is pulled back", left100 < 2500 and left100 <= 1920)
check("at 50 % the same number is still on screen", left50 == 2500, left50)
check("and one beyond the screen at that scale is pulled back", W.ClampToScreen(4000, 900, 400, 300, 0.5) < 4000)

-- Restored from a saved position at another scale.
Options.Set("appearance.uiScale", 0.5)
M.RunFrames(2)
ns.db.profile.layout.point = { left = 2500, top = 900 }
window:RestoreGeometry()
local _, _, rx = anchor(window)
check("a saved position far right is still reachable at 50 %", rx >= 2500 - 1 and rx < 3840, rx)
Options.Set("appearance.uiScale", 1)
M.RunFrames(2)
ns.db.profile.layout.point = { left = 2500, top = 900 }
window:RestoreGeometry()
M.RunFrames(2)
local _, _, rx1 = anchor(window)
check("and clamped at 100 %", rx1 < 1920, rx1)

--------------------------------------------------------------------------------
-- Font size goes further down than it did
--------------------------------------------------------------------------------

local fs
for _, category in ipairs(Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			if row.path == "appearance.fontScale" then fs = row end
		end
	end
end
check("the font size reaches -4", fs and fs.minValue == -4)
local before = ns.Theme.FontSize("BODY")
Options.Set("appearance.fontScale", -4)
check("and the type is that much smaller", ns.Theme.FontSize("BODY") == before - 4,
	ns.Theme.FontSize("BODY"))
check("while nothing is drawn below eight pixels", ns.Theme.FontSize("MICRO") >= 8)
Options.Set("appearance.fontScale", 0)

local automatic
for _, option in ipairs(Options.FontOptions()) do
	if option.value == false then automatic = option end
end
eq = function(label, got, want) check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end
eq("the font choice says what Automatic is", automatic and automatic.label, L["Automatic (Inter)"])

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
