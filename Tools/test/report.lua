-- Reporting a whisper.
--
-- The game's way to report a whisper is a right click on the sender's name in
-- its chat window -- and with whispers shown in the messenger only, there is no
-- such name anywhere. An addon may not file the report itself
-- (C_ReportSystem.SendReport: "Not allowed to be called by addons"), and
-- opening Blizzard's report window from addon code taints the report. So the
-- addon puts the name back where the game handles it: a player link in the chat
-- window, carrying the whisper's chat line, whose right-click menu has Report.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

-- The client's report system, as far as an addon may touch it: it may ask
-- whether a line can be reported, and it may not send one.
local refuse = {}
local sentReports = 0
_G.PlayerLocation = {}
function PlayerLocation:CreateFromChatLineID(lineID) return { lineID = lineID } end
_G.C_ReportSystem = {
	CanReportPlayer = function(location) return not refuse[location.lineID] end,
	SendReport = function() sentReports = sentReports + 1 end,
}

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL [report] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
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

local CM, UI, L = ns.ConversationManager, ns.UI, ns.L
ns.Options.Set("messages.openOnWhisper", false)

local line = 500
local function whisper(text, sender)
	line = line + 1
	M.chatLines[line] = { text = text, sender = sender, guid = "G-" .. sender }
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(2)
	return line
end

local function menuEntry(entries, text)
	for _, entry in ipairs(entries) do
		if entry.text == text then return entry end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The conversation menu
--------------------------------------------------------------------------------

local first = whisper("du noob", "Thrall")
local last = whisper("uninstall", "Thrall")
local conv = CM.Get("Thrall-Blackrock")
local entry = menuEntry(UI.BuildConversationMenu(conv), L["Report"])
check("the conversation menu offers Report", entry ~= nil and not entry.disabled)

M.chat = {}
if entry and entry.onClick then entry.onClick() end
local printed = M.chat[#M.chat] or ""
check("which puts the name into the chat window", printed:find("|Hplayer:", 1, true) ~= nil, printed)
check("as the chat window's own link, on the newest whisper",
	printed:find("|Hplayer:Thrall:" .. last .. ":WHISPER:Thrall|h[Thrall]|h", 1, true) ~= nil, printed)
check("and says what to do with it", printed:find(L["Right-click %s, then choose Report in the menu."]:match("^[^%%]+"), 1, true) ~= nil, printed)
eq("nothing was reported by the addon itself", sentReports, 0)

--------------------------------------------------------------------------------
-- A single message
--------------------------------------------------------------------------------

ns.UI.Show()
CM.Select("Thrall-Blackrock")
M.RunFrames(4)
local list = ns.MainWindow.Get().view.list
local firstMsg = conv.messages[1]
local bubble
for _, f in ipairs(M.frames) do
	if f.msg == firstMsg and f:IsVisible() then bubble = f end
end
check("the first whisper has a bubble", bubble ~= nil)
if bubble then
	M.chat = {}
	list:OpenMessageMenu(bubble)
	M.RunFrames(2)
	local menu = ns.Menu.Current and ns.Menu.Current()
	local reportEntry
	for _, f in ipairs(M.frames) do
		if f.entry and f.entry.text == L["Report"] and f:IsVisible() then reportEntry = f.entry end
	end
	check("its menu offers Report", reportEntry ~= nil, menu)
	if reportEntry then reportEntry.onClick() end
	local text = M.chat[#M.chat] or ""
	check("filed against that message, not the newest",
		text:find(":" .. first .. ":WHISPER:", 1, true) ~= nil, text)
	ns.Menu.Close()
end

-- The player's own messages are not theirs to report.
CM.SendMessage("Thrall-Blackrock", "selber")
M.RunTimers(2)
check("a sent message cannot be reported", not CM.CanReport(conv, conv.messages[#conv.messages]))

--------------------------------------------------------------------------------
-- When it cannot be offered
--------------------------------------------------------------------------------

-- Loaded from history: the line it arrived on means nothing any more.
local old = CM.AddMessage("Jaina-Blackrock", ns.DIR_IN, "von gestern", ns.MSG_WHISPER)
local jaina = CM.Get("Jaina-Blackrock")
check("a whisper from before a reload cannot be reported", not CM.CanReport(jaina, old))
entry = menuEntry(UI.BuildConversationMenu(jaina), L["Report"])
check("so the menu shows Report greyed out", entry ~= nil and entry.disabled == true)
eq("and says why", entry and entry.tooltip, L["Only whispers from this session can be reported."])

-- A line that has aged out of the client's store.
local aged = whisper("alt", "Anduin")
M.invalidLines[aged] = true
local anduin = CM.Get("Anduin-Blackrock")
check("a line the client no longer has cannot be reported",
	not CM.CanReport(anduin, anduin.messages[1]))

-- A line the client itself says it would not take a report for.
local refused = whisper("hallo", "Varian")
refuse[refused] = true
check("a line the client refuses is not offered",
	not CM.CanReport(CM.Get("Varian-Blackrock"), CM.Get("Varian-Blackrock").messages[1]))

-- A conversation with nothing from them has nothing to report.
CM.GetOrCreate("Garrosh-Blackrock")
check("an empty thread has no Report at all",
	menuEntry(UI.BuildConversationMenu(CM.Get("Garrosh-Blackrock")), L["Report"]) == nil)

-- Battle.net: the game's own link for those carries no line to report against.
M.bnet = { [7001] = { tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }
M.bnFriends = { { id = 7001, tag = "Kumpel#1111", name = "Kumpel", character = "Main" } }
line = line + 1
M.FireEvent("CHAT_MSG_BN_WHISPER", "moin", "Kumpel", "", "", "", "", 0, 0, "", 0, line, "", 7001)
M.RunTimers(2)
local bn = CM.Get("BN:Kumpel#1111")
check("a Battle.net thread exists", bn ~= nil)
if bn then
	check("and offers no Report", menuEntry(UI.BuildConversationMenu(bn), L["Report"]) == nil)
end

-- The line ids live for the session only: kept beside the message, never in
-- it, so nothing of them is written to the saved history.
local inRecord = false
for _, msg in ipairs(conv.messages) do
	for _, value in pairs(msg) do
		if value == first or value == last then inRecord = true end
	end
end
check("no chat line id is stored in the message record", not inRecord)

eq("the addon never sent a report", sentReports, 0)

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
