-- WhatTheWhisper -- Messages the client would not hand over yet.
--
-- In an arena or a rated battleground the client hands addons *secret values*
-- instead of chat text. Reading one is a hard error, so the message cannot be
-- stored -- and the addon used to stop there, which meant a whisper sent to you
-- in an arena was gone. The chat frame had it; the conversation never did.
--
-- It is not gone. A chat line's ID is never secret, and once the restriction
-- lifts the client will answer for that line. So an unreadable event is put here
-- with its ID and the time it arrived, and taken back out the moment chat is no
-- longer withheld: the whisper lands in its own thread, in order, stamped with
-- when it was actually sent rather than when we got around to reading it.
--
-- Nothing is invented while it waits. A held message has no text at all, and the
-- thread shows nothing until there is something real to show.

local _, ns = ...
local Compat, Debug = ns.Compat, ns.Debug

local Deferred = {}
ns.Deferred = Deferred

-- Arg 11 of every CHAT_MSG_ event is the chat line ID, and args 1, 2 and 12 are
-- the three the client withholds: the text, the sender, and their GUID.
local ARG_TEXT, ARG_SENDER, ARG_LINE_ID, ARG_GUID = 1, 2, 11, 12
-- The client passes seventeen; keeping a couple more costs nothing and means a
-- future argument is carried rather than dropped.
local ARG_COUNT = 20

-- A long arena is a few dozen whispers at the very most. The cap is not about
-- memory, it is about never letting a bug here grow without bound.
local MAX_HELD = 200
-- How often to look. Chat comes back when the arena ends, which is an event
-- nobody is watching the clock for.
local POLL_SECONDS = 1

local held = {}
local dispatch
local ticker

--------------------------------------------------------------------------------
-- Holding
--------------------------------------------------------------------------------

-- Everything the client will still let us keep. A secret argument is dropped
-- rather than stored: it cannot be read now and it cannot be read later either,
-- which is what the line ID is for.
local function keepable(...)
	local args, n = {}, select("#", ...)
	for i = 1, ARG_COUNT do
		if i <= n then
			local value = select(i, ...)
			if not Compat.IsSecretValue(value) then args[i] = value end
		end
	end
	return args
end

function Deferred.Count()
	return #held
end

-- Registered by ChatEvents: how to hand an event back once it can be read.
function Deferred.SetDispatcher(fn)
	dispatch = fn
end

function Deferred.Hold(event, ...)
	if type(event) ~= "string" then return false end
	local args = keepable(...)
	if type(args[ARG_LINE_ID]) ~= "number" then
		-- With no line ID there is nothing to ask the client for later, so
		-- holding it would only be pretending. The chat frame still has it.
		Debug.Log("events", "%s withheld and unrecoverable: no chat line id", event)
		return false
	end
	if #held >= MAX_HELD then
		Debug.Log("events", "the deferred queue is full; dropping the oldest")
		table.remove(held, 1)
	end
	held[#held + 1] = {
		event = event,
		args = args,
		at = Compat.GetServerTime(),
	}
	Debug.Log("events", "%s held until chat comes back (%d waiting)", event, #held)
	Deferred.Start()
	return true
end

--------------------------------------------------------------------------------
-- Releasing
--------------------------------------------------------------------------------

-- One entry, if the client will now answer for it. Returns false when it will
-- not, which is how the caller knows to stop trying for the moment.
local function release(entry)
	local text, sender, guid = Compat.GetChatLine(entry.args[ARG_LINE_ID])
	if not text then return false end
	local args = entry.args
	args[ARG_TEXT] = text
	args[ARG_SENDER] = sender or args[ARG_SENDER]
	args[ARG_GUID] = guid or args[ARG_GUID]
	-- The time it was sent, not the time we caught up. A thread that reorders
	-- itself after an arena is worse than one that was briefly behind.
	args.timestamp = entry.at
	if dispatch then
		ns.Guard("Deferred." .. entry.event, dispatch, entry.event, args)
	end
	return true
end

-- Everything that can be released now. Returns how many were.
function Deferred.Flush()
	if #held == 0 then return 0 end
	if Compat.InChatMessagingLockdown() then return 0 end
	local released = 0
	while #held > 0 do
		local entry = held[1]
		if not release(entry) then break end
		table.remove(held, 1)
		released = released + 1
	end
	if released > 0 then
		Debug.Log("events", "released %d held message(s), %d still waiting",
			released, #held)
	end
	if #held == 0 then Deferred.Stop() end
	return released
end

-- A poll rather than an event, because there is no event for "the client has
-- stopped withholding chat" -- only for leaving an arena, which is not the same
-- list of situations and would go stale the next time Blizzard adds one. It
-- re-arms itself only while something is waiting, so an idle session does no
-- work at all.
function Deferred.Start()
	if ticker or #held == 0 then return end
	ticker = true
	local function tick()
		ticker = nil
		ns.Guard("Deferred.Flush", Deferred.Flush)
		Deferred.Start()
	end
	ns.Anim.After(POLL_SECONDS, tick)
end

function Deferred.Stop()
	ticker = nil
end

-- Everything, whether or not the client is ready. Used when the player asks for
-- a clean slate; the messages are dropped, not shown.
function Deferred.Clear()
	held = {}
	Deferred.Stop()
end
