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
	M.censoredLines = {}
	softErrors = {}
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
		and #conv.messages == 1, conv and #conv.messages or "no thread")
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
