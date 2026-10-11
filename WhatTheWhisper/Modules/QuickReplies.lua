-- WhatTheWhisper -- Lines that are sent often, one click away.
--
-- "On my way", "one moment", "thanks": a handful of sentences that make up most
-- of what most people say in a whisper. They sit behind a button in the
-- composer, and choosing one puts it in the box -- in the box, not sent, so it
-- can be changed first and nothing leaves by a slip of the mouse.
--
-- Until the player writes their own the list is a set of starters in the
-- language the addon is in. That is not stored: a list saved in English at first
-- run would stay English for somebody who changes language later, and would look
-- like their own words when it was not.

local _, ns = ...
local L = ns.L

local QuickReplies = {}
ns.QuickReplies = QuickReplies

-- Ten is what fits in a menu without it becoming a list to scroll, and two
-- hundred bytes is most of a whisper with room left to add a name.
QuickReplies.MAX = 10
QuickReplies.MAX_BYTES = 200

local SETTING = "messages.quickReplies"

function QuickReplies.Starters()
	return {
		L["On my way"],
		L["One moment, please"],
		L["Thank you!"],
		L["Sorry, I am busy right now"],
	}
end

-- Whether the list is the player's own, or still the starters.
function QuickReplies.IsCustom()
	return type(ns.Setting(SETTING)) == "table"
end

function QuickReplies.List()
	local saved = ns.Setting(SETTING)
	if type(saved) ~= "table" then return QuickReplies.Starters() end
	local out = {}
	for i = 1, #saved do
		if type(saved[i]) == "string" and saved[i] ~= "" then out[#out + 1] = saved[i] end
	end
	return out
end

-- What a line has to be to be kept: some words, not a pile of spaces, and short
-- enough to be one whisper. Returns nil for a line that is just empty.
function QuickReplies.Clean(line)
	if type(line) ~= "string" then return nil end
	line = ns.Text.Trim((line:gsub("[%c]+", " ")))
	if line == "" then return nil end
	if #line > QuickReplies.MAX_BYTES then
		line = ns.Text.SafeByteLimit(line, QuickReplies.MAX_BYTES)
	end
	return line
end

-- Saves a list, cleaned. An empty list is a decision -- somebody who wants none
-- -- and is kept as one, rather than quietly turning back into the starters.
function QuickReplies.Set(lines)
	local out = {}
	for i = 1, #lines do
		local line = QuickReplies.Clean(lines[i])
		if line then
			out[#out + 1] = line
			if #out >= QuickReplies.MAX then break end
		end
	end
	ns.Options.Set(SETTING, out)
	return out
end

function QuickReplies.Reset()
	ns.Options.Set(SETTING, false)
end
