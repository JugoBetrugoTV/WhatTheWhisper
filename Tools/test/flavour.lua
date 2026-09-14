-- Does the addon actually work on this client, not merely come up on it.
--
-- Tools/test/run.lua asks whether everything loads and draws. This asks the
-- other half: whispers in and out, Battle.net in and out, history, a reload,
-- suppression, a refused send, an identity that cannot be recovered -- on every
-- client the addon claims to support.
--
-- It also checks the client itself against Tools/test/client.lua's contract,
-- because a mock that grows a function the real client does not have is a mock
-- that makes a wrong implementation look right. That has already happened once.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
local Client = dofile(ROOT .. "Tools/test/client.lua")

local FLAVOUR = (arg and arg[1]) or "retail"
local profile = Client.Setup(FLAVOUR, arg and arg[2])

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL [" .. FLAVOUR .. "] " .. label
			.. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

--------------------------------------------------------------------------------
-- The client is the client we said it was
--------------------------------------------------------------------------------

local contract = Client.CONTRACT[FLAVOUR] or {}
for _, path in ipairs(contract.present or {}) do
	check("has " .. path, Client.Lookup(path) ~= nil,
		"the contract says this client has it")
end
for _, path in ipairs(contract.absent or {}) do
	check("does not have " .. path, Client.Lookup(path) == nil,
		"the contract says this client does not have it")
end

--------------------------------------------------------------------------------

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local CM, Compat = ns.ConversationManager, ns.Compat

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local softErrors = {}
ns.SoftError = function(c, e) softErrors[#softErrors + 1] = c .. ": " .. tostring(e) end
local function noErrors(label)
	check(label, #softErrors == 0,
		table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))
	softErrors = {}
end

ns.db.profile.messages.hideFromChatFrame = true
ns.db.profile.messages.openOnWhisper = false

local nextLine = 5000
local function lineID() nextLine = nextLine + 1 return nextLine end

-- The client's argument order, built rather than counted out by hand: arg 11 is
-- the chat line, 12 the sender's GUID, 13 the Battle.net account. Miscounting
-- those is how a test passes for the wrong reason.
local function args(text, who, opts)
	opts = opts or {}
	return {
		text, who, "Common", "", who, "", 0, 0, "", 0,
		opts.line or lineID(), opts.guid or "", opts.bnet,
	}
end

--------------------------------------------------------------------------------
-- An ordinary whisper, in and out
--------------------------------------------------------------------------------

do
	local incoming = args("hallo", "Thrall", { guid = "G-THRALL" })
	M.FireEvent("CHAT_MSG_WHISPER", unpack(incoming, 1, 13))
	M.RunTimers(2)
	local id = Compat.NormalizeName("Thrall")
	local conv = CM.Get(id)
	check("an incoming whisper is stored", conv ~= nil and #conv.messages == 1,
		conv and #conv.messages or "no thread")
	check("and it is taken out of the chat frame",
		not M.ChatFrameWouldShow("CHAT_MSG_WHISPER", unpack(incoming, 1, 13)))

	M.sent = {}
	local sent = CM.SendMessage(id, "hallo zurueck")
	check("a whisper can be sent", sent == true)
	eq("and reached the client", #(M.sent or {}), 1)

	M.FireEvent("CHAT_MSG_WHISPER_INFORM",
		unpack(args("hallo zurueck", "Thrall", { guid = "G-THRALL" }), 1, 13))
	M.RunTimers(2)
	conv = CM.Get(id)
	eq("the server's echo is matched to it", #conv.messages, 2)
	eq("and marked as delivered", conv.messages[2][ns.MSG_STATUS], ns.SEND_OK)
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- Battle.net, on every client that has one
--------------------------------------------------------------------------------

-- Which is all of them: Classic Era included, which is the point of this file.
check("this client has Battle.net", Compat.hasBattleNet)
check("and can send to it", Compat.canSendBattleNet)
check("and can resolve its friends", Compat.canResolveBattleNetFriends)

do
	local FRIENDS = {
		[1] = { bnetAccountID = 7001, battleTag = "Kumpel#1111",
			accountName = "Kumpel",
			gameAccountInfo = { isOnline = true, characterName = "Main" } },
	}
	_G.C_BattleNet.GetFriendAccountInfo = function(i) return FRIENDS[i] end
	_G.C_BattleNet.GetAccountInfoByID = function(id)
		return FRIENDS[1].bnetAccountID == id and FRIENDS[1] or nil
	end
	if _G.BNGetNumFriends then _G.BNGetNumFriends = function() return 1 end end

	M.FireEvent("CHAT_MSG_BN_WHISPER",
		unpack(args("moin", "Kumpel", { bnet = 7001 }), 1, 13))
	M.RunTimers(2)
	local conv = CM.Get("BN:Kumpel#1111")
	check("an incoming Battle.net whisper is stored", conv ~= nil
		and #conv.messages == 1, conv and #conv.messages or "no thread")

	M.sentBN = {}
	local sent = CM.SendMessage("BN:Kumpel#1111", "moin auch")
	check("a Battle.net whisper can be sent", sent == true)
	eq("to the right account", M.sentBN[1] and M.sentBN[1].id, 7001)

	M.FireEvent("CHAT_MSG_BN_WHISPER_INFORM",
		unpack(args("moin auch", "Kumpel", { bnet = 7001 }), 1, 13))
	M.RunTimers(2)
	conv = CM.Get("BN:Kumpel#1111")
	eq("and its echo is matched", #conv.messages, 2)

	-- The account id goes; the BattleTag is what the conversation is filed under,
	-- and the id has to be findable again from it.
	conv.bnetAccountID = nil
	M.sentBN = {}
	check("it can still be written to without a cached id",
		CM.SendMessage(conv.id, "nach dem reload") == true)
	eq("resolved from the BattleTag", M.sentBN[1] and M.sentBN[1].id, 7001)

	-- An identity nobody can resolve: not stored, and never hidden.
	local unknown = args("wer bin ich", "Fremder", { bnet = M.Secret() })
	local before = CM.Count()
	local suppressed = not M.ChatFrameWouldShow("CHAT_MSG_BN_WHISPER",
		unpack(unknown, 1, 13))
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(unknown, 1, 13))
	M.RunTimers(2)
	eq("an unresolvable Battle.net identity opens no thread", CM.Count(), before)
	eq("and is never hidden from the chat frame", suppressed, false)

	-- A refused send is a failed bubble, not a delivered one.
	M.refuseBN = true
	local conv2 = CM.Get("BN:Kumpel#1111")
	local n = #conv2.messages
	CM.SendMessage(conv2.id, "wird abgelehnt")
	eq("a refused send still records the message", #conv2.messages, n + 1)
	eq("marked as failed", conv2.messages[#conv2.messages][ns.MSG_STATUS],
		ns.SEND_FAILED)
	M.RunTimers(4)
	eq("and the sweep never upgrades it",
		conv2.messages[#conv2.messages][ns.MSG_STATUS], ns.SEND_FAILED)
	M.refuseBN = false
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- Restricted content, where the client has it
--------------------------------------------------------------------------------

-- Retail 12.0 and later only. Everywhere else these functions do not exist, and
-- the addon has to behave as though nothing is ever withheld -- which is a
-- different thing from crashing because it asked.
if profile.project == 1 then
	eq("this client can withhold chat", Compat.InChatMessagingLockdown(), false)
	M.chatLockdown = true
	eq("and says so when it does", Compat.InChatMessagingLockdown(), true)

	local l = lineID()
	M.chatLines[l] = { text = "aus der arena", sender = "Gegner", guid = "G-G" }
	M.FireEvent("CHAT_MSG_WHISPER",
		unpack(args(M.Secret(), M.Secret(), { line = l, guid = "G-G" }), 1, 13))
	M.RunTimers(2)
	eq("a withheld whisper is held", ns.Deferred.Count(), 1)
	M.chatLockdown = false
	for _ = 1, 4 do M.RunTimers(2) M.RunFrames(2) end
	eq("and released afterwards", ns.Deferred.Count(), 0)
	check("into its thread", CM.Get(Compat.NormalizeName("Gegner")) ~= nil)
	noErrors("nothing raised")
else
	-- No secret values here, so nothing may be treated as withheld.
	eq("nothing is ever withheld on this client",
		Compat.InChatMessagingLockdown(), false)
	eq("and no value is ever secret", Compat.IsSecretValue("hallo"), false)
	eq("sending is never restricted", Compat.OutgoingChatRestricted(), false)
	eq("a chat line has no validity to ask about", Compat.IsValidChatLine(1), nil)
	eq("and nothing is ever censored", Compat.IsChatLineCensored(1), false)

	local l = lineID()
	M.FireEvent("CHAT_MSG_WHISPER",
		unpack(args("ganz normal", "Normalo", { line = l, guid = "G-N" }), 1, 13))
	M.RunTimers(2)
	check("and an ordinary whisper is simply stored",
		CM.Get(Compat.NormalizeName("Normalo")) ~= nil)
	eq("with nothing held", ns.Deferred.Count(), 0)
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- History survives a reload
--------------------------------------------------------------------------------

do
	local id = Compat.NormalizeName("Thrall")
	local before = #CM.Get(id).messages
	CM.LoadPersisted()
	M.RunFrames(2)
	local conv = CM.Get(id)
	check("history is still there after a reload", conv ~= nil
		and #conv.messages == before, conv and #conv.messages or "no thread")
	eq("and nothing is left dangling", ns.Deferred.Count(), 0)
	noErrors("a reload raises nothing")
end

--------------------------------------------------------------------------------

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("[%s] %d passed, %d failed"):format(FLAVOUR, pass, fail))
os.exit(fail == 0 and 0 or 1)
