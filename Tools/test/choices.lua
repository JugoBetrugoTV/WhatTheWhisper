-- Every choice in the settings can be made with the mouse.
--
-- effects.lua and settings.lua set values through the control's own SetValue,
-- which is how a setting is proved to *do* something -- and is also how a choice
-- that cannot be clicked passes. "Messenger and chat" could not be clicked for as
-- long as it existed: its value is `false`, and the segment's click handler
-- skipped any option whose value was falsy, which it took for "no option here".
--
-- So this one never calls SetValue. For every choice in every category, whatever
-- control it was drawn as, it presses each option the way a player does and asks
-- the setting what it became.

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
		print("FAIL [choices] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local Options, SettingsUI = ns.Options, ns.SettingsUI

-- The row of the open menu showing `text`. Only the menu's own rows count: a
-- dropdown elsewhere on the page can be showing the same word as its value.
local function menuRow(text)
	local menu = _G.WhatTheWhisperContextMenu
	for _, f in ipairs(M.frames) do
		if f.label and f.label.GetText and f.label:GetText() == text and f:IsVisible()
			and f._scripts and f._scripts.OnMouseUp then
			local node, inside = f._parent, false
			while node do
				if node == menu then inside = true break end
				node = node._parent
			end
			if inside then return f end
		end
	end
end

local function sameValue(a, b)
	return a == b
end

SettingsUI.Show()
M.RunFrames(4)

local tested, skipped = 0, {}
local specs = {}
for _, category in ipairs(Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			if row.type == "dropdown" and row.path then
				specs[#specs + 1] = { category = category.id, path = row.path, label = row.label,
					options = row.options }
			end
		end
	end
end
check("the schema has choices to try", #specs > 10, #specs)

for _, spec in ipairs(specs) do
	SettingsUI.SelectCategory(spec.category)
	M.RunFrames(4)
	local control
	for row in SettingsUI.RowPool():EnumerateActive() do
		if row.control and row.control.spec and row.control.spec.path == spec.path then
			control = row.control
		end
	end
	if not control then
		skipped[#skipped + 1] = spec.path
	else
		local original = Options.Get(spec.path)
		for i, option in ipairs(spec.options) do
			-- Start from somewhere else, so choosing is a change that can be seen.
			for _, other in ipairs(spec.options) do
				if other.value ~= option.value then Options.Set(spec.path, other.value) break end
			end
			SettingsUI.Refresh()
			M.RunFrames(2)
			control = nil
			for row in SettingsUI.RowPool():EnumerateActive() do
				if row.control and row.control.spec and row.control.spec.path == spec.path then
					control = row.control
				end
			end

			local label = ("%s: %s"):format(spec.path, tostring(option.label))
			if control.segments then
				-- Segments: press the one that carries this option.
				local button
				for _, segment in ipairs(control.segments) do
					if segment:IsShown() and segment.optionValue == option.value then button = segment end
				end
				check(label .. " has a segment of its own", button ~= nil)
				if button then M.Click(button, "LeftButton") end
			else
				-- A menu: open it, then press the entry.
				M.Click(control, "LeftButton")
				M.RunFrames(2)
				local entry = menuRow(option.label)
				check(label .. " is in the menu", entry ~= nil)
				if entry then M.Click(entry, "LeftButton") end
				ns.Menu.Close()
			end
			M.RunFrames(2)
			check(label .. " is what the setting became by clicking it",
				sameValue(Options.Get(spec.path), option.value),
				("got %s"):format(tostring(Options.Get(spec.path))))
			tested = tested + 1
		end
		Options.Set(spec.path, original)
	end
end

check("every choice was reachable on screen", #skipped == 0, table.concat(skipped, ", "))
check("a good many options were pressed", tested > 40, tested)

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
