-- History and SavedVariables verification: what actually gets written to disk,
-- whether it survives a round trip, and whether pruning can damage it.

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
local softErrors = {}
ns.SoftError = function(context, err) softErrors[#softErrors + 1] = context .. ": " .. tostring(err) end

local CM, History = ns.ConversationManager, ns.History
local MSG_TS, MSG_TEXT = ns.MSG_TS, ns.MSG_TEXT

--------------------------------------------------------------------------------
-- What WoW is able to write
--------------------------------------------------------------------------------

-- Mirrors the SavedVariables writer: tables of strings, numbers and booleans,
-- no functions, no userdata, no cycles.
local function auditSerializable(value, path, seen, problems)
	local kind = type(value)
	if kind == "string" or kind == "number" or kind == "boolean" then return end
	if kind ~= "table" then
		problems[#problems + 1] = ("%s is a %s"):format(path, kind)
		return
	end
	if seen[value] then
		problems[#problems + 1] = ("%s is a circular reference"):format(path)
		return
	end
	seen[value] = true
	for key, child in pairs(value) do
		local keyKind = type(key)
		if keyKind ~= "string" and keyKind ~= "number" then
			problems[#problems + 1] = ("%s has a %s key"):format(path, keyKind)
		end
		auditSerializable(child, path .. "." .. tostring(key), seen, problems)
	end
	seen[value] = nil
end

local function audit(root, name)
	local problems = {}
	auditSerializable(root, name, {}, problems)
	return problems
end

-- Writes the table the way WoW does, so it can be read back in a fresh session.
local function serialize(value, indent)
	indent = indent or ""
	local kind = type(value)
	if kind == "string" then return ("%q"):format(value) end
	if kind == "number" or kind == "boolean" then return tostring(value) end
	local keys = {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = { "{\n" }
	for _, key in ipairs(keys) do
		local encoded = type(key) == "number" and ("[%d]"):format(key)
			or ("[%q]"):format(key)
		parts[#parts + 1] = ("%s\t%s = %s,\n")
			:format(indent, encoded, serialize(value[key], indent .. "\t"))
	end
	parts[#parts + 1] = indent .. "}"
	return table.concat(parts)
end

--------------------------------------------------------------------------------
-- Empty
--------------------------------------------------------------------------------

eq("fresh history has no conversations", select(1, History.Stats()), 0)
eq("fresh history has no messages", select(2, History.Stats()), 0)
eq("schema version stamped", ns.db.global.schemaVersion, ns.SCHEMA_VERSION)
eq("history file version stamped", _G.WhatTheWhisperHistoryDB.version, ns.SCHEMA_VERSION)
eq("first run reports no repairs", #softErrors, 0, table.concat(softErrors, "; "))

--------------------------------------------------------------------------------
-- Volume
--------------------------------------------------------------------------------

ns.Options.Set("history.retention", "forever")
ns.Options.Set("history.maxPerConversation", 10000)
ns.Options.Set("history.maxConversations", 500)

CM.AddMessage("Solo-Blackrock", ns.DIR_IN, "einzige nachricht", ns.MSG_WHISPER, 1788000000)
eq("single message stored", #CM.Get("Solo-Blackrock").messages, 1)

local base = 1788000000
for i = 1, 1000 do
	CM.AddMessage("Thousand-Blackrock", i % 2, "nachricht " .. i, ns.MSG_WHISPER, base + i)
end
eq("1000 messages stored", #CM.Get("Thousand-Blackrock").messages, 1000)

for i = 1, 10000 do
	CM.AddMessage("TenK-Blackrock", i % 2, "eintrag " .. i, ns.MSG_WHISPER, base + i)
end
eq("10000 messages stored", #CM.Get("TenK-Blackrock").messages, 10000)

for c = 1, 120 do
	CM.AddMessage("Freund" .. c .. "-Blackrock", ns.DIR_IN, "hi", ns.MSG_WHISPER, base + c)
end
check("many conversations", CM.Count() >= 120, CM.Count())

local problems = audit(_G.WhatTheWhisperHistoryDB, "HistoryDB")
check("history contains only serialisable data", #problems == 0,
	table.concat(problems, "\n      ", 1, math.min(#problems, 5)))
problems = audit(_G.WhatTheWhisperDB, "DB")
check("settings contain only serialisable data", #problems == 0,
	table.concat(problems, "\n      ", 1, math.min(#problems, 5)))

--------------------------------------------------------------------------------
-- Round trip through the file
--------------------------------------------------------------------------------

local encoded = "return " .. serialize(_G.WhatTheWhisperHistoryDB)
local chunk, compileError = loadstring(encoded)
check("history serialises to loadable Lua", chunk ~= nil, compileError)
local restored = chunk and chunk() or {}
local restoredStore = restored.chars and restored.chars["Testchar-Blackrock"]
check("round trip keeps the character store", restoredStore ~= nil)
eq("round trip keeps every message",
	restoredStore and #restoredStore.conv["TenK-Blackrock"].msgs or -1, 10000)
eq("round trip keeps the text",
	restoredStore and restoredStore.conv["TenK-Blackrock"].msgs[500][MSG_TEXT] or "",
	"eintrag 500")
eq("round trip keeps the schema version", restored.version, ns.SCHEMA_VERSION)
check("encoded size is sane for 11k messages", #encoded < 3 * 1024 * 1024,
	("%d bytes"):format(#encoded))

--------------------------------------------------------------------------------
-- Pruning
--------------------------------------------------------------------------------

local function isOrdered(list)
	local previous = 0
	for i = 1, #list do
		local ts = list[i][MSG_TS] or 0
		if ts < previous then return false end
		previous = ts
	end
	return true
end

ns.Options.Set("history.maxPerConversation", 500)
History.Prune()
local tenK = CM.Get("TenK-Blackrock")
check("per-conversation cap applied", #tenK.messages <= 500, #tenK.messages)
eq("newest message survived the cap",
	tenK.messages[#tenK.messages][MSG_TEXT], "eintrag 10000")
check("cap keeps order", isOrdered(tenK.messages))
check("cap leaves no holes", #tenK.messages == select(2, (function()
	local n = 0
	for _ in ipairs(tenK.messages) do n = n + 1 end
	return nil, n
end)()))

ns.Options.Set("history.maxConversations", 20)
History.Prune()
local remaining = 0
for _ in pairs(History.AllRecords()) do remaining = remaining + 1 end
check("conversation cap applied", remaining <= 20, remaining)

-- Pinned threads survive the conversation cap.
CM.GetOrCreate("Wichtig-Blackrock")
CM.AddMessage("Wichtig-Blackrock", ns.DIR_IN, "merken", ns.MSG_WHISPER, base)
CM.SetPinned("Wichtig-Blackrock", true)
for c = 1, 80 do
	CM.AddMessage("Fuell" .. c .. "-Blackrock", ns.DIR_IN, "x", ns.MSG_WHISPER, base + 10000 + c)
end
History.Prune()
check("pinned conversation survives the cap",
	History.AllRecords()["Wichtig-Blackrock"] ~= nil)

-- Retention window.
ns.Options.Set("history.maxConversations", 500)
ns.Options.Set("history.maxPerConversation", 10000)
local now = ns.Compat.GetServerTime()
CM.AddMessage("Alt-Blackrock", ns.DIR_IN, "sehr alt", ns.MSG_WHISPER, now - 40 * 86400)
CM.AddMessage("Alt-Blackrock", ns.DIR_IN, "neu", ns.MSG_WHISPER, now - 60)
ns.Options.Set("history.retention", "30d")
History.Prune()
local alt = CM.Get("Alt-Blackrock")
eq("message outside the window dropped", #alt.messages, 1)
eq("message inside the window kept", alt.messages[1][MSG_TEXT], "neu")

problems = audit(_G.WhatTheWhisperHistoryDB, "HistoryDB")
check("pruning leaves the file serialisable", #problems == 0,
	table.concat(problems, "\n      ", 1, math.min(#problems, 5)))

--------------------------------------------------------------------------------
-- Retention switches
--------------------------------------------------------------------------------

ns.Options.Set("history.retention", "session")
check("session mode detaches from the saved file", not History.IsPersistent())
local sessionConv = CM.GetOrCreate("Fluechtig-Blackrock")
CM.AddMessage("Fluechtig-Blackrock", ns.DIR_IN, "nur jetzt", ns.MSG_WHISPER, now)
eq("session messages still work", #sessionConv.messages, 1)
check("session messages are not in the saved file",
	History.AllRecords()["Fluechtig-Blackrock"] == nil)

ns.Options.Set("history.retention", "forever")
check("switching back re-attaches", History.IsPersistent())
check("re-attached conversation is saved again",
	History.AllRecords()["Fluechtig-Blackrock"] ~= nil)
eq("re-attached messages survived", #CM.Get("Fluechtig-Blackrock").messages, 1)

ns.Options.Set("history.retention", "off")
History.Prune()
eq("off drops stored messages", select(2, History.Stats()), 0)
ns.Options.Set("history.retention", "forever")

--------------------------------------------------------------------------------
-- Character identity
--------------------------------------------------------------------------------

local charKey = ns.Compat.PlayerFullName()
eq("character key includes the realm", charKey, "Testchar-Blackrock")
check("history is keyed per character",
	_G.WhatTheWhisperHistoryDB.chars[charKey] ~= nil)

-- A different character (or the same name after a realm transfer) gets its own
-- store and must not see or disturb the first one.
_G.WhatTheWhisperHistoryDB.chars["Testchar-Draenor"] = {
	conv = { ["Freund-Draenor"] = { msgs = { { base, 0, "vom anderen realm", 1 } } } },
}
History.Init()
check("original character store intact",
	_G.WhatTheWhisperHistoryDB.chars[charKey] ~= nil)
check("other character store untouched",
	_G.WhatTheWhisperHistoryDB.chars["Testchar-Draenor"].conv["Freund-Draenor"] ~= nil)
check("other character's threads are not loaded", CM.Get("Freund-Draenor") == nil)

--------------------------------------------------------------------------------
-- Damaged data
--------------------------------------------------------------------------------

local damaged = {
	version = ns.SCHEMA_VERSION,
	chars = {
		["Testchar-Blackrock"] = {
			conv = {
				Good = { msgs = { { base, 0, "ok", 1 }, { base + 1, 1, "auch ok", 1 } } },
				BadRecord = "not a table",
				BadMessages = { msgs = "not a table" },
				BadRow = { msgs = { { base, 0, "gut", 1 }, "kaputt", { nil, 0, "auch kaputt" } } },
			},
		},
		BadStore = 42,
	},
}
local repaired = ns.Migrations.Repair(damaged)
check("damage was repaired", repaired > 0, repaired)
eq("bad record removed", damaged.chars["Testchar-Blackrock"].conv.BadRecord, nil)
eq("bad message list replaced",
	type(damaged.chars["Testchar-Blackrock"].conv.BadMessages.msgs), "table")
eq("bad rows dropped, good rows kept",
	#damaged.chars["Testchar-Blackrock"].conv.BadRow.msgs, 1)
eq("good record survived untouched",
	#damaged.chars["Testchar-Blackrock"].conv.Good.msgs, 2)
eq("bad character store replaced", type(damaged.chars.BadStore), "table")
problems = audit(damaged, "repaired")
check("repaired data is serialisable", #problems == 0, table.concat(problems, "; "))

--------------------------------------------------------------------------------
-- Migration runner
--------------------------------------------------------------------------------

local fakeDB = { global = {} }
local fakeHistory = { chars = {} }
local stored, current = ns.Migrations.Run(fakeDB, fakeHistory)
eq("fresh install is stamped current", stored, ns.SCHEMA_VERSION)
eq("fresh install needs no migration", current, ns.SCHEMA_VERSION)

fakeDB.global.schemaVersion = ns.SCHEMA_VERSION + 5
local newerStored = ns.Migrations.Run(fakeDB, fakeHistory)
eq("newer data is left alone", newerStored, ns.SCHEMA_VERSION + 5)
eq("newer data keeps its version", fakeDB.global.schemaVersion, ns.SCHEMA_VERSION + 5)

-- A synthetic upgrade proves the runner actually walks the steps in order.
local visited = {}
ns.Migrations.steps[ns.SCHEMA_VERSION + 1] = function(db) visited[#visited + 1] = "a" end
ns.Migrations.steps[ns.SCHEMA_VERSION + 2] = function(db) visited[#visited + 1] = "b" end
local realVersion = ns.SCHEMA_VERSION
ns.SCHEMA_VERSION = realVersion + 2
fakeDB.global.schemaVersion = realVersion
local _, _, migrated = ns.Migrations.Run(fakeDB, fakeHistory)
check("migration ran", migrated)
eq("steps ran in order", table.concat(visited, ""), "ab")
eq("version advanced to current", fakeDB.global.schemaVersion, realVersion + 2)

-- A failing step must not claim success.
ns.Migrations.steps[realVersion + 2] = function() error("boom") end
fakeDB.global.schemaVersion = realVersion + 1
local stoppedAt = ns.Migrations.Run(fakeDB, fakeHistory)
eq("a failed step leaves the version behind", stoppedAt, realVersion + 1)
ns.SCHEMA_VERSION = realVersion
ns.Migrations.steps[realVersion + 1] = nil
ns.Migrations.steps[realVersion + 2] = nil

--------------------------------------------------------------------------------
-- Logout
--------------------------------------------------------------------------------

M.FireEvent("PLAYER_LOGOUT")
M.RunTimers(2)
problems = audit(_G.WhatTheWhisperHistoryDB, "HistoryDB")
check("data is still serialisable after logout", #problems == 0,
	table.concat(problems, "; "))
check("no soft errors during the run", #softErrors == 0, table.concat(softErrors, "; "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
