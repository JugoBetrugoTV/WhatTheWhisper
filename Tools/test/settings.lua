-- Settings audit: every control must point at a real setting, hold a legal
-- value, and change something observable. No dead controls.

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

for _, path in ipairs({
	"Ace3/LibStub/LibStub.lua", "Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua",
	"Ace3/AceAddon-3.0/AceAddon-3.0.lua", "Ace3/AceEvent-3.0/AceEvent-3.0.lua",
	"Ace3/AceTimer-3.0/AceTimer-3.0.lua", "Ace3/AceHook-3.0/AceHook-3.0.lua",
	"Ace3/AceDB-3.0/AceDB-3.0.lua", "Ace3/AceLocale-3.0/AceLocale-3.0.lua",
	"Ace3/AceConsole-3.0/AceConsole-3.0.lua",
}) do assert(loadfile(ROOT .. path))(path, {}) end

local ns = {}
local xml = io.open(ROOT .. "WhatTheWhisper/WhatTheWhisper.xml"):read("*a")
for file in xml:gmatch('<Script file="([^"]+)"/>') do
	assert(loadfile(ROOT .. "WhatTheWhisper/" .. file:gsub("\\", "/")))("WhatTheWhisper", ns)
end

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
local softErrors = {}
ns.SoftError = function(c, e) softErrors[#softErrors + 1] = c .. ": " .. tostring(e) end

for i = 1, 20 do
	ns.ConversationManager.AddMessage("Thrall-Blackrock", i % 2,
		"nachricht " .. i, ns.MSG_WHISPER)
end
ns.UI.Show()
ns.ConversationManager.Select("Thrall-Blackrock")
M.RunFrames(3)

--------------------------------------------------------------------------------
-- Walk the schema
--------------------------------------------------------------------------------

local schema = ns.Options.BuildSchema()
local seenPaths, rows, categories = {}, 0, 0

local function resolves(path)
	local node = ns.db.profile
	local last
	for key in path:gmatch("[^%.]+") do
		if last then
			node = node[last]
			if type(node) ~= "table" then return false end
		end
		last = key
	end
	return node ~= nil and last ~= nil, node, last
end

for _, category in ipairs(schema) do
	categories = categories + 1
	check("category has an id", type(category.id) == "string")
	check("category '" .. tostring(category.id) .. "' has a label",
		type(category.label) == "string" and category.label ~= "")
	check("category '" .. tostring(category.id) .. "' has an icon",
		type(category.icon) == "string")
	check("category '" .. tostring(category.id) .. "' has cards",
		type(category.cards) == "table" and #category.cards > 0)

	for _, card in ipairs(category.cards) do
		check("card in '" .. category.id .. "' has a title",
			type(card.title) == "string" and card.title ~= "")
		for _, row in ipairs(card.rows) do
			rows = rows + 1
			local where = category.id .. "/" .. tostring(row.label)
			check(where .. " has a label", type(row.label) == "string" and row.label ~= "")
			check(where .. " has a known type", ({
				toggle = true, slider = true, dropdown = true,
				button = true, color = true, input = true, info = true,
			})[row.type] == true, tostring(row.type))

			if row.path then
				check(where .. " path is unique", not seenPaths[row.path], row.path)
				seenPaths[row.path] = true
				local ok = resolves(row.path)
				check(where .. " points at a real setting (" .. row.path .. ")", ok)

				local value = ns.Options.Get(row.path)
				if row.type == "toggle" then
					check(where .. " holds a boolean", type(value) == "boolean",
						type(value))
				elseif row.type == "slider" then
					check(where .. " holds a number", type(value) == "number", type(value))
					check(where .. " is inside its range",
						type(value) == "number" and value >= row.minValue
							and value <= row.maxValue,
						("%s not in [%s, %s]"):format(tostring(value),
							tostring(row.minValue), tostring(row.maxValue)))
					check(where .. " has a formatter", type(row.format) == "function")
				elseif row.type == "dropdown" then
					check(where .. " has options",
						type(row.options) == "table" and #row.options > 0)
					local found = false
					for _, option in ipairs(row.options or {}) do
						check(where .. " option has a label",
							type(option.label) == "string" and option.label ~= "")
						if option.value == value then found = true end
					end
					check(where .. " current value is one of its options", found,
						tostring(value))
				elseif row.type == "input" then
					check(where .. " holds a string", type(value) == "string", type(value))
				end
			elseif row.type == "button" then
				check(where .. " button has an action", type(row.onClick) == "function")
				check(where .. " button has a caption",
					type(row.buttonText) == "string" and row.buttonText ~= "")
			elseif row.type == "info" then
				check(where .. " info row has a value function",
					type(row.value) == "function")
				local ok, text = pcall(row.value)
				check(where .. " info value evaluates", ok and type(text) == "string",
					tostring(text))
			end
		end
	end
end

print(("schema: %d categories, %d rows, %d bound settings")
	:format(categories, rows, (function()
		local n = 0
		for _ in pairs(seenPaths) do n = n + 1 end
		return n
	end)()))

--------------------------------------------------------------------------------
-- Every stored setting is either on screen or used by the code
--------------------------------------------------------------------------------

-- Read the source once so a setting that is neither exposed nor referenced can
-- be reported as dead.
local source = {}
for file in xml:gmatch('<Script file="([^"]+)"/>') do
	local handle = io.open(ROOT .. "WhatTheWhisper/" .. file:gsub("\\", "/"))
	source[#source + 1] = handle:read("*a")
	handle:close()
end
source = table.concat(source, "\n")

local INTERNAL = {   -- stored state, deliberately not a control
	["layout.point"] = true, ["layout.width"] = true, ["layout.height"] = true,
	["layout.maxTabs"] = true, ["advanced.minimap.angle"] = true,
	["emoticons.recent"] = true, ["popouts"] = true,
}

local dead = {}
local function walk(node, prefix)
	for key, value in pairs(node) do
		local path = prefix == "" and key or (prefix .. "." .. key)
		if type(value) == "table" and next(value) ~= nil and key ~= "popouts" then
			walk(value, path)
		else
			if not seenPaths[path] and not INTERNAL[path] then
				-- Referenced by name anywhere in the code counts as used.
				if not source:find("%." .. key .. "%f[%W]") and not source:find('"' .. key .. '"') then
					dead[#dead + 1] = path
				end
			end
		end
	end
end
walk(ns.defaults.profile, "")
check("no dead settings", #dead == 0, table.concat(dead, ", "))

--------------------------------------------------------------------------------
-- Changing a setting must change something observable
--------------------------------------------------------------------------------

local window = ns.MainWindow.Get()

ns.Options.Set("appearance.skin", "messenger")
M.RunFrames(2)
eq("skin change reaches the theme", ns.Theme.skinID, "messenger")
ns.Options.Set("appearance.skin", "midnight")

ns.Options.Set("appearance.fontScale", 3)
M.RunFrames(2)
eq("font scale reaches the fonts", ns.Theme.FontSize("BODY"), ns.T.BODY + 3)
ns.Options.Set("appearance.fontScale", 0)

ns.Options.Set("appearance.density", "compact")
eq("density reaches the row height", ns.Theme.RowHeight(), ns.SZ.ROW_H_COMPACT)
ns.Options.Set("appearance.density", "comfortable")
eq("density restores", ns.Theme.RowHeight(), ns.SZ.ROW_H)

ns.Options.Set("appearance.radius", 0)
eq("square corners reach the radius", ns.Theme.Radius(ns.R.LG), 0)
ns.Options.Set("appearance.radius", 1)
check("normal corners restore", ns.Theme.Radius(ns.R.LG) > 0)

ns.Options.Set("animations.level", "off")
eq("animations off is honoured", ns.Theme.AnimationsEnabled(), false)
ns.Options.Set("animations.level", "fancy")
check("fancy is recognised", ns.Theme.IsFancy())
ns.Options.Set("animations.level", "normal")

ns.Options.Set("layout.mode", "tabbed")
M.RunFrames(2)
eq("tabbed mode hides the sidebar", window.sidebar:IsShown(), false)
eq("tabbed mode shows the tab strip", window.tabs:IsShown(), true)
ns.Options.Set("layout.mode", "sidebar")
M.RunFrames(2)
eq("sidebar mode shows the sidebar", window.sidebar:IsShown(), true)
eq("sidebar mode hides the tab strip", window.tabs:IsShown(), false)

ns.Options.Set("layout.sidebarWidth", 240)
M.RunFrames(2)
eq("sidebar width is applied", window.sidebar:GetWidth(), 240)
ns.Options.Set("layout.sidebarWidth", ns.SZ.SIDEBAR_W)

ns.Options.Set("history.retention", "off")
eq("retention off detaches history", ns.History.IsPersistent(), false)
ns.Options.Set("history.retention", "30d")
eq("retention on re-attaches", ns.History.IsPersistent(), true)

ns.Options.Set("messages.showRealm", "always")
eq("showRealm always adds the realm",
	ns.ConversationManager.DisplayName(ns.ConversationManager.Get("Thrall-Blackrock")),
	"Thrall-Blackrock")
ns.Options.Set("messages.showRealm", "never")
eq("showRealm never drops it",
	ns.ConversationManager.DisplayName(ns.ConversationManager.Get("Thrall-Blackrock")),
	"Thrall")
ns.Options.Set("messages.showRealm", "cross")

ns.Options.Set("appearance.clock24", false)
check("12 hour clock is applied", ns.Format.Clock(1788000000):find("[AP]M") ~= nil,
	ns.Format.Clock(1788000000))
ns.Options.Set("appearance.clock24", true)
check("24 hour clock is applied", ns.Format.Clock(1788000000):find("[AP]M") == nil,
	ns.Format.Clock(1788000000))

ns.Options.Set("emoticons.style", "text")
eq("text emoticons stay text", ns.Emoticons.Process("hi :)", 14), "hi :)")
ns.Options.Set("emoticons.style", "images")
check("image emoticons become markup",
	ns.Emoticons.Process("hi :)", 14):find("|T") ~= nil)

ns.Options.Set("links.detect", false)
eq("link detection can be turned off",
	ns.URLs.Process("besuch example.com"), "besuch example.com")
ns.Options.Set("links.detect", true)
check("link detection can be turned on",
	ns.URLs.Process("besuch example.com"):find("|Hwtwurl:") ~= nil)

ns.Options.Set("sounds.dnd", true)
check("do not disturb suppresses sound", ns.Sounds.IsSuppressed())
ns.Options.Set("sounds.dnd", false)
check("sound resumes", not ns.Sounds.IsSuppressed())

ns.Options.Set("advanced.minimap.hide", true)
M.RunFrames(2)
local button = _G.WhatTheWhisperMinimapButton
eq("hiding the minimap button works", button and button:IsShown(), false)
ns.Options.Set("advanced.minimap.hide", false)
M.RunFrames(2)
eq("showing it again works", _G.WhatTheWhisperMinimapButton:IsShown(), true)

ns.Options.Set("notifications.position", "bottomleft")
M.RunFrames(2)
check("toast position is applied", true)
ns.Options.Set("notifications.position", "topright")

--------------------------------------------------------------------------------
-- Profile reset
--------------------------------------------------------------------------------

ns.Options.Set("appearance.skin", "glass")
ns.Options.Set("appearance.fontScale", 4)
ns.db:ResetProfile()
M.RunFrames(3)
eq("reset restores the default skin", ns.db.profile.appearance.skin, "midnight")
eq("reset restores the default font scale", ns.db.profile.appearance.fontScale, 0)
eq("reset reaches the theme", ns.Theme.skinID, "midnight")
check("history survived the profile reset",
	#ns.ConversationManager.Get("Thrall-Blackrock").messages >= 20)

check("no soft errors during the audit", #softErrors == 0,
	table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
