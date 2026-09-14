-- Restricted content, end to end.
--
-- In an arena or a rated battleground the client hands addons secret values
-- instead of chat. A messenger that stops there is not a messenger: the whisper
-- has to reach its conversation, in order, under the right name, without ever
-- being both swallowed from the chat frame and missing from the window.
--
-- Everything here is the failure mode, not the happy path. One chat line that
-- never comes back must not take the queue with it. A Battle.net account id that
-- is withheld must not become a conversation filed under somebody else. A
-- message the addon could not store must still be on the player's screen.

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

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local CM = ns.ConversationManager

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local softErrors = {}
ns.SoftError = function(context, err)
	softErrors[#softErrors + 1] = tostring(context) .. ": " .. tostring(err)
end
local function noErrors(label)
	check(label, #softErrors == 0,
		table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))
	softErrors = {}
end

ns.db.profile.messages.hideFromChatFrame = true
ns.db.profile.messages.openOnWhisper = false

-- tostring on a secret value is a read, so a failure message written the usual
-- way would blow up on its way to being printed.
local function describe(value)
	local ok, text = pcall(tostring, value)
	return ok and text or "<withheld>"
end

--------------------------------------------------------------------------------
-- Building events
--------------------------------------------------------------------------------

local nextLine = 1000
local function lineID()
	nextLine = nextLine + 1
	return nextLine
end

-- A CHAT_MSG_WHISPER as the client sends it. `opts.secret` names the arguments
-- this client is withholding; `opts.line` is what it will say about that line
-- later, or nil for a line that never comes back.
local function whisperArgs(text, sender, guid, line, secret)
	secret = secret or {}
	local args = {
		secret.text and M.Secret() or text,
		secret.sender and M.Secret() or sender,
		"Common", "", sender, "", 0, 0, "", 0, line,
		secret.guid and M.Secret() or guid,
	}
	return args
end

local function fire(event, args)
	M.FireEvent(event, unpack(args, 1, 13))
	M.RunTimers(2)
	M.RunFrames(2)
end

local function threadOf(name)
	return CM.Get(ns.Compat.NormalizeName(name))
end

local function texts(conv)
	local out = {}
	for i = 1, #(conv and conv.messages or {}) do
		out[#out + 1] = conv.messages[i][3]
	end
	return out
end

local function enterArena()
	M.chatLockdown = true
end

local function leaveArena(seconds)
	M.chatLockdown = false
	M.now = M.now + (seconds or 0)
	for _ = 1, 6 do
		M.RunTimers(2)
		M.RunFrames(2)
	end
end

local function reset()
	ns.Deferred.Clear()
	ns.Debug.ClearDegraded()
	M.chatLockdown = false
	M.chatLines = {}
	M.refuseUncensor = nil
	M.validLines = {}
	M.invalidLines = {}
	M.censoredLines = {}
	softErrors = {}
end

M.bnet = M.bnet or {}
M.bnet[4711] = { tag = "Freund#1234", name = "Freund", character = "Alt" }
_G.BNGetNumFriends = function() return 1 end
_G.C_BattleNet.GetFriendAccountInfo = function(index)
	if index ~= 1 then return nil end
	return { bnetAccountID = 4711, battleTag = "Freund#1234", accountName = "Freund",
		gameAccountInfo = { isOnline = true, characterName = "Alt" } }
end

local function bnArgs(text, accountName, senderID, line, secret)
	secret = secret or {}
	return {
		secret.text and M.Secret() or text,
		secret.sender and M.Secret() or accountName,
		"Common", "", accountName, "", 0, 0, "", 0, line, "",
		secret.id and M.Secret() or senderID,
	}
end

--------------------------------------------------------------------------------
-- The matrix: where a whisper can arrive, and what has to happen
--------------------------------------------------------------------------------

-- Every one of these is the same promise in a different place: the message ends
-- up in its thread, and nothing is ever both unstored and suppressed.
local PLACES = {
	{ "the open world",        lockdown = false },
	{ "combat outside PvP",    lockdown = false, combat = true },
	{ "a battleground",        lockdown = false, instance = "pvp" },
	{ "a rated battleground",  lockdown = true,  instance = "pvp" },
	{ "arena preparation",     lockdown = true,  instance = "arena" },
	{ "an arena",              lockdown = true,  instance = "arena" },
}

for i = 1, #PLACES do
	local place = PLACES[i]
	local label, restricted = place[1], place.lockdown
	reset()
	M.inCombat = place.combat or false
	M.chatLockdown = restricted

	local sender = "Gegner" .. i
	local line = lineID()
	M.chatLines[line] = { text = "in " .. label, sender = sender, guid = "G-" .. i }

	local args = whisperArgs("in " .. label, sender, "G-" .. i, line,
		restricted and { text = true, sender = true } or nil)

	-- The invariant, checked before anything is stored: a message the addon will
	-- not have must still be on the player's screen.
	local suppressed = not M.ChatFrameWouldShow("CHAT_MSG_WHISPER", unpack(args, 1, 13))
	fire("CHAT_MSG_WHISPER", args)
	local stored = threadOf(sender) ~= nil
	check("in " .. label .. ": never both unstored and hidden",
		stored or not suppressed,
		("stored=%s suppressed=%s"):format(tostring(stored), tostring(suppressed)))

	if restricted then
		check("in " .. label .. ": it is held", ns.Deferred.Count() == 1,
			ns.Deferred.Count())
		leaveArena()
	end
	local conv = threadOf(sender)
	check("in " .. label .. ": the message arrives", conv ~= nil
		and #conv.messages == 1 and conv.messages[1][3] == "in " .. label,
		conv and table.concat(texts(conv), " | ") or "no thread")

	-- ...and outgoing, which the server echoes back as an INFORM.
	if not restricted then
		local outLine = lineID()
		M.chatLines[outLine] = { text = "reply", sender = sender }
		fire("CHAT_MSG_WHISPER_INFORM",
			whisperArgs("reply", sender, "G-" .. i, outLine))
		conv = threadOf(sender)
		eq("in " .. label .. ": the echo lands too", #conv.messages, 2)
	else
		local outLine = lineID()
		M.chatLines[outLine] = { text = "reply", sender = sender }
		enterArena()
		fire("CHAT_MSG_WHISPER_INFORM",
			whisperArgs("reply", sender, "G-" .. i, outLine,
				{ text = true, sender = true }))
		eq("in " .. label .. ": the echo is held", ns.Deferred.Count(), 1)
		leaveArena()
		conv = threadOf(sender)
		eq("in " .. label .. ": and lands afterwards", #conv.messages, 2)
	end
	noErrors("in " .. label .. ": nothing raised")
end
M.inCombat = false

--------------------------------------------------------------------------------
-- One line that never comes back must not take the queue with it
--------------------------------------------------------------------------------

-- The client keeps chat lines in a ring buffer. A line that scrolled out of it
-- is gone for good, and a queue that waits at the head for one of those loses
-- every message behind it -- which, in a ten-minute arena, is all of them.
do
	reset()
	local a, b, c = lineID(), lineID(), lineID()
	-- A is sabotaged: the client will never answer for it.
	M.chatLines[b] = { text = "zweite", sender = "Bravo", guid = "G-B" }
	M.chatLines[c] = { text = "dritte", sender = "Charlie", guid = "G-C" }

	-- A is valid as far as the client is concerned, it simply never produces
	-- text. That is the case the timeout exists for.
	M.validLines[a] = true

	enterArena()
	local withheld = { text = true, sender = true }
	fire("CHAT_MSG_WHISPER", whisperArgs("erste", "Alpha", "G-A", a, withheld))
	fire("CHAT_MSG_WHISPER", whisperArgs("zweite", "Bravo", "G-B", b, withheld))
	fire("CHAT_MSG_WHISPER", whisperArgs("dritte", "Charlie", "G-C", c, withheld))
	eq("three held", ns.Deferred.Count(), 3)

	-- Out of the arena, but not yet past the head's patience: nothing is given
	-- up on, and nothing behind it jumps the queue either.
	leaveArena()
	eq("the head is not abandoned on the first try", ns.Deferred.Count(), 3)
	eq("and nothing behind it jumps the queue", threadOf("Bravo"), nil)

	-- Long enough.
	leaveArena(60)
	eq("the queue drains", ns.Deferred.Count(), 0)
	eq("the line that never came back was given up on", ns.Deferred.DroppedCount(), 1)
	eq("and it opened no thread", threadOf("Alpha"), nil)
	check("but the one behind it arrived", threadOf("Bravo") ~= nil)
	check("and the one behind that", threadOf("Charlie") ~= nil)
	noErrors("no errors while giving up")
end

-- ...and a line that is merely slow is not treated as lost.
do
	reset()
	local slow, fast = lineID(), lineID()
	M.chatLines[fast] = { text = "schnell", sender = "Fast", guid = "G-F" }

	-- Valid, just not ready: the client knows the line, it has simply not
	-- handed over the text yet.
	M.validLines[slow] = true

	enterArena()
	local withheld = { text = true, sender = true }
	fire("CHAT_MSG_WHISPER", whisperArgs("langsam", "Slow", "G-S", slow, withheld))
	fire("CHAT_MSG_WHISPER", whisperArgs("schnell", "Fast", "G-F", fast, withheld))

	leaveArena(5)
	eq("a slow line is still waiting", ns.Deferred.Count(), 2)
	eq("and is not dropped early", ns.Deferred.DroppedCount(), 0)
	eq("nor is the one behind it let past", threadOf("Fast"), nil)

	-- The client catches up.
	M.chatLines[slow] = { text = "langsam", sender = "Slow", guid = "G-S" }
	leaveArena(5)
	eq("the slow line arrives", ns.Deferred.Count(), 0)
	eq("nothing was given up on", ns.Deferred.DroppedCount(), 0)
	local slowConv, fastConv = threadOf("Slow"), threadOf("Fast")
	check("both threads exist", slowConv ~= nil and fastConv ~= nil)
	eq("and in the order they were sent", slowConv.messages[1][1] <= fastConv.messages[1][1], true)
	noErrors("no errors while catching up")
end

-- ...and when the client says outright that a line is gone, there is nothing to
-- wait for. Waiting anyway would hold up every message behind it for half a
-- minute to learn what the client already said.
do
	reset()
	local gone, b, c = lineID(), lineID(), lineID()
	M.invalidLines[gone] = true
	M.chatLines[b] = { text = "zweite", sender = "Bravo2", guid = "G-B2" }
	M.chatLines[c] = { text = "dritte", sender = "Charlie2", guid = "G-C2" }

	enterArena()
	local withheld = { text = true, sender = true }
	fire("CHAT_MSG_WHISPER", whisperArgs("erste", "Alpha2", "G-A2", gone, withheld))
	fire("CHAT_MSG_WHISPER", whisperArgs("zweite", "Bravo2", "G-B2", b, withheld))
	fire("CHAT_MSG_WHISPER", whisperArgs("dritte", "Charlie2", "G-C2", c, withheld))
	eq("three held", ns.Deferred.Count(), 3)

	-- No clock advanced at all: the queue must drain on the strength of the
	-- client's answer alone.
	leaveArena()
	eq("a line the client calls gone is abandoned at once", ns.Deferred.Count(), 0)
	eq("and counted", ns.Deferred.DroppedCount(), 1)
	eq("it opened no thread", threadOf("Alpha2"), nil)
	check("the one behind it arrived without waiting", threadOf("Bravo2") ~= nil)
	check("and the one behind that", threadOf("Charlie2") ~= nil)
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- Half an answer is not an answer
--------------------------------------------------------------------------------

-- The client answers for a line one field at a time: the text can turn up a tick
-- before the sender does. Treating "the text arrived" as a successful recovery
-- hands the handler a message with nobody to file it under -- the handler stores
-- nothing, the entry is dequeued as done, and the missing half arrives a second
-- later to an empty queue. The message is not swallowed, because the chat frame
-- still has it, but the addon has lost it for good.
--
-- So a release is not "text exists". It is the reconstructed event passing the
-- same admissibility contract a live one does.
do
	reset()
	local partial, after = lineID(), lineID()
	M.chatLines[after] = { text = "danach", sender = "Danach", guid = "G-D" }

	enterArena()
	local withheld = { text = true, sender = true }
	fire("CHAT_MSG_WHISPER", whisperArgs("halb", "Halbfertig", "G-HF", partial, withheld))
	fire("CHAT_MSG_WHISPER", whisperArgs("danach", "Danach", "G-D", after, withheld))
	eq("two held", ns.Deferred.Count(), 2)

	-- Out of the arena, and the client answers with the text only.
	M.chatLines[partial] = { text = "halb" }
	leaveArena(2)
	eq("text without a sender is not a release", ns.Deferred.Count(), 2)
	eq("no thread was opened for it", threadOf("Halbfertig"), nil)
	eq("and it was not given up on either", ns.Deferred.DroppedCount(), 0)
	eq("nor did the one behind it jump the queue", threadOf("Danach"), nil)

	-- The rest of the answer turns up.
	M.chatLines[partial] = { text = "halb", sender = "Halbfertig", guid = "G-HF" }
	leaveArena(2)
	eq("the completed message is released", ns.Deferred.Count(), 0)
	eq("with nothing given up on", ns.Deferred.DroppedCount(), 0)
	local conv = threadOf("Halbfertig")
	check("into the right thread", conv ~= nil and #conv.messages == 1
		and conv.messages[1][3] == "halb",
		conv and table.concat(texts(conv), " | ") or "no thread")
	check("and the one behind it followed", threadOf("Danach") ~= nil)
	noErrors("nothing raised")

	-- The other way round: the sender is known before the text.
	reset()
	local reversed = lineID()
	M.chatLines[reversed] = { sender = "Zuerst", guid = "G-Z2" }
	enterArena()
	fire("CHAT_MSG_WHISPER", whisperArgs("später", "Zuerst", "G-Z2", reversed, withheld))
	leaveArena(2)
	eq("a sender without text is not a release either", ns.Deferred.Count(), 1)
	M.chatLines[reversed] = { text = "später", sender = "Zuerst", guid = "G-Z2" }
	leaveArena(2)
	eq("and it lands once both halves are there", ns.Deferred.Count(), 0)
	check("in its thread", threadOf("Zuerst") ~= nil)

	-- ...and a half-answer that never completes is still given up on in the end,
	-- rather than holding the queue open forever.
	reset()
	local never = lineID()
	M.chatLines[never] = { text = "nie vollständig" }
	enterArena()
	fire("CHAT_MSG_WHISPER", whisperArgs("nie", "Nie", "G-N2", never, withheld))
	leaveArena(2)
	eq("still waiting", ns.Deferred.Count(), 1)
	leaveArena(60)
	eq("and eventually given up on", ns.Deferred.Count(), 0)
	eq("counted as lost", ns.Deferred.DroppedCount(), 1)
	eq("with no half-message invented", threadOf("Nie"), nil)
	noErrors("nothing raised")
end

-- Battle.net: the identity can be temporarily unresolvable too, and a message
-- must not be thrown away over a friends list that has not loaded yet.
do
	reset()
	local l = lineID()
	M.chatLines[l] = { text = "von drüben", sender = "Freund" }
	local realFriends = M.bnet
	local friendCount = 0
	local savedGet = _G.C_BattleNet.GetFriendAccountInfo
	_G.C_BattleNet.GetFriendAccountInfo = function(index)
		if friendCount == 0 then return nil end
		if index ~= 1 then return nil end
		return { bnetAccountID = 4711, battleTag = "Freund#1234",
			accountName = "Freund",
			gameAccountInfo = { isOnline = true, characterName = "Alt" } }
	end
	local savedBNCount = _G.BNGetNumFriends
	_G.BNGetNumFriends = function() return friendCount end

	enterArena()
	M.FireEvent("CHAT_MSG_BN_WHISPER", M.Secret(), M.Secret(), "Common", "",
		"Freund", "", 0, 0, "", 0, l, "", M.Secret())
	M.RunTimers(2)
	eq("a fully withheld bnet whisper is held", ns.Deferred.Count(), 1)

	-- Out of the arena, text and name recovered -- but the friends list is empty,
	-- so there is still nobody to file it under.
	leaveArena(2)
	eq("an unresolvable identity is not a release", ns.Deferred.Count(), 1)
	eq("and nothing was given up on", ns.Deferred.DroppedCount(), 0)

	-- The list loads.
	friendCount = 1
	leaveArena(2)
	eq("and it lands once the friend is known", ns.Deferred.Count(), 0)
	local conv = CM.Get("BN:Freund#1234")
	check("under the right account", conv ~= nil
		and conv.messages[#conv.messages][3] == "von drüben",
		conv and #conv.messages or "no thread")
	noErrors("nothing raised")

	_G.C_BattleNet.GetFriendAccountInfo = savedGet
	_G.BNGetNumFriends = savedBNCount
	M.bnet = realFriends
end

--------------------------------------------------------------------------------
-- Two friends, one display name
--------------------------------------------------------------------------------

-- An account name is a display name, not an identifier. The BattleTag with its
-- discriminator is the durable one, and that is exactly what a withheld whisper
-- does not come with. Two friends can present the same name, and "first match
-- wins" would file the message under whichever the client happened to list
-- first -- which is the one thing this whole path exists to prevent.
do
	reset()
	local savedGet = _G.C_BattleNet.GetFriendAccountInfo
	local savedById = _G.C_BattleNet.GetAccountInfoByID
	local savedCount = _G.BNGetNumFriends
	local TWINS = {
		[1] = { bnetAccountID = 1001, battleTag = "SameName#1111",
			accountName = "SameName",
			gameAccountInfo = { isOnline = true, characterName = "A" } },
		[2] = { bnetAccountID = 1002, battleTag = "SameName#2222",
			accountName = "SameName",
			gameAccountInfo = { isOnline = true, characterName = "B" } },
	}
	_G.C_BattleNet.GetFriendAccountInfo = function(i) return TWINS[i] end
	_G.C_BattleNet.GetAccountInfoByID = function(id)
		for i = 1, 2 do
			if TWINS[i].bnetAccountID == id then return TWINS[i] end
		end
		return nil
	end
	_G.BNGetNumFriends = function() return 2 end

	eq("an ambiguous name resolves to nobody",
		ns.Compat.ResolveBNAccountByName("SameName"), nil)

	local before = CM.Count()
	local ambiguous = bnArgs("wer von beiden", "SameName", 1001, lineID(), { id = true })
	local suppressed = not M.ChatFrameWouldShow("CHAT_MSG_BN_WHISPER",
		unpack(ambiguous, 1, 13))
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(ambiguous, 1, 13))
	M.RunTimers(2)
	eq("no thread is guessed at", CM.Count(), before)
	eq("neither of them", CM.Get("BN:SameName#1111"), nil)
	eq("nor the other", CM.Get("BN:SameName#2222"), nil)
	eq("and the chat frame keeps its copy", suppressed, false)
	noErrors("nothing raised")

	-- With a readable id there is no ambiguity to resolve.
	local clear = bnArgs("ich bin der zweite", "SameName", 1002, lineID())
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(clear, 1, 13))
	M.RunTimers(2)
	local conv = CM.Get("BN:SameName#2222")
	check("a readable id goes to exactly that account", conv ~= nil
		and conv.messages[#conv.messages][3] == "ich bin der zweite",
		conv and #conv.messages or "no thread")
	eq("and not to the other one", CM.Get("BN:SameName#1111"), nil)
	noErrors("nothing raised")

	_G.C_BattleNet.GetFriendAccountInfo = savedGet
	_G.C_BattleNet.GetAccountInfoByID = savedById
	_G.BNGetNumFriends = savedCount
end

--------------------------------------------------------------------------------
-- Order, and who said what
--------------------------------------------------------------------------------

do
	reset()
	enterArena()
	local withheld = { text = true, sender = true }
	local lines = {}
	for n = 1, 4 do
		local l = lineID()
		lines[n] = l
		M.chatLines[l] = { text = "nachricht " .. n, sender = "Vielredner", guid = "G-V" }
		fire("CHAT_MSG_WHISPER",
			whisperArgs("nachricht " .. n, "Vielredner", "G-V", l, withheld))
		M.now = M.now + 1
	end
	leaveArena()
	local conv = threadOf("Vielredner")
	check("four whispers from one person make one thread", conv ~= nil
		and #conv.messages == 4, conv and #conv.messages or "no thread")
	if conv then
		local ordered = true
		for n = 1, 4 do
			if conv.messages[n][3] ~= "nachricht " .. n then ordered = false end
			if n > 1 and conv.messages[n][1] < conv.messages[n - 1][1] then
				ordered = false
			end
		end
		check("in the order they were sent, with their own timestamps", ordered,
			table.concat(texts(conv), " | "))
	end
	noErrors("nothing raised")

	-- Several different people, each in their own thread.
	reset()
	enterArena()
	for n = 1, 3 do
		local l = lineID()
		M.chatLines[l] = { text = "hallo", sender = "Person" .. n, guid = "G-P" .. n }
		fire("CHAT_MSG_WHISPER", whisperArgs("hallo", "Person" .. n, "G-P" .. n, l, withheld))
	end
	leaveArena()
	local separate = true
	for n = 1, 3 do
		local c = threadOf("Person" .. n)
		if not c or #c.messages ~= 1 then separate = false end
	end
	check("three people make three threads", separate)
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- Battle.net
--------------------------------------------------------------------------------

-- A Battle.net whisper needs an account id that a normal whisper does not. It is
-- the argument most likely to be withheld on its own, and it is the one that
-- decides whose conversation this is -- so getting it wrong is worse than not
-- having it.
do
	reset()
	-- The id alone is withheld. The name is readable, and the friends list has
	-- both, so the message does not need to wait for anything.
	local l = lineID()
	local before = ns.Deferred.Count()
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(bnArgs("hi", "Freund", 4711, l,
		{ id = true }), 1, 13))
	M.RunTimers(2)
	eq("a withheld account id does not delay the message", ns.Deferred.Count(), before)
	local conv = CM.Get("BN:Freund#1234")
	check("and it lands on the right account", conv ~= nil
		and conv.messages[#conv.messages][3] == "hi",
		conv and conv.messages[#conv.messages][3] or "no thread")
	eq("under the right account id", conv and conv.bnetAccountID, 4711)
	noErrors("a withheld account id raises nothing")

	-- The id is withheld and the name belongs to nobody on the list. There is no
	-- honest way to say whose this is, so no thread is opened.
	reset()
	local threadsBefore = CM.Count()
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(bnArgs("hi", "Fremder", 9999, lineID(),
		{ id = true }), 1, 13))
	M.RunTimers(2)
	eq("an unidentifiable account opens no thread", CM.Count(), threadsBefore)
	noErrors("and raises nothing")

	-- Text and id both withheld: held, then recovered, then identified by name.
	reset()
	local held = lineID()
	M.chatLines[held] = { text = "aus der arena", sender = "Freund" }
	enterArena()
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(bnArgs("aus der arena", "Freund", 4711,
		held, { text = true, sender = true, id = true }), 1, 13))
	M.RunTimers(2)
	eq("a fully withheld bnet whisper is held", ns.Deferred.Count(), 1)
	leaveArena()
	eq("and released", ns.Deferred.Count(), 0)
	conv = CM.Get("BN:Freund#1234")
	check("onto the right account", conv ~= nil
		and conv.messages[#conv.messages][3] == "aus der arena",
		conv and conv.messages[#conv.messages][3] or "no thread")
	noErrors("no errors on the way")

	-- Every combination, purely for "does it raise".
	reset()
	local combos = {
		{ "text only", { text = true } },
		{ "sender only", { sender = true } },
		{ "id only", { id = true } },
		{ "text and id", { text = true, id = true } },
		{ "everything", { text = true, sender = true, id = true } },
	}
	for n = 1, #combos do
		local l2 = lineID()
		M.chatLines[l2] = { text = "x", sender = "Freund" }
		local ok = pcall(M.FireEvent, "CHAT_MSG_BN_WHISPER",
			unpack(bnArgs("x", "Freund", 4711, l2, combos[n][2]), 1, 13))
		check("a bnet whisper with " .. combos[n][1] .. " withheld does not throw", ok)
		local ok2 = pcall(M.FireEvent, "CHAT_MSG_BN_WHISPER_INFORM",
			unpack(bnArgs("x", "Freund", 4711, lineID(), combos[n][2]), 1, 13))
		check("nor does the echo with " .. combos[n][1] .. " withheld", ok2)
		M.RunTimers(2)
	end
	noErrors("no combination raises a soft error")
	reset()
end

--------------------------------------------------------------------------------
-- Battle.net with nobody behind it
--------------------------------------------------------------------------------

-- The case the first round of this got wrong. Text and account name both
-- readable, so nothing looked withheld -- but the account id was gone and the
-- name belonged to nobody on the friends list, so the handler had nothing to
-- file it under and quietly dropped it. Meanwhile the chat filter, which only
-- looked at whether the required fields were readable, hid the player's copy.
--
-- Not stored, and not visible. The one outcome the whole design exists to
-- prevent.
do
	for _, event in ipairs({ "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }) do
		reset()
		ns.db.profile.messages.hideFromChatFrame = true
		local threadsBefore = CM.Count()
		-- "Niemand" is on nobody's friends list, so the name cannot be resolved.
		local args = bnArgs("wer bin ich", "Niemand", 9999, lineID(), { id = true })

		local suppressed = not M.ChatFrameWouldShow(event, unpack(args, 1, 13))
		M.FireEvent(event, unpack(args, 1, 13))
		M.RunTimers(2)

		local stored = CM.Count() > threadsBefore
		eq(event .. ": an unidentifiable account is not stored", stored, false)
		eq(event .. ": and is NOT hidden from the chat frame", suppressed, false)
		eq(event .. ": nor held, because there is nothing to recover",
			ns.Deferred.Count(), 0)
		noErrors(event .. ": and nothing raised")
	end

	-- ...while an account that CAN be identified is stored and may be hidden.
	reset()
	ns.db.profile.messages.hideFromChatFrame = true
	local args = bnArgs("ich schon", "Freund", 4711, lineID(), { id = true })
	local suppressed = not M.ChatFrameWouldShow("CHAT_MSG_BN_WHISPER", unpack(args, 1, 13))
	M.FireEvent("CHAT_MSG_BN_WHISPER", unpack(args, 1, 13))
	M.RunTimers(2)
	local conv = CM.Get("BN:Freund#1234")
	check("an identifiable account is stored", conv ~= nil
		and conv.messages[#conv.messages][3] == "ich schon")
	eq("and may be taken out of the chat frame", suppressed, true)
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- The invariant, generalised
--------------------------------------------------------------------------------

-- Withheld is only one way for a required field to be unusable. A nil sender, an
-- empty one, a number where a name belongs -- the handler refuses all of them,
-- and the filter has to refuse to hide them for exactly the same reason.
do
	local BROKEN = {
		{ "no text", function(a) a[1] = nil end },
		{ "empty text", function(a) a[1] = "" end },
		{ "no sender", function(a) a[2] = nil end },
		{ "an empty sender", function(a) a[2] = "" end },
		{ "a number where the sender belongs", function(a) a[2] = 12345 end },
		{ "a table where the text belongs", function(a) a[1] = {} end },
	}
	for i = 1, #BROKEN do
		local label, breakIt = BROKEN[i][1], BROKEN[i][2]
		for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }) do
			reset()
			ns.db.profile.messages.hideFromChatFrame = true
			local who = ("Kaputt%d"):format(i)
			local l = lineID()
			M.chatLines[l] = { text = "x", sender = who }
			local args = whisperArgs("x", who, "G-K", l)
			breakIt(args)

			local suppressed = not M.ChatFrameWouldShow(event, unpack(args, 1, 13))
			local threadsBefore = CM.Count()
			local ok = pcall(M.FireEvent, event, unpack(args, 1, 13))
			M.RunTimers(2)
			check(("%s with %s does not throw"):format(event, label), ok)
			local stored = CM.Count() > threadsBefore
			local heldForLater = ns.Deferred.Count() > 0
			check(("%s with %s: never both unstored and hidden"):format(event, label),
				stored or heldForLater or not suppressed,
				("stored=%s held=%s suppressed=%s"):format(tostring(stored),
					tostring(heldForLater), tostring(suppressed)))
			noErrors(("%s with %s raised nothing"):format(event, label))
		end
	end

	-- Withheld payload with no chat line id to ask about later: nothing to hold,
	-- so nothing may be hidden either.
	reset()
	ns.db.profile.messages.hideFromChatFrame = true
	local args = whisperArgs("x", "Verloren", "G-L", nil, { text = true, sender = true })
	local suppressed = not M.ChatFrameWouldShow("CHAT_MSG_WHISPER", unpack(args, 1, 13))
	local threadsBefore = CM.Count()
	M.FireEvent("CHAT_MSG_WHISPER", unpack(args, 1, 13))
	M.RunTimers(2)
	eq("a withheld message with no chat line is not held", ns.Deferred.Count(), 0)
	eq("nor stored", CM.Count(), threadsBefore)
	eq("and so is not hidden either", suppressed, false)
	noErrors("nothing raised")
	reset()
end

--------------------------------------------------------------------------------
-- The invariant, under every setting that could break it
--------------------------------------------------------------------------------

-- A message must never end up in the state "the addon did not store it AND the
-- addon hid it from the chat frame". Everything else is a preference; this one
-- is the floor.
do
	local SETTINGS = {
		{ "normally", {} },
		{ "with the addon switched off", { enabled = false } },
		{ "with chat-frame hiding off", { hide = false } },
		{ "after repeated errors", { degrade = true } },
		{ "with whispers popped out by the game", { whisperMode = "popout" } },
	}
	local CASES = {
		{ "a normal whisper", "CHAT_MSG_WHISPER", nil },
		{ "a withheld whisper", "CHAT_MSG_WHISPER", { text = true, sender = true } },
		{ "a withheld echo", "CHAT_MSG_WHISPER_INFORM", { text = true, sender = true } },
	}
	for a = 1, #SETTINGS do
		local name, setting = SETTINGS[a][1], SETTINGS[a][2]
		for b = 1, #CASES do
			reset()
			ns.db.profile.enabled = setting.enabled ~= false
			ns.db.profile.messages.hideFromChatFrame = setting.hide ~= false
			M.cvars.whisperMode = setting.whisperMode or "inline"
			if setting.degrade then ns.Debug.NoteUnreadable() end

			local label, event, secret = CASES[b][1], CASES[b][2], CASES[b][3]
			local l = lineID()
			local who = ("Wer%d%d"):format(a, b)
			M.chatLines[l] = { text = "probe", sender = who, guid = "G-W" }
			if secret then enterArena() end
			local args = whisperArgs("probe", who, "G-W", l, secret)

			local suppressed = not M.ChatFrameWouldShow(event, unpack(args, 1, 13))
			fire(event, args)
			local storedNow = threadOf(who) ~= nil
			local heldForLater = ns.Deferred.Count() > 0
			check(("%s %s: never both unstored and hidden"):format(label, name),
				storedNow or heldForLater or not suppressed,
				("stored=%s held=%s suppressed=%s"):format(tostring(storedNow),
					tostring(heldForLater), tostring(suppressed)))
			if secret then
				check(("%s %s: a withheld message is never hidden"):format(label, name),
					not suppressed)
				leaveArena()
			end
		end
	end
	ns.db.profile.enabled = true
	ns.db.profile.messages.hideFromChatFrame = true
	M.cvars.whisperMode = "inline"
	reset()
end

--------------------------------------------------------------------------------
-- Things that must keep working around it
--------------------------------------------------------------------------------

do
	reset()
	-- Animations off: the recovery timer must not have been an animation.
	ns.db.profile.animations.level = "off"
	ns.Theme.Refresh()
	local l = lineID()
	M.chatLines[l] = { text = "ohne animationen", sender = "Ruhig", guid = "G-R" }
	enterArena()
	fire("CHAT_MSG_WHISPER", whisperArgs("ohne animationen", "Ruhig", "G-R", l,
		{ text = true, sender = true }))
	leaveArena()
	check("recovery works with animations switched off", threadOf("Ruhig") ~= nil)
	ns.db.profile.animations.level = "normal"
	ns.Theme.Refresh()

	-- The window closed: history is the model, not the view.
	reset()
	ns.UI.Hide()
	M.RunFrames(3)
	local l2 = lineID()
	M.chatLines[l2] = { text = "fenster zu", sender = "Zugemacht", guid = "G-Z" }
	enterArena()
	fire("CHAT_MSG_WHISPER", whisperArgs("fenster zu", "Zugemacht", "G-Z", l2,
		{ text = true, sender = true }))
	leaveArena()
	local conv = threadOf("Zugemacht")
	check("a message recovered with the window shut is still stored",
		conv ~= nil and #conv.messages == 1)
	check("and counts as unread", conv and (conv.unread or 0) > 0,
		conv and conv.unread)
	noErrors("nothing raised")

	-- Sending is refused where the client will not carry it, and the text stays.
	reset()
	enterArena()
	local printed = 0
	local realPrint = ns.Print
	ns.Print = function() printed = printed + 1 end
	local sentBefore = #(M.sent or {})
	local sent = CM.SendMessage(ns.Compat.NormalizeName("Zugemacht"), "geht das?")
	ns.Print = realPrint
	check("sending is refused while chat is withheld", not sent)
	eq("nothing reached the server", #(M.sent or {}), sentBefore)
	check("and the player is told", printed > 0)
	leaveArena()
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- Lines the game itself is hiding
--------------------------------------------------------------------------------

-- Blizzard's own chat filter, which is moderation rather than a restriction on
-- addons. The addon has the placeholder the client handed over, not the words,
-- and working around somebody else's filter is not its job. So it says the line
-- is hidden, and offers the player the one thing the client allows: asking.
do
	reset()
	local l = lineID()
	M.chatLines[l] = { text = "das echte wort", sender = "Gefiltert", guid = "G-F2" }
	M.censoredLines[l] = true

	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Gefiltert", "G-F2", l))
	local conv = threadOf("Gefiltert")
	check("a hidden line is still a message", conv ~= nil and #conv.messages == 1)
	local msg = conv and conv.messages[1]
	eq("shown as hidden rather than as its placeholder",
		CM.MessageText(msg), ns.L["Message hidden by the game's chat filter."])
	check("and it remembers which line to ask about", msg[ns.MSG_LINE] == l)
	eq("the export says the same thing", ns.Export.PlainMessage(msg),
		ns.L["Message hidden by the game's chat filter."])
	eq("nothing was uncensored without being asked", #(M.uncensored or {}), 0)

	-- The player asks.
	check("revealing it works", CM.RevealMessage(conv, msg))
	eq("the client was asked exactly once", #(M.uncensored or {}), 1)
	eq("and the words are there now", CM.MessageText(msg), "das echte wort")
	check("with nothing left to ask about", msg[ns.MSG_LINE] == nil)
	check("and asking again does nothing", not CM.RevealMessage(conv, msg))

	-- A line hidden while chat was withheld: held, recovered, still hidden.
	reset()
	local l2 = lineID()
	M.chatLines[l2] = { text = "auch gefiltert", sender = "Gefiltert2", guid = "G-F3" }
	M.censoredLines[l2] = true
	enterArena()
	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Gefiltert2", "G-F3", l2,
		{ text = true, sender = true }))
	leaveArena()
	local conv2 = threadOf("Gefiltert2")
	check("a held line that is also filtered still arrives", conv2 ~= nil
		and #conv2.messages == 1)
	eq("and is still shown as hidden", CM.MessageText(conv2.messages[1]),
		ns.L["Message hidden by the game's chat filter."])
	noErrors("nothing raised")

	-- An ordinary message carries none of this.
	reset()
	local l3 = lineID()
	M.chatLines[l3] = { text = "ganz normal", sender = "Normal", guid = "G-N" }
	fire("CHAT_MSG_WHISPER", whisperArgs("ganz normal", "Normal", "G-N", l3))
	local plain = threadOf("Normal").messages[1]
	eq("an ordinary message reads as itself", CM.MessageText(plain), "ganz normal")
	check("and remembers no line", plain[ns.MSG_LINE] == nil)

	-- A client with no such API is a client with no such feature.
	reset()
	local info = _G.C_ChatInfo.IsChatLineCensored
	_G.C_ChatInfo.IsChatLineCensored = nil
	local ok = pcall(CM.MessageText, plain)
	check("a client without the filter API still renders messages", ok)
	_G.C_ChatInfo.IsChatLineCensored = info
end

--------------------------------------------------------------------------------
-- Being unable to read is not being unable to write
--------------------------------------------------------------------------------

-- Two different questions with two different APIs. Not being allowed to read an
-- opponent's whisper does not by itself mean you cannot answer it, and refusing
-- to send on the strength of the wrong question would refuse in places the
-- client would have carried the message.
do
	-- The flags are set after reset(), which clears them: a helper that quietly
	-- undoes its own setup is a helper that passes for the wrong reason.
	local function attemptSend(lockdown, restricted)
		reset()
		M.chatLockdown, M.outgoingRestricted = lockdown, restricted
		CM.GetOrCreate(ns.Compat.NormalizeName("Empfaenger"))
		M.sent = {}
		local realPrint = ns.Print
		local printed = 0
		ns.Print = function() printed = printed + 1 end
		local sent = CM.SendMessage(ns.Compat.NormalizeName("Empfaenger"), "versuch")
		ns.Print = realPrint
		return sent, #(M.sent or {}), printed
	end

	local sent, reached, told = attemptSend(true, true)
	check("both restricted: refused", not sent)
	eq("nothing reached the server", reached, 0)
	check("and the player is told", told > 0)

	-- Chat is withheld, but sending is not restricted: the message goes.
	sent, reached = attemptSend(true, false)
	check("withheld chat alone does not stop a send", sent == true)
	eq("and it reached the server", reached, 1)

	-- Neither: ordinary.
	sent, reached = attemptSend(false, false)
	check("unrestricted: sent", sent == true)
	eq("and reached the server", reached, 1)

	-- A client with no specific API falls back to the general one.
	local specific = _G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
	sent, reached, told = attemptSend(true, false)
	check("without the specific API, withheld chat refuses the send", not sent)
	eq("nothing reached the server", reached, 0)
	check("and the player is told", told > 0)
	_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = specific

	M.chatLockdown, M.outgoingRestricted = false, nil
	reset()
end

--------------------------------------------------------------------------------
-- A hidden message stays hidden across a reload
--------------------------------------------------------------------------------

-- A chat line id means nothing in a new session. If display depended on it, a
-- message the game had hidden would come back as the raw placeholder the client
-- handed over -- which the player would read as what was actually said.
do
	reset()
	local l = lineID()
	M.chatLines[l] = { text = "das echte wort", sender = "Bleibt", guid = "G-B3" }
	M.censoredLines[l] = true
	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Bleibt", "G-B3", l))
	local conv = threadOf("Bleibt")
	local msg = conv.messages[1]
	check("it is marked hidden durably", msg[ns.MSG_CENSORED] == true)
	check("and carries a line to ask about, for now", msg[ns.MSG_LINE] == l)
	check("so the reveal is offered", CM.CanReveal(msg))

	-- The reload, as the addon actually meets one: the saved message comes back
	-- from the history table and the load pass runs over it. The line id is
	-- written to saved variables like every other field, which is exactly why it
	-- has to be dropped on the way in.
	check("the line id is part of what gets saved", msg[ns.MSG_LINE] ~= nil)
	ns.ConversationManager.LoadPersisted()
	M.RunFrames(2)
	conv = threadOf("Bleibt")
	msg = conv and conv.messages[#conv.messages]
	check("the message survived", msg ~= nil)
	eq("and still reads as hidden", CM.MessageText(msg),
		ns.L["Message hidden by the game's chat filter."])
	check("with no stale line left behind", msg[ns.MSG_LINE] == nil)
	check("so the reveal is no longer offered", not CM.CanReveal(msg))
	eq("and the sidebar says the same", CM.Preview(conv),
		ns.L["Message hidden by the game's chat filter."])
	noErrors("a reload raises nothing")
end

-- A reveal the client cannot actually satisfy must leave the message hidden.
-- Showing the placeholder instead would be showing "***" as though it were what
-- they wrote.
do
	reset()
	local l = lineID()
	M.chatLines[l] = { text = "steht bereit", sender = "Halb", guid = "G-H" }
	M.censoredLines[l] = true
	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Halb", "G-H", l))
	local conv = threadOf("Halb")
	local msg = conv.messages[1]

	-- The line is still valid and still censored -- so the reveal is genuinely
	-- offered -- but the client hands nothing back when asked. That is the case
	-- where it would be easiest to clear the flag and show the placeholder.
	M.chatLines[l] = nil
	M.validLines[l] = true
	check("the reveal is still offered", CM.CanReveal(msg))
	check("a reveal that recovers nothing fails", not CM.RevealMessage(conv, msg))
	check("and the line is still marked as hidden afterwards",
		M.censoredLines[l] == nil and msg[ns.MSG_CENSORED] == true,
		"the client was asked, and the message stayed hidden")
	eq("and the message is still hidden", CM.MessageText(msg),
		ns.L["Message hidden by the game's chat filter."])
	check("and still marked as such", msg[ns.MSG_CENSORED] == true)
	eq("the placeholder is never shown", CM.MessageText(msg) == "***", false)

	-- The client comes back from UncensorChatLine without complaint and leaves
	-- the line censored anyway. It answers nothing about whether it worked, so
	-- the only honest thing is to ask again -- and the text it hands over in that
	-- state is the placeholder, which must never become the durable record.
	reset()
	local l3 = lineID()
	M.chatLines[l3] = { text = "***", sender = "Bleibtzu", guid = "G-BZ" }
	M.censoredLines[l3] = true
	M.refuseUncensor = true
	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Bleibtzu", "G-BZ", l3))
	local stubborn = threadOf("Bleibtzu")
	local stubbornMsg = stubborn.messages[1]
	check("the reveal is offered", CM.CanReveal(stubbornMsg))
	check("but a refused uncensor is not a reveal",
		not CM.RevealMessage(stubborn, stubbornMsg))
	eq("the client was asked", #(M.uncensored or {}) > 0, true)
	eq("and it is still hidden", CM.MessageText(stubbornMsg),
		ns.L["Message hidden by the game's chat filter."])
	check("still marked hidden", stubbornMsg[ns.MSG_CENSORED] == true)
	check("and still knows which line to ask about",
		stubbornMsg[ns.MSG_LINE] == l3)
	check("the placeholder never became the message",
		stubbornMsg[ns.MSG_TEXT] ~= nil and CM.MessageText(stubbornMsg) ~= "***")
	M.refuseUncensor = nil

	-- A line that has aged out is not offered at all.
	reset()
	local l2 = lineID()
	M.chatLines[l2] = { text = "weg", sender = "Alt", guid = "G-A3" }
	M.censoredLines[l2] = true
	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Alt", "G-A3", l2))
	local old = threadOf("Alt").messages[1]
	M.invalidLines[l2] = true
	check("a stale line offers no reveal", not CM.CanReveal(old))
	check("and revealing it does nothing", not CM.RevealMessage(threadOf("Alt"), old))
	eq("it is still hidden", CM.MessageText(old),
		ns.L["Message hidden by the game's chat filter."])
	noErrors("nothing raised")
end

-- ...and a reveal that works, persists.
do
	reset()
	local l = lineID()
	M.chatLines[l] = { text = "jetzt sichtbar", sender = "Sichtbar", guid = "G-S2" }
	M.censoredLines[l] = true
	fire("CHAT_MSG_WHISPER", whisperArgs("***", "Sichtbar", "G-S2", l))
	local conv = threadOf("Sichtbar")
	local msg = conv.messages[1]
	eq("the sidebar shows it as hidden first", CM.Preview(conv),
		ns.L["Message hidden by the game's chat filter."])

	check("the reveal works", CM.RevealMessage(conv, msg))
	eq("the real words are there", CM.MessageText(msg), "jetzt sichtbar")
	check("the durable mark is gone", msg[ns.MSG_CENSORED] == nil)
	eq("and the sidebar caught up rather than cacheing the old line",
		CM.Preview(conv), "jetzt sichtbar")
	eq("the export says the real thing now",
		ns.Export.PlainMessage(msg), "jetzt sichtbar")

	ns.ConversationManager.LoadPersisted()
	M.RunFrames(2)
	local after = threadOf("Sichtbar")
	eq("and it is still the real thing after a reload",
		CM.MessageText(after.messages[#after.messages]), "jetzt sichtbar")
	noErrors("nothing raised")
end

--------------------------------------------------------------------------------
-- A reload in the middle
--------------------------------------------------------------------------------

-- What is held lives only in memory, by design: a chat line id is meaningless
-- after a reload, so carrying the queue across one would be carrying a promise
-- that cannot be kept. What must survive is everything already stored.
do
	reset()
	local l = lineID()
	M.chatLines[l] = { text = "vor dem reload", sender = "Vorher", guid = "G-V2" }
	enterArena()
	fire("CHAT_MSG_WHISPER", whisperArgs("vor dem reload", "Vorher", "G-V2", l,
		{ text = true, sender = true }))
	leaveArena()
	check("stored before the reload", threadOf("Vorher") ~= nil)

	M.FireEvent("PLAYER_LOGOUT")
	M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
	M.FireEvent("PLAYER_LOGIN")
	M.RunFrames(4)
	local conv = threadOf("Vorher")
	check("and still there afterwards", conv ~= nil and #conv.messages >= 1,
		conv and #conv.messages or "no thread")
	eq("with nothing left dangling", ns.Deferred.Count(), 0)
	noErrors("a reload raises nothing")
end

--------------------------------------------------------------------------------

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
