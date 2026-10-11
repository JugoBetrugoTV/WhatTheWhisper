-- The composer's keys: Up and Down bring back what was already said in the
-- thread, Tab and Shift+Tab move through the conversations.
--
-- Both come from WIM, where they are among the things its players miss first:
-- a whisper that did not arrive is one key away from being sent again, and the
-- next person to answer is one key away without reaching for the mouse.

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
		print("FAIL [keys] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
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

local CM = ns.ConversationManager
ns.Options.Set("messages.openOnWhisper", false)

local line = 200
local function whisper(text, sender)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(2)
end

local function settle()
	M.RunTimers(1)
	M.RunFrames(4)
end

whisper("hallo", "Thrall")
whisper("moin", "Jaina")
whisper("na?", "Anduin")

ns.UI.Show()
CM.Select("Thrall-Blackrock")
settle()
local window = ns.MainWindow.Get()
local composer = window.view.composer
local field = composer.input
local box = field.editBox

local function press(key)
	local script = box._scripts and box._scripts.OnArrowPressed
	check("the field listens to the arrow keys", script ~= nil)
	if script then script(box, key) end
end
local function tab(shift)
	local script = box._scripts and box._scripts.OnTabPressed
	check("the field listens to Tab", script ~= nil)
	M.shift = shift or false
	if script then script(box) end
	M.shift = false
	settle()
end

--------------------------------------------------------------------------------
-- Up and Down
--------------------------------------------------------------------------------

for _, text in ipairs({ "erste", "zweite", "dritte" }) do
	CM.SendMessage("Thrall-Blackrock", text)
end
M.RunTimers(2)
field:Focus()

press("UP")
eq("Up in an empty field brings back the last thing said here", field:GetText(), "dritte")
press("UP")
eq("and again, the one before", field:GetText(), "zweite")
press("UP")
eq("and the first", field:GetText(), "erste")
press("UP")
eq("past the first, it stays", field:GetText(), "erste")
press("DOWN")
eq("Down goes forward again", field:GetText(), "zweite")
press("DOWN")
press("DOWN")
eq("and past the newest, the field is empty again", field:GetText(), "")
press("DOWN")
eq("Down in an empty field does nothing", field:GetText(), "")

-- Something the player typed belongs to the caret.
field:SetText("ich schreibe gerade")
press("UP")
eq("Up in a field with the player's own text leaves it alone", field:GetText(),
	"ich schreibe gerade")

-- ...and so does a recalled message once it has been changed.
field:SetText("")
press("UP")
field:SetText("dritte, aber anders")
press("UP")
eq("a recalled message that was edited is the player's own", field:GetText(),
	"dritte, aber anders")

-- Enter sends what was brought back.
field:SetText("")
press("UP")
press("UP")
M.sent = {}
composer:Submit()
M.RunTimers(2)
eq("a recalled message is sent like any other", M.sent[1] and M.sent[1].text, "zweite")
eq("and the field is empty after", field:GetText(), "")
press("UP")
eq("after which Up starts from the newest again", field:GetText(), "zweite")
field:SetText("")

-- Each thread has its own.
CM.Select("Jaina-Blackrock")
settle()
press("UP")
eq("a thread with nothing said in it has nothing to bring back", field:GetText(), "")

-- A message that never arrived is exactly the one worth sending again.
CM.SendMessage("Jaina-Blackrock", "bist du da?")
M.RunTimers(2)
M.FireEvent("CHAT_MSG_SYSTEM", _G.ERR_CHAT_PLAYER_NOT_FOUND_S:format("Jaina"))
M.RunTimers(2)
field:SetText("")
press("UP")
eq("an undelivered message can be brought back", field:GetText(), "bist du da?")
field:SetText("")

-- Switching thread in the middle of it starts over.
CM.Select("Thrall-Blackrock")
settle()
press("UP")
eq("Thrall's thread brings back Thrall's messages", field:GetText(), "zweite")
CM.Select("Jaina-Blackrock")
settle()
check("and the half-finished recall does not follow to Jaina",
	field:GetText() ~= "zweite", field:GetText())
field:SetText("")
CM.Select("Thrall-Blackrock")
settle()
field:SetText("")

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

local order = {}
for _, conv in ipairs(window.sidebar.filtered) do order[#order + 1] = conv.id end
eq("three conversations in the list", #order, 3)

CM.Select(order[1])
settle()
field:Focus()
tab()
eq("Tab moves to the next conversation in the list", CM.SelectedID(), order[2])
check("and the keyboard stays in the composer", field:HasFocus())
tab()
tab()
eq("from the last, Tab goes round to the first", CM.SelectedID(), order[1])
tab(true)
eq("Shift+Tab goes back, round to the last", CM.SelectedID(), order[3])

-- The draft stays with its thread.
CM.Select(order[1])
settle()
field:SetText("halb fertig")
tab()
eq("the next thread has its own empty field", field:GetText(), "")
tab(true)
eq("and the half-written message is still in the first", field:GetText(), "halb fertig")
field:SetText("")

-- A filtered sidebar is the list the player sees, so it is the list Tab uses.
window.sidebar:SetFilter("Jaina")
settle()
CM.Select("Jaina-Blackrock")
settle()
tab()
eq("with the list filtered to one, Tab has nowhere to go", CM.SelectedID(), "Jaina-Blackrock")
window.sidebar:SetFilter("")
settle()

-- Without a sidebar, the tabs are the list.
ns.Options.Set("layout.mode", "tabbed")
settle()
local tabs = ns.UI.GetTabOrder()
check("the tabbed layout has tabs to move through", #tabs >= 2, #tabs)
if #tabs >= 2 then
	CM.Select(tabs[1])
	settle()
	tab()
	eq("in the tabbed layout, Tab follows the tabs", CM.SelectedID(), tabs[2])
end
ns.Options.Set("layout.mode", "sidebar")
settle()

-- A window of its own has one conversation, and Tab there does nothing at all.
ns.Popout.Open("Anduin-Blackrock")
settle()
local popout = ns.Popout.Get("Anduin-Blackrock")
local before = CM.SelectedID()
local popBox = popout.view.composer.input.editBox
local script = popBox._scripts and popBox._scripts.OnTabPressed
if script then script(popBox) end
settle()
eq("Tab in a conversation's own window changes nothing", CM.SelectedID(), before)

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
