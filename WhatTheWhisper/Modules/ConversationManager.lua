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

-- How long the same refusal stays quiet after it has been said once. A player
-- who cannot send presses Enter again, and again -- that is what people do --
-- and repeating the explanation once per press fills the chat frame with the
-- addon's own voice at the exact moment the addon is being unhelpful.
local REFUSAL_QUIET_SECONDS = 30
local lastRefusalAt
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
			-- A chat line id means nothing in a new session. The fact that a
			-- message is hidden is kept; the way to ask about it is not, so the
			-- reveal is simply not offered for anything from before the reload.
			for i = 1, #rec.msgs do
				local msg = rec.msgs[i]
				if type(msg) == "table" then msg[ns.MSG_LINE] = nil end
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

-- What a message reads as, which is not always what was stored.
--
-- The game's own chat filter can hide a line. The addon has the placeholder the
-- client handed over, not the words, and it is not the addon's business to work
-- around somebody else's moderation -- so the message says plainly that it is
-- hidden, and offers the player the one thing the client allows: asking for it.
--
-- Once the player has asked, the client answers for that line and the real text
-- takes its place, so this checks rather than caches.
function CM.MessageText(msg)
	if not msg then return "" end
	-- The durable flag alone, never the chat line. An id that has gone stale
	-- must not turn a hidden message back into the placeholder the client handed
	-- over, which is what the player would then read as the message.
	if msg[ns.MSG_CENSORED] then
		return ns.L["Message hidden by the game's chat filter."]
	end
	return msg[MSG_TEXT] or ""
end

-- Whether there is still something to ask the client about. False after a
-- reload, when the id is meaningless, and false once the line has aged out.
function CM.CanReveal(msg)
	if not msg or not msg[ns.MSG_CENSORED] then return false end
	local line = msg[ns.MSG_LINE]
	if type(line) ~= "number" then return false end
	if Compat.IsValidChatLine(line) == false then return false end
	return Compat.IsChatLineCensored(line)
end

-- The player asked to see one. Only ever from a click: revealing a line somebody
-- chose to filter is their decision, not ours, and the client enforces that too.
--
-- Returns true only when real text actually arrived. Asking and getting nothing
-- back leaves the message hidden, because the alternative is showing the raw
-- placeholder as though it were what they wrote.
function CM.RevealMessage(conv, msg)
	if not CM.CanReveal(msg) then return false end
	local line = msg[ns.MSG_LINE]
	Compat.UncensorChatLine(line)

	-- UncensorChatLine says nothing about whether it worked, so the client is
	-- asked again rather than taken on trust. A line the client still calls
	-- censored has not been revealed, whatever text it hands over -- and that
	-- text is the placeholder, which must never be promoted into the durable
	-- record as though it were what somebody wrote.
	if Compat.IsChatLineCensored(line) then
		ns.Debug.Log("events", "chat line %d is still censored after asking", line)
		return false
	end

	local text = Compat.GetChatLine(line)
	if not text or text == "" then
		ns.Debug.Log("events", "uncensoring chat line %d gave nothing back", line)
		return false
	end
	msg[MSG_TEXT] = text
	msg[ns.MSG_CENSORED] = nil
	msg[ns.MSG_LINE] = nil
	CM.InvalidatePreview(msg)
	if conv then ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv) end
	return true
end

function CM.AddMessage(id, direction, text, kind, timestamp, status, opts)
	local conv = CM.GetOrCreate(id, opts)
	if not conv then return nil end

	local msg = { timestamp or Compat.GetServerTime(), direction, text, kind or ns.MSG_WHISPER }
	if status then msg[MSG_STATUS] = status end
	-- Only for a line the game's own filter is hiding: that it is hidden, which
	-- outlives the session, and which line to ask about, which does not.
	if opts and opts.censoredLine then
		msg[ns.MSG_CENSORED] = true
		msg[ns.MSG_LINE] = opts.censoredLine
	end

	History.Append(conv, msg)

	conv.lastActivity = msg[MSG_TS]
	orderDirty = true

	if direction == ns.DIR_IN then
		-- They wrote, so they exist and they are online: whatever the server
		-- said about the name earlier is stale.
		conv.notFound = nil
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

-- Marks the most recent outgoing message as not delivered.
--
-- The server's "no player named" answer arrives after the client has already
-- echoed the whisper back, so by then the bubble usually says sent. Only ever
-- touching pending messages would leave a delivered-looking bubble for a message
-- nobody received, which is the one thing delivery state exists to prevent.
--
-- Exactly one message is failed per call, because the server sends one error per
-- whisper -- a long message split into parts produces one error for each part.
function CM.FailLastOutgoing(conv, maxAge)
	if not conv then return nil end
	local list = conv.messages
	if not list then return nil end
	local now = Compat.GetServerTime()
	for i = #list, math.max(1, #list - 20), -1 do
		local m = list[i]
		if m and m[MSG_DIR] == ns.DIR_OUT
			and m[MSG_STATUS] ~= ns.SEND_FAILED
			and (now - (m[MSG_TS] or 0)) <= (maxAge or 30) then
			m[MSG_STATUS] = ns.SEND_FAILED
			ns.Bus.Fire(ns.EV.MESSAGE_UPDATED, conv, m, i)
			return m, i
		end
	end
	return nil
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

-- Selecting a thread is the player looking at it, so it clears the unread mark
-- -- unless they have asked it not to. That setting had a checkbox and no
-- effect: the mark was cleared unconditionally, so switching it off did nothing.
local function markReadIfWanted(id)
	if ns.Setting("messages.markReadOnFocus") then CM.MarkRead(id) end
end

function CM.Select(id, silent)
	if id and not conversations[id] then return end
	if selectedID == id then
		if id then markReadIfWanted(id) end
		return
	end
	local previous = selectedID
	selectedID = id
	if id then markReadIfWanted(id) end
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

	-- The client refuses chat sent by an addon in an arena or a rated
	-- battleground. What somebody typed stays in the box, because dropping it
	-- silently is the one outcome worse than not being able to send it.
	--
	-- Said out loud the first time and then not again for a while. The refusal
	-- is the same every time and the player has already read it; what they need
	-- after that is the text still sitting in the composer, which they have.
	if Compat.OutgoingChatRestricted() then
		local now = Compat.GetServerTime()
		if not lastRefusalAt or (now - lastRefusalAt) >= REFUSAL_QUIET_SECONDS then
			lastRefusalAt = now
			ns.Print(ns.L["Whispers cannot be sent from here. Use the game's own chat box."])
		end
		return false
	end
	-- Sending worked, so the next refusal is news again.
	lastRefusalAt = nil

	local parts = ns.Text.SplitForSend(text, ns.MAX_MESSAGE_BYTES)
	local sentAny = false

	-- Every attempt starts from a clean slate: they may have logged in since
	-- the last one. If they still are not there, the server says so again.
	conv.notFound = nil

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
-- A name the player chose for somebody, or nil.
--
-- Display only, and deliberately so: XxlegolasxX-TarrenMill is who the message
-- goes to whatever it says on the thread, and a nickname that quietly changed
-- the recipient would be a nickname that sent a whisper to the wrong person.
function CM.GetAlias(id)
	local db = ns.db
	local aliases = db and db.profile and db.profile.aliases
	local alias = aliases and aliases[id]
	if type(alias) == "string" and alias ~= "" then return alias end
	return nil
end

function CM.SetAlias(id, alias)
	-- The real table, not ns.Setting's answer: this one is written to, and
	-- ns.Setting hands back the shipped defaults when the section is gone.
	local store = ns.db and ns.db.profile and ns.db.profile.aliases
	if not store or not id then return end
	alias = alias and ns.Text.Trim(alias) or nil
	if alias == "" then alias = nil end
	if store[id] == alias then return end
	store[id] = alias
	local conv = CM.Get(id)
	if conv then ns.Bus.Fire(ns.EV.CONVERSATION_UPDATED, conv) end
end

-- Who they actually are, for the line under the nickname. nil when there is no
-- nickname, because then the name above it already says it.
function CM.RealNameIfAliased(conv)
	if not conv or not CM.GetAlias(conv.id) then return nil end
	if conv.isBN then return conv.battleTag or conv.name end
	return conv.id
end

function CM.DisplayName(conv)
	if not conv then return "" end
	local alias = CM.GetAlias(conv.id)
	if alias then return alias end
	if conv.isBN then return conv.name or conv.id end
	local base = Compat.ShortName(conv.id)
	-- On Forever the realm is an internal detail the player never sees.
	if not Compat.namesHaveRealms then return base end
	local mode = ns.Setting("messages.showRealm") or "cross"
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

-- Forgets one line of the sidebar. Called when a message's text changes under
-- it, which happens exactly once in this addon's life: when the player reveals
-- something the game was hiding.
function CM.InvalidatePreview(msg)
	if msg then previewCache[msg] = nil end
end

function CM.Preview(conv)
	local msg = CM.LastMessage(conv)
	if not msg then return nil end
	local cached = previewCache[msg]
	if cached then return cached, msg[MSG_DIR] end
	-- What the bubble says, not what is stored: a message the game is hiding
	-- reads as hidden in the sidebar too, rather than as the placeholder.
	local text = ns.Text.Strip(CM.MessageText(msg))
	text = text:gsub("%s+", " ")
	previewCache[msg] = text
	return text, msg[MSG_DIR]
end
