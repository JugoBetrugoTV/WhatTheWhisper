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
Client.Setup(FLAVOUR, arg and arg[2])

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
	-- One fixture, read through whichever door this client has: the modern
	-- namespace on the shipping clients, BNGetFriendInfo on the artificial
	-- fallback. Setting it up per client shape is how the legacy branch would
	-- stop being tested without anyone noticing.
	M.bnFriends = {
		{ id = 7001, tag = "Kumpel#1111", name = "Kumpel", character = "Main" },
	}
	M.bnet = { [7001] = { tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }

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

	-- A refused send is a failed bubble, not a delivered one -- on a client that
	-- can say it refused. C_BattleNet.SendWhisper returns a boolean and all four
	-- shipping clients have it; the old BNSendWhisper global returns nothing at
	-- all, so on the fallback there is no refusal to observe. That is a property
	-- of the client rather than of this addon, and it is asserted as one instead
	-- of being quietly skipped.
	local canRefuse = type(_G.C_BattleNet) == "table"
		and type(_G.C_BattleNet.SendWhisper) == "function"
	eq("this client's Battle.net send reports its own refusals", canRefuse,
		Client.HasChatRestrictionAPI(FLAVOUR))

	M.refuseBN = true
	local conv2 = CM.Get("BN:Kumpel#1111")
	local n = #conv2.messages
	CM.SendMessage(conv2.id, "wird abgelehnt")
	eq("a refused send still records the message", #conv2.messages, n + 1)
	eq("marked as failed", conv2.messages[#conv2.messages][ns.MSG_STATUS],
		canRefuse and ns.SEND_FAILED or ns.SEND_PENDING)
	M.RunTimers(4)
	eq("and the sweep never upgrades it",
		conv2.messages[#conv2.messages][ns.MSG_STATUS],
		canRefuse and ns.SEND_FAILED or ns.SEND_PENDING)
	M.refuseBN = false
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- Restricted content
--------------------------------------------------------------------------------

-- Not a Retail question. C_ChatInfo's restriction and chat-line functions,
-- C_Secrets.HasSecretRestrictions and the issecretvalue globals are all present
-- on 12.1.0, 5.5.4, 2.5.6 and 1.15.9 alike, so every shipping client runs the
-- whole block. The only client that skips it is the artificial fallback, which
-- has those APIs taken away on purpose -- and it is made to prove that taking
-- them away leaves the addon working rather than guessing.
if Client.HasChatRestrictionAPI(FLAVOUR) then
	-- Three separate questions, and the addon is wrong the moment it collapses
	-- them into one. The API being there is not the restriction being on; the
	-- restriction being on is not chat being withheld; chat being withheld is
	-- not an outgoing message being refused.
	eq("this client answers the restriction question at all",
		type(Compat.HasSecretRestrictions()), "boolean")
	eq("and says no while nothing is restricted", Compat.HasSecretRestrictions(), false)
	eq("chat is not withheld", Compat.InChatMessagingLockdown(), false)
	eq("and sending is not refused", Compat.OutgoingChatRestricted(), false)

	-- Restrictions on without chat being withheld: the client can be in the
	-- restricted state for something other than this addon's business, and an
	-- addon that holds whispers on that signal holds them for nothing.
	M.secretRestrictions = true
	eq("restrictions can be on with chat still flowing",
		Compat.HasSecretRestrictions(), true)
	eq("and chat is still not withheld", Compat.InChatMessagingLockdown(), false)
	M.secretRestrictions = nil

	-- An ordinary whisper, with the APIs present and nothing restricted. The
	-- case that has to keep working, and the one a nervous implementation
	-- breaks first.
	do
		local l = lineID()
		M.chatLines[l] = { text = "ganz normal", sender = "Normalo", guid = "G-N" }
		M.FireEvent("CHAT_MSG_WHISPER",
			unpack(args("ganz normal", "Normalo", { line = l, guid = "G-N" }), 1, 13))
		M.RunTimers(2)
		local conv = CM.Get(Compat.NormalizeName("Normalo"))
		check("an ordinary whisper is simply stored", conv ~= nil
			and conv.messages[#conv.messages][ns.MSG_TEXT] == "ganz normal",
			conv and conv.messages[#conv.messages][ns.MSG_TEXT] or "no thread")
		eq("with nothing held", ns.Deferred.Count(), 0)
	end

	-- Lockdown, both ways round.
	M.chatLockdown = true
	eq("the client says so when chat is withheld",
		Compat.InChatMessagingLockdown(), true)
	eq("and reports itself restricted", Compat.HasSecretRestrictions(), true)

	-- What a chat line is worth while chat is withheld: the id is never secret,
	-- but the client will not give up the text yet. Asking is allowed; the
	-- answer is nothing, and nothing is not an error.
	local held = lineID()
	M.chatLines[held] = { text = "aus der arena", sender = "Gegner", guid = "G-G" }
	eq("a held line is still a line the client knows",
		Compat.IsValidChatLine(held), true)
	eq("a line that has aged out is not", Compat.IsValidChatLine(999999), false)
	eq("and its text is withheld for now", (Compat.GetChatLine(held)), nil)

	M.FireEvent("CHAT_MSG_WHISPER",
		unpack(args(M.Secret(), M.Secret(), { line = held, guid = "G-G" }), 1, 13))
	M.RunTimers(2)
	eq("a withheld whisper is held, not dropped", ns.Deferred.Count(), 1)
	eq("and nothing was invented for it",
		CM.Get(Compat.NormalizeName("Gegner")), nil)

	-- Outgoing is its own switch. Being unable to read an opponent's whisper
	-- does not mean the player cannot answer it, so the addon must ask the
	-- specific question rather than infer from the general one.
	M.outgoingRestricted = false
	eq("sending can still be allowed while chat is withheld",
		Compat.OutgoingChatRestricted(), false)
	M.sent = {}
	check("so a whisper still goes out",
		CM.SendMessage(Compat.NormalizeName("Thrall"), "trotzdem") == true)
	eq("and reached the client", #(M.sent or {}), 1)

	M.outgoingRestricted = true
	eq("and refused when the client says so", Compat.OutgoingChatRestricted(), true)
	do
		-- What the player typed stays in the box. Not a failed bubble: a failed
		-- bubble is for a message the client took and the server rejected, and
		-- this one was never taken -- retyping it is the one outcome worse than
		-- being told it cannot go.
		local id = Compat.NormalizeName("Thrall")
		local conv = CM.Get(id)
		local n = #conv.messages
		M.sent = {}
		eq("a restricted send reports failure", CM.SendMessage(id, "geht nicht"), false)
		eq("and nothing reached the client", #(M.sent or {}), 0)
		eq("and no bubble is invented for it", #conv.messages, n)

		-- Through the composer, which is where the player actually meets this.
		CM.Select(id)
		ns.UI.Show()
		M.RunFrames(2)
		local composer = ns.MainWindow.Get().view.composer
		composer.input:SetText("geht nicht")
		composer:Submit()
		M.RunFrames(2)
		eq("the text stays in the box", composer.input:GetText(), "geht nicht")
		eq("and still nothing reached the client", #(M.sent or {}), 0)
		composer.input:SetText("")
	end
	M.outgoingRestricted = nil

	-- Recovery. The client stops withholding, the line becomes readable, and
	-- the held message is reconstructed from it -- with the timestamp of when
	-- it was sent, not of when the addon caught up.
	M.chatLockdown = false
	eq("restrictions lift with the lockdown", Compat.HasSecretRestrictions(), false)
	eq("and the line is readable now", (Compat.GetChatLine(held)), "aus der arena")
	for _ = 1, 4 do M.RunTimers(2) M.RunFrames(2) end
	eq("the held whisper is released", ns.Deferred.Count(), 0)
	do
		local conv = CM.Get(Compat.NormalizeName("Gegner"))
		check("into its own thread", conv ~= nil, "no thread for the released message")
		eq("with the text the client gave back",
			conv and conv.messages[1][ns.MSG_TEXT], "aus der arena")
		eq("exactly once", conv and #conv.messages, 1)
	end
	noErrors("nothing raised")
else
	-- The artificial fallback: none of those APIs. The addon must behave as
	-- though nothing is ever withheld, which is a different thing from crashing
	-- because it asked, and different again from claiming to know the answer.
	eq("this client cannot answer the restriction question",
		Compat.HasSecretRestrictions(), nil)
	eq("nothing is ever withheld", Compat.InChatMessagingLockdown(), false)
	eq("no value is ever secret", Compat.IsSecretValue("hallo"), false)
	eq("sending is never restricted", Compat.OutgoingChatRestricted(), false)
	eq("a chat line has no validity to ask about", Compat.IsValidChatLine(1), nil)
	eq("nothing is ever censored", Compat.IsChatLineCensored(1), false)
	eq("and there is no line text to reconstruct from", (Compat.GetChatLine(1)), nil)

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
