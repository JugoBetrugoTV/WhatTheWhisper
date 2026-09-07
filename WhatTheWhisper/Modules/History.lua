-- WhatTheWhisper -- Message persistence.
--
-- History lives in its own SavedVariable (WhatTheWhisperHistoryDB) so profile
-- copies, resets and imports can never duplicate or destroy it.
--
-- The in-memory message list *is* the saved table while history is enabled, so
-- appending a message is a single insert with no second copy. Turning history
-- off or on migrates between the saved table and a volatile one.

local _, ns = ...
local Compat = ns.Compat

local History = {}
ns.History = History

local wipe = wipe
local floor, max = math.floor, math.max

local MSG_TS, MSG_TEXT = ns.MSG_TS, ns.MSG_TEXT

local root      -- WhatTheWhisperHistoryDB
local charStore -- root.chars[playerKey]

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

-- Read one history setting.
--
-- Deliberately per key rather than "grab the table once": AceDB strips values
-- that equal their default out of the profile during PLAYER_LOGOUT so they are
-- not written to the SavedVariables file, and handler order at logout is not
-- defined. Pruning runs at logout, so it has to survive reading a stripped
-- table -- hence the explicit fallback to the shipped defaults.
local function setting(key)
	local db = ns.db
	local profile = db and db.profile and db.profile.history
	local value = profile and profile[key]
	if value == nil then value = ns.defaults.profile.history[key] end
	return value
end
History.Setting = setting

function History.IsPersistent()
	local r = setting("retention")
	return r ~= "off" and r ~= "session"
end

function History.Init()
	root = _G.WhatTheWhisperHistoryDB
	if type(root) ~= "table" then
		root = {}
		_G.WhatTheWhisperHistoryDB = root
	end
	-- Structural repair first: a file damaged mid-write must not take the
	-- migration runner (or the first render) down with it.
	local repaired = ns.Migrations.Repair(root)
	if repaired > 0 then
		ns.SoftError("History", ("repaired %d damaged entries"):format(repaired))
	end
	ns.Migrations.Run(ns.db, root)

	local key = Compat.PlayerFullName()
	local store = root.chars[key]
	if type(store) ~= "table" then
		store = { conv = {} }
		root.chars[key] = store
	end
	store.conv = store.conv or {}
	store.lastLogin = time()
	charStore = store

	History.Prune()
end

function History.GetCharStore()
	return charStore
end

--------------------------------------------------------------------------------
-- Records
--------------------------------------------------------------------------------

-- Returns the persistent record for a conversation, creating it on demand.
-- Returns nil when history is disabled -- callers then keep messages in memory.
function History.GetRecord(id, create)
	if not charStore then return nil end
	local rec = charStore.conv[id]
	if rec then return rec end
	if not create then return nil end
	rec = { msgs = {}, t = 0, u = 0 }
	charStore.conv[id] = rec
	return rec
end

function History.AllRecords()
	if not charStore then return nil end
	return charStore.conv
end

--------------------------------------------------------------------------------
-- Appending and trimming
--------------------------------------------------------------------------------

-- Removing one element at a time from the front of a 2000 entry array on every
-- single message would be quadratic. Instead the list is allowed to overshoot
-- and then trimmed in one pass.
local TRIM_SLACK = 0.10

function History.Trim(messages, limit)
	limit = limit or setting("maxPerConversation")
	if limit <= 0 then return end
	local n = #messages
	local ceiling = limit + max(16, floor(limit * TRIM_SLACK))
	if n <= ceiling then return end
	local drop = n - limit
	for i = 1, limit do
		messages[i] = messages[i + drop]
	end
	for i = limit + 1, n do
		messages[i] = nil
	end
end

function History.Append(conv, message)
	local list = conv.messages
	list[#list + 1] = message
	History.Trim(list, setting("maxPerConversation"))
	if conv.record then
		conv.record.t = message[MSG_TS]
	end
end

--------------------------------------------------------------------------------
-- Pruning
--------------------------------------------------------------------------------

local function retentionCutoff()
	local seconds = ns.RETENTION_SECONDS[setting("retention")]
	if not seconds or seconds < 0 then return nil end   -- forever / session
	if seconds == 0 then return math.huge end           -- off: drop everything
	return time() - seconds
end

-- Drops messages older than the retention window and conversations that are
-- empty or beyond the conversation cap. Runs at login and when the retention
-- setting changes; never on a message event.
function History.Prune()
	if not charStore then return 0, 0 end
	local conv = charStore.conv
	local cutoff = retentionCutoff()
	local removedMessages, removedConversations = 0, 0
	local limit = setting("maxPerConversation")

	for _, rec in pairs(conv) do
		local msgs = rec.msgs
		if type(msgs) ~= "table" then
			msgs = {}
			rec.msgs = msgs
		end
		if cutoff == math.huge then
			removedMessages = removedMessages + #msgs
			wipe(msgs)
		elseif cutoff then
			local first = 1
			local n = #msgs
			while first <= n do
				local m = msgs[first]
				if type(m) ~= "table" or (m[MSG_TS] or 0) >= cutoff then break end
				first = first + 1
			end
			if first > 1 then
				removedMessages = removedMessages + (first - 1)
				local write = 1
				for i = first, n do
					msgs[write] = msgs[i]
					write = write + 1
				end
				for i = write, n do msgs[i] = nil end
			end
		end
		History.Trim(msgs, limit)
	end

	-- Conversation cap: keep pinned threads and the most recently active ones.
	local maxConv = setting("maxConversations") or 0
	local ordered = {}
	for convID, rec in pairs(conv) do
		ordered[#ordered + 1] = { id = convID, rec = rec }
	end
	if maxConv > 0 and #ordered > maxConv then
		table.sort(ordered, function(a, b)
			local pa, pb = a.rec.p and 1 or 0, b.rec.p and 1 or 0
			if pa ~= pb then return pa > pb end
			return (a.rec.t or 0) > (b.rec.t or 0)
		end)
		for i = maxConv + 1, #ordered do
			local entry = ordered[i]
			if not entry.rec.p then
				conv[entry.id] = nil
				removedConversations = removedConversations + 1
			end
		end
	end

	-- Empty, unpinned records carry no value.
	for id, rec in pairs(conv) do
		if (not rec.msgs or #rec.msgs == 0) and not rec.p then
			conv[id] = nil
			removedConversations = removedConversations + 1
		end
	end

	return removedMessages, removedConversations
end

-- Called when the retention setting changes: moves messages between the saved
-- table and volatile memory so the change takes effect immediately.
function History.ApplyRetention()
	local persistent = History.IsPersistent()
	local CM = ns.ConversationManager
	if not CM then return end

	for _, conv in pairs(CM.All()) do
		if persistent then
			local rec = History.GetRecord(conv.id, true)
			if conv.messages ~= rec.msgs then
				-- adopt the in-memory list; it is the newer one
				wipe(rec.msgs)
				for i = 1, #conv.messages do rec.msgs[i] = conv.messages[i] end
				conv.messages = rec.msgs
			end
			conv.record = rec
			History.WriteMeta(conv)
		else
			if conv.record and conv.messages == conv.record.msgs then
				local copy = {}
				for i = 1, #conv.messages do copy[i] = conv.messages[i] end
				conv.messages = copy
			end
			conv.record = nil
		end
	end

	if not persistent and charStore then
		wipe(charStore.conv)
	else
		History.Prune()
	end
end

--------------------------------------------------------------------------------
-- Metadata
--------------------------------------------------------------------------------

function History.WriteMeta(conv)
	local rec = conv.record
	if not rec then return end
	rec.n = conv.name
	rec.c = conv.class
	rec.lv = conv.level
	rec.f = conv.faction
	rec.bt = conv.battleTag
	rec.t = conv.lastActivity
	rec.u = conv.unread > 0 and conv.unread or nil
	rec.p = conv.pinned or nil
	rec.m = conv.muted or nil
end

--------------------------------------------------------------------------------
-- Clearing
--------------------------------------------------------------------------------

function History.Clear(id)
	local CM = ns.ConversationManager
	local conv = CM and CM.Get(id)
	local removed = 0
	if conv then
		removed = #conv.messages
		wipe(conv.messages)
	end
	local rec = History.GetRecord(id, false)
	if rec and rec.msgs and rec.msgs ~= (conv and conv.messages) then
		removed = max(removed, #rec.msgs)
		wipe(rec.msgs)
	end
	ns.Bus.Fire(ns.EV.HISTORY_CLEARED, id)
	return removed
end

function History.ClearAll()
	local CM = ns.ConversationManager
	local removed = 0
	if CM then
		for _, conv in pairs(CM.All()) do
			removed = removed + #conv.messages
			wipe(conv.messages)
		end
	end
	if charStore then
		for _, rec in pairs(charStore.conv) do
			if rec.msgs then wipe(rec.msgs) end
		end
	end
	ns.Bus.Fire(ns.EV.HISTORY_CLEARED, nil)
	return removed
end

--------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------

-- Rough byte estimate of what this history will cost in the SavedVariables
-- file. Used by the settings panel so nobody discovers a 40 MB Lua file the
-- hard way.
function History.Stats()
	local conversations, messages, bytes = 0, 0, 0
	if charStore then
		for id, rec in pairs(charStore.conv) do
			conversations = conversations + 1
			bytes = bytes + #id + 48
			local msgs = rec.msgs
			if msgs then
				local n = #msgs
				messages = messages + n
				for i = 1, n do
					local m = msgs[i]
					if type(m) == "table" then
						bytes = bytes + 28 + #(m[MSG_TEXT] or "")
					end
				end
			end
		end
	end
	return conversations, messages, bytes
end
