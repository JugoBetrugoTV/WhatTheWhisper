-- Taking a conversation away.
--
-- A player who cleared a thread's history was left with an empty row they had no
-- way to remove: "Close conversation" shut a tab, "Clear history" emptied the
-- thread, and nothing took the thread itself out of the list.

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
		print("FAIL [delete] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM, UI, L, History = ns.ConversationManager, ns.UI, ns.L, ns.History
ns.Options.Set("messages.openOnWhisper", false)
ns.Options.Set("sounds.cooldown", 0)

local line = 700
local function whisper(text, sender)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(1)
end
local function menuEntry(conv, text)
	for _, entry in ipairs(UI.BuildConversationMenu(conv)) do
		if entry.text == text then return entry end
	end
end
local function answer(accept)
	M.RunFrames(2)
	local d = _G.WhatTheWhisperConfirmDialog
	check("a confirmation is asked first", d and d:IsShown())
	if d and d:IsShown() then
		M.Click(accept and d.confirm or d.cancel, "LeftButton")
		M.RunFrames(2)
	end
end

whisper("hallo", "Thrall")
whisper("hallo", "Jaina")
whisper("hallo", "Sylvanas")
CM.SetPinned(ns.Compat.NormalizeName("Sylvanas"), true)
UI.Show()
M.RunFrames(6)
local window = ns.MainWindow.Get()

local thrallID = ns.Compat.NormalizeName("Thrall")
local jainaID = ns.Compat.NormalizeName("Jaina")
local thrall = CM.Get(thrallID)

--------------------------------------------------------------------------------
-- Clearing is not deleting
--------------------------------------------------------------------------------

UI.ConfirmClear(thrall)
answer(true)
check("clearing the history keeps the conversation", CM.Get(thrallID) ~= nil)
eq("with no messages", #thrall.messages, 0)

--------------------------------------------------------------------------------
-- One conversation
--------------------------------------------------------------------------------

local delete = menuEntry(thrall, L["Delete conversation"])
check("the conversation menu offers Delete conversation", delete ~= nil)
check("as a dangerous action", delete and delete.danger == true)
check("even for a conversation with no messages", delete and not delete.disabled)

ns.Popout.Open(jainaID)
M.RunFrames(4)
local before = 0
for _ in pairs(CM.All()) do before = before + 1 end

if delete then delete.onClick() end
answer(false)
check("declining keeps it", CM.Get(thrallID) ~= nil)

if delete then delete.onClick() end
answer(true)
check("confirming removes it", CM.Get(thrallID) == nil)
local after = 0
for _ in pairs(CM.All()) do after = after + 1 end
eq("and only it", after, before - 1)
local records = History.AllRecords()
check("and what is stored for it", not records or records[thrallID] == nil)
check("the other conversations are untouched", CM.Get(jainaID) ~= nil
	and #CM.Get(jainaID).messages == 1)
check("a pinned one too", CM.Get(ns.Compat.NormalizeName("Sylvanas")).pinned)

-- A notification card for it goes too: it would open nothing.
for _, card in ipairs(ns.Toast.Active()) do
	check("no card is left for a deleted conversation", card.convID ~= thrallID)
end

-- Its row is gone from the list.
window.sidebar:Refresh()
M.RunFrames(2)
local rows = 0
for _, f in ipairs(M.frames) do
	if f.conv == thrall and f:IsVisible() then rows = rows + 1 end
end
eq("the row is gone from the sidebar", rows, 0)

-- A window of its own for the deleted conversation is closed with it.
local jaina = CM.Get(jainaID)
local d2 = menuEntry(jaina, L["Delete conversation"])
d2.onClick()
answer(true)
check("a conversation's own window closes with it", not ns.Popout.IsOpen(jainaID))
check("and it is gone", CM.Get(jainaID) == nil)

-- Somebody writing again starts a fresh thread, not the old one.
whisper("wieder da", "Thrall")
local again = CM.Get(thrallID)
check("a new whisper from them makes a new conversation", again ~= nil and again ~= thrall)
eq("holding only that message", again and #again.messages, 1)

-- And it survives a logout and a login as gone.
M.FireEvent("PLAYER_LOGOUT")
local stored = History.AllRecords()
check("what was deleted is not written out", not stored or stored[jainaID] == nil)

--------------------------------------------------------------------------------
-- All of them
--------------------------------------------------------------------------------

local function settingsButton(label)
	for _, category in ipairs(ns.Options.BuildSchema()) do
		for _, card in ipairs(category.cards or {}) do
			for _, row in ipairs(card.rows or {}) do
				if row.label == label then return row end
			end
		end
	end
end
local all = settingsButton(L["Delete all conversations"])
check("Settings > History offers Delete all conversations", all ~= nil)
check("as a dangerous action", all and all.danger == true)
local clearAll = settingsButton(L["Clear all history"])
check("beside Clear all history, which keeps the rows", clearAll ~= nil)

all.onClick()
answer(false)
check("declining keeps everything", next(CM.All()) ~= nil)

all.onClick()
answer(true)
check("confirming leaves no conversation", next(CM.All()) == nil)
local count = History.Stats()
eq("and nothing stored", count, 0)
check("the window shows its empty state", window.sidebar.empty:IsShown())

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
