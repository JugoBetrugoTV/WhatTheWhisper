-- Combat behaviour: nothing the addon does while the player is in combat may
-- touch a protected frame, and every combat mode must restore cleanly.

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

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM = ns.ConversationManager
local guid = "G-THRALL"
M.guids = { [guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" } }

local function whisper(text)
	M.FireEvent("CHAT_MSG_WHISPER", text, "Thrall", "Common", "", "Thrall", "", 0, 0, "", 0, 1, guid)
	M.RunFrames(2)
end
local function enterCombat()
	M.inCombat = true
	M.FireEvent("PLAYER_REGEN_DISABLED")
	M.RunFrames(3)
end
local function leaveCombat()
	M.inCombat = false
	M.FireEvent("PLAYER_REGEN_ENABLED")
	M.RunFrames(3)
end
local function clearProblems()
	local list = problems
	problems = {}
	for i = 1, #M.errors do list[#list + 1] = "mock: " .. M.errors[i] end
	M.errors = {}
	return list
end

whisper("hallo")
whisper("noch was")
ns.UI.Show()
CM.Select("Thrall-Blackrock")
M.RunFrames(3)
clearProblems()

--------------------------------------------------------------------------------
-- Every combat mode, window open
--------------------------------------------------------------------------------

for _, mode in ipairs({ "nothing", "fade", "minimize", "hide" }) do
	ns.Options.Set("combat.onEnter", mode)
	ns.Options.Set("combat.onLeave", "restore")
	ns.UI.Show()
	M.RunFrames(2)
	clearProblems()

	enterCombat()
	check("entering combat with mode '" .. mode .. "' is clean",
		#clearProblems() == 0)

	whisper("nachricht im kampf " .. mode)
	check("a whisper during combat with mode '" .. mode .. "' is clean",
		#clearProblems() == 0)
	eq("the message still arrived (" .. mode .. ")",
		CM.Get("Thrall-Blackrock").messages[#CM.Get("Thrall-Blackrock").messages][ns.MSG_TEXT],
		"nachricht im kampf " .. mode)

	local ok = CM.SendMessage("Thrall-Blackrock", "antwort im kampf " .. mode)
	check("sending during combat works (" .. mode .. ")", ok)
	check("sending during combat is clean (" .. mode .. ")", #clearProblems() == 0)

	leaveCombat()
	check("leaving combat with mode '" .. mode .. "' is clean",
		#clearProblems() == 0)
end

ns.Options.Set("combat.onEnter", "hide")
ns.UI.Show()
M.RunFrames(2)
enterCombat()
eq("hide mode hides the window", ns.MainWindow.Get():IsShown(), false)
leaveCombat()
eq("restore brings it back", ns.MainWindow.Get():IsShown(), true)

ns.Options.Set("combat.onLeave", "stay")
enterCombat()
leaveCombat()
eq("stay mode leaves it hidden", ns.MainWindow.Get():IsShown(), false)
ns.Options.Set("combat.onLeave", "restore")
ns.Options.Set("combat.onEnter", "nothing")
ns.UI.Show()
M.RunFrames(2)
clearProblems()

--------------------------------------------------------------------------------
-- Popouts
--------------------------------------------------------------------------------

ns.UI.TogglePopout("Thrall-Blackrock")
M.RunFrames(2)
clearProblems()
for _, mode in ipairs({ "fade", "minimize", "hide" }) do
	ns.Options.Set("combat.onEnter", mode)
	enterCombat()
	check("popout survives combat mode '" .. mode .. "'", #clearProblems() == 0)
	whisper("popout im kampf " .. mode)
	check("popout receives a whisper in combat (" .. mode .. ")", #clearProblems() == 0)
	leaveCombat()
	check("popout restores after combat (" .. mode .. ")", #clearProblems() == 0)
end
ns.Options.Set("combat.onEnter", "nothing")
ns.Popout.CloseAll()
M.RunFrames(2)
clearProblems()

--------------------------------------------------------------------------------
-- Exposé
--------------------------------------------------------------------------------

ns.UI.Show()
ns.UI.TogglePopout("Thrall-Blackrock")
M.RunFrames(2)
enterCombat()
ns.Expose.Open()
M.RunFrames(2)
check("opening the overview in combat is clean", #clearProblems() == 0)
check("the overview opened", ns.Expose.IsOpen())
ns.Expose.Close()
M.RunFrames(2)
check("closing the overview in combat is clean", #clearProblems() == 0)
leaveCombat()
ns.Popout.CloseAll()
clearProblems()

--------------------------------------------------------------------------------
-- The one genuinely protected feature
--------------------------------------------------------------------------------

local conv = CM.Get("Thrall-Blackrock")

-- Out of combat the secure macro is attached and armed.
ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
M.RunFrames(2)
local secure = _G.WhatTheWhisperSecureTarget
check("the secure target button exists", secure ~= nil)
eq("its macro targets the right player",
	secure and secure:GetAttribute("macrotext"), "/target Thrall-Blackrock")
check("attaching it out of combat is clean", #clearProblems() == 0)
ns.Menu.Close()
check("closing the menu out of combat is clean", #clearProblems() == 0)

-- In combat the entry must be offered but disabled, and nothing protected touched.
enterCombat()
ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
M.RunFrames(2)
check("opening the menu in combat touches nothing protected", #clearProblems() == 0)
ns.Menu.Close()
check("closing the menu in combat touches nothing protected", #clearProblems() == 0)

-- Repeatedly, because Close() must not try to tidy the protected button either.
for _ = 1, 5 do
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
	ns.Menu.Close()
end
M.RunFrames(2)
check("repeated menu use in combat stays clean", #clearProblems() == 0)
leaveCombat()

-- And it re-arms correctly once combat ends.
ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
M.RunFrames(2)
eq("the macro is armed again after combat",
	_G.WhatTheWhisperSecureTarget:GetAttribute("macrotext"), "/target Thrall-Blackrock")
ns.Menu.Close()
check("re-arming after combat is clean", #clearProblems() == 0)

--------------------------------------------------------------------------------
-- Notifications and settings during combat
--------------------------------------------------------------------------------

enterCombat()
ns.UI.Hide()
whisper("toast im kampf")
M.RunFrames(3)
check("a toast during combat is clean", #clearProblems() == 0)
ns.Toast.DismissAll()
M.RunFrames(3)

ns.SettingsUI.Show()
ns.SettingsUI.SelectCategory("combat")
ns.SettingsUI.Hide()
M.RunFrames(2)
check("the settings window works in combat", #clearProblems() == 0)

ns.Options.Set("appearance.skin", "glass")
ns.Options.Set("appearance.skin", "midnight")
M.RunFrames(2)
check("re-skinning in combat is clean", #clearProblems() == 0)
leaveCombat()

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
