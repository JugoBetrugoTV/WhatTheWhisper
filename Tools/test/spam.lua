-- Three things from WIM, each reduced to what it is for:
--
--   * a spam filter -- a stranger's whisper with one of the player's words is
--     kept, silently, at the bottom of the list, and gone from the chat window
--   * windows that stay shut inside dungeons, raids and PvP, if asked
--   * inviting to the guild, for players who may

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local played = 0
_G.PlaySound = function() played = played + 1 return true end
local instanceType
_G.IsInInstance = function() return instanceType ~= nil, instanceType or "none" end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL [spam] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
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

local CM, UI, L, Toast = ns.ConversationManager, ns.UI, ns.L, ns.Toast
ns.Options.Set("sounds.cooldown", 0)
ns.Options.Set("messages.openOnWhisper", false)
-- Messenger and chat: the case where the chat window would otherwise show spam.
ns.Options.Set("messages.hideFromChatFrame", false)

local line = 900
local shownInChat
local function whisper(text, sender)
	line = line + 1
	local args = { text, sender, "Common", "", sender, "", 0, 0, "", 0, line, "G-" .. sender }
	shownInChat = M.ChatFrameReceives("CHAT_MSG_WHISPER", unpack(args, 1, 12))
	M.FireEvent("CHAT_MSG_WHISPER", unpack(args, 1, 12))
	M.RunTimers(1)
	M.RunFrames(2)
end
local function menuEntry(conv, text)
	for _, entry in ipairs(UI.BuildConversationMenu(conv)) do
		if entry.text == text then return entry end
	end
end

M.friends = { { name = "Jaina", connected = true } }
M.guildRoster = { { name = "Anduin-Blackrock", level = 70, class = "PRIEST" } }
M.inGuild = true

--------------------------------------------------------------------------------
-- Off until the player writes a word
--------------------------------------------------------------------------------

played = 0
whisper("billiges gold", "Verkaeufer")
local seller = CM.Get("Verkaeufer-Blackrock")
check("with no words, nothing is filtered", seller and not seller.filtered)
check("and the whisper interrupts as always", played > 0 and #Toast.Active() > 0)
Toast.DismissAll()
M.RunTimers(1)
M.RunFrames(6)

--------------------------------------------------------------------------------
-- A stranger's whisper with one of the words
--------------------------------------------------------------------------------

ns.Options.Set("filter.words", "Gold, WTS , 100%")
played = 0
local unreadBefore = CM.TotalUnread()
local toastsBefore = #Toast.Active()
local flashesBefore = M.flashes or 0
whisper("WTS cheap GOLD, visit our site", "Goldhaendler")
local spam = CM.Get("Goldhaendler-Blackrock")
check("the whisper is kept", spam ~= nil and #spam.messages == 1)
check("in a thread marked as filtered", spam and spam.filtered == true)
eq("no sound", played, 0)
eq("no card", #Toast.Active(), toastsBefore)
eq("no flash", M.flashes or 0, flashesBefore)
eq("nothing counted unread", CM.TotalUnread(), unreadBefore)
check("and gone from the chat window", shownInChat == false)
check("the messenger was not opened for it", not UI.IsShown())
check("and it is not what the Reply key answers",
	ns.ChatEvents.ReplyTarget() ~= "Goldhaendler-Blackrock")

-- Case does not matter, and the words are plain text: "100%" means itself.
check("a word matches in any case", ns.SpamFilter.Matches("buy gOlD"))
check("and a percent sign is just a percent sign", ns.SpamFilter.Matches("100% legit"))
check("while a near miss is not a match", not ns.SpamFilter.Matches("goal"))

-- The same stranger again, without any of the words: the thread stays quiet.
played = 0
whisper("hallo?", "Goldhaendler")
check("a filtered thread stays filtered", spam.filtered and #spam.messages == 2)
eq("and stays silent", played, 0)
check("and out of the chat window", shownInChat == false)

-- The list: at the bottom, and saying why.
local ordered = CM.Ordered()
eq("a filtered thread sorts last", ordered[#ordered].id, "Goldhaendler-Blackrock")
UI.Show()
M.RunFrames(4)
local window = ns.MainWindow.Get()
window.sidebar:Refresh()
M.RunFrames(2)
local previewText
for _, f in ipairs(M.frames) do
	if f.conv == spam and f.preview and f:IsVisible() then previewText = f.preview:GetText() end
end
check("its row says it is filtered", previewText and previewText:find(L["Filtered"], 1, true) == 1,
	previewText)
UI.Hide()
M.RunFrames(4)

-- It is remembered.
check("the verdict is saved with the thread", spam.record ~= nil and spam.record.fl == true)

--------------------------------------------------------------------------------
-- Who is never filtered
--------------------------------------------------------------------------------

whisper("hast du gold?", "Jaina")
check("a friend is never filtered", not CM.Get("Jaina-Blackrock").filtered)
whisper("brauche gold", "Anduin")
check("nor a guildmate", not CM.Get("Anduin-Blackrock").filtered)
CM.SendMessage("Thrall-Blackrock", "hi")
M.RunTimers(2)
whisper("WTS mount", "Thrall")
check("nor anyone the player has written to", not CM.Get("Thrall-Blackrock").filtered)

M.bnet = { [7001] = { tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }
M.bnFriends = { { id = 7001, tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }
line = line + 1
M.FireEvent("CHAT_MSG_BN_WHISPER", "gold gold", "Kumpel", "", "", "", "", 0, 0, "", 0, line, "", 7001)
M.RunTimers(2)
check("nor a Battle.net friend", CM.Get("BN:Kumpel#1111") and not CM.Get("BN:Kumpel#1111").filtered)

--------------------------------------------------------------------------------
-- The player's verdict
--------------------------------------------------------------------------------

local notSpam = menuEntry(spam, L["Not spam"])
check("a filtered thread offers Not spam", notSpam ~= nil)
if notSpam then notSpam.onClick() end
check("which lifts the filter", not spam.filtered)
check("and that is saved too", spam.record and spam.record.fl == nil and spam.record.ns == true)
played = 0
whisper("gold ist wieder da", "Goldhaendler")
check("and the words do not catch that thread again", not spam.filtered)
check("so it interrupts like any other", played > 0)

local markSpam = menuEntry(CM.Get("Verkaeufer-Blackrock"), L["Mark as spam"])
check("any other thread offers Mark as spam", markSpam ~= nil)
if markSpam then markSpam.onClick() end
eq("which files it away", CM.Get("Verkaeufer-Blackrock").filtered, true)
eq("and clears its unread count", CM.Get("Verkaeufer-Blackrock").unread, 0)
check("Battle.net threads are not offered either",
	menuEntry(CM.Get("BN:Kumpel#1111"), L["Mark as spam"]) == nil)
Toast.DismissAll()
M.RunTimers(1)
M.RunFrames(6)

--------------------------------------------------------------------------------
-- Windows inside instances
--------------------------------------------------------------------------------

ns.Options.Set("messages.openOnWhisper", true)
instanceType = "raid"
whisper("bist du im raid?", "Varian")
check("out of the box a whisper opens the messenger, even in a raid", UI.IsShown())
UI.Hide()
M.RunFrames(4)

ns.Options.Set("messages.openInInstances", false)
-- Sounds in raids have a switch of their own, off by default; on here, so the
-- check below is about the window rule and nothing else.
ns.Options.Set("sounds.muteRaid", false)
played = 0
whisper("jetzt?", "Garrosh")
check("with the option off, the messenger stays shut in a raid", not UI.IsShown())
check("while the card and the sound still come", played > 0 and #Toast.Active() > 0)
ns.Options.Set("sounds.muteRaid", true)
Toast.DismissAll()
M.RunTimers(1)
M.RunFrames(6)

instanceType = nil
whisper("und draussen?", "Garrosh")
check("outside an instance it opens as usual", UI.IsShown())
UI.Hide()
M.RunFrames(4)
ns.Options.Set("messages.openInInstances", true)
ns.Options.Set("messages.openOnWhisper", false)

--------------------------------------------------------------------------------
-- Inviting to the guild
--------------------------------------------------------------------------------

local garrosh = CM.Get("Garrosh-Blackrock")
check("no guild invite without the right to invite", menuEntry(garrosh, L["Invite to guild"]) == nil)
M.canGuildInvite = true
local invite = menuEntry(garrosh, L["Invite to guild"])
check("with it, the menu offers Invite to guild", invite ~= nil)
if invite then invite.onClick() end
eq("which invites them by name", M.guildInvites[1], "Garrosh")
check("not offered for somebody already in the guild",
	menuEntry(CM.Get("Anduin-Blackrock"), L["Invite to guild"]) == nil)
check("nor for a Battle.net thread",
	menuEntry(CM.Get("BN:Kumpel#1111"), L["Invite to guild"]) == nil)

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
