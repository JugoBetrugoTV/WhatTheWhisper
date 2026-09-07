-- Focused verification of the whisper pipeline: identity, ordering, unread
-- accounting and -- above all -- that a message appears exactly once.

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
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

-- Libraries and addon files both come from the shipped manifests, so these
-- tests load exactly what a player who unzipped only WhatTheWhisper/ gets.
local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
ns.SoftError = function(context, err) check("no soft error", false, context .. ": " .. tostring(err)) end

local CM = ns.ConversationManager
local MSG_TS, MSG_DIR, MSG_TEXT, MSG_STATUS = ns.MSG_TS, ns.MSG_DIR, ns.MSG_TEXT, ns.MSG_STATUS

M.guids = {
	["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-THRALL2"] = { class = "MAGE", race = "Human", name = "Thrall", realm = "Draenor" },
}

local function whisper(text, sender, guid)
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "", 0, 1, guid)
	M.RunTimers(2)
end
local function inform(text, target, guid)
	M.FireEvent("CHAT_MSG_WHISPER_INFORM", text, target, "Common", "", target, "", 0, 0, "", 0, 2, guid)
	M.RunTimers(2)
end
local function count(id, text)
	local conv = CM.Get(id)
	if not conv then return -1 end
	local n = 0
	for i = 1, #conv.messages do
		if conv.messages[i][MSG_TEXT] == text then n = n + 1 end
	end
	return n
end

--------------------------------------------------------------------------------
-- Identity and normalisation
--------------------------------------------------------------------------------

eq("bare name gets our realm", ns.Compat.NormalizeName("Thrall"), "Thrall-Blackrock")
eq("name with realm kept", ns.Compat.NormalizeName("Thrall-Draenor"), "Thrall-Draenor")
eq("realm spaces stripped", ns.Compat.NormalizeName("Thrall-Burning Legion"), "Thrall-BurningLegion")
eq("battle.net key untouched", ns.Compat.NormalizeName("BN:Tag#1234"), "BN:Tag#1234")
eq("empty name rejected", ns.Compat.NormalizeName(""), nil)
eq("short name drops own realm", ns.Compat.ShortName("Thrall-Blackrock"), "Thrall")
eq("short name drops other realm too", ns.Compat.ShortName("Thrall-Draenor"), "Thrall")
eq("cross realm detected", ns.Compat.IsCrossRealm("Thrall-Draenor"), true)
eq("same realm not cross", ns.Compat.IsCrossRealm("Thrall-Blackrock"), false)

--------------------------------------------------------------------------------
-- Incoming
--------------------------------------------------------------------------------

whisper("hallo", "Thrall", "G-THRALL")
local conv = CM.Get("Thrall-Blackrock")
check("conversation created on first whisper", conv ~= nil)
eq("one message stored", #conv.messages, 1)
eq("direction is incoming", conv.messages[1][MSG_DIR], ns.DIR_IN)
eq("text preserved", conv.messages[1][MSG_TEXT], "hallo")
eq("class resolved from guid", conv.class, "SHAMAN")
eq("unread counted", conv.unread, 1)
check("timestamp present", (conv.messages[1][MSG_TS] or 0) > 0)

-- Same name, different realm: two separate threads.
whisper("ich bin ein anderer", "Thrall-Draenor", "G-THRALL2")
local other = CM.Get("Thrall-Draenor")
check("cross-realm namesake is its own thread", other ~= nil and other ~= conv)
eq("namesake thread has its own message", #other.messages, 1)
eq("original thread untouched", #conv.messages, 1)
eq("namesake class resolved", other.class, "MAGE")
eq("display name disambiguates cross-realm",
	CM.DisplayName(other), "Thrall-Draenor")
eq("display name plain for same realm", CM.DisplayName(conv), "Thrall")

--------------------------------------------------------------------------------
-- Outgoing: exactly once
--------------------------------------------------------------------------------

M.sent = {}
local sent = CM.SendMessage("Thrall-Blackrock", "bin gleich da")
M.RunTimers(2)
eq("send reported success", sent, true)
eq("reached SendChatMessage once", #M.sent, 1)
eq("target was the full name", M.sent[1].target, "Thrall-Blackrock")
eq("bubble added immediately", count("Thrall-Blackrock", "bin gleich da"), 1)
eq("marked pending", conv.messages[#conv.messages][MSG_STATUS], ns.SEND_PENDING)

inform("bin gleich da", "Thrall", "G-THRALL")
eq("still exactly one copy after the server echo",
	count("Thrall-Blackrock", "bin gleich da"), 1)
eq("upgraded to sent", conv.messages[#conv.messages][MSG_STATUS], ns.SEND_OK)

-- A whisper typed into Blizzard's own chat frame: we never sent it, so the
-- echo is the only signal and it must be adopted exactly once.
inform("von blizzard chat", "Thrall", "G-THRALL")
eq("adopted foreign outgoing message", count("Thrall-Blackrock", "von blizzard chat"), 1)
eq("adopted as sent", conv.messages[#conv.messages][MSG_STATUS], ns.SEND_OK)
inform("von blizzard chat", "Thrall", "G-THRALL")
eq("a second identical echo is a second message",
	count("Thrall-Blackrock", "von blizzard chat"), 2)

-- The reload case: the pending bubble is already stored but the in-memory queue
-- is gone. The echo must reconcile, not duplicate.
local msg = CM.AddMessage("Thrall-Blackrock", ns.DIR_OUT, "nach reload",
	ns.MSG_WHISPER, nil, ns.SEND_PENDING)
eq("pending bubble stored", count("Thrall-Blackrock", "nach reload"), 1)
inform("nach reload", "Thrall", "G-THRALL")
eq("reload echo reconciled, not duplicated", count("Thrall-Blackrock", "nach reload"), 1)
eq("reload bubble upgraded", msg[MSG_STATUS], ns.SEND_OK)

-- An old pending bubble must not swallow a genuinely new echo.
local stale = CM.AddMessage("Thrall-Blackrock", ns.DIR_OUT, "sehr alt",
	ns.MSG_WHISPER, ns.Compat.GetServerTime() - 600, ns.SEND_PENDING)
inform("sehr alt", "Thrall", "G-THRALL")
eq("stale pending does not absorb a new echo", count("Thrall-Blackrock", "sehr alt"), 2)
eq("stale bubble left pending", stale[MSG_STATUS], ns.SEND_PENDING)

--------------------------------------------------------------------------------
-- Failure
--------------------------------------------------------------------------------

CM.SendMessage("Jaina-Blackrock", "bist du da?")
M.RunTimers(1)
local jaina = CM.Get("Jaina-Blackrock")
eq("pending before the error", jaina.messages[#jaina.messages][MSG_STATUS], ns.SEND_PENDING)
M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Jaina' is currently playing.")
M.RunTimers(1)
eq("marked failed", jaina.messages[#jaina.messages][MSG_STATUS], ns.SEND_FAILED)
eq("no duplicate from the failure path", count("Jaina-Blackrock", "bist du da?"), 1)

--------------------------------------------------------------------------------
-- Splitting
--------------------------------------------------------------------------------

M.sent = {}
local long = string.rep("Ein ziemlich langer Satz mit Umlauten wie oeaeue. ", 14)
local ok, parts = CM.SendMessage("Thrall-Blackrock", long)
M.RunTimers(1)
check("long message sent", ok)
check("split into several parts", parts > 1, parts)
eq("every part reached the server", #M.sent, parts)
local allFit = true
for i = 1, #M.sent do
	if #M.sent[i].text > ns.MAX_MESSAGE_BYTES then allFit = false end
end
check("no part exceeds the byte limit", allFit)
eq("one bubble per part", #M.sent, parts)

--------------------------------------------------------------------------------
-- Unread accounting
--------------------------------------------------------------------------------

CM.MarkRead("Thrall-Blackrock")
eq("mark read clears the count", CM.Get("Thrall-Blackrock").unread, 0)

ns.UI.Show()
CM.Select("Thrall-Blackrock")
M.RunTimers(2)
whisper("waehrend sichtbar", "Thrall", "G-THRALL")
eq("no unread while the thread is visible", CM.Get("Thrall-Blackrock").unread, 0)

CM.Select("Thrall-Draenor")
M.RunTimers(2)
whisper("waehrend anderer aktiv", "Thrall", "G-THRALL")
eq("unread while another thread is active", CM.Get("Thrall-Blackrock").unread, 1)

ns.UI.Hide()
M.RunTimers(2)
whisper("waehrend geschlossen", "Thrall", "G-THRALL")
eq("unread while the window is closed", CM.Get("Thrall-Blackrock").unread, 2)
check("total unread accumulates", CM.TotalUnread() >= 2, CM.TotalUnread())

--------------------------------------------------------------------------------
-- Ordering
--------------------------------------------------------------------------------

-- Messages recorded from live events carry GetServerTime and must never go
-- backwards. (The Blackrock thread is skipped here: the stale-pending case above
-- deliberately back-dated one entry.)
local function isOrdered(list)
	local previous = 0
	for i = 1, #list do
		local ts = list[i][MSG_TS] or 0
		if ts < previous then return false end
		previous = ts
	end
	return true
end
check("timestamps are non-decreasing", isOrdered(other.messages))

for i = 1, 30 do
	whisper("burst " .. i, "Thrall-Draenor", "G-THRALL2")
end
check("a burst of messages stays ordered", isOrdered(other.messages))
eq("every burst message stored", #other.messages, 31)

-- Reopening keeps everything.
local before = #conv.messages
CM.Select(nil)
CM.Select("Thrall-Blackrock")
M.RunTimers(2)
eq("reopening preserves history", #CM.Get("Thrall-Blackrock").messages, before)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
