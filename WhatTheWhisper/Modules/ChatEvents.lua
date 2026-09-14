-- WhatTheWhisper -- Game chat events in, conversations out.
--
-- Delivery state is real information, not decoration:
--   * we add an outgoing bubble immediately, marked pending
--   * CHAT_MSG_WHISPER_INFORM is the server echoing the message back, which is
--     the only confirmation the client ever gets -> mark it sent
--   * ERR_CHAT_PLAYER_NOT_FOUND_S means it never arrived -> mark it failed
-- Whispers typed into the default chat frame or sent by another addon are
-- picked up by the same echo, so the thread stays complete either way.

local _, ns = ...
local Compat, CM, PlayerInfo = ns.Compat, ns.ConversationManager, ns.PlayerInfo
local Debug = ns.Debug

local ChatEvents = {}
ns.ChatEvents = ChatEvents

local MSG_STATUS = ns.MSG_STATUS

local frame = CreateFrame("Frame")
local pending = {}
local pendingSweepScheduled = false
local PENDING_TIMEOUT = 12

local myName

--------------------------------------------------------------------------------
-- Pending outgoing messages
--------------------------------------------------------------------------------

function ChatEvents.RegisterPending(id, text, msg)
	pending[#pending + 1] = { id = id, text = text, msg = msg, at = GetTime() }
	if not pendingSweepScheduled then
		pendingSweepScheduled = true
		ns.Anim.After(PENDING_TIMEOUT + 1, ChatEvents.SweepPending)
	end
end

-- Anything still pending after the timeout almost certainly arrived: the only
-- failure the server reports is "no player named", and that comes back fast.
function ChatEvents.SweepPending()
	pendingSweepScheduled = false
	local now = GetTime()
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if now - entry.at > PENDING_TIMEOUT then
			if entry.msg and entry.msg[MSG_STATUS] == ns.SEND_PENDING then
				entry.msg[MSG_STATUS] = ns.SEND_OK
				local conv = CM.Get(entry.id)
				if conv then ns.Bus.Fire(ns.EV.MESSAGE_UPDATED, conv, entry.msg) end
			end
			table.remove(pending, i)
		end
	end
	if #pending > 0 and not pendingSweepScheduled then
		pendingSweepScheduled = true
		ns.Anim.After(PENDING_TIMEOUT + 1, ChatEvents.SweepPending)
	end
end

local function takePending(id, text)
	for i = 1, #pending do
		local entry = pending[i]
		if entry.id == id and entry.text == text then
			table.remove(pending, i)
			return entry
		end
	end
	return nil
end

local function failPendingFor(id)
	for i = #pending, 1, -1 do
		local entry = pending[i]
		if entry.id == id then
			table.remove(pending, i)
			if entry.msg then
				entry.msg[MSG_STATUS] = ns.SEND_FAILED
				local conv = CM.Get(id)
				if conv then ns.Bus.Fire(ns.EV.MESSAGE_UPDATED, conv, entry.msg) end
			end
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Upgrades a pending outgoing message to "sent".
--
-- The in-memory queue is the normal path. After a /reload the queue is empty but
-- the message is already in the stored thread, so the thread itself is checked
-- before adding what would be a duplicate.
local function resolvePending(id, text)
	local conv = CM.Get(id)
	local entry = takePending(id, text)
	if entry and entry.msg then
		entry.msg[MSG_STATUS] = ns.SEND_OK
		if conv then ns.Bus.Fire(ns.EV.MESSAGE_UPDATED, conv, entry.msg) end
		return true
	end
	if not conv then return false end
	local index, msg = CM.FindPendingOutgoing(conv, text)
	if index and (Compat.GetServerTime() - (msg[ns.MSG_TS] or 0)) <= 60 then
		CM.UpdateMessageStatus(conv, index, ns.SEND_OK)
		return true
	end
	return false
end

local function isMention(text)
	if not myName or not text then return false end
	return ns.Text.Contains(text, myName)
end

-- Account ids are only stable within a session, so the BattleTag is the durable
-- key. It is cached per account id because a friend who goes offline can stop
-- resolving mid-session, and falling back to the presence name would silently
-- open a second thread for the same person.
local bnKeyCache = {}

-- Who a Battle.net whisper is with, from whatever the client was willing to say.
--
-- The account id arrives beside the text and is sometimes the one thing withheld
-- -- and a withheld value may not be tested for truth, used as a table key, or
-- turned into a string, so it is made readable or discarded before any of that.
-- When it is gone the name is the way back: a Battle.net whisper only comes from
-- somebody on your list, and the list has both.
--
-- Returns nil when neither works. That has to mean "do not know": a thread filed
-- under the wrong person is worse than one that was never opened.
-- The Battle.net account the admissibility check resolved for this event, so the
-- handler files it under the same person the filter decided it could be filed
-- under. Set only for the duration of one handler call.
local admittedBNAccountID

-- Work that happens because a message was stored, rather than in order to store
-- it: a toast, a sound, the window scrolling. None of it can un-store anything,
-- so a failure here is recorded and stepped over -- and, crucially, does not
-- make a replayed message look unstored and get delivered twice.
local function aftermath(label, fn, ...)
	if type(fn) ~= "function" then return end
	ns.Guard(label, fn, ...)
end

-- The account id behind a Battle.net whisper, or nil.
--
-- The id arrives beside the text and is sometimes the one thing withheld -- and
-- a withheld value may not be tested for truth, used as a table key or turned
-- into a string, so it is made readable or discarded before any of that. When it
-- is gone the name is the way back: a Battle.net whisper only comes from
-- somebody on your list, and the list has both.
--
-- nil has to mean "do not know". Everything upstream treats that as a message
-- this addon cannot file, and leaves the player's copy in the chat frame.
function ChatEvents.ResolveBNIdentity(rawSenderID, accountName)
	local bnetAccountID = Compat.ReadableNumber(rawSenderID)
	if bnetAccountID then return bnetAccountID end
	bnetAccountID = Compat.ResolveBNAccountByName(accountName)
	if bnetAccountID then
		Debug.Log("events", "bnet id was withheld; recovered it from %s",
			tostring(accountName))
	end
	return bnetAccountID
end

local function bnIdentity(rawSenderID, accountName)
	local bnetAccountID = admittedBNAccountID
		or ChatEvents.ResolveBNIdentity(rawSenderID, accountName)
	if not bnetAccountID then return nil end

	local cached = bnKeyCache[bnetAccountID]
	if cached then
		return cached.id, cached.name or accountName, cached.tag, bnetAccountID
	end
	local battleTag, name = Compat.GetBNAccountInfoByID(bnetAccountID)
	local id = battleTag and ("BN:" .. battleTag)
		or (accountName and accountName ~= "" and ("BN:" .. accountName))
		or ("BN:" .. tostring(bnetAccountID))
	local entry = { id = id, name = name or accountName, tag = battleTag }
	if battleTag then bnKeyCache[bnetAccountID] = entry end
	return entry.id, entry.name, entry.tag, bnetAccountID
end

--------------------------------------------------------------------------------
-- Incoming
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Payloads that cannot be read
--------------------------------------------------------------------------------

-- In arenas, battlegrounds and other restricted content the client delivers chat
-- payloads as secret values rather than strings. Reading one is a hard error
-- that also taints the caller, and the addon was reading every one of them
-- without asking -- which filled the chat frame with errors in an arena and, for
-- a whisper, stopped the message being handled at all.
--
-- Being somewhere restricted is not a fault, so an unreadable payload is not
-- reported as one. It is counted, and `/wtw debug` says how often it happened.
local unreadable = 0
-- Set only while a held message is being put back, so the handlers below store
-- it with the time it was sent instead of the time it was recovered.
local replayTimestamp
-- ...and whether the game was hiding that line when it came back. `false` means
-- "asked, and it was not"; nil means "not a replay".
local replayCensoredLine

function ChatEvents.UnreadableCount()
	return unreadable
end

-- For a system message there is nothing to lose: we read those only to notice
-- "no player named" and friends coming online, and missing one costs nothing.
local function readableOrNil(value)
	local readable = Compat.ReadableText(value)
	if readable == nil and value ~= nil then unreadable = unreadable + 1 end
	return readable
end

-- For a whisper there is everything to lose. If the text cannot be read we
-- cannot store it, and we must not also be the reason it is missing from the
-- chat frame -- so the addon stops suppressing whispers, exactly as it does when
-- it has been erroring, and says so once.
-- The game's own chat filter can hide a line and hand the addon a placeholder.
-- That is moderation, not a restriction on addons, and the most an addon may do
-- is say so and let the player ask. Returns the line to ask about, or nil when
-- there is nothing hidden -- which is almost always.
--
-- On a replayed message the answer was worked out when it was released; asking
-- again could give a different one, because the player may have revealed it in
-- the chat frame in the meantime.
local function censoredLineOf(lineID)
	if replayCensoredLine ~= nil then return replayCensoredLine or nil end
	local line = Compat.ReadableNumber(lineID)
	if line and Compat.IsChatLineCensored(line) then return line end
	return nil
end

local function readableWhisper(value)
	local readable = Compat.ReadableText(value)
	if readable ~= nil then return readable end
	unreadable = unreadable + 1
	Debug.NoteUnreadable()
	return nil
end

local function onWhisper(text, sender, _, _, _, flags, _, _, _, _, lineID, guid)
	text, sender, guid = readableWhisper(text), readableOrNil(sender), readableOrNil(guid)
	if text == nil or sender == nil or sender == "" then return end
	local censoredLine = censoredLineOf(lineID)
	local id = Compat.NormalizeName(sender)
	PlayerInfo.Observe(id, guid)
	local info = PlayerInfo.Get(id)

	local conv = CM.GetOrCreate(id, { class = info and info.class })
	if info then
		conv.class = info.class or conv.class
		conv.level = info.level or conv.level
		conv.faction = info.faction or conv.faction
	end

	local kind = ns.MSG_WHISPER
	if flags == "GM" or flags == "DEV" then kind = ns.MSG_SYSTEM end

	-- They just wrote, so they are online. This is the only presence source
	-- that exists for somebody who is neither a friend nor a guildmate, and it
	-- was being thrown away -- which is why the status dot was almost never
	-- drawn for anybody.
	PlayerInfo.NoteActivity(id)

	-- The commit. Everything above is working out where it goes; this is the
	-- line that means the message exists.
	local msg = CM.AddMessage(id, ns.DIR_IN, text, kind, replayTimestamp, nil,
		censoredLine and { censoredLine = censoredLine } or nil)
	if not msg then return false end
	Debug.Log("events", "whisper in from %s (%d bytes)", id, #(text or ""))

	-- ...and everything below is what happens because it exists. Guarded on its
	-- own so a toast that throws cannot un-store a stored message: a replayed
	-- one would otherwise be retried and land twice.
	aftermath("Notifications.OnIncoming", ns.Notifications.OnIncoming, conv, msg,
		isMention(text))
	return true
end

local function onWhisperInform(text, target, _, _, _, _, _, _, _, _, _, guid)
	text, target, guid = readableWhisper(text), readableOrNil(target), readableOrNil(guid)
	if text == nil or target == nil then return end
	if target == "" then return end
	local id = Compat.NormalizeName(target)
	PlayerInfo.Observe(id, guid)
	-- The server echoing a whisper back is the server confirming it had
	-- somebody to give it to.
	PlayerInfo.NoteActivity(id)

	if resolvePending(id, text) then
		-- Matching an echo to a message already on screen is a commit too: the
		-- model changed, and replaying it would mark the same message twice.
		Debug.Log("dedupe", "inform matched a pending message to %s", id)
		return true
	end

	-- Sent from the default chat frame or another addon: adopt it.
	Debug.Log("dedupe", "adopting foreign outgoing whisper to %s", id)
	local msg = CM.AddMessage(id, ns.DIR_OUT, text, ns.MSG_WHISPER, replayTimestamp,
		ns.SEND_OK)
	if not msg then return false end
	if ns.db.profile.messages.openOnSend then
		aftermath("UI.EnsureConversationOpen", ns.UI.EnsureConversationOpen, id, true)
	end
	return true
end

local function onBNWhisper(text, accountName, _, _, _, _, _, _, _, _, _, _, bnSenderID)
	text, accountName = readableWhisper(text), readableOrNil(accountName)
	if text == nil then return end
	local id, name, tag, accountID = bnIdentity(bnSenderID, accountName)
	if not id then
		-- Readable text, unknowable account. Counted and left where it is rather
		-- than filed under a guess; the chat frame still has it.
		unreadable = unreadable + 1
		Debug.Log("events", "a bnet whisper arrived with no usable identity")
		return
	end
	local conv = CM.GetOrCreate(id, {
		name = name or accountName, battleTag = tag, bnetAccountID = accountID,
	})
	conv.bnetAccountID = accountID
	local msg = CM.AddMessage(id, ns.DIR_IN, text, ns.MSG_BNET, replayTimestamp)
	if not msg then return false end
	Debug.Log("events", "bnet whisper in on %s", id)
	aftermath("Notifications.OnIncoming", ns.Notifications.OnIncoming, conv, msg,
		isMention(text))
	return true
end

local function onBNWhisperInform(text, accountName, _, _, _, _, _, _, _, _, _, _, bnSenderID)
	text, accountName = readableWhisper(text), readableOrNil(accountName)
	if text == nil then return end
	local id = select(1, bnIdentity(bnSenderID, accountName))
	if not id then
		unreadable = unreadable + 1
		Debug.Log("events", "a bnet echo arrived with no usable identity")
		return
	end
	if resolvePending(id, text) then
		Debug.Log("dedupe", "bnet inform matched a pending message on %s", id)
		return true
	end
	Debug.Log("dedupe", "adopting foreign outgoing bnet whisper on %s", id)
	return CM.AddMessage(id, ns.DIR_OUT, text, ns.MSG_BNET, replayTimestamp,
		ns.SEND_OK) ~= nil
end

-- The target's away/busy auto-reply. Shown inside the thread, where it belongs.
local function onAutoReply(kind)
	return function(text, sender, _, _, _, _, _, _, _, _, _, guid)
		text, sender, guid = readableWhisper(text), readableOrNil(sender), readableOrNil(guid)
		if text == nil or sender == nil or sender == "" then return end
		local id = Compat.NormalizeName(sender)
		if not CM.Get(id) then return end
		-- An away message is their client answering, which is as good a proof
		-- that they are online as a typed reply -- and it carries the same GUID,
		-- which is where class and race come from. Both were being dropped.
		PlayerInfo.Observe(id, guid)
		PlayerInfo.NoteActivity(id)
		return CM.AddMessage(id, ns.DIR_IN, text, kind, replayTimestamp) ~= nil
	end
end

--------------------------------------------------------------------------------
-- System messages
--------------------------------------------------------------------------------

local notFoundPattern, friendOnlinePattern, friendOfflinePattern

-- Turns one of the client's own format strings into a Lua pattern that reads
-- the name back out of it. Built from the constant rather than hard coded, so
-- it works in every locale the game ships -- and returns nil when the constant
-- is missing, which is how a client without it ends up simply not using it.
local function toPattern(template)
	if type(template) ~= "string" then return nil end
	local escaped = template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	local pattern, captures = escaped:gsub("%%%%s", "(.-)")
	if captures == 0 then return nil end
	return "^" .. pattern .. "$"
end

local function buildSystemPatterns()
	notFoundPattern = toPattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S)
	friendOnlinePattern = toPattern(_G.ERR_FRIEND_ONLINE_SS)
	friendOfflinePattern = toPattern(_G.ERR_FRIEND_OFFLINE_S)
end

-- How far back an error is allowed to reach. The server answers within a second
-- or two; anything older than this belongs to a different attempt.
local NOT_FOUND_WINDOW = 30

-- "X has come online" / "X has gone offline". The client announces these for
-- friends and guildmates, and they are the only presence updates that arrive
-- without being asked for, so the status dot follows them live.
local function onFriendPresence(text)
	if not text then return end
	local name, online
	if friendOnlinePattern then
		local first, second = text:match(friendOnlinePattern)
		if first then name, online = second or first, true end
	end
	if not name and friendOfflinePattern then
		local only = text:match(friendOfflinePattern)
		if only then name, online = only, false end
	end
	if not name or name == "" then return end
	-- The online form carries the name inside a player link.
	name = name:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	name = name:gsub("^%[", ""):gsub("%]$", "")
	if name == "" then return end
	local id = Compat.NormalizeName(ns.Text.UpperFirst(name))
	if not id or not CM.Get(id) then return end
	PlayerInfo.Set(id, { online = online, presenceSource = "friend" })
	Debug.Log("events", "%s is now %s", id, online and "online" or "offline")
end

local function onSystem(text)
	text = readableOrNil(text)
	if text == nil then return end
	onFriendPresence(text)
	if not notFoundPattern then return end
	local name = text:match(notFoundPattern)
	if not name then return end
	name = name:gsub("^['\"]", ""):gsub("['\"%.]$", "")
	local id = Compat.NormalizeName(ns.Text.UpperFirst(name))
	if not id then return end
	local conv = CM.Get(id)
	if not conv then return end

	-- Two orderings, both real. On some clients the whisper is echoed back
	-- before the error arrives, which consumes the pending entry and leaves the
	-- bubble marked sent; on others the error is all that comes. So the pending
	-- queue is tried first, and if it has nothing left, the message the echo
	-- already marked as delivered is corrected. Without the second half the
	-- player is shown a perfectly ordinary sent message that never arrived.
	if not failPendingFor(id) then
		CM.FailLastOutgoing(conv, NOT_FOUND_WINDOW)
	end

	Debug.Log("events", "server reports no player named %s", id)
	conv.notFound = true
	PlayerInfo.Set(id, { online = false, presenceSource = "message" })
	ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
end

--------------------------------------------------------------------------------
-- Starting a whisper from the default chat box
--------------------------------------------------------------------------------

-- Opens the thread the player is about to write in, without stealing their
-- keystrokes: the default chat box keeps focus, so typing and pressing Enter
-- works exactly as it did. This only puts the conversation on screen.
function ChatEvents.OnComposeWhisper(target)
	local db = ns.db
	if not db or not db.profile or not db.profile.enabled then return end
	if not db.profile.messages.openOnCompose then return end
	if not target or target == "" then return end

	local id = Compat.NormalizeName(ns.Text.UpperFirst(target))
	Debug.Log("events", "composing a whisper to %s", id)
	CM.GetOrCreate(id)
	ns.UI.Show()
	CM.Select(id)
	ns.UI.EnsureConversationOpen(id, false)
end

--------------------------------------------------------------------------------
-- Chat frame suppression
--------------------------------------------------------------------------------

-- Can this event be consumed, and how?
--
-- One answer, asked in two places that must never disagree: the chat filter,
-- which decides whether to take the message out of the chat frame, and the
-- dispatcher, which decides what to do with it. The invariant the whole design
-- rests on is that a message is never both missing from here and hidden from
-- there, and the only way to guarantee that is for the same function to decide.
--
--   "store"  the handler can take it now, so the chat frame need not keep it
--   "hold"   it will be put aside and replayed, so the chat frame must keep it
--            until it comes back -- that copy is the only one there is
--   "pass"   it cannot be consumed at all, so the chat frame keeps it. Full stop
--
-- Every field of a chat event is one of three things:
--
--   REQUIRED   the message is not a message without it. Arg 1 is the text and
--              arg 2 is the other person -- the sender on an incoming whisper,
--              the target on the server's echo of an outgoing one.
--   OPTIONAL   fills something in. Arg 12 is the sender's GUID, which colours a
--              name by class. Withheld, it is dropped and the message handled
--              now: holding a whisper back over the decoration would trade the
--              message for the trimmings.
--   UNUSED     everything else. Never read, so never a problem.
--
-- Battle.net is the case that does not fit that pattern. Arg 13 is the account
-- id, and it is the only thing that says whose conversation this is. It is not
-- required, because it can be recovered from the account name beside it -- but
-- when neither works there is no honest answer, and "pass" is the only safe one.
--
-- CHAT_MSG_SYSTEM is absent entirely: those are read only to notice "no player
-- named" and friends coming online, and one missed costs nothing.
local ARG_TEXT, ARG_WHO, ARG_LINE, ARG_BNET = 1, 2, 11, 13
local REQUIRED = {
	CHAT_MSG_WHISPER = true,
	CHAT_MSG_WHISPER_INFORM = true,
	CHAT_MSG_BN_WHISPER = true,
	CHAT_MSG_BN_WHISPER_INFORM = true,
	CHAT_MSG_AFK = true,
	CHAT_MSG_DND = true,
}
local IS_BNET = {
	CHAT_MSG_BN_WHISPER = true,
	CHAT_MSG_BN_WHISPER_INFORM = true,
}
-- These two are only ever added to a conversation that already exists, so an
-- away message from a stranger is one the addon will not store.
local NEEDS_EXISTING = {
	CHAT_MSG_AFK = true,
	CHAT_MSG_DND = true,
}

local ADMIT_STORE, ADMIT_HOLD, ADMIT_PASS = "store", "hold", "pass"

-- The filter and the dispatcher can be called in either order for the same
-- message, and resolving a Battle.net account walks the friends list -- which
-- can change between the two calls. Remembering the last answer keeps them from
-- disagreeing about a message that is halfway through being handled.
local lastAdmission = {}

local function decide(event, ...)
	-- No contract here means nothing to check: the system and roster events read
	-- their own payload and decide for themselves. They are not in the chat
	-- filter either, so this answer only ever reaches the dispatcher.
	if not REQUIRED[event] then return ADMIT_STORE end

	-- 1. Anything the client is withholding that we cannot do without. Asked
	--    before a single one of them has been compared, tested or concatenated.
	local line = Compat.ReadableNumber((select(ARG_LINE, ...)))
	if Compat.IsSecretValue((select(ARG_TEXT, ...)))
		or Compat.IsSecretValue((select(ARG_WHO, ...))) then
		-- Recoverable only if there is a line id to ask the client about later.
		return line and ADMIT_HOLD or ADMIT_PASS
	end

	-- 2. Present, and actually usable. A nil sender, an empty one, or a number
	--    where a name should be is not something this addon can file anywhere.
	local text = Compat.ReadableText((select(ARG_TEXT, ...)))
	if text == nil or text == "" then return ADMIT_PASS end
	local who = Compat.ReadableText((select(ARG_WHO, ...)))
	if who == nil or who == "" then return ADMIT_PASS end

	-- 3. Battle.net: an identity, or nothing.
	if IS_BNET[event] then
		local accountID = ns.ChatEvents.ResolveBNIdentity((select(ARG_BNET, ...)), who)
		if not accountID then return ADMIT_PASS end
		return ADMIT_STORE, accountID
	end

	-- 4. An away message only ever joins a conversation that already exists.
	if NEEDS_EXISTING[event] and not CM.Get(Compat.NormalizeName(who)) then
		return ADMIT_PASS
	end

	return ADMIT_STORE
end

-- The same decision, asked afresh. A held message is reconstructed piece by
-- piece as the client gets round to answering, so each attempt is a different
-- occasion with different arguments: the memo below exists to keep the filter
-- and the live dispatcher agreeing about one event, and reusing it here would
-- answer a question about the message as it arrived rather than as it is now.
function ChatEvents.Reconsider(event, ...)
	return decide(event, ...)
end

-- The answer, memoised per chat line so both callers see the same one.
function ChatEvents.Admit(event, ...)
	local line = Compat.ReadableNumber((select(ARG_LINE, ...)))
	local key = line and (event .. ":" .. line) or nil
	if key and lastAdmission.key == key then
		return lastAdmission.mode, lastAdmission.detail
	end
	local mode, detail = decide(event, ...)
	if key then
		lastAdmission.key, lastAdmission.mode, lastAdmission.detail = key, mode, detail
	end
	return mode, detail
end

local function shouldHide()
	local db = ns.db
	if not db or not db.profile then return false end
	if not db.profile.enabled then return false end
	-- Failsafe: if the addon has been erroring, it stops taking whispers out of
	-- the chat frame. Better a duplicate than a message the player never sees.
	if ns.Debug.IsDegraded() then return false end
	return db.profile.messages.hideFromChatFrame
end

-- The client passes the frame and the event before the payload.
--
-- Only a message this addon will definitely have is taken out of the chat frame.
-- Anything it is merely holding, and anything it cannot use at all, stays where
-- the player can read it -- which for a held message is the only copy there is,
-- and for an unusable one is the only copy there will ever be.
local function suppressFilter(_, event, ...)
	if not shouldHide() then return false end
	return ChatEvents.Admit(event, ...) == ADMIT_STORE
end

--------------------------------------------------------------------------------
-- Event plumbing
--------------------------------------------------------------------------------

local handlers = {
	CHAT_MSG_WHISPER = onWhisper,
	CHAT_MSG_WHISPER_INFORM = onWhisperInform,
	CHAT_MSG_BN_WHISPER = onBNWhisper,
	CHAT_MSG_BN_WHISPER_INFORM = onBNWhisperInform,
	CHAT_MSG_AFK = onAutoReply(ns.MSG_AFK),
	CHAT_MSG_DND = onAutoReply(ns.MSG_DND),
	CHAT_MSG_SYSTEM = onSystem,
}

local rosterHandlers = {
	GUILD_ROSTER_UPDATE = function() PlayerInfo.ScanGuild() end,
	FRIENDLIST_UPDATE = function() PlayerInfo.ScanFriends() end,
	WHO_LIST_UPDATE = function() PlayerInfo.HandleWhoResults() end,
	BN_FRIEND_INFO_CHANGED = function() ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, nil) end,
}

frame:SetScript("OnEvent", function(_, event, ...)
	local db = ns.db
	if not db or not db.profile.enabled then
		-- Roster bookkeeping still runs; message routing does not.
		local roster = rosterHandlers[event]
		if roster then ns.Guard(event, roster) end
		return
	end
	local handler = handlers[event] or rosterHandlers[event]
	if not handler then return end

	-- The same decision the chat filter made, from the same function, so the two
	-- cannot disagree about whether this message is anyone's to keep.
	local mode, identity = ChatEvents.Admit(event, ...)

	if mode == ADMIT_HOLD then
		-- Put aside with its chat line id, and back the moment the client will
		-- answer for that line. This is what makes a whisper sent to you in an
		-- arena end up in its thread instead of only in the chat frame.
		unreadable = unreadable + 1
		if ns.Deferred.Hold(event, ...) then
			Debug.NoteWithheld()
		else
			Debug.NoteUnreadable()
		end
		return
	end

	if mode ~= ADMIT_STORE then
		-- Nothing to file it under. The chat frame was told to keep it, which is
		-- the whole reason declining here is safe.
		unreadable = unreadable + 1
		Debug.Log("events", "%s cannot be filed anywhere; left in the chat frame",
			event)
		return
	end

	admittedBNAccountID = identity
	ns.Guard(event, handler, ...)
	admittedBNAccountID = nil
end)

-- How a message that was put aside gets back in. `args` is the original event's
-- arguments with the three the client withheld filled in from the chat line,
-- and `args.timestamp` is when it actually arrived rather than when we caught
-- up -- a thread that reorders itself after an arena is worse than one that was
-- briefly behind.
-- Returns whether the message was actually committed to the model -- stored, or
-- matched to one already there. Not whether the handler ran without throwing:
-- a handler that threw on its way to AddMessage stored nothing, and treating
-- that as delivered throws the message away.
local function replay(event, args, identity)
	local handler = handlers[event]
	if not handler then return false end
	replayTimestamp = args.timestamp
	replayCensoredLine = args.censored and args.lineID or false
	admittedBNAccountID = identity
	local ran, committed = pcall(handler, unpack(args, 1, 20))
	replayTimestamp, replayCensoredLine, admittedBNAccountID = nil, nil, nil
	if not ran then
		ns.SoftError("Deferred." .. event, committed)
		return false
	end
	return committed == true
end

function ChatEvents.Init()
	myName = Compat.PlayerName()
	buildSystemPatterns()
	ns.Deferred.SetDispatcher(replay)

	for event in pairs(handlers) do
		if not Compat.RegisterEventSafe(frame, event) then
			ns.SoftError("ChatEvents", "event unavailable: " .. event)
		else
			Debug.Log("compat", "registered %s", event)
		end
	end
	for event in pairs(rosterHandlers) do
		Compat.RegisterEventSafe(frame, event)
	end

	-- Typing "/w Thrall" in the default chat box means the player is about to
	-- write to somebody, which is exactly the moment the thread should be in
	-- front of them -- before the message is sent, not after.
	if not Compat.HookWhisperCompose(ChatEvents.OnComposeWhisper) then
		Debug.Log("compat", "chat compose hook unavailable on this client")
	end

	-- Registered once; the filter itself checks the setting so toggling it never
	-- has to add or remove filters (which is where double-registration bugs live).
	Compat.AddMessageEventFilter("CHAT_MSG_WHISPER", suppressFilter)
	Compat.AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", suppressFilter)
	if Compat.hasBattleNet then
		Compat.AddMessageEventFilter("CHAT_MSG_BN_WHISPER", suppressFilter)
		Compat.AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", suppressFilter)
	end

	Compat.RequestGuildRoster()
end

function ChatEvents.Shutdown()
	frame:UnregisterAllEvents()
	Compat.RemoveMessageEventFilter("CHAT_MSG_WHISPER", suppressFilter)
	Compat.RemoveMessageEventFilter("CHAT_MSG_WHISPER_INFORM", suppressFilter)
	Compat.RemoveMessageEventFilter("CHAT_MSG_BN_WHISPER", suppressFilter)
	Compat.RemoveMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", suppressFilter)
end
