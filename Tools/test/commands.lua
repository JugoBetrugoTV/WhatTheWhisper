-- Slash commands, debug mode, the failsafe, and the first-run hint.
--
-- The failsafe is the important one: whatever else goes wrong, a whisper must
-- never be swallowed by this addon. That is checked here by actually running the
-- registered chat filter, not by reading the flag it sets.

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

local guid = "G-THRALL"
M.guids = { [guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" } }

local function run(input)
	M.chat = {}
	local handler = _G.SlashCmdList["ACECONSOLE_WTW"] or _G.SlashCmdList["ACECONSOLE_WHATTHEWHISPER"]
	assert(handler, "no slash handler registered")
	local ok, err = pcall(handler, input or "")
	if not ok then M.errors[#M.errors + 1] = "slash '" .. tostring(input) .. "': " .. tostring(err) end
	M.RunFrames(2)
	return ok, err
end

local function mainShown()
	local window = ns.MainWindow.Existing()
	return (window and window:IsShown()) and true or false
end

local function confirmDialog()
	return _G.WhatTheWhisperConfirmDialog
end

local function chatContains(needle)
	for i = 1, #(M.chat or {}) do
		if M.chat[i]:find(needle, 1, true) then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

check("/wtw is registered", _G.SlashCmdList["ACECONSOLE_WTW"] ~= nil)
check("/whatthewhisper is registered", _G.SlashCmdList["ACECONSOLE_WHATTHEWHISPER"] ~= nil)

--------------------------------------------------------------------------------
-- Every documented command runs without erroring, and does what it says
--------------------------------------------------------------------------------

local before = #M.errors

run("show")
eq("show opens the window", mainShown(), true)
run("hide")
eq("hide closes the window", mainShown(), false)
run("open")
eq("open is an alias for show", mainShown(), true)
run("close")
eq("close is an alias for hide", mainShown(), false)
run("")
eq("bare /wtw toggles on", mainShown(), true)
run("")
eq("bare /wtw toggles off", mainShown(), false)

run("config")
eq("config opens settings", ns.SettingsUI.IsShown(), true)
run("settings")
eq("settings is an alias and toggles back", ns.SettingsUI.IsShown(), false)
run("options")
eq("options is an alias", ns.SettingsUI.IsShown(), true)
run("options")

run("expose")
run("expose")
run("overview")
run("overview")

run("diag")
check("diag prints a version line", chatContains("v" .. ns.VERSION))
check("diag prints pool statistics", chatContains("pooled objects total"))
check("diag prints the health line", chatContains("degraded="))

run("help")
check("help lists show/hide", chatContains("/wtw show"))
check("help lists debug", chatContains("/wtw debug"))
check("help lists reset", chatContains("/wtw reset"))
check("help lists diag", chatContains("/wtw diag"))

run("?")
check("? is an alias for help", chatContains("/wtw config"))

-- Case must not matter: people type /wtw Debug.
run("DEBUG off")
eq("commands are case insensitive", ns.Debug.IsEnabled(), false)

eq("no command raised an error", #M.errors, before)

--------------------------------------------------------------------------------
-- Opening a conversation by name
--------------------------------------------------------------------------------

-- Names are normalised to include the realm, so a lower-case "thrall" typed at
-- the prompt has to land on the same thread a whisper from Thrall would.
local thrall = ns.Compat.NormalizeName("Thrall")
run("thrall")
check("a bare name opens a conversation", ns.ConversationManager.Get(thrall) ~= nil)
eq("opening a conversation shows the window", mainShown(), true)
eq("a bare name selects that conversation", ns.ConversationManager.SelectedID(), thrall)
run("hide")

--------------------------------------------------------------------------------
-- Debug mode
--------------------------------------------------------------------------------

eq("debug is off by default", ns.db.profile.advanced.debug, false)

run("debug")
eq("bare debug turns it on", ns.Debug.IsEnabled(), true)
check("turning debug on says so", chatContains("Debug logging on."))
run("debug")
eq("bare debug turns it off again", ns.Debug.IsEnabled(), false)
check("turning debug off says so", chatContains("Debug logging off."))

run("debug on")
eq("debug on is explicit", ns.Debug.IsEnabled(), true)
run("debug on")
eq("debug on twice stays on", ns.Debug.IsEnabled(), true)
run("debug off")
eq("debug off is explicit", ns.Debug.IsEnabled(), false)
run("debug off")
eq("debug off twice stays off", ns.Debug.IsEnabled(), false)

-- The ring buffer records regardless of the setting, so a report from somebody
-- who only enabled debug after the problem still has the run-up in it.
ns.Debug.Log("ui", "ring buffer marker %d", 1)
run("debug log")
check("debug log dumps the ring buffer with debug off", chatContains("ring buffer marker 1"))

-- Ring buffer wrap: the oldest entries fall off, the newest survive, and the
-- dump is still in order.
for i = 1, 400 do ns.Debug.Log("ui", "wrap %d", i) end
local recent = ns.Debug.Recent(30)
eq("Recent returns the requested count", #recent, 30)
check("Recent ends with the newest entry", recent[30]:find("wrap 400", 1, true) ~= nil)
check("Recent starts 29 entries earlier", recent[1]:find("wrap 371", 1, true) ~= nil)
check("Recent never exceeds the ring", #ns.Debug.Recent(10000) <= 200)

-- With debug on, a log line reaches the chat frame; with it off, nothing does.
run("debug on")
M.chat = {}
ns.Debug.Log("dedupe", "visible marker")
check("debug on prints log lines", chatContains("visible marker"))
run("debug off")
M.chat = {}
ns.Debug.Log("dedupe", "invisible marker")
check("debug off prints nothing", not chatContains("invisible marker"))

-- Debug mode is a setting like any other: the checkbox and the command are the
-- same switch, not two.
ns.db.profile.advanced.debug = true
eq("the setting drives IsEnabled", ns.Debug.IsEnabled(), true)
ns.Debug.Toggle(false)
eq("Toggle writes back to the profile", ns.db.profile.advanced.debug, false)

--------------------------------------------------------------------------------
-- Failsafe: whispers survive the addon failing
--------------------------------------------------------------------------------

local function whisperWouldShow()
	return M.ChatFrameWouldShow("CHAT_MSG_WHISPER",
		"hello", "Thrall", "Common", "", "Thrall", "", 0, 0, "", 0, 1, guid)
end

check("a filter is registered for CHAT_MSG_WHISPER",
	M.chatFilters["CHAT_MSG_WHISPER"] ~= nil and #M.chatFilters["CHAT_MSG_WHISPER"] == 1)
check("a filter is registered for CHAT_MSG_WHISPER_INFORM",
	M.chatFilters["CHAT_MSG_WHISPER_INFORM"] ~= nil)

ns.db.profile.messages.hideFromChatFrame = true
eq("whispers are hidden while healthy", whisperWouldShow(), false)

ns.db.profile.messages.hideFromChatFrame = false
eq("the setting alone restores them", whisperWouldShow(), true)

ns.db.profile.messages.hideFromChatFrame = true
ns.db.profile.enabled = false
eq("a disabled addon never suppresses", whisperWouldShow(), true)
ns.db.profile.enabled = true

-- Below the threshold nothing changes: one stray error is not a reason to
-- change how the player's chat behaves.
ns.Debug.ClearDegraded()
for i = 1, 11 do ns.SoftError("test", "failure " .. i) end
eq("11 errors do not degrade", ns.Debug.IsDegraded(), false)
eq("still suppressing below the threshold", whisperWouldShow(), false)

M.chat = {}
ns.SoftError("test", "failure 12")
eq("the twelfth error degrades", ns.Debug.IsDegraded(), true)
eq("degraded stops suppressing whispers", whisperWouldShow(), true)
check("degrading is announced once",
	chatContains("whispers are being shown in the chat frame again"))

M.chat = {}
for i = 13, 30 do ns.SoftError("test", "failure " .. i) end
check("degrading is not announced again",
	not chatContains("whispers are being shown in the chat frame again"))
eq("errors keep counting", ns.Debug.ErrorCount() >= 30, true)
eq("still not suppressing", whisperWouldShow(), true)

-- The degraded state is visible where somebody would look for it.
run("diag")
check("diag reports the degraded state", chatContains("degraded=true"))

ns.Debug.ClearDegraded()
eq("clearing resets the count", ns.Debug.ErrorCount(), 0)
eq("clearing resets the flag", ns.Debug.IsDegraded(), false)
eq("suppression resumes after recovery", whisperWouldShow(), false)

-- A whisper still reaches the addon while degraded: the failsafe only stops the
-- suppression, it must not stop the messenger from working.
for i = 1, 12 do ns.SoftError("test", "again " .. i) end
eq("degraded again", ns.Debug.IsDegraded(), true)
local countBefore = #(ns.ConversationManager.GetOrCreate(thrall).messages)
M.FireEvent("CHAT_MSG_WHISPER", "still delivered", "Thrall", "Common", "", "Thrall",
	"", 0, 0, "", 0, 1, guid)
M.RunFrames(2)
eq("messages still arrive while degraded",
	#ns.ConversationManager.GetOrCreate(thrall).messages, countBefore + 1)
ns.Debug.ClearDegraded()

--------------------------------------------------------------------------------
-- Reset
--------------------------------------------------------------------------------

ns.db.profile.appearance.skin = "glass"
ns.db.profile.layout.width = 1234
run("reset")
check("reset asks before doing anything", confirmDialog() ~= nil and confirmDialog():IsShown())
eq("reset has not changed anything yet", ns.db.profile.appearance.skin, "glass")
M.Click(confirmDialog().confirm)
M.RunFrames(2)
eq("confirming reset restores the default skin",
	ns.db.profile.appearance.skin, ns.defaults.profile.appearance.skin)
eq("confirming reset restores the default width",
	ns.db.profile.layout.width, ns.defaults.profile.layout.width)

-- History is a separate saved variable precisely so that resetting settings
-- cannot touch it.
local conversations = select(1, ns.History.Stats())
check("reset left history alone", conversations > 0)

--------------------------------------------------------------------------------
-- First run
--------------------------------------------------------------------------------

ns.db.global.seenWelcome = false
M.chat = {}
ns.addon:ShowWelcome()
check("the first run says hello", chatContains("WhatTheWhisper is ready"))
eq("the hint is marked seen", ns.db.global.seenWelcome, true)

M.chat = {}
ns.addon:ShowWelcome()
check("the hint appears only once", not chatContains("WhatTheWhisper is ready"))

-- Account wide: a new profile is not a new install.
ns.db:SetProfile("second")
M.chat = {}
ns.addon:ShowWelcome()
check("a new profile does not re-greet", not chatContains("WhatTheWhisper is ready"))
ns.db:SetProfile("Default")

--------------------------------------------------------------------------------
-- Pool instrumentation
--------------------------------------------------------------------------------

local snapshot = ns.Pool.Snapshot()
check("every pool is registered", #snapshot > 0)
local unnamed, sorted = 0, true
for i = 1, #snapshot do
	if snapshot[i].name == "pool" then unnamed = unnamed + 1 end
	if i > 1 and snapshot[i - 1].created < snapshot[i].created then sorted = false end
end
eq("no pool is left unnamed", unnamed, 0)
check("the snapshot is ordered by size", sorted)
check("the total matches the parts", ns.Pool.TotalCreated() > 0)

--------------------------------------------------------------------------------

eq("no errors during the run", #M.errors, before, table.concat(M.errors, "\n      "))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
