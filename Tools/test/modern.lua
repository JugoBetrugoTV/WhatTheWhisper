-- Retail with nothing but the modern API.
--
-- Blizzard has been moving chat behind C_ChatInfo and Battle.net behind
-- C_BattleNet. The bare globals still exist today, which is exactly the problem:
-- an addon that reaches for them keeps working right up until the day it does
-- not, and nothing before that day tells you. So this file removes them before
-- the addon loads and expects everything to still work -- sending, receiving,
-- Battle.net identity, resolving an account after a reload.
--
-- Capability flags are read once at load, which is why this is its own file
-- rather than a section somewhere: switching a global off afterwards would not
-- change what Compat already decided.

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

--------------------------------------------------------------------------------
-- The client of the day after tomorrow
--------------------------------------------------------------------------------

-- Everything Blizzard has a namespaced replacement for is gone: every alias in
-- a Blizzard_Deprecated* file (what a client with the loadDeprecationFallbacks
-- CVar off looks like today, and every client after the next expansion), and
-- the old friends-list globals besides.
M.DropDeprecationFallbacks()
local REMOVED = { "BNGetNumFriends", "BNGetFriendInfo" }
for i = 1, #REMOVED do _G[REMOVED[i]] = nil end

-- ...and the friends list answers through C_BattleNet alone.
local FRIENDS = {
	[1] = { bnetAccountID = 4711, battleTag = "Freund#1234", accountName = "Freund",
		gameAccountInfo = { isOnline = true, characterName = "Alt" } },
	[2] = { bnetAccountID = 4712, battleTag = "Zweiter#5678", accountName = "Zweiter",
		gameAccountInfo = { isOnline = false, characterName = "" } },
}
_G.C_BattleNet.GetFriendAccountInfo = function(index) return FRIENDS[index] end
_G.C_BattleNet.GetAccountInfoByID = function(id)
	for i = 1, #FRIENDS do
		if FRIENDS[i].bnetAccountID == id then return FRIENDS[i] end
	end
	return nil
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local CM, Compat = ns.ConversationManager, ns.Compat

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local softErrors = {}
ns.SoftError = function(c, e) softErrors[#softErrors + 1] = c .. ": " .. tostring(e) end

--------------------------------------------------------------------------------
-- What the addon thinks it can do
--------------------------------------------------------------------------------

-- "Battle.net exists" used to mean "the deprecated send alias exists", which
-- would have switched the whole feature off on exactly the client that has it.
check("Battle.net is available without the old globals", Compat.hasBattleNet)
check("and can be sent to", Compat.canSendBattleNet)
check("and its friends can be resolved", Compat.canResolveBattleNetFriends)
eq("the old send global really is gone", _G.BNSendWhisper, nil)
eq("and so is the old chat one", _G.SendChatMessage, nil)
eq("and the old chat filter global", _G.ChatFrame_AddMessageEventFilter, nil)
eq("and the old chat header global", _G.ChatEdit_UpdateHeader, nil)
check("chat filters are still available", Compat.hasChatFilters)

--------------------------------------------------------------------------------
-- The chat frame, without the deprecated aliases
--------------------------------------------------------------------------------

-- "Keep whispers out of the chat frame" is the one promise the whole design
-- rests on. It went through ChatFrame_AddMessageEventFilter, which on every
-- supported client exists only in Blizzard_DeprecatedChatInfo -- so with the
-- fallbacks off, the filter was never registered and the setting did nothing.
do
	local filters = M.chatFilters["CHAT_MSG_WHISPER"]
	eq("the whisper filter is registered through ChatFrameUtil", filters and #filters, 1)
	ns.Options.Set("messages.hideFromChatFrame", true)
	eq("with hiding on, a whisper the addon keeps leaves the chat frame",
		M.ChatFrameWouldShow("CHAT_MSG_WHISPER", "hallo", "Thrall-Blackrock", "", "",
			"Thrall-Blackrock", "", 0, 0, "", 0, 77, "G-1"), false)
	ns.Options.Set("messages.hideFromChatFrame", false)
	eq("and with it off, it stays", M.ChatFrameWouldShow("CHAT_MSG_WHISPER", "hallo",
		"Thrall-Blackrock", "", "", "Thrall-Blackrock", "", 0, 0, "", 0, 78, "G-1"), true)
end

-- "/w Name" opening the thread: Blizzard updates the header through the edit
-- box's own method, so that is what has to be hooked -- on the boxes that exist
-- and on the ones a whisper tab brings later.
do
	ns.Options.Set("messages.openOnCompose", true)
	ns.UI.Hide()
	M.ComposeWhisper("Jaina")
	M.RunFrames(2)
	local jaina = Compat.NormalizeName("Jaina")
	check("composing in the main chat box opens the thread",
		CM.Get(jaina) ~= nil and ns.MainWindow.Existing() and ns.MainWindow.Existing():IsShown())
	eq("and selects it", CM.SelectedID(), jaina)

	local tab = _G.FCF_OpenTemporaryWindow("WHISPER", "Anduin")
	M.ComposeWhisper("Anduin", tab.editBox)
	M.RunFrames(2)
	eq("a whisper tab opened later is heard too", CM.SelectedID(), Compat.NormalizeName("Anduin"))

	-- It runs inside Blizzard's chat input: an error on this side must stop here.
	local show = ns.UI.Show
	ns.UI.Show = function() error("kaputt") end
	local ok = pcall(M.ComposeWhisper, "Garrosh")
	ns.UI.Show = show
	check("an error while opening the thread never reaches the chat box", ok)
	check("and is reported as the addon's own", #softErrors == 1 and softErrors[1]:find("kaputt") ~= nil,
		table.concat(softErrors, "; "))
	softErrors = {}
	ns.Options.Set("messages.openOnCompose", false)
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

do
	M.sent, M.sentBN = {}, {}
	CM.GetOrCreate("Thrall-Blackrock")
	local sent = CM.SendMessage("Thrall-Blackrock", "hallo")
	check("an ordinary whisper still sends", sent == true)
	eq("through the namespaced API", M.sent[1] and M.sent[1].via, "C_ChatInfo")

	local bn = CM.GetOrCreate("BN:Freund#1234", { name = "Freund" })
	bn.isBN = true
	bn.battleTag = "Freund#1234"
	bn.bnetAccountID = nil
	local sentBN = CM.SendMessage(bn.id, "hallo auch")
	check("a Battle.net whisper still sends", sentBN == true)
	eq("through the namespaced API too", M.sentBN[1] and M.sentBN[1].via, "C_BattleNet")
	eq("to the account resolved from the stored BattleTag",
		M.sentBN[1] and M.sentBN[1].id, 4711)
end

--------------------------------------------------------------------------------
-- A send the client refused
--------------------------------------------------------------------------------

-- C_BattleNet.SendWhisper answers whether the message actually went. A call that
-- returned is not a message that arrived, and reporting one as the other means a
-- bubble that says delivered about something nobody received.
do
	local realSend = _G.C_BattleNet.SendWhisper

	-- Accepted: true, and a bubble waiting for the server's echo.
	local bn = CM.Get("BN:Freund#1234")
	eq("an accepted send is reported as sent",
		Compat.SendBNWhisper(4711, "geht doch"), true)
	local countBefore = #bn.messages
	CM.SendMessage(bn.id, "und im fenster")
	local okMsg = bn.messages[#bn.messages]
	eq("with a message recorded", #bn.messages, countBefore + 1)
	eq("as pending, waiting for the server", okMsg[ns.MSG_STATUS], ns.SEND_PENDING)

	-- Refused: false, a failed bubble, and nothing that could later be upgraded.
	M.refuseBN = true
	eq("a refused send is reported as refused",
		Compat.SendBNWhisper(4711, "geht nicht"), false)

	local before = #bn.messages
	CM.SendMessage(bn.id, "geht auch nicht")
	local msg = bn.messages[#bn.messages]
	eq("a message was still recorded", #bn.messages, before + 1)
	eq("and it is marked as failed", msg[ns.MSG_STATUS], ns.SEND_FAILED)

	-- The sweep that upgrades pending bubbles must not touch a failed one.
	M.RunTimers(4)
	M.RunFrames(6)
	eq("and the sweep never upgrades it", msg[ns.MSG_STATUS], ns.SEND_FAILED)
	M.refuseBN = false

	-- nil is not modesty. C_BattleNet.SendWhisper is documented to return a
	-- boolean; not answering is not answering, and reporting it as delivered
	-- puts a tick beside a message nobody received.
	_G.C_BattleNet.SendWhisper = function() return nil end
	eq("an unanswered modern send is a failed send",
		Compat.SendBNWhisper(4711, "still"), false)

	-- ...and one that throws is a failure too, not an error the player sees.
	_G.C_BattleNet.SendWhisper = function() error("kaputt") end
	local ok, result = pcall(Compat.SendBNWhisper, 4711, "knall")
	check("a send that throws does not escape as an error", ok)
	eq("and is reported as failed", result, false)
	_G.C_BattleNet.SendWhisper = realSend

	-- The legacy global has the other contract: it answers nothing, so a call
	-- that came back is the best signal there is. Merging the two would take the
	-- weaker promise for both.
	local modern = _G.C_BattleNet.SendWhisper
	_G.C_BattleNet.SendWhisper = nil
	_G.BNSendWhisper = function(id, text)
		M.sentBN = M.sentBN or {}
		M.sentBN[#M.sentBN + 1] = { id = id, text = text, via = "global" }
	end
	eq("the legacy global answering nothing still counts as sent",
		Compat.SendBNWhisper(4711, "alt"), true)
	_G.BNSendWhisper = nil
	_G.C_BattleNet.SendWhisper = modern
end

--------------------------------------------------------------------------------
-- Receiving, and finding out who it was from
--------------------------------------------------------------------------------

do
	M.FireEvent("CHAT_MSG_BN_WHISPER", "von drüben", "Freund", "Common", "",
		"Freund", "", 0, 0, "", 9001, "", 4711)
	M.RunTimers(2)
	local conv = CM.Get("BN:Freund#1234")
	check("an incoming Battle.net whisper lands", conv ~= nil
		and conv.messages[#conv.messages][3] == "von drüben")

	-- ...and with the account id withheld, recovered from the name.
	M.FireEvent("CHAT_MSG_BN_WHISPER", "und nochmal", "Zweiter", "Common", "",
		"Zweiter", "", 0, 0, "", 9002, "", M.Secret())
	M.RunTimers(2)
	local second = CM.Get("BN:Zweiter#5678")
	check("and one with a withheld id is recovered from the name",
		second ~= nil and second.messages[#second.messages][3] == "und nochmal",
		second and #second.messages or "no thread")
end

--------------------------------------------------------------------------------
-- Across a reload
--------------------------------------------------------------------------------

-- Account ids are only stable within a session; the BattleTag is the durable
-- key. After a reload the id has to be found again from the tag alone.
do
	local conv = CM.Get("BN:Freund#1234")
	check("the conversation is there", conv ~= nil)
	if conv then
		-- What a reload leaves behind: the durable BattleTag, and no id.
		conv.bnetAccountID = nil
		M.sentBN = {}
		local sent = CM.SendMessage(conv.id, "nach dem reload")
		check("and can still be written to", sent == true)
		eq("to the right account, found from the BattleTag alone",
			M.sentBN[1] and M.sentBN[1].id, 4711)
		eq("which is also how the id comes back",
			Compat.ResolveBNAccountID("Freund#1234"), 4711)
		eq("and a tag nobody has resolves to nothing",
			Compat.ResolveBNAccountID("Niemand#0000"), nil)
	end
end

--------------------------------------------------------------------------------

check("no soft errors on a modern-only client", #softErrors == 0,
	table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))
eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
