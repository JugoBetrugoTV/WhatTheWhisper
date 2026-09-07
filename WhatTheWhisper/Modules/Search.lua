-- WhatTheWhisper -- Searching names and message bodies.
--
-- Name filtering is instant. Full-text search over a large history is chunked
-- across frames so that searching 200 000 stored messages never produces a
-- visible hitch; each tick has a fixed message budget and yields.

local _, ns = ...
local CM, Text = ns.ConversationManager, ns.Text

local Search = {}
ns.Search = Search

local MSG_TEXT = ns.MSG_TEXT
local BUDGET = 2500

local activeToken = 0

--------------------------------------------------------------------------------
-- Conversation names
--------------------------------------------------------------------------------

function Search.FilterConversations(query, out)
	out = out or {}
	wipe(out)
	local list = CM.Ordered()
	if not query or query == "" then
		for i = 1, #list do out[i] = list[i] end
		return out
	end
	for i = 1, #list do
		local conv = list[i]
		if Text.Contains(conv.name, query)
			or Text.Contains(conv.id, query)
			or (conv.realm and Text.Contains(conv.realm, query)) then
			out[#out + 1] = conv
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Message bodies
--------------------------------------------------------------------------------

local function snippet(text, query, radius)
	local plain = Text.Strip(text or "")
	plain = plain:gsub("%s+", " ")
	local s = plain:lower():find(query:lower(), 1, true)
	if not s then return plain end
	radius = radius or 42
	local from = math.max(1, s - radius)
	local to = math.min(#plain, s + #query + radius)
	local out = plain:sub(from, to)
	if from > 1 then out = "..." .. out end
	if to < #plain then out = out .. "..." end
	return out
end
Search.Snippet = snippet

-- onProgress(results, done) is called after every chunk so the UI can render
-- partial results while the scan continues.
function Search.Messages(query, scopeID, onProgress)
	activeToken = activeToken + 1
	local token = activeToken
	local results = {}

	if not query or #query < 2 then
		onProgress(results, true)
		return token
	end

	local queue = {}
	if scopeID then
		local conv = CM.Get(scopeID)
		if conv then queue[1] = conv end
	else
		local list = CM.Ordered()
		for i = 1, #list do queue[i] = list[i] end
	end

	local qi, mi = 1, 0
	local needle = query

	local function step()
		if token ~= activeToken then return end   -- superseded by a newer search
		local budget = BUDGET
		while qi <= #queue and budget > 0 do
			local conv = queue[qi]
			local messages = conv.messages
			local n = #messages
			if mi == 0 then mi = n end            -- newest first
			while mi >= 1 and budget > 0 do
				local m = messages[mi]
				if m and Text.Contains(m[MSG_TEXT], needle) then
					results[#results + 1] = {
						conv = conv,
						index = mi,
						msg = m,
						snippet = snippet(m[MSG_TEXT], needle),
					}
				end
				mi = mi - 1
				budget = budget - 1
			end
			if mi < 1 then
				qi = qi + 1
				mi = 0
			end
		end

		local done = qi > #queue
		onProgress(results, done)
		if not done then
			ns.Anim.After(0, step)
		end
	end

	step()
	return token
end

function Search.Cancel()
	activeToken = activeToken + 1
end
