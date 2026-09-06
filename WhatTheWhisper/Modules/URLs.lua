-- WhatTheWhisper -- Link detection.
--
-- An addon cannot open a browser, and pretending otherwise would be a lie. What
-- it can do is find links reliably, colour them, and put them in a box that is
-- already selected so Ctrl+C is the only keystroke needed.
--
-- Detection is token based rather than one big pattern: it never runs inside an
-- existing hyperlink, never splits a UTF-8 sequence, and does not turn "3.5" or
-- "e.g." into a link.

local _, ns = ...
local Text = ns.Text

local URLs = {}
ns.URLs = URLs

local find, sub, gsub, lower, format = string.find, string.sub, string.gsub, string.lower, string.format

URLs.LINK_TYPE = "wtwurl"

-- Top level domains we accept without a scheme. Deliberately conservative:
-- anything not on this list needs "http://" or "www." to be treated as a link.
local TLDS = {
	com = true, net = true, org = true, edu = true, gov = true, info = true,
	io = true, gg = true, tv = true, co = true, me = true, app = true, dev = true,
	de = true, at = true, ch = true, uk = true, fr = true, es = true, it = true,
	nl = true, be = true, se = true, no = true, dk = true, fi = true, pl = true,
	cz = true, ru = true, eu = true, pt = true, br = true, ca = true, au = true,
	jp = true, kr = true, cn = true, tw = true, hu = true, ro = true, gr = true,
	tr = true, ua = true, nz = true, mx = true, ar = true, cl = true, za = true,
}

local TRAILING = "[%.,;:!%?%)%]%}'\"]+$"

local function looksLikeURL(token)
	-- scheme://host
	if find(token, "^%a[%w%+%-%.]*://%w") then return true end
	-- www.something
	if find(lower(token), "^www%.[%w%-_]+%.%a") then return true end
	-- host.tld with a known TLD
	local host = token:match("^([%w%-_%.]+)")
	if not host then return false end
	local label, tld = host:match("^([%w%-_%.]+)%.(%a%a+)$")
	if not label or not tld then return false end
	if not TLDS[lower(tld)] then return false end
	-- reject pure numbers like "192.168" or "3.14"
	if find(label, "^%d+$") and find(tld, "^%d+$") then return false end
	return true
end

-- Everything after the marker is the URL, so no side table is needed and the
-- link survives being copied into an export.
local function makeLink(url, display, colorEscape)
	return format("%s|H%s:%s|h%s|h|r", colorEscape, URLs.LINK_TYPE, url, display)
end

local function processChunk(chunk, colorEscape)
	if not find(chunk, "%\S") then return chunk end
	local out, pos, last = nil, 1, 1
	local length = #chunk
	while pos <= length do
		local s, e = find(chunk, "%\S+", pos)
		if not s then break end
		local core = sub(chunk, s, e)
		local trailing = ""
		local tStart = find(core, TRAILING)
		if tStart then
			trailing = sub(core, tStart)
			core = sub(core, 1, tStart - 1)
		end
		local leading = ""
		local _, lEnd = find(core, "^[%(%[%{'\"]+")
		if lEnd then
			leading = sub(core, 1, lEnd)
			core = sub(core, lEnd + 1)
		end

		if core ~= "" and looksLikeURL(core) then
			out = out or {}
			out[#out + 1] = sub(chunk, last, s - 1)
			out[#out + 1] = leading
			out[#out + 1] = makeLink(core, core, colorEscape)
			out[#out + 1] = trailing
			last = e + 1
		end
		pos = e + 1
	end
	if not out then return chunk end
	out[#out + 1] = sub(chunk, last)
	return table.concat(out)
end

-- Wraps every link in the message with a clickable hyperlink. Escape sequences
-- that are already in the text (item links, textures, colours) are untouched.
function URLs.Process(text, colorEscape)
	local db = ns.db
	if db and db.profile and not db.profile.links.detect then return text end
	if not text or text == "" then return text end
	if not find(text, "%.") and not find(text, "://") then return text end
	colorEscape = colorEscape or ns.Color.ToEscape(ns.Theme.Get("link"))
	return Text.MapPlain(text, function(chunk) return processChunk(chunk, colorEscape) end)
end

-- Every link in a message, for the "copy link" context menu entry.
function URLs.Extract(text)
	local found
	if not text then return nil end
	Text.MapPlain(text, function(chunk)
		local pos, length = 1, #chunk
		while pos <= length do
			local s, e = find(chunk, "%S+", pos)
			if not s then break end
			local token = sub(chunk, s, e)
			token = gsub(token, TRAILING, "")
			token = gsub(token, "^[%(%[%{'\"]+", "")
			if token ~= "" and looksLikeURL(token) then
				found = found or {}
				found[#found + 1] = token
			end
			pos = e + 1
		end
		return chunk
	end)
	return found
end

function URLs.IsOurLink(link)
	return link and find(link, "^" .. URLs.LINK_TYPE .. ":") ~= nil
end

function URLs.URLFromLink(link)
	return link and link:match("^" .. URLs.LINK_TYPE .. ":(.+)$")
end

-- Adds the scheme people usually mean, purely for display in the copy box.
function URLs.Canonical(url)
	if not url then return url end
    if find(url, "^%a[%w%+%-%.]*://") then return url end
	return "https://" .. url
end
