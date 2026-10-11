-- The Reply key, and "/r ", with whispers shown in the messenger only.
--
-- The game learns who to reply to from its own chat frame, after the message
-- filters have run: a whisper this addon took out of the chat frame is one the
-- Reply key never hears about. Out of the box that meant R went to nobody at
-- all, or to whoever last whispered while nothing was being hidden -- a reply
-- typed to the wrong person. The mock's chat frame and chat box behave the way
-- Blizzard's do (M.ChatFrameReceives, ChatFrameUtil.ReplyTell, ProcessChatType),
-- so what the player would see is what is tested.

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
		print("FAIL [reply] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
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

local CM, UI = ns.ConversationManager, ns.UI
local box = _G.DEFAULT_CHAT_FRAME_EDITBOX
-- Nothing pops up on its own here: the point is what the Reply key opens.
ns.Options.Set("messages.openOnWhisper", false)
ns.Options.Set("messages.openOnCompose", false)

-- A whisper as the client delivers it: the chat frame first (it registered at
-- login, before any addon), then everybody else.
local line = 100
local function whisper(text, sender)
	line = line + 1
	M.ChatFrameReceives("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(2)
end

local function mainComposerFocused()
	local window = ns.MainWindow.Existing()
	return window ~= nil and window.view.composer.input:HasFocus()
end

local function settle()
	M.RunTimers(1)
	M.RunFrames(4)
end

local function reset()
	UI.Hide()
	ns.Popout.CloseAll()
	settle()
	if M.focus then M.focus:ClearFocus() end
	box:SetChatType("SAY")
	box:SetTellTarget(nil)
	box:SetText("")
	box:Hide()
end

--------------------------------------------------------------------------------
-- The report: nothing happens when R is pressed
--------------------------------------------------------------------------------

eq("whispers are shown in the messenger only, out of the box",
	ns.Setting("messages.hideFromChatFrame"), true)

whisper("hey, bist du da?", "Thrall")
eq("the game never heard of the whisper, so it has nobody to reply to",
	(ChatFrameUtil.GetLastTellTarget()), nil)

ChatFrameUtil.ReplyTell()
settle()
check("R opens the messenger", UI.IsShown())
eq("on the person who whispered", CM.SelectedID(), "Thrall-Blackrock")
check("with the keyboard in the reply field", mainComposerFocused(), tostring(M.focus))

--------------------------------------------------------------------------------
-- Worse: the game's answer is somebody else
--------------------------------------------------------------------------------

reset()
-- Jaina whispered while whispers were still going to the chat frame too...
ns.Options.Set("messages.hideFromChatFrame", false)
whisper("kommst du mit?", "Jaina")
eq("a whisper the chat frame shows is one the game can reply to",
	(ChatFrameUtil.GetLastTellTarget()), "Jaina")
-- ...and Thrall afterwards, with the chat frame kept clear.
ns.Options.Set("messages.hideFromChatFrame", true)
whisper("noch was", "Thrall")
eq("so the game still thinks the last whisper was Jaina's",
	(ChatFrameUtil.GetLastTellTarget()), "Jaina")

ChatFrameUtil.ReplyTell()
settle()
eq("R answers Thrall, who wrote last", CM.SelectedID(), "Thrall-Blackrock")
check("in the messenger's reply field", mainComposerFocused(), tostring(M.focus))
check("and the chat box the game opened on Jaina is closed again", not box:IsShown())
check("without a whisper to Jaina left in it", box:GetChatType() ~= "WHISPER",
	tostring(box:GetChatType()) .. " " .. tostring(box:GetTellTarget()))

-- The reply itself goes where the thread says.
M.sent = {}
CM.SendMessage(CM.SelectedID(), "gleich")
M.RunTimers(2)
eq("and what is typed there goes to Thrall", M.sent[1] and M.sent[1].target, "Thrall")

--------------------------------------------------------------------------------
-- "/r " typed into a chat box
--------------------------------------------------------------------------------

reset()
box:Show()
box:SetFocus()
box:ProcessChatType("", "REPLY", 0)
settle()
eq("/r answers Thrall too", CM.SelectedID(), "Thrall-Blackrock")
check("in the messenger", mainComposerFocused(), tostring(M.focus))
check("and the chat box lets go of the whisper to Jaina", not box:IsShown()
	and box:GetChatType() ~= "WHISPER")

-- Any other chat type is none of this addon's business.
reset()
box:Show()
box:SetFocus()
box:ProcessChatType("", "GUILD", 0)
settle()
check("/g is left alone", not UI.IsShown() and M.focus == box)

--------------------------------------------------------------------------------
-- When the game already has the right person
--------------------------------------------------------------------------------

reset()
ns.Options.Set("messages.hideFromChatFrame", false)
whisper("bin da", "Jaina")
ns.Options.Set("messages.hideFromChatFrame", true)
ChatFrameUtil.ReplyTell()
settle()
check("a whisper shown in the chat frame is the game's to reply to", not UI.IsShown())
check("and its chat box keeps the keyboard", M.focus == box)
eq("on the right person", box:GetTellTarget(), "Jaina")

-- A whisper the addon cannot file stays in the chat frame, and so does its reply.
reset()
whisper("noch mal", "Thrall")
whisper("", "Anduin")
ChatFrameUtil.ReplyTell()
settle()
check("a whisper left in the chat frame is newer than one taken out of it",
	not UI.IsShown() and box:GetTellTarget() == "Anduin", tostring(box:GetTellTarget()))

--------------------------------------------------------------------------------
-- Its own window, when that is how whispers open
--------------------------------------------------------------------------------

reset()
ns.Options.Set("messages.openAs", "window")
whisper("hier drüben", "Thrall")
ChatFrameUtil.ReplyTell()
settle()
local popout = ns.Popout.Get("Thrall-Blackrock")
check("R opens the conversation's own window", popout ~= nil and popout:IsShown())
check("with the keyboard in it", popout ~= nil and popout.view.composer.input:HasFocus(),
	tostring(M.focus))
check("and leaves the messenger shut", not UI.IsShown())

-- The messenger's own menu stays in the messenger: "Whisper" picked from the
-- list there opening a separate window would be a surprise.
reset()
whisper("und hier", "Jaina")
local whisperEntry
for _, entry in ipairs(UI.BuildConversationMenu(CM.Get("Jaina-Blackrock"))) do
	if entry.text == ns.L["Whisper"] then whisperEntry = entry end
end
check("the menu offers Whisper", whisperEntry ~= nil)
if whisperEntry then
	whisperEntry.onClick()
	settle()
	check("which opens the messenger", UI.IsShown())
	eq("on that thread", CM.SelectedID(), "Jaina-Blackrock")
	check("and no window of its own", not ns.Popout.IsOpen("Jaina-Blackrock"))
	check("with the keyboard in the reply field", mainComposerFocused(), tostring(M.focus))
end
ns.Options.Set("messages.openAs", "messenger")

--------------------------------------------------------------------------------
-- Where the addon stays out of it
--------------------------------------------------------------------------------

reset()
whisper("im arena?", "Thrall")
M.chatLockdown = true
ChatFrameUtil.ReplyTell()
settle()
check("in chat lockdown the Reply key is the game's alone", not UI.IsShown())
M.chatLockdown = false

reset()
whisper("aus?", "Thrall")
ns.db.profile.enabled = false
ChatFrameUtil.ReplyTell()
settle()
check("a disabled addon does nothing", not UI.IsShown())
ns.db.profile.enabled = true

-- A whisper that arrives while the addon is disabled goes to the chat frame,
-- which makes it the game's reply target, not the hidden one before it.
reset()
whisper("zuerst", "Thrall")
ns.db.profile.enabled = false
whisper("dann ich", "Jaina")
ns.db.profile.enabled = true
ChatFrameUtil.ReplyTell()
settle()
check("so R answers Jaina through the chat box", not UI.IsShown()
	and box:GetTellTarget() == "Jaina", tostring(box:GetTellTarget()))

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
