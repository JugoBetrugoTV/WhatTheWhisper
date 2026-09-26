-- Two more things WIM players are used to: a sound of its own for the people
-- they know, and the unread count on a data-broker display (Titan Panel,
-- ElvUI's datatexts, Bazooka...) for players who hide minimap buttons.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

-- Every sound kit the addon asks the client to play.
local played = {}
_G.PlaySound = function(kit) played[#played + 1] = kit return true end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL [extras] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
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
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM, Compat = ns.ConversationManager, ns.Compat
local KIT = Compat.SOUNDS
ns.Options.Set("messages.openOnWhisper", false)
ns.Options.Set("sounds.cooldown", 0)

local line = 300
local function whisper(text, sender)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(2)
end
local function soundFor(text, sender)
	played = {}
	whisper(text, sender)
	return played[#played]
end

M.friends = { { name = "Jaina", connected = true } }
M.guildRoster = { { name = "Anduin-Blackrock", level = 70, class = "PRIEST" } }

--------------------------------------------------------------------------------
-- A sound for friends and guild
--------------------------------------------------------------------------------

eq("out of the box, a friend sounds like anybody else", soundFor("hi", "Jaina"), KIT.TELL_MESSAGE)

ns.Options.Set("sounds.friendMessage", "READY_CHECK")
eq("with a sound chosen, a friend gets it", soundFor("hi", "Jaina"), KIT.READY_CHECK)
eq("so does a guildmate", soundFor("hi", "Anduin"), KIT.READY_CHECK)
eq("a stranger still gets the ordinary one", soundFor("hi", "Thrall"), KIT.TELL_MESSAGE)

local me = Compat.PlayerName()
eq("saying the player's name still outranks who it is from",
	soundFor("hey " .. me .. ", schau mal", "Jaina"), KIT.RAID_WARNING)

CM.SetMuted("Jaina-Blackrock", true)
eq("a muted friend is silent", soundFor("pst", "Jaina"), nil)
CM.SetMuted("Jaina-Blackrock", false)

-- A conversation on screen makes no sound, friend or not.
ns.UI.Show()
CM.Select("Jaina-Blackrock")
M.RunFrames(2)
eq("a friend's thread already on screen is silent", soundFor("noch da?", "Jaina"), nil)
ns.UI.Hide()
M.RunFrames(4)

-- Battle.net is only ever a friend.
M.bnFriends = { { id = 7001, tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }
M.bnet = { [7001] = { tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }
played = {}
line = line + 1
M.FireEvent("CHAT_MSG_BN_WHISPER", "moin", "Kumpel", "", "", "", "", 0, 0, "", 0, line, "", 7001)
M.RunTimers(2)
eq("a Battle.net friend gets the friends' sound", played[#played], KIT.READY_CHECK)

eq("the setting is offered", (function()
	for _, category in ipairs(ns.Options.BuildSchema()) do
		for _, card in ipairs(category.cards or {}) do
			for _, row in ipairs(card.rows or {}) do
				if row.path == "sounds.friendMessage" then return row.options[1].value end
			end
		end
	end
end)(), "same")

ns.Options.Set("sounds.friendMessage", "same")

--------------------------------------------------------------------------------
-- Data-broker displays
--------------------------------------------------------------------------------

check("with no display installed there is nothing to register with",
	not ns.Minimap.RegisterBroker())

-- A display that loads later brings the library with it, the way Titan Panel
-- and ElvUI do. Only what a display relies on: named objects, first come.
local LDB = LibStub:NewLibrary("LibDataBroker-1.1", 4)
LDB.objects = {}
function LDB:NewDataObject(name, object)
	if self.objects[name] then return nil end
	self.objects[name] = object
	return object
end
M.FireEvent("ADDON_LOADED", "Titan")
local feed = LDB.objects.WhatTheWhisper
check("the feed is registered once a display brings the library", feed ~= nil)

if feed then
	eq("it is a data source", feed.type, "data source")
	check("with the addon's icon", type(feed.icon) == "string" and feed.icon:find("Logo") ~= nil)

	for _, conv in pairs(CM.All()) do CM.MarkRead(conv.id) end
	M.RunTimers(2)
	M.RunFrames(2)
	eq("nothing waiting reads as such", feed.text, ns.L["No new messages"])

	whisper("bist du on?", "Thrall")
	whisper("hallo?", "Thrall")
	M.RunFrames(2)
	eq("two unread whispers are counted", feed.text, ns.L["%d unread"]:format(2))

	local lines = {}
	feed.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
	local named = false
	for _, text in ipairs(lines) do
		if text:find("Thrall", 1, true) then named = true end
	end
	check("the tooltip names who is waiting", named, table.concat(lines, " | "))

	feed.OnClick(UIParent, "LeftButton")
	M.RunFrames(4)
	check("a click opens the messenger", ns.UI.IsShown())
	eq("on the thread that is waiting", CM.SelectedID(), "Thrall-Blackrock")
	M.RunTimers(2)
	M.RunFrames(2)
	eq("and once it is read, the count goes", feed.text, ns.L["No new messages"])

	ns.UI.Hide()
	M.RunFrames(4)
	feed.OnClick(UIParent, "RightButton")
	M.RunFrames(2)
	check("a right click opens the list", ns.Menu.IsOpen and ns.Menu.IsOpen())
	ns.Menu.Close()

	-- Hiding the minimap button hides the button, not the count elsewhere.
	ns.Options.Set("advanced.minimap.hide", true)
	whisper("noch einer", "Thrall")
	M.RunFrames(2)
	eq("with the minimap button hidden, the display still counts", feed.text,
		ns.L["%d unread"]:format(1))
	ns.Options.Set("advanced.minimap.hide", false)

	check("registering again changes nothing", ns.Minimap.RegisterBroker()
		and LDB.objects.WhatTheWhisper == feed)
end

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
