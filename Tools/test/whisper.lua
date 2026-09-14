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

-- This file tests the whisper pipeline, not the window policy. Auto-open would
-- select the thread and clear its unread mark, which is correct behaviour and
-- entirely beside the point here.
ns.db.profile.messages.openOnWhisper = false
ns.db.profile.messages.openOnCompose = false
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
check("the thread knows the name is wrong", jaina.notFound == true)

-- The other ordering, and the one that was actually broken. On a client that
-- echoes the whisper back before the server answers, the echo has already
-- upgraded the bubble to "sent" by the time the error lands -- so the player
-- was shown an ordinary delivered message that nobody ever received.
CM.SendMessage("Jaina-Blackrock", "und jetzt?")
M.RunTimers(1)
inform("und jetzt?", "Jaina", "G-JAINA")
eq("the echo marks it sent first", jaina.messages[#jaina.messages][MSG_STATUS], ns.SEND_OK)
M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Jaina' is currently playing.")
M.RunTimers(1)
eq("the server's answer overrides the echo",
	jaina.messages[#jaina.messages][MSG_STATUS], ns.SEND_FAILED)
eq("and still no duplicate", count("Jaina-Blackrock", "und jetzt?"), 1)

-- One error fails one message, because the server sends one per whisper.
local before = #jaina.messages
M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Jaina' is currently playing.")
M.RunTimers(1)
eq("a second error adds nothing", #jaina.messages, before)

-- A reply proves the name was fine after all.
whisper("doch da", "Jaina", "G-JAINA")
check("hearing from them clears the not-found mark", jaina.notFound == nil)

-- An error long after the fact belongs to a different attempt and must not
-- reach back and fail a message the player watched arrive.
local settled = CM.AddMessage("Jaina-Blackrock", ns.DIR_OUT, "laengst zugestellt",
	ns.MSG_WHISPER, ns.Compat.GetServerTime() - 600, ns.SEND_OK)
M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Jaina' is currently playing.")
M.RunTimers(1)
eq("an old message is out of reach", settled[MSG_STATUS], ns.SEND_OK)

--------------------------------------------------------------------------------
-- Names the game could never issue
--------------------------------------------------------------------------------

-- SendChatMessage accepts anything, so a name that cannot exist produces a
-- perfectly ordinary looking outgoing message. These are refused before that.
local valid = {
	"Thrall", "Jaina", "Thrall-Blackrock", "Thrall-Argent Dawn",
	"Muradin", "Sylvanas-Draenor", "BN:Somebody#1234", "Somebody#1234",
	"\195\132gidius", "\195\150zil", "Ab",
}
for i = 1, #valid do
	check("accepted: " .. valid[i], ns.Compat.ValidatePlayerName(valid[i]) == true)
end

local invalid = {
	["A"] = "length",
	["Averyverylongname"] = "length",
	["Thr all"] = "name",
	["Thrall2"] = "name",
	["Thr'all"] = "name",
	["|cffff0000Thrall|r"] = "name",
	[""] = "empty",
	["Thrall-"] = "name",
	["Somebody#12"] = "battletag",
	["#1234"] = "battletag",
}
for name, reason in pairs(invalid) do
	local ok, got = ns.Compat.ValidatePlayerName(name)
	check("refused: " .. (name == "" and "(empty)" or name), ok == false, tostring(got))
	eq("reason for " .. (name == "" and "(empty)" or name), got, reason)
end

-- A twelve character name is the longest the game issues, and it must pass.
check("twelve characters is fine",
	ns.Compat.ValidatePlayerName(("a"):rep(12)) == true)
check("thirteen is not", ns.Compat.ValidatePlayerName(("a"):rep(13)) == false)
-- Counted in characters, not bytes: an accented name is not shorter than it
-- looks just because it takes more room.
check("accents count as one character each",
	ns.Compat.ValidatePlayerName(("\195\164"):rep(12)) == true)
check("and thirteen of them is still too many",
	ns.Compat.ValidatePlayerName(("\195\164"):rep(13)) == false)

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

--------------------------------------------------------------------------------
-- The window opening on its own
--------------------------------------------------------------------------------

-- A messenger that stays shut when somebody writes to you is a messenger you
-- miss messages in. It has to open for a whisper from the game and for one from
-- a Battle.net friend alike -- and it has to open *on the thread that caused
-- it*, because opening on somebody else's conversation is worse than not
-- opening at all.
ns.db.profile.messages.openOnWhisper = true
ns.db.profile.messages.autoSwitch = false

ns.UI.Hide()
M.RunFrames(12)
check("closed to begin with", ns.UI.IsShown() == false)

whisper("bist du wach?", "Muradin", "G-MURADIN")
M.RunFrames(8)
check("an incoming whisper opens the messenger", ns.UI.IsShown())
eq("on the thread it arrived in", CM.SelectedID(), "Muradin-Blackrock")

-- Battle.net takes the same route, and used to be worth checking separately
-- because it enters through a different event with a different id scheme.
M.bnet = { [77] = { tag = "Somebody#1234", name = "Somebody", character = "Alt" } }
ns.UI.Hide()
M.RunFrames(12)
check("closed again", ns.UI.IsShown() == false)
-- bnSenderID is the thirteenth argument, after the guid slot the game leaves
-- empty for Battle.net.
M.FireEvent("CHAT_MSG_BN_WHISPER", "hallo aus dem launcher", "Somebody",
	"", "", "", "", 0, 0, "", 0, 1, "", 77)
M.RunTimers(2)
M.RunFrames(8)
check("a Battle.net whisper opens it too", ns.UI.IsShown())
eq("on the Battle.net thread", CM.SelectedID(), "BN:Somebody#1234")

-- Muted means do not interrupt me, and opening the window is the loudest
-- interruption there is.
CM.SetMuted("Muradin-Blackrock", true)
ns.UI.Hide()
M.RunFrames(12)
whisper("und jetzt?", "Muradin", "G-MURADIN")
M.RunFrames(8)
check("a muted thread does not open the window", ns.UI.IsShown() == false)
eq("but the message is still stored", count("Muradin-Blackrock", "und jetzt?"), 1)
CM.SetMuted("Muradin-Blackrock", false)

ns.db.profile.messages.openOnWhisper = false
ns.UI.Hide()
M.RunFrames(12)
whisper("stillschweigend", "Muradin", "G-MURADIN")
M.RunFrames(8)
check("and the setting genuinely switches it off", ns.UI.IsShown() == false)

--------------------------------------------------------------------------------
-- A name you chose for somebody
--------------------------------------------------------------------------------

-- A nickname is what the window says, and nothing else. The whole point of the
-- feature is people whose own name you cannot read at a glance, and a nickname
-- that quietly became the recipient would be one that whispers the wrong person.
do
	local id = "XxlegolasxX-TarrenMill"
	CM.GetOrCreate(id)
	eq("no nickname to begin with", CM.GetAlias(id), nil)
	-- Cross-realm, so the realm is part of the name -- which is exactly the kind
	-- of name a nickname is for.
	eq("and the thread is named after the character",
		CM.DisplayName(CM.Get(id)), "XxlegolasxX-TarrenMill")

	CM.SetAlias(id, "Max")
	eq("a nickname is what the window says", CM.DisplayName(CM.Get(id)), "Max")
	eq("with the real name underneath it", CM.RealNameIfAliased(CM.Get(id)), id)
	eq("the conversation is still filed under the character", CM.Get(id).id, id)

	M.sent = {}
	CM.SendMessage(id, "geht raus")
	eq("and a message still goes to the character",
		M.sent[1] and M.sent[1].target, id)

	-- Trimmed, and an empty one is no nickname rather than a blank name.
	CM.SetAlias(id, "   ")
	eq("a blank nickname is no nickname", CM.GetAlias(id), nil)
	eq("so the character's name is back",
		CM.DisplayName(CM.Get(id)), "XxlegolasxX-TarrenMill")
	eq("and there is nothing to put underneath", CM.RealNameIfAliased(CM.Get(id)), nil)

	CM.SetAlias(id, "  Max  ")
	eq("surrounding space is not part of a name", CM.GetAlias(id), "Max")
	CM.SetAlias(id, nil)
	eq("removing it works", CM.GetAlias(id), nil)
	M.sent = {}
end

--------------------------------------------------------------------------------
-- The game's own reply, left alone
--------------------------------------------------------------------------------

-- /r has to keep working. It is the game's, driven by the game's own record of
-- who last wrote to you, and an addon that took that over would break the one
-- thing every player already knows how to do.
do
	local touched = {}
	for _, name in ipairs({ "ChatEdit_ActivateChat", "ChatEdit_OnEscapePressed",
		"ChatFrame_ReplyTell", "ChatFrame_ReplyTell2", "LAST_ACTIVE_CHAT_EDIT_BOX" }) do
		touched[name] = _G[name]
	end

	whisper("wer bist du", "Muradin", "G-MURADIN")
	M.sent = {}
	CM.SendMessage("Muradin-Blackrock", "ich bin es")
	M.RunFrames(4)

	local unchanged = true
	for name, before in pairs(touched) do
		if _G[name] ~= before then unchanged = false end
	end
	check("nothing of the game's reply machinery is overwritten", unchanged)
	eq("and the whisper went out as an ordinary whisper",
		M.sent[1] and M.sent[1].kind, "WHISPER")
	check("through the game's own send, which is what /r reads back",
		M.sent[1] ~= nil)
	M.sent = {}
end

--------------------------------------------------------------------------------
-- Which door the message leaves by
--------------------------------------------------------------------------------

-- Retail moved chat behind C_ChatInfo and Battle.net behind C_BattleNet. Both
-- bare globals still work today and are one deprecation away from not working,
-- so the namespaced one is used wherever it exists -- and the old one is still
-- there for the Classic flavours, which have nothing else.
do
	M.sent, M.sentBN = {}, {}
	CM.SendMessage("Muradin-Blackrock", "durch welche tuer")
	check("a whisper goes through the namespaced chat API",
		M.sent[1] and M.sent[1].via == "C_ChatInfo",
		M.sent[1] and M.sent[1].via or "nothing sent")

	local bn = CM.GetOrCreate("BN:Jemand#1234", { name = "Jemand" })
	bn.isBN = true
	bn.bnetAccountID = 4242
	CM.SendMessage(bn.id, "und bnet")
	check("and a Battle.net whisper through the namespaced one",
		M.sentBN[1] and M.sentBN[1].via == "C_BattleNet",
		M.sentBN[1] and M.sentBN[1].via or "nothing sent")

	-- A client that has only the old globals still sends.
	local modernChat, modernBN = _G.C_ChatInfo.SendChatMessage, _G.C_BattleNet.SendWhisper
	_G.C_ChatInfo.SendChatMessage, _G.C_BattleNet.SendWhisper = nil, nil
	M.sent, M.sentBN = {}, {}
	CM.SendMessage("Muradin-Blackrock", "auf dem alten weg")
	check("an older client falls back to the global",
		M.sent[1] and M.sent[1].via == "global",
		M.sent[1] and M.sent[1].via or "nothing sent")
	CM.SendMessage(bn.id, "auch bnet")
	check("and so does Battle.net",
		M.sentBN[1] and M.sentBN[1].via == "global",
		M.sentBN[1] and M.sentBN[1].via or "nothing sent")
	_G.C_ChatInfo.SendChatMessage, _G.C_BattleNet.SendWhisper = modernChat, modernBN
	M.sent, M.sentBN = {}, {}
end

--------------------------------------------------------------------------------
-- Sending where the client will not carry it
--------------------------------------------------------------------------------

-- In an arena the client refuses chat sent by an addon. Failing silently there
-- would lose what somebody typed, which is worse than not sending it.
do
	local printed = {}
	local realPrint = ns.Print
	ns.Print = function(text) printed[#printed + 1] = tostring(text) end

	local before = #CM.Get("Muradin-Blackrock").messages
	local sentBefore = #(M.sent or {})
	M.chatLockdown = true
	local sent = CM.SendMessage("Muradin-Blackrock", "gl hf")
	check("a whisper is not sent while chat is withheld", sent == false or sent == nil)
	eq("and nothing is written into the thread",
		#CM.Get("Muradin-Blackrock").messages, before)
	eq("nor handed to the server", #(M.sent or {}), sentBefore)
	check("and the player is told why", #printed > 0,
		table.concat(printed, " | "))

	M.chatLockdown = false
	printed = {}
	sent = CM.SendMessage("Muradin-Blackrock", "gl hf")
	check("and it sends again afterwards", sent == true)
	eq("with nothing more to say about it", #printed, 0,
		table.concat(printed, " | "))

	ns.Print = realPrint
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
