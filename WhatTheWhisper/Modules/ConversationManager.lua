-- WhatTheWhisper -- The conversation model.
--
-- One thread per player. This module owns the data; the UI only reads it and
-- listens for the bus events fired here.

local _, ns = ...
local Compat, History, PlayerInfo = ns.Compat, ns.History, ns.PlayerInfo

local CM = {}
ns.ConversationManager = CM

local MSG_TS, MSG_DIR, MSG_TEXT, MSG_STATUS =
	ns.MSG_TS, ns.MSG_DIR, ns.MSG_TEXT, ns.MSG_STATUS

local conversations = {}
local orderCache = {}
local orderDirty = true
local selectedID
local totalUnread = 0

local sort, wipe = table.sort, wipe

--------------------------------------------------------------------------------
-- Creation
--------------------------------------------------------------------------------

local function newConversation(id, opts)
	opts = opts or {}
	local isBN = Compat.IsBattleNet(id)
	local conv = {
		id           = id,
		isBN         = isBN,
		name         = opts.name or (isBN and id:gsub("^BN:", "") or Compat.ShortName(id)),
		fullName     = not isBN and id or nil,
		realm        = not isBN and Compat.RealmOf(id) or nil,
		battleTag    = opts.battleTag or (isBN and id:gsub("^BN:", "") or nil),
		bnetAccountID = opts.bnetAccountID,
		class        = opts.class,
		level        = opts.level,
		faction      = opts.faction,
		messages     = nil,
		record       = nil,
		unread       = 0,
		lastActivity = 0,
		pinned       = false,
		muted        = false,
		draft        = "",
		lastSoundAt  = 0,
		scrollPinned = true,
		scrollOffset = 0,
		open         = false,   -- has a tab / popout
		poppedOut    = false,
	}

	local rec = History.IsPersistent() and History.GetRecord(id, true) or nil
	if rec then
		conv.record = rec
		conv.messages = rec.msgs
		conv.name = rec.n or conv.name
		conv.class = rec.c or conv.class
		conv.level = rec.lv or conv.level
		conv.faction = rec.f or conv.faction
		conv.battleTag = rec.bt or conv.battleTag
		conv.lastActivity = rec.t or 0
		conv.unread = rec.u or 0
		conv.pinned = rec.p and true or false
		conv.muted = rec.m and true or false
	else
		conv.messages = {}
	end

	if conv.class then
		PlayerInfo.Set(id, { class = conv.class, level = conv.level })
	end
	return conv
end

function CM.Get(id)
	return conversations[id]
end

function CM.GetOrCreate(id, opts)
	if not id then return nil end
	local conv = conversations[id]
	if conv then
		if opts then
			if opts.class and not conv.class then conv.class = opts.class end
			if opts.bnetAccountID then conv.bnetAccountID = opts.bnetAccountID end
			if opts.name and conv.isBN then conv.name = opts.name end
		end
		return conv
	end
	conv = newConversation(id, opts)
	conversations[id] = conv
	totalUnread = totalUnread + conv.unread
	orderDirty = true
	ns.Debug.Log("events", "conversation created: %s", tostring(id))
	ns.Bus.Fire(ns.EV.CONVERSATION_ADDED, conv)
	return conv
end

function CM.All()
	return conversations
end

function CM.Count()
	local n = 0
	for _ in pairs(conversations) do n = n + 1 end
	return n
end

--------------------------------------------------------------------------------
-- Loading persisted threads at login
--------------------------------------------------------------------------------

function CM.LoadPersisted()
	local records = History.AllRecords()
	if not records then return end
	for id, rec in pairs(records) do
		if type(rec) == "table" and rec.msgs then
			local conv = CM.GetOrCreate(id)
			-- unread counts do not survive a session: you have seen them by now
			if conv.unread > 0 then
				totalUnread = totalUnread - conv.unread
				conv.unread = 0
				if conv.record then conv.record.u = nil end
			end
		end
	end
	orderDirty = true
	ns.Debug.Log("history", "loaded %d persisted conversations", CM.Count())
	ns.Bus.Fire(ns.EV.UNREAD_CHANGED, totalUnread)
end

--------------------------------------------------------------------------------
-- Ordering
--------------------------------------------------------------------------------

local function compare(a, b)
	if a.pinned ~= b.pinned then return a.pinned end
	if a.lastActivity ~= b.lastActivity then return a.lastActivity > b.lastActivity end
	return a.name < b.name
end

-- Sorted list: pinned first, then most recent activity. Rebuilt lazily, so a
-- burst of ten messages costs one sort, not ten.
function CM.Ordered()
	if orderDirty then
		wipe(orderCache)
		for _, conv in pairs(conversations) do
			orderCache[#orderCache + 1] = conv
		end
		sort(orderCache, compare)
		orderDirty = false
	end
	return orderCache
end

function CM.Invalidate()
	orderDirty = true
end

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

function CM.AddMessage(id, direction, text, kind, timestamp, status, opts)
	local conv = CM.GetOrCreate(id, opts)
	if not conv then return nil end

	local msg = { timestamp or Compat.GetServerTime(), direction, text, kind or ns.MSG_WHISPER }
	if status then msg[MSG_STATUS] = status end

	History.Append(conv, msg)

	conv.lastActivity = msg[MSG_TS]
	orderDirty = true

	if direction == ns.DIR_IN then
		if selectedID ~= id or not ns.UI or not ns.UI.IsConversationVisible(id) then
			conv.unread = conv.unread + 1
			totalUnread = totalUnread + 1
			ns.Bus.Fire(ns.EV.UNREAD_CHANGED, totalUnread)
		end
	end

	if conv.record then History.WriteMeta(conv) end

	ns.Bus.Fire(ns.EV.MESSAGE_ADDED, conv, msg, #conv.messages)
	ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
	return msg, #conv.messages
end

function CM.UpdateMessageStatus(conv, index, status)
	local msg = conv and conv.messages[index]
	if not msg then return end
	if msg[MSG_STATUS] == status then return end
	msg[MSG_STATUS] = status
	ns.Bus.Fire(ns.EV.MESSAGE_UPDATED, conv, msg, index)
end

-- Finds the most recent outgoing message matching `text` that is still pending.
function CM.FindPendingOutgoing(conv, text)
	if not conv then return nil end
	local list = conv.messages
	for i = #list, math.max(1, #list - 12), -1 do
		local m = list[i]
		if m and m[MSG_DIR] == ns.DIR_OUT
			and (m[MSG_STATUS] == ns.SEND_PENDING or m[MSG_STATUS] == nil)
			and m[MSG_TEXT] == text then
			return i, m
		end
	end
	return nil
end

function CM.LastMessage(conv)
	local list = conv.messages
	return list[#list]
end

--------------------------------------------------------------------------------
-- Read state
--------------------------------------------------------------------------------

function CM.MarkRead(id)
	local conv = conversations[id]
	if not conv or conv.unread == 0 then return end
	totalUnread = totalUnread - conv.unread
	if totalUnread < 0 then totalUnread = 0 end
	conv.unread = 0
	if conv.record then conv.record.u = nil end
	ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
	ns.Bus.Fire(ns.EV.UNREAD_CHANGED, totalUnread)
end

function CM.MarkUnread(id)
	local conv = conversations[id]
	if not conv or conv.unread > 0 then return end
	conv.unread = 1
	totalUnread = totalUnread + 1
	if conv.record then conv.record.u = 1 end
	ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
	ns.Bus.Fire(ns.EV.UNREAD_CHANGED, totalUnread)
end

function CM.TotalUnread()
	return totalUnread
end

--------------------------------------------------------------------------------
-- Selection
--------------------------------------------------------------------------------

function CM.Select(id, silent)
	if id and not conversations[id] then return end
	if selectedID == id then
		if id then CM.MarkRead(id) end
		return
	end
	local previous = selectedID
	selectedID = id
	if id then CM.MarkRead(id) end
	ns.Bus.Fire(ns.EV.CONVERSATION_SELECTED, id, previous, silent)
end

function CM.Selected()
	return selectedID and conversations[selectedID] or nil
end

function CM.SelectedID()
	return selectedID
end

--------------------------------------------------------------------------------
-- Flags
--------------------------------------------------------------------------------

function CM.SetPinned(id, pinned)
	local conv = conversations[id]
	if not conv then return end
	conv.pinned = pinned and true or false
	if conv.record then conv.record.p = conv.pinned or nil end
	orderDirty = true
	ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
	ns.Bus.Fire(ns.EV.LAYOUT_CHANGED)
end

function CM.SetMuted(id, muted)
	local conv = conversations[id]
	if not conv then return end
	conv.muted = muted and true or false
	if conv.record then conv.record.m = conv.muted or nil end
	ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
end

function CM.SetDraft(id, text)
	local conv = conversations[id]
	if conv then conv.draft = text or "" end
end

--------------------------------------------------------------------------------
-- Removal
--------------------------------------------------------------------------------

function CM.Remove(id)
	local conv = conversations[id]
	if not conv then return end
	if conv.unread > 0 then
		totalUnread = math.max(0, totalUnread - conv.unread)
		ns.Bus.Fire(ns.EV.UNREAD_CHANGED, totalUnread)
	end
	conversations[id] = nil
	orderDirty = true
	local records = History.AllRecords()
	if records then records[id] = nil end
	if selectedID == id then
		selectedID = nil
		local ordered = CM.Ordered()
		CM.Select(ordered[1] and ordered[1].id or nil)
	end
	ns.Bus.Fire(ns.EV.CONVERSATION_REMOVED, id)
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

-- Splits over-long input into whisper-legal chunks, sends each, and records a
-- pending bubble so delivery state can be reconciled from the server's echo.
function CM.SendMessage(id, text)
	local conv = CM.GetOrCreate(id)
	if not conv then return false end
	text = ns.Text.Trim(text or "")
	if text == "" then return false end

	local parts = ns.Text.SplitForSend(text, ns.MAX_MESSAGE_BYTES)
	local sentAny = false

	for i = 1, #parts do
		local part = parts[i]
		local ok
		if conv.isBN then
			local accountID = conv.bnetAccountID or Compat.ResolveBNAccountID(conv.battleTag)
			if accountID then
				conv.bnetAccountID = accountID
				ok = Compat.SendBNWhisper(accountID, part)
			else
				ok = false
			end
		else
			ok = Compat.SendWhisper(conv.id, part)
		end

		local kind = conv.isBN and ns.MSG_BNET or ns.MSG_WHISPER
		if ok then
			sentAny = true
			-- The bubble appears immediately; the server echo upgrades it from
			-- pending to sent, or the "no player named" error marks it failed.
			local msg = CM.AddMessage(conv.id, ns.DIR_OUT, part, kind, nil, ns.SEND_PENDING)
			ns.ChatEvents.RegisterPending(conv.id, part, msg)
		else
			CM.AddMessage(conv.id, ns.DIR_OUT, part, kind, nil, ns.SEND_FAILED)
		end
	end

	if sentAny and #parts > 1 then
		ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv)
	end
	return sentAny, #parts
end

--------------------------------------------------------------------------------
-- Display name
--------------------------------------------------------------------------------

-- Honours messages.showRealm: never, only for cross-realm players, or always.
-- Computed on render rather than stored, so changing the setting takes effect
-- everywhere at once instead of only for new conversations.
function CM.DisplayName(conv)
	if not conv then return "" end
	if conv.isBN then return conv.name or conv.id end
	local base = Compat.ShortName(conv.id)
	local mode = (ns.db and ns.db.profile.messages.showRealm) or "cross"
	if mode == "never" then return base end
	local realm = Compat.RealmOf(conv.id)
	if not realm then return base end
	if mode == "always" then return base .. "-" .. realm end
	if Compat.IsCrossRealm(conv.id) then return base .. "-" .. realm end
	return base
end

--------------------------------------------------------------------------------
-- Preview text for the sidebar
--------------------------------------------------------------------------------

local previewCache = setmetatable({}, { __mode = "k" })

function CM.Preview(conv)
	local msg = CM.LastMessage(conv)
	if not msg then return nil end
	local cached = previewCache[msg]
	if cached then return cached, msg[MSG_DIR] end
	local text = ns.Text.Strip(msg[MSG_TEXT] or "")
	text = text:gsub("%s+", " ")
	previewCache[msg] = text
	return text, msg[MSG_DIR]
end
