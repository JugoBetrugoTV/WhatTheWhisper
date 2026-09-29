-- WhatTheWhisper -- Keeping unwanted whispers from interrupting.
--
-- WIM's filters could block a whisper outright. This does less, on purpose: a
-- whisper from a stranger that contains one of the player's words still lands
-- in its thread -- nothing is ever thrown away -- but the thread is marked as
-- filtered, and a filtered thread makes no sound, shows no card, opens no
-- window, counts nothing unread and sits at the bottom of the list. It is taken
-- out of the chat window too, so the gold seller is gone from both places the
-- player looks, and one click ("Not spam") brings the thread back.
--
-- Only strangers are ever filtered: never a friend, a guildmate, a Battle.net
-- friend, or anybody the player has written to. A word list that happened to
-- catch a friend's sentence would otherwise hide a real conversation.

local _, ns = ...
local Compat = ns.Compat

local SpamFilter = {}
ns.SpamFilter = SpamFilter

local lower, gsub, gmatch, find = string.lower, string.gsub, string.gmatch, string.find

-- The player's list, parsed once per change: words or phrases separated by
-- commas, matched as plain text without regard to case. Plain text, not Lua
-- patterns -- a "." or a "%" in somebody's list must mean itself.
local parsedFrom, parsed = nil, {}

local function words()
	local raw = ns.Setting("filter.words")
	if type(raw) ~= "string" then raw = "" end
	if raw ~= parsedFrom then
		parsedFrom, parsed = raw, {}
		for part in gmatch(raw, "[^,\n]+") do
			part = gsub(gsub(part, "^%s+", ""), "%s+$", "")
			if part ~= "" then parsed[#parsed + 1] = lower(part) end
		end
	end
	return parsed
end

function SpamFilter.Words()
	return words()
end

-- Whether the text contains one of the words. ASCII case is ignored; letters
-- outside it are compared as written, since lowering them needs a table of
-- every script and a filter word is typed the way it is spelled anyway.
function SpamFilter.Matches(text)
	if type(text) ~= "string" or text == "" then return false end
	local list = words()
	if #list == 0 then return false end
	local haystack = lower(text)
	for i = 1, #list do
		if find(haystack, list[i], 1, true) then return true end
	end
	return false
end

-- Somebody the player knows, who is never filtered: a friend, a guildmate,
-- anyone they have written to, or a thread they said is not spam. Battle.net
-- never gets this far -- every sender there is on the player's own list.
function SpamFilter.IsKnown(id)
	if not id or Compat.IsBattleNet(id) then return true end
	local conv = ns.ConversationManager.Get(id)
	if conv and conv.notSpam then return true end
	if conv and not conv.filtered then
		local messages = conv.messages or {}
		for i = #messages, 1, -1 do
			if messages[i][ns.MSG_DIR] == ns.DIR_OUT then return true end
		end
	end
	return Compat.IsFriend(id) or Compat.IsGuildMember(id)
end

-- The whole question, for a whisper from `id` saying `text`. A thread already
-- filtered stays filtered whatever the next message says, until the player
-- says otherwise.
function SpamFilter.ShouldFilter(id, text)
	if not id then return false end
	local conv = ns.ConversationManager.Get(id)
	if conv and conv.filtered then return true end
	if #words() == 0 then return false end
	if not SpamFilter.Matches(text) then return false end
	return not SpamFilter.IsKnown(id)
end
