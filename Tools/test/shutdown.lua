-- The addon after its own settings have been taken away.
--
-- AceDB strips every value that equals its default out of the profile at
-- PLAYER_LOGOUT, so the SavedVariables file holds only what the player actually
-- changed. For a profile nobody has customised that empties it completely --
-- `db.profile` is still a table and every section under it is gone -- and the
-- order in which logout handlers run is not defined, so the addon keeps working
-- for a while in that state: a whisper can still arrive, a ticker can still
-- fire, the window can still lay itself out.
--
-- A guard of the shape `db and db.profile and db.profile.animations.level` looks
-- careful and is exactly one link short. Twenty of them were, and each one threw
-- into the error counter that decides whether the addon gives up and starts
-- showing whispers in the chat frame again.
--
-- So this suite strips the profile for real -- by firing the event and letting
-- the shipped AceDB do it -- and then does the things the client still does.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
_G.SlashCmdList = {}
_G.UnitRace = function() return "Human","Human" end
_G.UnitFactionGroup = function() return "Alliance","Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end
local ns = dofile(ROOT .. "Tools/test/harness.lua").Load()
local CM = ns.ConversationManager
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.guids = { ["G-T"] = { class="SHAMAN", race="Orc", name="Thrall", realm="Blackrock" } }
M.FireEvent("CHAT_MSG_WHISPER", "hey", "Thrall", "Common","","Thrall","",0,0,"",0,1,"G-T")
ns.UI.Show()
local id = ns.Compat.NormalizeName("Thrall")
CM.Select(id)
CM.SendMessage(id, "hi")
M.RunFrames(8)

local soft = {}
ns.SoftError = function(c, e) soft[#soft+1] = c .. ": " .. tostring(e) end

-- Exactly what AceDB does at logout: every value equal to its default is
-- removed, which for an untouched profile empties it completely.
M.FireEvent("PLAYER_LOGOUT")
M.RunFrames(2)
local sectionsLeft = 0
for _ in pairs(ns.db.profile) do sectionsLeft = sectionsLeft + 1 end

-- Now do the things the client and the addon still do while that is true.
local CALLS = {
	{ "Theme.MotionScale", function() return ns.Theme.MotionScale() end },
	{ "Theme.Duration", function() return ns.Theme.Duration("FAST") end },
	{ "Theme.AnimationsEnabled", function() return ns.Theme.AnimationsEnabled() end },
	{ "Theme.IsFancy", function() return ns.Theme.IsFancy() end },
	{ "Theme.Refresh", function() return ns.Theme.Refresh() end },
	{ "Theme.RowHeight", function() return ns.Theme.RowHeight() end },
	{ "Theme.BubbleRadius", function() return ns.Theme.BubbleRadius() end },
	{ "Theme.MessageSpacing", function() return ns.Theme.MessageSpacing(10) end },
	{ "Theme.FontSize", function() return ns.Theme.FontSize("BODY") end },
	{ "Debug.IsEnabled", function() return ns.Debug.IsEnabled() end },
	{ "Debug.Log", function() return ns.Debug.Log("x", "y") end },
	{ "Format.Clock", function() return ns.Format.Clock(1788000000) end },
	{ "Format.DayLabel", function() return ns.Format.DayLabel(1788000000) end },
	{ "Format.ListStamp", function() return ns.Format.ListStamp(1788000000) end },
	{ "History.Prune", function() return ns.History.Prune() end },
	{ "History.Stats", function() return ns.History.Stats() end },
	{ "CM.DisplayName", function() return CM.DisplayName(CM.Get(id)) end },
	{ "CM.MessageText", function() return CM.MessageText(CM.Get(id).messages[1]) end },
	{ "CM.AddMessage", function() return CM.AddMessage(id, 0, "spaet", ns.MSG_WHISPER) end },
	{ "CM.Select", function() return CM.Select(id) end },
	{ "CM.MarkRead", function() return CM.MarkRead(id) end },
	{ "chat event arrives", function()
		M.FireEvent("CHAT_MSG_WHISPER", "noch was", "Thrall", "Common","","Thrall","",0,0,"",0,1,"G-T")
	end },
	{ "UI.RefreshAll", function() return ns.UI.RefreshAll() end },
	{ "UI.Show", function() return ns.UI.Show() end },
	{ "UI.Toggle", function() return ns.UI.Toggle() end },
	{ "Toast.Show", function()
		local c = CM.Get(id)
		return ns.Toast.Show(c, c.messages[#c.messages], false)
	end },
	{ "Notifications", function() M.FireEvent("PLAYER_REGEN_ENABLED") end },
	{ "Sounds.Play", function() return ns.Sounds.Play("incoming") end },
	{ "Minimap refresh", function() return ns.Minimap.Refresh and ns.Minimap.Refresh() end },
	{ "Export.Conversation", function() return ns.Export.Conversation(CM.Get(id), "text") end },
	{ "Search.FilterConversations", function() return ns.Search.FilterConversations("he") end },
	{ "Emoticons.Process", function() return ns.Emoticons.Process(":)", 14) end },
	{ "URLs.Process", function() return ns.URLs.Process("see https://a.example/b") end },
	{ "ProfileLinks.For", function() return ns.ProfileLinks.For(id) end },
	{ "UI.ShowProfileLinks", function() return ns.UI.ShowProfileLinks(id) end },
	{ "frames tick", function() M.RunFrames(10) end },
}

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end

check("AceDB really did strip the profile", sectionsLeft == 0,
	("%d sections survived; this suite is testing nothing"):format(sectionsLeft))

for _, spec in ipairs(CALLS) do
	local ok, err = pcall(spec[2])
	check("survives a stripped profile: " .. spec[1], ok,
		tostring(err):gsub(".*WhatTheWhisper/", ""))
end

check("and nothing was logged on the way",
	#soft == 0, soft[1] and soft[1]:gsub(".*WhatTheWhisper/", ""))

-- The consequence this is really about: every one of those throws is counted,
-- and enough of them in one session turns the failsafe on.
check("the failsafe was not tripped by a logout", not ns.Debug.IsDegraded(),
	("error count %d"):format(ns.Debug.ErrorCount()))

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
