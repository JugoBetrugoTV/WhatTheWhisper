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

local function bnConversationID(bnSenderID, accountName)
	local cached = bnKeyCache[bnSenderID]
	if cached then return cached.id, cached.name or accountName, cached.tag end
	local battleTag, name = Compat.GetBNAccountInfoByID(bnSenderID)
	local id = battleTag and ("BN:" .. battleTag)
		or ("BN:" .. tostring(accountName or bnSenderID))
	local entry = { id = id, name = name or accountName, tag = battleTag }
	if battleTag then bnKeyCache[bnSenderID] = entry end
	return entry.id, entry.name, entry.tag
end

--------------------------------------------------------------------------------
-- Incoming
--------------------------------------------------------------------------------

local function onWhisper(text, sender, _, _, _, flags, _, _, _, _, _, guid)
	if not sender or sender == "" then return end
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

	local msg = CM.AddMessage(id, ns.DIR_IN, text, kind)
	ns.Notifications.OnIncoming(conv, msg, isMention(text))
end

local function onWhisperInform(text, target, _, _, _, _, _, _, _, _, _, guid)
	if not target or target == "" then return end
	local id = Compat.NormalizeName(target)
	PlayerInfo.Observe(id, guid)

	if resolvePending(id, text) then return end

	-- Sent from the default chat frame or another addon: adopt it.
	CM.AddMessage(id, ns.DIR_OUT, text, ns.MSG_WHISPER, nil, ns.SEND_OK)
	if ns.db.profile.messages.openOnSend then
		ns.UI.EnsureConversationOpen(id, true)
	end
end

local function onBNWhisper(text, accountName, _, _, _, _, _, _, _, _, _, _, bnSenderID)
	if not bnSenderID then return end
	local id, name, tag = bnConversationID(bnSenderID, accountName)
	local conv = CM.GetOrCreate(id, {
		name = name or accountName, battleTag = tag, bnetAccountID = bnSenderID,
	})
	conv.bnetAccountID = bnSenderID
	local msg = CM.AddMessage(id, ns.DIR_IN, text, ns.MSG_BNET)
	ns.Notifications.OnIncoming(conv, msg, isMention(text))
end

local function onBNWhisperInform(text, accountName, _, _, _, _, _, _, _, _, _, _, bnSenderID)
	if not bnSenderID then return end
	local id = select(1, bnConversationID(bnSenderID, accountName))
	if resolvePending(id, text) then return end
	CM.AddMessage(id, ns.DIR_OUT, text, ns.MSG_BNET, nil, ns.SEND_OK)
end

-- The target's away/busy auto-reply. Shown inside the thread, where it belongs.
local function onAutoReply(kind)
	return function(text, sender)
		if not sender or sender == "" then return end
		local id = Compat.NormalizeName(sender)
		if not CM.Get(id) then return end
		CM.AddMessage(id, ns.DIR_IN, text, kind)
	end
end

--------------------------------------------------------------------------------
-- System messages
--------------------------------------------------------------------------------

local notFoundPattern
local function buildSystemPatterns()
	local template = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
	if type(template) == "string" then
		notFoundPattern = "^" .. template
			:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
			:gsub("%%%%s", "(.+)") .. "$"
	end
end

local function onSystem(text)
	if not notFoundPattern or not text then return end
	local name = text:match(notFoundPattern)
	if not name then return end
	name = name:gsub("^['\"]", ""):gsub("['\"%.]$", "")
	local id = Compat.NormalizeName(name)
	if failPendingFor(id) then
		local conv = CM.Get(id)
		if conv then
			PlayerInfo.Set(id, { online = false })
			ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
		end
	end
end

--------------------------------------------------------------------------------
-- Chat frame suppression
--------------------------------------------------------------------------------

local function shouldHide()
	local db = ns.db
	return db and db.profile and db.profile.enabled and db.profile.messages.hideFromChatFrame
end

local function suppressFilter()
	return shouldHide()
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
	if handler then
		ns.Guard(event, handler, ...)
	end
end)

function ChatEvents.Init()
	myName = UnitName("player")
	buildSystemPatterns()

	for event in pairs(handlers) do
		if not Compat.RegisterEventSafe(frame, event) then
			ns.SoftError("ChatEvents", "event unavailable: " .. event)
		end
	end
	for event in pairs(rosterHandlers) do
		Compat.RegisterEventSafe(frame, event)
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
