-- WhatTheWhisper -- UTF-8 safe string handling.
--
-- WoW's Lua is 5.1: there is no utf8 library, string.len counts bytes and
-- string.sub cuts bytes. Chat is full of multi-byte text and of escape
-- sequences (|cRRGGBB, |Hitem:...|h[..]|h, |Tpath:16|t) that must never be cut
-- in half, so all message handling goes through these helpers.

local _, ns = ...

local Text = {}
ns.Text = Text

local byte, sub, len, find, gsub = string.byte, string.sub, string.len,
	string.find, string.gsub
local floor = math.floor
local tconcat, twipe = table.concat, wipe

--------------------------------------------------------------------------------
-- UTF-8 primitives
--------------------------------------------------------------------------------

-- Number of bytes in the UTF-8 sequence starting at position i.
function Text.CharBytes(s, i)
	local b = byte(s, i)
	if not b then return 0 end
	if b < 0x80 then return 1
	elseif b < 0xC0 then return 1        -- stray continuation byte: treat as one
	elseif b < 0xE0 then return 2
	elseif b < 0xF0 then return 3
	elseif b < 0xF8 then return 4
	end
	return 1
end

function Text.Len(s)
	if not s then return 0 end
	local i, n, l = 1, 0, len(s)
	while i <= l do
		i = i + Text.CharBytes(s, i)
		n = n + 1
	end
	return n
end

-- Substring by character index (1-based, inclusive).
function Text.Sub(s, first, last)
	if not s then return "" end
	if last and last < first then return "" end
	local l = len(s)
	local i, ci = 1, 1
	local startByte, endByte
	while i <= l do
		if ci == first then startByte = i end
		local step = Text.CharBytes(s, i)
		if last and ci == last then endByte = i + step - 1 break end
		i = i + step
		ci = ci + 1
	end
	if not startByte then return "" end
	return sub(s, startByte, endByte or l)
end

function Text.FirstChar(s)
	if not s or s == "" then return "" end
	return sub(s, 1, Text.CharBytes(s, 1))
end

-- Uppercase that leaves multi-byte characters alone instead of corrupting them.
function Text.UpperFirst(s)
	if not s or s == "" then return s end
	local n = Text.CharBytes(s, 1)
	if n == 1 then
		return string.upper(sub(s, 1, 1)) .. sub(s, 2)
	end
	return s
end

function Text.Trim(s)
	if not s then return "" end
	return (gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Snaps a byte offset down to the start of the character containing it.
function Text.ByteFloor(s, i)
	if not s or i <= 1 then return 1 end
	if i > len(s) then i = len(s) end
	while i > 1 do
		local b = byte(s, i)
		if b < 0x80 or b >= 0xC0 then return i end
		i = i - 1
	end
	return 1
end

-- Snaps a byte offset up to the last byte of the character containing it.
function Text.ByteCeil(s, i)
	if not s then return 0 end
	local l = len(s)
	if i >= l then return l end
	if i < 1 then return 0 end
	local start = Text.ByteFloor(s, i)
	return math.min(l, start + Text.CharBytes(s, start) - 1)
end

-- Byte-range substring that can never cut a character in half.
function Text.SafeByteSub(s, from, to)
	if not s or s == "" then return "" end
	return sub(s, Text.ByteFloor(s, from or 1), Text.ByteCeil(s, to or len(s)))
end

--------------------------------------------------------------------------------
-- WoW escape sequences
--------------------------------------------------------------------------------

-- Walks a string and hands every run to one of two callbacks:
--   onText(str)                        plain, safe to transform
--   onEscape(str, kind, payload, body) an escape sequence, must stay intact
-- kind is "color", "reset", "link", "texture", "atlas" or "other".
function Text.Walk(s, onText, onEscape)
	if not s or s == "" then return end
	local i, l = 1, len(s)
	local plainStart = 1

	local function flush(upTo)
		if upTo >= plainStart then
			onText(sub(s, plainStart, upTo))
		end
	end

	while i <= l do
		if byte(s, i) == 124 then -- '|'
			local nxt = sub(s, i + 1, i + 1)
			if nxt == "|" then
				flush(i - 1)
				onEscape("||", "escape")
				i = i + 2
				plainStart = i
			elseif nxt == "c" then
				flush(i - 1)
				onEscape(sub(s, i, i + 9), "color")
				i = i + 10
				plainStart = i
			elseif nxt == "r" then
				flush(i - 1)
				onEscape("|r", "reset")
				i = i + 2
				plainStart = i
			elseif nxt == "H" then
				local _, closeEnd, body = find(s, "^|H(.-)|h", i)
				if closeEnd then
					local _, textEnd, display = find(s, "^(.-)|h", closeEnd + 1)
					if textEnd then
						flush(i - 1)
						onEscape(sub(s, i, textEnd), "link", body, display)
						i = textEnd + 1
						plainStart = i
					else
						i = i + 2
					end
				else
					i = i + 2
				end
			elseif nxt == "T" then
				local _, closeEnd = find(s, "^|T.-|t", i)
				if closeEnd then
					flush(i - 1)
					onEscape(sub(s, i, closeEnd), "texture")
					i = closeEnd + 1
					plainStart = i
				else
					i = i + 2
				end
			elseif nxt == "A" then
				local _, closeEnd = find(s, "^|A.-|a", i)
				if closeEnd then
					flush(i - 1)
					onEscape(sub(s, i, closeEnd), "atlas")
					i = closeEnd + 1
					plainStart = i
				else
					i = i + 2
				end
			elseif nxt == "n" then
				flush(i - 1)
				onEscape("|n", "other")
				i = i + 2
				plainStart = i
			else
				i = i + 2
			end
		else
			i = i + Text.CharBytes(s, i)
		end
	end
	flush(l)
end

-- Applies `transform` to plain-text runs only, leaving links, textures and
-- colour codes byte-identical.
function Text.MapPlain(s, transform)
	if not s or s == "" then return s or "" end
	local out = {}
	Text.Walk(s,
		function(chunk) out[#out + 1] = transform(chunk) end,
		function(chunk) out[#out + 1] = chunk end)
	return tconcat(out)
end

-- Strips every escape sequence. Used for previews, search and plain-text export.
function Text.Strip(s)
	if not s or s == "" then return "" end
	local out = {}
	Text.Walk(s,
		function(chunk) out[#out + 1] = chunk end,
		function(_, kind, _, display)
			if kind == "link" and display then
				out[#out + 1] = (gsub(display, "|c%x%x%x%x%x%x%x%x", ""))
			elseif kind == "escape" then
				out[#out + 1] = "|"
			end
		end)
	local result = tconcat(out)
	result = gsub(result, "|r", "")
	return result
end

-- Makes arbitrary text safe to place inside a FontString without any of it
-- being interpreted as markup.
function Text.EscapeMarkup(s)
	if not s then return "" end
	return (gsub(s, "|", "||"))
end

--------------------------------------------------------------------------------
-- Splitting for the 255-byte whisper limit
--------------------------------------------------------------------------------

local atoms = {}

-- Splits into pieces that each fit `maxBytes`, never cutting a UTF-8 sequence,
-- an escape sequence or (where avoidable) a word.
function Text.SplitForSend(s, maxBytes)
	maxBytes = maxBytes or ns.MAX_MESSAGE_BYTES
	local result = {}
	if not s or s == "" then return result end
	if len(s) <= maxBytes then
		result[1] = s
		return result
	end

	twipe(atoms)
	-- Build a list of indivisible atoms: escape sequences, words, whitespace.
	Text.Walk(s,
		function(chunk)
			for piece in string.gmatch(chunk, "%S+%s*") do
				atoms[#atoms + 1] = piece
			end
			if find(chunk, "^%s+$") then atoms[#atoms + 1] = chunk end
		end,
		function(chunk) atoms[#atoms + 1] = chunk end)

	local current = ""
	for i = 1, #atoms do
		local atom = atoms[i]
		if len(atom) > maxBytes then
			-- A single atom too long for one message (a pathological word or a
			-- giant link): hard-split it on character boundaries.
			if current ~= "" then result[#result + 1] = current; current = "" end
			local j, l = 1, len(atom)
			while j <= l do
				local take, bytes = j, 0
				while take <= l do
					local step = Text.CharBytes(atom, take)
					if bytes + step > maxBytes then break end
					bytes = bytes + step
					take = take + step
				end
				result[#result + 1] = sub(atom, j, take - 1)
				j = take
			end
		elseif len(current) + len(atom) > maxBytes then
			result[#result + 1] = Text.Trim(current)
			current = atom
		else
			current = current .. atom
		end
	end
	if Text.Trim(current) ~= "" then result[#result + 1] = Text.Trim(current) end
	return result
end

--------------------------------------------------------------------------------
-- Measuring and eliding
--------------------------------------------------------------------------------

local ELLIPSIS = "..."

-- Truncates to `maxChars` *visible* characters.
--
-- Escape sequences cost nothing and are never cut: stopping in the middle of a
-- "|cffRRGGBB" or a hyperlink would leave the rest of the line rendering as raw
-- markup. A colour opened before the cut is closed again.
function Text.TruncateVisible(s, maxChars)
	if not s or s == "" or maxChars <= 0 then return "" end

	-- Each piece records whether it carried visible text, so trailing escapes
	-- that ended up with nothing after them can be dropped rather than left as
	-- an empty "|cffa335ee|r" at the end of the line.
	local pieces, visible, budget, done = {}, {}, maxChars, false

	local function emit(chunk, isVisible)
		pieces[#pieces + 1] = chunk
		visible[#pieces] = isVisible
	end

	Text.Walk(s,
		function(chunk)
			if done then return end
			local taken, i, l = 0, 1, len(chunk)
			while i <= l and budget > 0 do
				local step = Text.CharBytes(chunk, i)
				i = i + step
				taken = taken + step
				budget = budget - 1
			end
			if taken > 0 then emit(sub(chunk, 1, taken), true) end
			if budget <= 0 and i <= l then done = true end
		end,
		function(chunk, kind, _, display)
			if done then return end
			if kind == "link" then
				-- A link is atomic: it fits whole or it is left out entirely.
				local cost = display and Text.Len(display) or 0
				if cost > budget then
					done = true
					return
				end
				budget = budget - cost
				emit(chunk, true)
				return
			end
			emit(chunk, kind == "escape" or kind == "texture" or kind == "atlas")
		end)

	-- Drop trailing pieces that show nothing.
	local last = #pieces
	while last > 0 and not visible[last] do last = last - 1 end

	local colourDepth = 0
	for i = 1, last do
		local piece = pieces[i]
		if piece == "|r" then
			colourDepth = math.max(0, colourDepth - 1)
		elseif sub(piece, 1, 2) == "|c" and #piece == 10 then
			colourDepth = colourDepth + 1
		end
	end

	local result = tconcat(pieces, "", 1, last)
	for _ = 1, colourDepth do result = result .. "|r" end
	return result
end

-- Shortens `text` until it fits `maxWidth` in the given FontString, appending an
-- ellipsis. Binary search keeps this at ~8 measurements even for long strings.
function Text.Ellipsize(fontString, text, maxWidth)
	if not text or text == "" then
		fontString:SetText("")
		return ""
	end
	fontString:SetText(text)
	if maxWidth <= 0 or fontString:GetStringWidth() <= maxWidth then
		return text
	end
	local total = Text.Len(text)
	local lo, hi, best = 0, total, ""
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local candidate = Text.TruncateVisible(text, mid) .. ELLIPSIS
		fontString:SetText(candidate)
		if fontString:GetStringWidth() <= maxWidth then
			best = candidate
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	fontString:SetText(best)
	return best
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

-- Case/diacritic-insensitive enough for a name search box.
function Text.Fold(s)
	if not s then return "" end
	return string.lower(s)
end

function Text.Contains(haystack, needle)
	if not needle or needle == "" then return true end
	if not haystack then return false end
	return find(Text.Fold(haystack), Text.Fold(needle), 1, true) ~= nil
end
