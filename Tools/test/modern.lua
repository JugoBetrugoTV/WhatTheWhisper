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

-- Everything Blizzard has a namespaced replacement for is gone.
local REMOVED = {
	"SendChatMessage", "BNSendWhisper", "BNGetNumFriends", "BNGetFriendInfo",
}
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
	_G.C_BattleNet.SendWhisper = function() return false end
	eq("a refused send is reported as refused",
		Compat.SendBNWhisper(4711, "geht nicht"), false)

	local bn = CM.Get("BN:Freund#1234")
	local before = #bn.messages
	CM.SendMessage(bn.id, "geht auch nicht")
	local msg = bn.messages[#bn.messages]
	eq("a message was still recorded", #bn.messages, before + 1)
	eq("and it is marked as failed", msg[ns.MSG_STATUS], ns.SEND_FAILED)

	-- The sweep that upgrades pending bubbles must not touch a failed one.
	M.RunTimers(4)
	M.RunFrames(6)
	eq("and the sweep never upgrades it", msg[ns.MSG_STATUS], ns.SEND_FAILED)

	_G.C_BattleNet.SendWhisper = realSend
	eq("a send the client accepts is reported as sent",
		Compat.SendBNWhisper(4711, "geht doch"), true)

	-- An API that answers nil rather than true is answering "no opinion", which
	-- is what the old global did, and must not read as failure.
	_G.C_BattleNet.SendWhisper = function() return nil end
	eq("silence is not refusal", Compat.SendBNWhisper(4711, "still"), true)
	_G.C_BattleNet.SendWhisper = realSend
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
