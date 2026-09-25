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

-- How long a line gets to become readable once the client is willing to talk
-- again, and how many tries that is worth. The client's chat line store is a
-- ring buffer: a line that scrolled out of it is never coming back, and waiting
-- for it forever would mean every message behind it waits forever too.
--
-- Generous, because the alternative to waiting is losing the message, and the
-- normal case answers on the first try.
local RECOVERY_SECONDS = 30
local RECOVERY_ATTEMPTS = 40

local held = {}
local dispatch
local ticker
local generation = 0
local dropped = 0

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
		attempts = 0,
		-- Set on the first try, not here: the clock that matters starts when
		-- the client is willing to answer, and an arena can last ten minutes.
		firstTry = nil,
	}
	Debug.Log("events", "%s held until chat comes back (%d waiting)", event, #held)
	Deferred.Start()
	return true
end

--------------------------------------------------------------------------------
-- Releasing
--------------------------------------------------------------------------------

-- Whether this one has waited long enough to be called lost.
--
-- The client will say outright when a line has aged out of its store, and being
-- told is much better than waiting out a timeout to find out: it means the
-- message behind this one moves at once rather than in half a minute. The
-- timeout stays for the client that does not answer, and for the line that is
-- still valid but not yet readable.
--
-- Time and tries, both: a client that has stopped calling the timer would never
-- reach the attempt count, and a timer running fast would never reach the clock.
local function exhausted(entry)
	local valid = Compat.IsValidChatLine(entry.args[ARG_LINE_ID])
	if valid == false then return true, "the client says that line is gone" end
	if entry.attempts >= RECOVERY_ATTEMPTS then return true, "out of tries" end
	local first = entry.firstTry
	if first ~= nil and (Compat.GetServerTime() - first) >= RECOVERY_SECONDS then
		return true, "out of time"
	end
	return false
end

-- One entry, if the client will now answer for it well enough to use.
--
-- "Well enough" is the whole point, and it is not "the text turned up". The
-- client answers for a line one field at a time: the text can arrive a tick
-- before the sender does. Handing the handler a message with text and nobody to
-- file it under means the handler stores nothing -- and if that counted as a
-- release, the entry would be thrown away a second before the missing half
-- arrived.
--
-- So the reconstructed event goes through the same admissibility contract a live
-- one does. Only "store" is a release. Anything else is "not yet", and the
-- caller decides whether there is still time to ask again.
--
-- Returns released, identity.
local function release(entry)
	entry.attempts = entry.attempts + 1
	entry.firstTry = entry.firstTry or Compat.GetServerTime()

	local args = entry.args
	local lineID = args[ARG_LINE_ID]
	local text, sender, guid = Compat.GetChatLine(lineID)

	-- Filled in where the client has an answer, left alone where it does not, so
	-- a field recovered on an earlier attempt is not lost on a later one.
	if text ~= nil then args[ARG_TEXT] = text end
	if sender ~= nil then args[ARG_SENDER] = sender end
	if guid ~= nil then args[ARG_GUID] = guid end

	local admit = ns.ChatEvents and ns.ChatEvents.Reconsider
	if not admit then return false end
	local mode, identity = admit(entry.event, unpack(args, 1, ARG_COUNT))
	if mode ~= "store" then return false end

	args.lineID = lineID
	args.censored = Compat.IsChatLineCensored(lineID) or nil
	-- The time it was sent, not the time we caught up. A thread that reorders
	-- itself after an arena is worse than one that was briefly behind.
	args.timestamp = entry.at
	if not dispatch then return false end

	-- Admissible is not stored. The handler can still fail on its way to the
	-- commit -- and dequeueing on "it was allowed to try" would throw the
	-- message away on the strength of an attempt. So the answer that matters is
	-- the one the model gives: did the message actually land.
	--
	-- Anything the handler does *after* the commit -- a toast, a sound, the
	-- window scrolling -- is guarded inside the handler and cannot report
	-- failure here, because retrying past a commit is how one message becomes
	-- two.
	return dispatch(entry.event, args, identity) == true
end

-- Everything that can be released now. Returns how many were.
--
-- The queue is drained from the front and stays in order, because a thread that
-- reshuffles itself after an arena is worse than one that was briefly behind.
-- But the front is not allowed to hold the rest hostage: the client's chat line
-- store is a ring buffer, a line that has scrolled out of it is never coming
-- back, and one such line at the head would otherwise mean every message behind
-- it is lost too. So the head waits, and then it is dropped -- only it -- and
-- the next one gets its turn.
--
-- Dropping is safe precisely because the addon never suppressed these from the
-- chat frame: the player's copy is still there.
function Deferred.Flush()
	if #held == 0 then return 0 end
	if Compat.InChatMessagingLockdown() then return 0 end
	local released, lost = 0, 0
	while #held > 0 do
		local entry = held[1]
		if release(entry) then
			table.remove(held, 1)
			released = released + 1
		else
			local done, why = exhausted(entry)
			if not done then
				-- Still within its budget. Wait, and keep the order.
				break
			end
			Debug.Log("events",
				"%s on chat line %s is not coming back (%s, %d tries); dropping "
				.. "it and carrying on -- the chat frame still has it",
				entry.event, tostring(entry.args[ARG_LINE_ID]), why, entry.attempts)
			table.remove(held, 1)
			dropped = dropped + 1
			lost = lost + 1
		end
	end
	if released > 0 or lost > 0 then
		Debug.Log("events", "released %d, gave up on %d, %d still waiting",
			released, lost, #held)
	end
	if #held == 0 then Deferred.Stop() end
	return released
end

-- How many were given up on this session. Read by the diagnostics command.
function Deferred.DroppedCount()
	return dropped
end

-- A poll rather than an event, because there is no event for "the client has
-- stopped withholding chat" -- only for leaving an arena, which is not the same
-- list of situations and would go stale the next time Blizzard adds one. It
-- re-arms itself only while something is waiting, so an idle session does no
-- work at all.
--
-- A timer cannot be taken back once it is scheduled, so each one carries the
-- generation it was started in and does nothing if that is no longer current.
-- Stop used to clear only the flag; the timer already on its way still fired and
-- re-armed, and the next Start began a second chain beside it -- one more for
-- every clean slate, each polling for the rest of the session.
function Deferred.Start()
	if ticker or #held == 0 then return end
	generation = generation + 1
	local mine = generation
	ticker = true
	local function tick()
		if mine ~= generation then return end
		ticker = nil
		ns.Guard("Deferred.Flush", Deferred.Flush)
		Deferred.Start()
	end
	ns.Anim.After(POLL_SECONDS, tick)
end

function Deferred.Stop()
	ticker = nil
	generation = generation + 1
end

-- Everything, whether or not the client is ready. Used when the player asks for
-- a clean slate; the messages are dropped, not shown.
function Deferred.Clear()
	held = {}
	dropped = 0
	Deferred.Stop()
end
