-- Profiles: switching, copying and resetting one has to leave the screen exactly
-- as if the addon had just started with that profile's settings.
--
-- Every setting has its side effects applied when it is changed one at a time
-- (Options.Apply). A profile change swaps all of them at once, underneath
-- everything, and nothing fires per setting -- so whatever the profile handler
-- forgets to redo stays drawn with the old profile's values: labels in the old
-- language, bubbles measured for the old emoticon style, toasts in the old
-- corner. This suite takes every setting in the schema off its default, then
-- compares what is on screen with a fresh start, region by region.

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
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM = ns.ConversationManager
M.guids = { ["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" } }
local function whisper(text)
	M.FireEvent("CHAT_MSG_WHISPER", text, "Thrall-Blackrock", "Common", "", "Thrall-Blackrock",
		"", 0, 0, "", 0, 1, "G-THRALL")
	M.RunFrames(2)
end
-- Content every display setting has something to act on: an emoticon, a raid
-- marker, a link, a long line that wraps, and more than one day.
whisper("hallo :) {star} schau mal https://example.com/seite")
whisper(("ein langer satz der umbrechen muss "):rep(4))
CM.SendMessage("Thrall-Blackrock", "antwort <3")
M.RunTimers(2)

ns.UI.Show()
CM.Select("Thrall-Blackrock")
M.RunFrames(6)

--------------------------------------------------------------------------------
-- What is on screen
--------------------------------------------------------------------------------

local function round(v) return v and math.floor(v * 2 + 0.5) / 2 or "-" end
local function colour(r, g, b, a)
	if not r then return "-" end
	-- Fully transparent is fully transparent, whatever the rest says.
	if (a or 1) == 0 then return "clear" end
	return ("%.2f,%.2f,%.2f,%.2f"):format(r, g or 0, b or 0, a or 1)
end

-- One line per visible frame or region under the windows the player sees: kind,
-- text, font size, colours, size, alpha. Sorted, so pooled frames that swapped
-- places compare equal; anything drawn differently does not.
local function snapshot()
	local roots = {}
	for _, name in ipairs({ "WhatTheWhisperFrame", "WhatTheWhisperMinimapButton" }) do
		if _G[name] then roots[#roots + 1] = _G[name] end
	end
	local lines = {}
	for _, root in ipairs(roots) do
		local nodes = M.Descendants(root)
		nodes[#nodes + 1] = root
		for _, node in ipairs(nodes) do
			if node.IsVisible and node:IsVisible() then
				local kind = node._kind
				local rec = { kind }
				if kind == "FontString" then
					rec[#rec + 1] = tostring(node:GetText())
					local _, size = node:GetFont()
					rec[#rec + 1] = tostring(size)
					rec[#rec + 1] = colour(node:GetTextColor())
				elseif kind == "Texture" then
					rec[#rec + 1] = colour(unpack(node._color or {}))
					rec[#rec + 1] = colour(unpack(node._vertex or {}))
				end
				rec[#rec + 1] = round(node:GetWidth()) .. "x" .. round(node:GetHeight())
				rec[#rec + 1] = ("a%.2f"):format(node:GetAlpha())
				lines[#lines + 1] = table.concat(rec, " | ")
			end
		end
	end
	-- And the things that are not a region under a window.
	local window = _G.WhatTheWhisperFrame
	lines[#lines + 1] = ("window %s %s scale %.2f alpha %.2f"):format(
		round(window:GetWidth()), round(window:GetHeight()), window:GetScale(), window:GetAlpha())
	lines[#lines + 1] = "minimap shown " .. tostring(_G.WhatTheWhisperMinimapButton
		and _G.WhatTheWhisperMinimapButton:IsShown())
	table.sort(lines)
	return lines
end

-- The lines only one side has, a few of each, for a failure message.
local function diff(a, b)
	local count = {}
	for _, line in ipairs(a) do count[line] = (count[line] or 0) + 1 end
	for _, line in ipairs(b) do count[line] = (count[line] or 0) - 1 end
	local onlyA, onlyB = {}, {}
	for line, n in pairs(count) do
		if n > 0 then onlyA[#onlyA + 1] = line elseif n < 0 then onlyB[#onlyB + 1] = line end
	end
	table.sort(onlyA)
	table.sort(onlyB)
	return onlyA, onlyB
end
local function same(label, got, want)
	local onlyGot, onlyWant = diff(got, want)
	local detail = {}
	for i = 1, math.min(#onlyGot, 6) do detail[#detail + 1] = "  now:    " .. onlyGot[i] end
	for i = 1, math.min(#onlyWant, 6) do detail[#detail + 1] = "  wanted: " .. onlyWant[i] end
	check(label, #onlyGot == 0 and #onlyWant == 0,
		("%d lines differ\n%s"):format(#onlyGot + #onlyWant, table.concat(detail, "\n      ")))
end

local function settle()
	M.RunTimers(2)
	M.RunFrames(8)
	ns.UI.Show()
	CM.Select("Thrall-Blackrock")
	M.RunFrames(8)
end

--------------------------------------------------------------------------------
-- A profile with every setting off its default
--------------------------------------------------------------------------------

settle()
local original = ns.db:GetCurrentProfile()
local defaults = snapshot()

-- Settings that would take the window away or make the comparison meaningless
-- rather than harder.
local SKIP = {
	["enabled"] = true,
	["combat.onEnter"] = true,
	["combat.onLeave"] = true,
}

local changed = 0
for _, category in ipairs(ns.Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			local path = row.path
			if path and not SKIP[path] then
				local current = ns.Options.Get(path)
				local value
				if row.type == "toggle" then
					value = not current
				elseif row.type == "dropdown" or row.type == "segmented" then
					for _, option in ipairs(row.options or {}) do
						if option.value ~= current and option.value ~= "auto" then value = option.value break end
					end
				elseif row.type == "slider" then
					value = (current ~= row.maxValue) and row.maxValue or row.minValue
				end
				if value ~= nil and value ~= current then
					ns.Options.Set(path, value)
					changed = changed + 1
				end
			end
		end
	end
end
check("the schema has settings to change", changed > 20, changed)
settle()
local custom = snapshot()
local a, b = diff(custom, defaults)
check("and changing them all changes what is drawn", #a + #b > 0)

--------------------------------------------------------------------------------
-- Switching, copying, resetting
--------------------------------------------------------------------------------

ns.db:SetProfile("Zweitprofil")
settle()
same("a new profile looks exactly like a fresh start", snapshot(), defaults)

ns.db:SetProfile(original)
settle()
same("switching back brings every custom setting back", snapshot(), custom)

ns.db:SetProfile("Zweitprofil")
ns.db:CopyProfile(original)
settle()
same("copying a profile in draws it exactly as the original", snapshot(), custom)

ns.db:ResetProfile()
settle()
same("resetting a profile looks exactly like a fresh start", snapshot(), defaults)

-- The reset the player can reach: /wtw reset, then Reset in the dialog.
ns.db:SetProfile(original)
settle()
-- A nickname is not a setting: the dialog promises the conversations are left
-- alone, and a nickname is part of one.
CM.SetAlias("Thrall-Blackrock", "Der Kriegshäuptling")
SlashCmdList["ACECONSOLE_WTW"]("reset")
local dialog = _G.WhatTheWhisperConfirmDialog
check("/wtw reset asks first", dialog ~= nil and dialog:IsShown())
if dialog and dialog:IsShown() then
	M.Click(dialog.confirm)
	settle()
	eq("the reset keeps the nicknames", ns.db.profile.aliases["Thrall-Blackrock"], "Der Kriegshäuptling")
	eq("and shows them", CM.DisplayName(CM.Get("Thrall-Blackrock")), "Der Kriegshäuptling")
	CM.SetAlias("Thrall-Blackrock", nil)
	settle()
	same("and apart from that it looks exactly like a fresh start", snapshot(), defaults)
end

-- Deleting the profile you are not on, then going back to it by name, starts it
-- over rather than reviving the old values.
ns.db:SetProfile("Zweitprofil")
ns.Options.Set("appearance.skin", "glass")
ns.db:SetProfile(original)
ns.db:DeleteProfile("Zweitprofil")
ns.db:SetProfile("Zweitprofil")
settle()
same("a deleted profile comes back as defaults", snapshot(), defaults)

--------------------------------------------------------------------------------
-- Things a snapshot of the window does not show
--------------------------------------------------------------------------------

-- A toast on screen while the profile changes moves to the new profile's corner
-- rather than staying where the old one put it.
do
	ns.db:SetProfile("Zweitprofil")
	ns.Options.Set("notifications.position", "topright")
	ns.Options.Set("notifications.toasts", true)
	ns.db:SetProfile("Toastprofil")
	ns.Options.Set("notifications.position", "bottomleft")
	ns.db:SetProfile("Zweitprofil")
	settle()
	ns.UI.Hide()
	M.RunFrames(4)
	whisper("ein toast")
	local toast = ns.Toast.Active()[1]
	check("a whisper with the window closed shows a toast", toast ~= nil)
	if toast then
		eq("in the corner the profile says", (toast:GetPoint(1)), "TOPRIGHT")
		ns.db:SetProfile("Toastprofil")
		M.RunFrames(2)
		eq("and after switching profiles, in the new profile's corner", (toast:GetPoint(1)), "BOTTOMLEFT")
	end
	ns.Toast.DismissAll()
	settle()
end

-- A text button is as wide as its label. Its label is re-set in the new type
-- size whenever the theme changes, so the width has to follow, both ways: a
-- button last given text at a larger font stayed that wide after the font went
-- back down, and one given text at a smaller font was too narrow for its label
-- after it went up.
do
	ns.db:SetProfile("Knopf")
	settle()
	local lookup = ns.MainWindow.Existing().view.profile.lookup
	local base = lookup:GetWidth()
	ns.Options.Set("appearance.fontScale", 4)
	settle()
	-- Label, padding on both sides, and the search glyph beside it.
	local need = lookup.label:GetStringWidth() + ns.S.MD * 2 + ns.SZ.ICON_GLYPH_SM + ns.S.SM
	check("at a larger font the button still holds its label and icon",
		lookup:GetWidth() >= need - 0.01, ("%s < %s"):format(lookup:GetWidth(), need))
	-- Given its text again at the larger size -- a language change does that --
	-- and then the font goes back down.
	ns.UI.Relocalize()
	ns.Options.Set("appearance.fontScale", 0)
	settle()
	eq("and back at the default it is its default width again", lookup:GetWidth(), base)
end

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
