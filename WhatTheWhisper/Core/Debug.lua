-- WhatTheWhisper -- Developer logging and the failsafe health guard.
--
-- Two jobs that belong together: recording what the addon did, and noticing when
-- it has gone wrong often enough that it should stop standing between the player
-- and their whispers.

local _, ns = ...

local Debug = {}
ns.Debug = Debug

local format, tostring = string.format, tostring

Debug.CATEGORIES = {
	events = "events", dedupe = "dedupe", history = "history",
	pool = "pool", compat = "compat", ui = "ui",
}

local COLOURS = {
	events = "|cff7AA2FF", dedupe = "|cffE8B84B", history = "|cff3FBF7F",
	pool = "|cffA07AFF", compat = "|cffE5484D", ui = "|cff8696A0",
}

local ring = {}
local ringSize = 0
local RING_LIMIT = 200

function Debug.IsEnabled()
	local db = ns.db
	return db and db.profile and db.profile.advanced.debug or false
end

-- Records into a small ring buffer always, prints only when debug is on. The
-- buffer means /wtw diag can show what happened just before a problem even if
-- debug was off at the time.
function Debug.Log(category, message, ...)
	local text = select("#", ...) > 0 and format(message, ...) or message
	ringSize = ringSize + 1
	ring[(ringSize - 1) % RING_LIMIT + 1] = format("[%s] %s", category, text)
	if not Debug.IsEnabled() then return end
	local colour = COLOURS[category] or "|cffA7B0BE"
	ns.Print(format("%s%s|r %s", colour, category, text))
end

function Debug.Recent(count)
	count = math.min(count or 20, RING_LIMIT, ringSize)
	local out = {}
	for i = ringSize - count + 1, ringSize do
		out[#out + 1] = ring[(i - 1) % RING_LIMIT + 1]
	end
	return out
end

function Debug.Toggle(enabled)
	if enabled == nil then enabled = not Debug.IsEnabled() end
	ns.db.profile.advanced.debug = enabled and true or false
	return ns.db.profile.advanced.debug
end

--------------------------------------------------------------------------------
-- Failsafe
--------------------------------------------------------------------------------

-- Whispers are the player's, not the addon's. If something in here is
-- repeatedly failing we must not also be the reason those whispers are missing
-- from the chat frame, so past a threshold the addon stops suppressing them and
-- says so once.
local ERROR_LIMIT = 12

local errorCount = 0
local degraded = false
local announced = false

function Debug.IsDegraded()
	return degraded
end

function Debug.ErrorCount()
	return errorCount
end

function Debug.NoteError(context, err)
	errorCount = errorCount + 1
	Debug.Log("events", "error in %s: %s", tostring(context), tostring(err))
	if degraded or errorCount < ERROR_LIMIT then return end
	degraded = true
	if not announced then
		announced = true
		local L = ns.L
		ns.Print(L["Something went wrong repeatedly, so whispers are being shown in the chat frame again. /wtw debug for details."])
	end
end

-- A payload the client would not let us read. Not an error -- being in an arena
-- is not a fault -- but we cannot store the message, so we must not also be the
-- reason it is missing from the chat frame.
function Debug.NoteUnreadable()
	Debug.Log("events", "a chat payload could not be read; restricted content")
	if degraded then return end
	degraded = true
	if announced then return end
	announced = true
	ns.Print(ns.L["Whispers here cannot be read by addons, so they are being shown in the chat frame instead."])
end

-- Called when the player explicitly asks for a fresh start.
function Debug.ClearDegraded()
	errorCount = 0
	degraded = false
	announced = false
end
