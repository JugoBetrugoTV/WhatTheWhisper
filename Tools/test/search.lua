-- Search: does it find the right messages, and does it stay responsive.
--
-- The existing suite only proved searching does not error. What matters is
-- whether it finds what is there, ignores what is not, survives the characters
-- people actually type, and never blocks the client on a large history.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

-- Libraries and addon files both come from the shipped manifests, so these
-- tests load exactly what a player who unzipped only WhatTheWhisper/ gets.
local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local CM, Search = ns.ConversationManager, ns.Search

--------------------------------------------------------------------------------
-- A thread to search
--------------------------------------------------------------------------------

local function seed(id, name, texts)
	local conv = CM.GetOrCreate(id, { name = name })
	conv.name = name
	for i = 1, #texts do
		CM.AddMessage(id, ns.DIR_IN, texts[i], ns.MSG_WHISPER)
	end
	return conv
end

seed("Thrall-Blackrock", "Thrall", {
	"Are you coming to the raid tonight",
	"we need two healers",
	"RAID starts at eight",
	"Übergrößenträger unterwegs",
	"check https://example.com/guide for the strategy",
	"100% ready",
	"a.b.c special (chars) [here] +plus",
})
seed("Jaina-Blackrock", "Jaina Proudmoore", {
	"portal please",
	"the raid was good",
	"見つけた",
})
seed("Sylvanas-Silvermoon", "Sylvanas", {
	"nothing relevant in this thread at all",
})

-- Search.Messages is chunked across frames; this drains it and returns the
-- final result set the way the UI would receive it.
local function searchAll(query, scope)
	local final, done = nil, false
	Search.Messages(query, scope, function(results, complete)
		final = results
		if complete then done = true end
	end)
	local spins = 0
	while not done and spins < 200 do
		M.RunFrames(2)
		M.RunTimers(4)
		spins = spins + 1
	end
	check("search for " .. ("%q"):format(query) .. " finished", done)
	return final or {}
end

local function contains(results, needle)
	for i = 1, #results do
		if results[i].msg[ns.MSG_TEXT]:find(needle, 1, true) then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Finding what is there
--------------------------------------------------------------------------------

local raid = searchAll("raid")
eq("finds every message containing the word", #raid, 3)
check("finds the incoming one", contains(raid, "coming to the raid"))
check("finds it regardless of case in the message", contains(raid, "RAID starts"))
check("finds it in another conversation too", contains(raid, "raid was good"))

eq("an upper case query matches lower case text", #searchAll("RAID"), 3)
eq("a mixed case query matches too", #searchAll("RaId"), 3)

eq("a substring inside a word matches", #searchAll("heal"), 1)
eq("a query that is not there finds nothing", #searchAll("zeppelin"), 0)

--------------------------------------------------------------------------------
-- Scope
--------------------------------------------------------------------------------

local scoped = searchAll("raid", "Thrall-Blackrock")
eq("scoping to one conversation excludes the others", #scoped, 2)
for i = 1, #scoped do
	eq("every scoped result is from that conversation",
		scoped[i].conv.id, "Thrall-Blackrock")
end

--------------------------------------------------------------------------------
-- Characters people actually type
--------------------------------------------------------------------------------

-- A query is matched literally, not as a Lua pattern: "a.b" must not match
-- "axb", and "100%" must not blow up on the percent sign.
eq("a dot is a dot, not any character", #searchAll("a.b.c"), 1)
eq("a dot does not match an arbitrary character", #searchAll("a-b-c"), 0)
eq("a percent sign is literal", #searchAll("100%"), 1)
eq("brackets are literal", #searchAll("[here]"), 1)
eq("parentheses are literal", #searchAll("(chars)"), 1)
eq("a plus sign is literal", #searchAll("+plus"), 1)

-- Non-ASCII has to match on whole characters, both as the query and the text.
eq("a German query with umlauts matches", #searchAll("Übergröße"), 1)
eq("a Japanese query matches", #searchAll("見つけた"), 1)
eq("a URL can be searched for", #searchAll("example.com"), 1)

-- Too short to be worth scanning a whole history for.
eq("a one character query returns nothing", #searchAll("r"), 0)
eq("an empty query returns nothing", #searchAll(""), 0)

--------------------------------------------------------------------------------
-- Snippets
--------------------------------------------------------------------------------

local snippet = Search.Snippet("Are you coming to the raid tonight", "raid")
check("a snippet contains the match", snippet:find("raid", 1, true) ~= nil)

local long = string.rep("filler words here ", 20) .. "needle" .. string.rep(" more text", 20)
local cut = Search.Snippet(long, "needle")
check("a long line is trimmed around the match", #cut < #long)
check("the trimmed snippet still holds the match", cut:find("needle", 1, true) ~= nil)
check("a trimmed snippet is marked as trimmed", cut:find("%.%.%.") ~= nil)

-- The cut must land on character boundaries, never inside a UTF-8 sequence.
local umlauts = string.rep("Übergrößenträger ", 12) .. "MARKER" .. string.rep(" Straße", 12)
local cutUmlauts = Search.Snippet(umlauts, "MARKER")
local function validUTF8(s)
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local width = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or c < 0xF8 and 4 or 0
		if width == 0 or c >= 0x80 and c < 0xC0 then return false end
		for k = 1, width - 1 do
			local cc = s:byte(i + k)
			if not cc or cc < 0x80 or cc >= 0xC0 then return false end
		end
		i = i + width
	end
	return true
end
check("a snippet never cuts a multi-byte character", validUTF8(cutUmlauts), cutUmlauts)

-- Escapes are display machinery, not content: a snippet shows the text.
local linked = "look at |cffa335ee|Hitem:19019|h[Thunderfury]|h|r please"
local linkSnippet = Search.Snippet(linked, "Thunderfury")
check("a snippet strips colour escapes",
	not linkSnippet:find("|cff", 1, true), linkSnippet)
check("a snippet keeps the readable part of a link",
	linkSnippet:find("Thunderfury", 1, true) ~= nil, linkSnippet)

--------------------------------------------------------------------------------
-- Name filtering
--------------------------------------------------------------------------------

local names = Search.FilterConversations("")
eq("an empty filter returns every conversation", #names, CM.Count())

eq("filtering by name finds one", #Search.FilterConversations("Jaina"), 1)
eq("name filtering is case insensitive", #Search.FilterConversations("jaina"), 1)
eq("a partial name matches", #Search.FilterConversations("Proud"), 1)
eq("filtering by realm works", #Search.FilterConversations("Silvermoon"), 1)
eq("a name that is not there matches nothing",
	#Search.FilterConversations("Nobodyhere"), 0)

-- The caller supplies the table, so filtering must not leak the previous result.
local reused = {}
Search.FilterConversations("Jaina", reused)
eq("the caller's table holds one result", #reused, 1)
Search.FilterConversations("Nobodyhere", reused)
eq("a second filter clears the table first", #reused, 0)

--------------------------------------------------------------------------------
-- A large history stays chunked, and a running search can be superseded
--------------------------------------------------------------------------------

-- Built with the named tuple indices rather than positionally, so a change to
-- the message layout cannot leave this seeding the wrong field.
local bulkID = "Bulk-Testrealm"
local bulk = CM.GetOrCreate(bulkID, { name = "Bulk" })
for i = 1, 12000 do
	local m = {}
	m[ns.MSG_TS] = ns.Compat.GetServerTime()
	m[ns.MSG_DIR] = ns.DIR_IN
	m[ns.MSG_TEXT] = "filler message number " .. i
	m[ns.MSG_KIND] = ns.MSG_WHISPER
	bulk.messages[i] = m
end

local chunks = 0
local bulkDone = false
Search.Messages("number 11999", bulkID, function(_, done)
	chunks = chunks + 1
	if done then bulkDone = true end
end)
local spins = 0
while not bulkDone and spins < 400 do
	M.RunFrames(1)
	M.RunTimers(4)
	spins = spins + 1
end
eq("a 12000 message search completes", bulkDone, true)
check("it is spread over several frames rather than done in one", chunks > 1,
	("only %d callback(s)"):format(chunks))

local hits = searchAll("number 11999", bulkID)
eq("the needle in 12000 messages is found", #hits, 1)
eq("the hit points at the right message index",
	hits[1] and hits[1].index, 11999)

-- A search over a small thread finishes inside the first synchronous step, so
-- cancellation is only observable on a history big enough to be chunked.
local stale = 0
Search.Messages("filler", bulkID, function(_, done) if done then stale = stale + 1 end end)
Search.Cancel()
for _ = 1, 40 do M.RunFrames(1) M.RunTimers(4) end
eq("a cancelled search never reports completion", stale, 0)

-- Starting a second search abandons the first: only the newer one may finish,
-- or the older result set would overwrite the newer on screen.
local firstDone, secondDone = false, false
Search.Messages("filler", bulkID, function(_, done) if done then firstDone = true end end)
Search.Messages("number 42", bulkID, function(_, done) if done then secondDone = true end end)
for _ = 1, 400 do
	M.RunFrames(1)
	M.RunTimers(4)
	if secondDone then break end
end
eq("the newer search completes", secondDone, true)
eq("the superseded search does not", firstDone, false)

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 5)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
