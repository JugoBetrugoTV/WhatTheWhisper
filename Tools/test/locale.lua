-- The language layer: every locale the picker offers, and switching between
-- them while the addon is running.
--
-- The interesting failures here are silent ones. A translation that drops a
-- "%d" does not look wrong in the file -- it throws at format() time, in front
-- of the player, in a language nobody on the team reads. A translation that
-- swaps "%d" and "%s" prints nonsense. A locale file nobody added to the XML
-- loads as an empty table and the picker offers a language that does nothing.
-- All three are checked here, for every locale, on every string.

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

local softErrors = {}
local realSoftError = ns.SoftError
ns.SoftError = function(c, e) softErrors[#softErrors + 1] = c .. ": " .. tostring(e) end

local L = ns.L
local BASE = "enUS"

--------------------------------------------------------------------------------
-- Every offered language is actually there
--------------------------------------------------------------------------------

check("the picker offers more than one language", #ns.LOCALES > 1)

local offered = {}
for i = 1, #ns.LOCALES do
	local entry = ns.LOCALES[i]
	offered[entry.code] = true
	check("offered locale " .. i .. " has a code", type(entry.code) == "string"
		and entry.code ~= "")
	-- Written in the language it names: a menu of language names you cannot
	-- read is not a menu you can use.
	check(entry.code .. " has a native name", type(entry.native) == "string"
		and entry.native ~= "")
	-- This is the one that catches a file missing from WhatTheWhisper.xml: the
	-- table simply is not there, and the option would silently do nothing.
	check(entry.code .. " is loaded", type(ns.LocaleData[entry.code]) == "table",
		"listed in ns.LOCALES but no table registered -- is it in the XML?")
end

for code in pairs(ns.LocaleData) do
	check(code .. " is offered in the picker", offered[code] == true,
		"a locale table nobody can select")
end

check("English is the base", ns.LocaleData[BASE] ~= nil)

--------------------------------------------------------------------------------
-- Coverage
--------------------------------------------------------------------------------

local source = ns.LocaleData[BASE]
local sourceCount = 0
for _ in pairs(source) do sourceCount = sourceCount + 1 end
check("the source language has strings", sourceCount > 100, sourceCount)

for i = 1, #ns.LOCALES do
	local code = ns.LOCALES[i].code
	local done, total = ns.LocaleCoverage(code)
	eq(code .. " coverage counts every source string", total, sourceCount)
	eq(code .. " answers every source string", done, sourceCount)
end

do
	local done, total = ns.LocaleCoverage("zzQQ")
	eq("coverage of a locale that does not exist is 0", done, 0)
	eq("and its total is 0 rather than a lie", total, 0)
end

--------------------------------------------------------------------------------
-- Format specifiers survive translation
--------------------------------------------------------------------------------

-- The conversions in a string, in order. Anything after a `%` that is not a
-- well-formed conversion comes back as the raw two characters, so a stray
-- percent sign in a translation shows up as a mismatch rather than slipping
-- through to string.format and blowing up there.
local function specs(text)
	local out, i = {}, 1
	while true do
		local at = string.find(text, "%%", i)
		if not at then break end
		local spec = string.match(text, "^%%[-+ #0]*%d*%.?%d*[%a%%]", at)
		out[#out + 1] = spec or string.sub(text, at, at + 1)
		i = at + (spec and #spec or 2)
	end
	return out
end

local function specList(text) return table.concat(specs(text), " ") end

-- One sample argument per conversion, so a translated string can be run through
-- string.format for real rather than only pattern-matched.
local function sampleArgs(list)
	local args = {}
	for i = 1, #list do
		local kind = string.sub(list[i], -1)
		if kind == "d" or kind == "i" or kind == "u" then args[i] = 7
		elseif kind == "f" or kind == "g" or kind == "e" then args[i] = 1.5
		elseif kind == "%" then args[i] = nil
		else args[i] = "sample" end
	end
	-- %% consumes no argument, so the holes have to be squeezed out.
	local packed, n = {}, 0
	for i = 1, #list do
		if args[i] ~= nil then n = n + 1; packed[n] = args[i] end
	end
	return packed, n
end

local specMismatches, formatFailures = 0, 0
for i = 1, #ns.LOCALES do
	local code = ns.LOCALES[i].code
	local strings = ns.LocaleData[code] or {}
	for key in pairs(source) do
		local value = strings[key]
		if type(value) == "string" then
			local want, got = specList(key), specList(value)
			if want ~= got then
				specMismatches = specMismatches + 1
				print(("FAIL %s [%s]\n      placeholders are %q, English has %q")
					:format(code, key, got, want))
			else
				local list = specs(value)
				if #list > 0 then
					local args, n = sampleArgs(list)
					local ok, err = pcall(string.format, value, unpack(args, 1, n))
					if not ok then
						formatFailures = formatFailures + 1
						print(("FAIL %s [%s]\n      will not format: %s")
							:format(code, key, tostring(err)))
					end
				end
			end
		end
	end
end
check("placeholders match English in every locale", specMismatches == 0,
	specMismatches .. " strings differ")
check("every translated string survives string.format", formatFailures == 0,
	formatFailures .. " strings throw")

--------------------------------------------------------------------------------
-- Translations are text, not accidents
--------------------------------------------------------------------------------

local shapeProblems = 0
for i = 1, #ns.LOCALES do
	local code = ns.LOCALES[i].code
	for key, value in pairs(ns.LocaleData[code] or {}) do
		if type(value) == "string" then
			local bad
			if value == "" then bad = "empty"
			elseif value ~= (string.gsub(value, "^%s+", "")) then bad = "leading space"
			elseif value ~= (string.gsub(value, "%s+$", "")) then bad = "trailing space"
			end
			if bad then
				shapeProblems = shapeProblems + 1
				print(("FAIL %s [%s]: %s"):format(code, key, bad))
			end
		elseif value ~= true then
			shapeProblems = shapeProblems + 1
			print(("FAIL %s [%s]: value is a %s"):format(code, key, type(value)))
		end
	end
end
check("no empty or padded translations", shapeProblems == 0)

--------------------------------------------------------------------------------
-- The lookup
--------------------------------------------------------------------------------

ns.Options.Set("appearance.locale", "auto")
eq("auto follows the client", ns.ActiveLocale(), ns.CLIENT_LOCALE)
eq("and the client here is English", ns.CLIENT_LOCALE, "enUS")
eq("English renders the key itself", L["Settings"], "Settings")
eq("a key nobody wrote falls through to itself",
	L["no string anywhere uses this"], "no string anywhere uses this")
eq("a non-string key comes back untouched", L[42], 42)

ns.Options.Set("appearance.locale", "deDE")
eq("choosing a language switches the lookup", ns.ActiveLocale(), "deDE")
eq("and the strings follow", L["Settings"], ns.LocaleData.deDE["Settings"])
check("the German is not just the English", L["Settings"] ~= "Settings")
-- The `true` convention: a product name is answered, and the answer is English.
eq("a name marked true falls back to the English", L["BattleTag"], "BattleTag")
eq("an unknown key still falls through in a translation",
	L["no string anywhere uses this"], "no string anywhere uses this")

ns.Options.Set("appearance.locale", "zzQQ")
eq("an unknown locale falls back rather than blanking", ns.ActiveLocale(), "enUS")
eq("and its strings are the English", L["Settings"], "Settings")

ns.Options.Set("appearance.locale", "auto")
eq("back to auto", L["Settings"], "Settings")

do
	local before = #softErrors
	L["Settings"] = "nope"
	check("writing to L is reported", #softErrors == before + 1)
	eq("and changes nothing", L["Settings"], "Settings")
	table.remove(softErrors)
end

check("LocaleIsAvailable knows what is loaded", ns.LocaleIsAvailable("frFR") == true)
check("and what is not", ns.LocaleIsAvailable("zzQQ") ~= true)

--------------------------------------------------------------------------------
-- The picker
--------------------------------------------------------------------------------

local options = ns.Options.LocaleOptions()
eq("the picker lists automatic plus every language", #options, #ns.LOCALES + 1)
eq("automatic comes first", options[1].value, "auto")
check("automatic is labelled", options[1].label ~= nil and options[1].label ~= "")
local seenValues = {}
for i = 1, #options do
	local option = options[i]
	check("option " .. i .. " has a label",
		type(option.label) == "string" and option.label ~= "")
	check("option " .. i .. " is not listed twice", not seenValues[option.value],
		tostring(option.value))
	seenValues[option.value] = true
end
for i = 1, #ns.LOCALES do
	check(ns.LOCALES[i].code .. " is in the picker", seenValues[ns.LOCALES[i].code] == true)
end
-- Complete locales are named plainly; the percentage is the warning label for a
-- half-finished one, so it must not be attached to a finished one.
local labelled = 0
for i = 1, #options do
	if string.find(options[i].label, "%%%)$") then labelled = labelled + 1 end
end
eq("no complete language is labelled with a percentage", labelled, 0)

-- ...and the label is not dead code. Every locale ships complete today, so the
-- only way to see the warning a half-finished one would carry is to make one.
do
	local victim = ns.LOCALES[2].code
	local strings = ns.LocaleData[victim]
	local key = "Settings"
	local kept = strings[key]
	strings[key] = nil

	local done, total = ns.LocaleCoverage(victim)
	eq("a missing string is missing from the count", done, total - 1)
	local warned = false
	local partial = ns.Options.LocaleOptions()
	for i = 1, #partial do
		if partial[i].value == victim then
			warned = string.find(partial[i].label, "%%%)$") ~= nil
		end
	end
	check("an incomplete language says so in the picker", warned)

	ns.Options.Set("appearance.locale", victim)
	eq("and the missing string falls back to English", L[key], "Settings")

	strings[key] = kept
	ns.Options.Set("appearance.locale", "auto")
end

--------------------------------------------------------------------------------
-- Switching with the window open
--------------------------------------------------------------------------------

ns.ConversationManager.AddMessage("Thrall-Blackrock", 0, "hallo", ns.MSG_WHISPER)
ns.ConversationManager.AddMessage("Jaina-Proudmoore", 0, "hallo", ns.MSG_WHISPER)
ns.UI.Show()
ns.ConversationManager.Select("Thrall-Blackrock")
-- A popout as well as the docked window: it is a second conversation view, built
-- by a different constructor, and its header buttons are labelled only by
-- tooltip. Nothing else in the suite would notice if it stayed in English.
ns.UI.TogglePopout("Jaina-Proudmoore")
ns.SettingsUI.Show()
M.RunFrames(3)

-- Every string a player can actually read: what is written on screen, and what
-- a tooltip would say if they hovered. Tooltips matter here because most of the
-- window chrome -- the titlebar, the header actions, the composer buttons -- is
-- icons, and the only words attached to them are the ones in the tooltip.
local function visibleTexts()
	local out = {}
	local function keep(text)
		if type(text) == "string" and text ~= "" then out[text] = true end
	end
	local nodes = M.Descendants(_G.UIParent)
	for i = 1, #nodes do
		local node = nodes[i]
		if M.EffectivelyShown(node) then
			if node.GetText then keep(node:GetText()) end
			local tip = node.__wtwTooltip
			if tip then keep(tip.text) keep(tip.subtext) end
		end
	end
	return out
end

local before = visibleTexts()
check("the settings window is showing English", before[L["Appearance"]] == true,
	"could not find " .. tostring(L["Appearance"]))

ns.Options.Set("appearance.locale", "frFR")
M.RunFrames(3)
eq("the lookup switched", L["Appearance"], ns.LocaleData.frFR["Appearance"])
local after = visibleTexts()
check("and the open window re-rendered", after[L["Appearance"]] == true,
	"could not find " .. tostring(L["Appearance"]))

-- The general form of the same question, because a label baked once at
-- construction never notices the setting changed. Any string still on screen
-- that is word for word an English source string, when the chosen language has
-- a different word for it, is a label that was written once and never revisited.
local stale = {}
for text in pairs(after) do
	local translated = ns.LocaleData.frFR[text]
	if type(translated) == "string" and translated ~= text then
		stale[#stale + 1] = text
	end
end
table.sort(stale)
check("nothing on screen is still in English", #stale == 0,
	table.concat(stale, " | "))

-- Every language in turn, with the window open, is where a translation that
-- breaks layout or throws on a format string shows itself.
for i = 1, #ns.LOCALES do
	local code = ns.LOCALES[i].code
	ns.Options.Set("appearance.locale", code)
	M.RunFrames(2)
	ns.SettingsUI.SetFilter(ns.L["Language"])
	M.RunFrames(2)
	ns.SettingsUI.SetFilter("")
	M.RunFrames(2)
	eq("switching to " .. code .. " takes effect", ns.ActiveLocale(), code)
	check("the settings window survives " .. code, ns.SettingsUI.IsShown())
	check("the messenger survives " .. code, ns.UI.IsShown())
end

ns.Options.Set("appearance.locale", "auto")
M.RunFrames(3)
ns.SettingsUI.Hide()
M.RunFrames(2)

check("no soft errors while switching languages", #softErrors == 0,
	table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))
ns.SoftError = realSoftError

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
