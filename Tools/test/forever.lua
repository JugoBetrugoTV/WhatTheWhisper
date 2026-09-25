-- WoW Forever: two-part names and no realm suffixes.
--
-- A Forever character is called "Matt Loc" -- a first and a second name, unique
-- in the region -- and there is one realm per ruleset, so nobody is addressed as
-- "Name-Realm". The client still reports a realm internally ("ClassicBetaPvE2"
-- in the beta), and the addon used to append it: every whisper typed into the
-- window went to "Matt Loc-ClassicBetaPvE2", which the server answers with "No
-- player named ... is currently playing", while a reply from the default chat
-- box went through. This file is that client.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
local Client = dofile(ROOT .. "Tools/test/client.lua")
Client.Setup("forever")

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local REALM = "ClassicBetaPvE2"
_G.GetRealmName = function() return REALM end
_G.GetNormalizedRealmName = function() return REALM end

-- UnitName on Forever: the player's full name, but for anyone else only the first
-- name, with the second one where the realm normally is. GetUnitName(unit, true)
-- is the chat form every time.
local units = {
	player = { first = "Blazii", second = "Tester" },
	target = { first = "Matt", second = "Loc" },
}
_G.UnitName = function(unit)
	local u = units[unit]
	if not u then return nil end
	if unit == "player" then return u.first .. " " .. u.second end
	return u.first, u.second
end
_G.GetUnitName = function(unit)
	local u = units[unit]
	return u and (u.first .. " " .. u.second) or nil
end

-- The server, as the beta answers it: a name with a realm suffix is nobody.
local sent = {}
local function send(text, kind, _, target)
	sent[#sent + 1] = { text = text, kind = kind, target = target }
	-- The answer comes back from the server a moment later, not from inside
	-- the call: by then the addon has recorded the message as on its way.
	if kind == "WHISPER" and target and target:find("%-") then
		_G.C_Timer.After(0.2, function()
			M.FireEvent("CHAT_MSG_SYSTEM", _G.ERR_CHAT_PLAYER_NOT_FOUND_S:format(target))
		end)
	end
end
_G.C_ChatInfo.SendChatMessage = send
_G.SendChatMessage = send
local invited, ignored = {}, {}
_G.C_PartyInfo = _G.C_PartyInfo or {}
_G.C_PartyInfo.InviteUnit = function(name) invited[#invited + 1] = name end
_G.C_FriendList.AddIgnore = function(name) ignored[#ignored + 1] = name return true end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL [forever] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local CM, Compat = ns.ConversationManager, ns.Compat

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

check("the addon knows this client has no realm names", not Compat.namesHaveRealms)

--------------------------------------------------------------------------------
-- The report: whispered by "Matt Loc", and the reply never arrived
--------------------------------------------------------------------------------

M.FireEvent("CHAT_MSG_WHISPER", "hey, kannst du helfen?", "Matt Loc", "Common", "",
	"Matt Loc", "", 0, 0, "", 0, 101, "Player-1-00000A")
M.RunTimers(2)
local id = Compat.PlayerID("Matt Loc")
local conv = CM.Get(id)
check("the whisper opened a thread", conv ~= nil, id)

local ok = CM.SendMessage(id, "klar, was brauchst du?")
M.RunTimers(2)
check("sending from the window reports success", ok)
eq("and the server was asked for the name alone", sent[1] and sent[1].target, "Matt Loc")
local last = conv and conv.messages[#conv.messages]
check("the message is not marked undelivered",
	last and last[ns.MSG_STATUS] ~= ns.SEND_FAILED, last and last[ns.MSG_STATUS])

-- The echo comes back under the same name, and lands in the same thread.
M.FireEvent("CHAT_MSG_WHISPER_INFORM", "klar, was brauchst du?", "Matt Loc", "Common", "",
	"Matt Loc", "", 0, 0, "", 0, 102, "Player-1-00000A")
M.RunTimers(2)
eq("the echo lands in the same thread", CM.Count(), 1)

--------------------------------------------------------------------------------
-- Everything else that names a player
--------------------------------------------------------------------------------

Compat.InviteUnit(id)
eq("an invite goes to the name alone", invited[1], "Matt Loc")
Compat.AddIgnore(id)
eq("and so does ignoring someone", ignored[1], "Matt Loc")

-- Typed in lowercase, a name still finds the thread the whisper opened.
eq("a name typed in lowercase is the same person", Compat.PlayerID("matt loc"), id)
eq("with any amount of space between the two names", Compat.PlayerID("  matt   loc "), id)

-- The unit functions: "Matt", "Loc" from UnitName is one person, not "Matt-Loc".
eq("a targeted player is identified by both names", Compat.UnitFullName("target"), id)
eq("and so is the player", Compat.PlayerFullName(), "Blazii Tester-" .. REALM)
eq("whose short name has both names in it", Compat.PlayerName(), "Blazii Tester")

--------------------------------------------------------------------------------
-- Names the player types
--------------------------------------------------------------------------------

check("a first and a second name is a valid name", Compat.ValidatePlayerName("Matt Loc"))
local valid, reason = Compat.ValidatePlayerName("Matt")
check("a first name alone is not", not valid, reason)
eq("and the reason says why", reason, "twoNames")
check("letters only, in both", not Compat.ValidatePlayerName("Matt L0c"))
check("and no third word", not Compat.ValidatePlayerName("Matt Loc Extra"))
check("accented letters are letters", Compat.ValidatePlayerName("Élodie Brûlé"))

--------------------------------------------------------------------------------
-- Nothing on screen talks about realms
--------------------------------------------------------------------------------

ns.Options.Set("messages.showRealm", "always")
eq("the realm is never shown, even when the setting asks for it",
	CM.DisplayName(conv), "Matt Loc")
ns.Options.Set("messages.showRealm", "cross")

local hasRealmRow = false
for _, category in ipairs(ns.Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			if row.path == "messages.showRealm" then hasRealmRow = true end
		end
	end
end
check("and the settings do not offer a realm option", not hasRealmRow)

ns.UI.Show()
CM.Select(id)
M.RunFrames(4)
local shown = {}
for _, r in ipairs(M.regions) do
	if r._kind == "FontString" and r:IsVisible() and r:GetText() then shown[#shown + 1] = r:GetText() end
end
local mentionsRealm = false
for _, text in ipairs(shown) do
	if text:find(REALM, 1, true) then mentionsRealm = true end
end
check("the window does not show the internal realm name anywhere", not mentionsRealm)

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
