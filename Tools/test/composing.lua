-- Three things a messenger is expected to do without being asked:
--
--   * a link shift-clicked in the game goes into the box being typed in
--   * a half-written message is still there after a reload
--   * a line that is sent often can be sent in one click
--
-- Run as `lua5.1 composing.lua`. The reload part starts a second process: the
-- first writes what the game would have saved, the second loads from it.

local ROOT = "/home/user/WhatTheWhisper/"
local PHASE, SAVED = arg[1], arg[2]

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
		print("FAIL [composing] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local function serialize(value)
	local t = type(value)
	if t == "string" then return string.format("%q", value) end
	if t ~= "table" then return tostring(value) end
	local out = {}
	for k, v in pairs(value) do
		out[#out + 1] = "[" .. serialize(k) .. "]=" .. serialize(v)
	end
	return "{" .. table.concat(out, ",") .. "}"
end

--------------------------------------------------------------------------------
-- A second session, started from what the first one saved
--------------------------------------------------------------------------------

if PHASE == "second" then
	_G.WhatTheWhisperHistoryDB = dofile(SAVED)
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM, UI, L, Compat = ns.ConversationManager, ns.UI, ns.L, ns.Compat
ns.Options.Set("messages.openOnWhisper", false)
ns.Options.Set("sounds.cooldown", 0)

local thrallID = Compat.NormalizeName("Thrall")
local jainaID = Compat.NormalizeName("Jaina")

if PHASE == "second" then
	--------------------------------------------------------------------------
	-- After the reload
	--------------------------------------------------------------------------
	local thrall = CM.Get(thrallID)
	check("the conversation is back", thrall ~= nil)
	eq("with the half-written message in it", thrall and thrall.draft, "bin gleich da, nur noch")
	check("and nothing for the one that was sent", CM.Get(jainaID) == nil
		or (CM.Get(jainaID).draft or "") == "")

	UI.Show()
	CM.Select(thrallID)
	M.RunFrames(20)
	local composer = ns.MainWindow.Get().view.composer
	eq("the box shows it", composer.input:GetText(), "bin gleich da, nur noch")
	check("which counts as something to send", composer.send.active ~= false)

	local huge = CM.Get(Compat.NormalizeName("Garrosh"))
	check("a draft too long to keep was not kept", huge == nil or (huge.draft or "") == "")

	check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
	check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))
	print(("\n%d passed, %d failed"):format(pass, fail))
	os.exit(fail == 0 and 0 or 1)
end

--------------------------------------------------------------------------------
-- The first session
--------------------------------------------------------------------------------

local line = 800
local function whisper(text, sender)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(1)
end
-- Frames pass between clicks, the way they do for a person.
local function nextFrame() M.now = (M.now or 0) + 0.05 M.RunFrames(1) end

whisper("hi", "Thrall")
whisper("hi", "Jaina")
UI.Show()
CM.Select(thrallID)
M.RunFrames(20)
local window = ns.MainWindow.Get()
local composer = window.view.composer
local gameBox = _G.DEFAULT_CHAT_FRAME_EDITBOX

local ITEM = "|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
local SPELL = "|cff71d5ff|Hspell:133|h[Fireball]|h|r"

--------------------------------------------------------------------------------
-- Links
--------------------------------------------------------------------------------

composer:Focus()
M.RunFrames(2)
check("the composer has the keyboard", composer:HasFocus())
ChatFrameUtil.InsertLink(ITEM)
eq("a shift-clicked item goes into it", composer.input:GetText(), ITEM)
check("and not into the game's own box", (gameBox:GetText() or "") == "")
nextFrame()

composer.input:SetText("schau mal ")
composer:Focus()
nextFrame()
ChatFrameUtil.InsertLink(SPELL)
check("after what is already there", composer.input:GetText():find("^schau mal ")
	and composer.input:GetText():find("Fireball", 1, true), composer.input:GetText())
nextFrame()

-- The same click reaching the addon by both names is one link.
composer.input:SetText("")
nextFrame()
ChatFrameUtil.InsertLink(ITEM)
_G.ChatEdit_InsertLink(ITEM)
local _, count = composer.input:GetText():gsub("Thunderfury", "")
eq("heard by both names, it goes in once", count, 1)
nextFrame()

-- The keyboard went somewhere else, but this is still the box being used.
composer.input:SetText("")
composer.input:ClearFocus()
nextFrame()
check("the composer let go of the keyboard", not composer:HasFocus())
ChatFrameUtil.InsertLink(SPELL)
check("the last box typed in still takes a link", composer.input:GetText():find("Fireball", 1, true))
check("and has the keyboard again", composer:HasFocus())
nextFrame()

-- If the game's own box is open, that is where it goes, and only there.
composer.input:SetText("")
gameBox:Show()
gameBox:SetFocus()
nextFrame()
ChatFrameUtil.InsertLink(ITEM)
check("with the game's chat box open, the link is the game's", (gameBox:GetText() or ""):find("Thunderfury", 1, true))
eq("and the composer is left alone", composer.input:GetText(), "")
gameBox:SetText("")
gameBox:ClearFocus()
nextFrame()

-- A window of its own for another conversation is a composer as well.
ns.Popout.Open(jainaID)
M.RunFrames(10)
local popout = ns.Popout.Get(jainaID)
local pcomposer = popout.view.composer
pcomposer:Focus()
nextFrame()
ChatFrameUtil.InsertLink(SPELL)
check("a window's own composer takes it", pcomposer.input:GetText():find("Fireball", 1, true))
eq("and the messenger's does not", composer.input:GetText(), "")
ns.Popout.CloseAll()
nextFrame()

-- Nothing on screen to type in.
UI.Hide()
M.RunFrames(6)
composer.input:SetText("")
ChatFrameUtil.InsertLink(ITEM)
eq("with the messenger closed, nothing is inserted anywhere", composer.input:GetText(), "")
nextFrame()

--------------------------------------------------------------------------------
-- Drafts
--------------------------------------------------------------------------------

UI.Show()
CM.Select(thrallID)
M.RunFrames(20)
composer:Focus()
composer.input:SetText("bin gleich da, nur noch")
nextFrame()
local thrall = CM.Get(thrallID)
eq("what is typed is the thread's draft", thrall.draft, "bin gleich da, nur noch")
eq("and it is in what the game will save", thrall.record and thrall.record.dr,
	"bin gleich da, nur noch")

-- Sending ends it.
CM.Select(jainaID)
M.RunFrames(10)
composer.input:SetText("kommt gleich")
nextFrame()
composer:Submit()
M.RunTimers(1)
M.RunFrames(4)
eq("a message that went leaves no draft behind", CM.Get(jainaID).record and CM.Get(jainaID).record.dr, nil)

-- Spaces are not a draft.
composer.input:SetText("    ")
nextFrame()
eq("whitespace alone is not kept", CM.Get(jainaID).record and CM.Get(jainaID).record.dr, nil)

-- A document is not a draft.
whisper("hi", "Garrosh")
local garrosh = CM.Get(Compat.NormalizeName("Garrosh"))
CM.SetDraft(garrosh.id, string.rep("x", 1200))
eq("a pasted document is kept in the box", #garrosh.draft, 1200)
eq("but not in the file", garrosh.record and garrosh.record.dr, nil)

-- A thread with nothing in it but a draft is not tidied away.
ns.History.Clear(thrallID)
local _, removed = ns.History.Prune()
check("an empty thread with a draft survives the tidy-up", CM.Get(thrallID) ~= nil
	and ns.History.GetRecord(thrallID, false) ~= nil)

-- A damaged file does not take the box down with it.
local rec = ns.History.GetRecord(jainaID, false)
rec.dr = { "not", "text" }
local repaired = ns.Migrations.Repair(_G.WhatTheWhisperHistoryDB)
check("a draft that is not text is dropped by the repair", repaired >= 1 and rec.dr == nil)

--------------------------------------------------------------------------------
-- Quick replies
--------------------------------------------------------------------------------

local QR = ns.QuickReplies
local function menuEntries()
	local captured
	local realOpen = ns.Menu.Open
	ns.Menu.Open = function(entries) captured = entries end
	composer:OpenQuickReplies()
	ns.Menu.Open = realOpen
	return captured or {}
end
local function entryNamed(entries, text)
	for _, e in ipairs(entries) do if e.text == text then return e end end
end

UI.Show()
CM.Select(thrallID)
M.RunFrames(20)
check("the composer has a quick replies button", composer.quick ~= nil and composer.quick:IsShown())
check("beside the emoji one, not on top of it", composer.quick:GetRight() <= composer.emoji:GetLeft() + 0.5)
check("and the field starts after both", composer.input:GetLeft() >= composer.emoji:GetRight() - 0.5)

check("until the player writes their own, the list is the starters", not QR.IsCustom())
eq("four of them", #QR.List(), 4)
eq("in the language the addon is in", QR.List()[1], L["On my way"])

composer.input:SetText("")
local entries = menuEntries()
local first = entryNamed(entries, L["On my way"])
check("the menu lists them", first ~= nil)
check("and ends with the way to change them", entryNamed(entries, L["Edit quick replies..."]) ~= nil)
first.onClick()
eq("choosing one puts it in the box", composer.input:GetText(), "On my way")
check("without sending it", #CM.Get(thrallID).messages == 0 or CM.Get(thrallID).messages[#CM.Get(thrallID).messages][ns.MSG_DIR] ~= ns.DIR_OUT)

composer.input:SetText("Hi")
menuEntries()
entryNamed(menuEntries(), L["Thank you!"]).onClick()
eq("after something written, with a space between", composer.input:GetText(), "Hi Thank you!")
composer.input:SetText("")

-- Writing their own.
local saved = QR.Set({ "  gleich  ", "", "bin da\n\nfast", string.rep("x", 400) })
eq("empty lines are dropped, the rest trimmed", saved[1], "gleich")
eq("a line break is a space", saved[2], "bin da fast")
eq("and a line is one whisper at most", #saved[3], QR.MAX_BYTES)
check("the list is now the player's", QR.IsCustom())
eq("and is what the menu shows", entryNamed(menuEntries(), "gleich") ~= nil, true)
check("the starters are gone from it", entryNamed(menuEntries(), L["On my way"]) == nil)

local many = {}
for i = 1, 15 do many[i] = "Zeile " .. i end
eq("at most ten", #QR.Set(many), QR.MAX)

QR.Set({})
eq("an empty list stays empty", #QR.List(), 0)
local only = menuEntries()
eq("with only the way to change it in the menu", #only, 1)
QR.Reset()
check("restoring brings the starters back", not QR.IsCustom() and #QR.List() == 4)

-- The editor.
ns.Dialogs.QuickReplies()
M.RunFrames(4)
local dialog = ns.Dialogs.quickDialog
check("the editor opens", dialog and dialog:IsShown())
eq("with a field for every line there can be", #dialog.fields, QR.MAX)
eq("the first holding the first starter", dialog.fields[1]:GetText(), L["On my way"])
dialog.fields[1]:SetText("Bin gleich zurück")
dialog.fields[2]:SetText("")
dialog.fields[3]:SetText("Danke dir")
for i = 4, QR.MAX do dialog.fields[i]:SetText("") end
M.Click(dialog.save, "LeftButton")
M.RunFrames(2)
check("saving closes it", not dialog:IsShown())
local list = QR.List()
eq("and keeps what was written, in order", table.concat(list, "|"), "Bin gleich zurück|Danke dir")

ns.Dialogs.QuickReplies()
M.RunFrames(2)
M.Click(dialog.restore, "LeftButton")
M.RunFrames(2)
check("Restore the starters refills the fields", dialog.fields[1]:GetText() == L["On my way"]
	and not QR.IsCustom())
M.Click(dialog.cancel, "LeftButton")
check("Cancel changes nothing", not dialog:IsShown() and not QR.IsCustom())

-- Back to the half-written message the second session is going to look for.
CM.Select(thrallID)
M.RunFrames(4)
composer.input:SetText("bin gleich da, nur noch")
nextFrame()

-- It is offered in Settings.
local found
for _, category in ipairs(ns.Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			if row.label == L["Quick replies"] and row.type == "button" then found = row end
		end
	end
end
check("Settings > Messages has a button for it", found ~= nil)
if found then
	dialog:Hide()
	found.onClick()
	check("which opens the editor", dialog:IsShown())
	dialog:Hide()
end

--------------------------------------------------------------------------------
-- Hand over to the second session
--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

M.FireEvent("PLAYER_LOGOUT")
local path = os.tmpname()
local fh = assert(io.open(path, "w"))
fh:write("return " .. serialize(_G.WhatTheWhisperHistoryDB))
fh:close()
local pipe = assert(io.popen(("lua5.1 %s second %s 2>&1"):format(
	ROOT .. "Tools/test/composing.lua", path)))
local out = pipe:read("*a")
pipe:close()
os.remove(path)
local sp, sf = out:match("(%d+) passed, (%d+) failed")
check("the second session ran", sp ~= nil, out)
if sp then
	pass = pass + tonumber(sp)
	fail = fail + tonumber(sf)
	if tonumber(sf) > 0 then print(out) end
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
