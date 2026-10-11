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
	M.SetCombat(true)
	M.RunFrames(3)
end
local function leaveCombat()
	M.SetCombat(false)
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
-- The one genuinely protected feature: adding a friend, through /friend
--------------------------------------------------------------------------------

local conv = CM.Get("Thrall-Blackrock")

-- Out of combat the secure macro is attached and armed.
ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
M.RunFrames(2)
local secure = _G.WhatTheWhisperSecureAction
check("the secure target button exists", secure ~= nil)
eq("its macro names the right player",
	secure and secure:GetAttribute("macrotext"), "/friend Thrall")
check("attaching it out of combat is clean", #clearProblems() == 0)

-- It has to sit exactly over the Add friend entry: it is placed by coordinates now,
-- not anchored, so a wrong conversion would leave a click area beside the row.
local function targetRow()
	local menu = _G.WhatTheWhisperContextMenu
	for i = 1, #M.frames do
		local row = M.frames[i]
		if row._parent == menu and row:IsShown() and row.entry and row.entry.secureMacro then
			return row
		end
	end
end
do
	local row = targetRow()
	local host = secure and secure:GetParent()
	check("the Add friend entry is in the menu", row ~= nil)
	if row and host then
		local k = row:GetEffectiveScale() / host:GetEffectiveScale()
		local function near(a, b) return a and b and math.abs(a - b) < 0.01 end
		check("the click area covers the Add friend entry exactly",
			near(host:GetLeft(), row:GetLeft() * k) and near(host:GetBottom(), row:GetBottom() * k)
			and near(host:GetWidth(), row:GetWidth() * k) and near(host:GetHeight(), row:GetHeight() * k),
			("host %s,%s %sx%s  row %s,%s %sx%s"):format(host:GetLeft(), host:GetBottom(),
				host:GetWidth(), host:GetHeight(), row:GetLeft(), row:GetBottom(), row:GetWidth(), row:GetHeight()))
		check("and is drawn above it", host:GetFrameLevel() > row:GetFrameLevel()
			and host:GetFrameStrata() == row:GetFrameStrata())
		check("the host is not the menu's child, so the menu stays free in combat",
			host:GetParent() ~= _G.WhatTheWhisperContextMenu)
	end
end
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
	_G.WhatTheWhisperSecureAction:GetAttribute("macrotext"), "/friend Thrall")
ns.Menu.Close()
check("re-arming after combat is clean", #clearProblems() == 0)

-- The case that actually happens: the menu is open with the button armed, and a
-- mob notices you. Combat starts with a live secure button on the screen, and
-- the addon is no longer allowed to hide it, move it, or hide anything it is
-- parented to or anchored to -- so whatever takes it away has to be the secure
-- environment itself, not addon code.
do
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
	M.RunFrames(2)
	local secureButton = _G.WhatTheWhisperSecureAction
	local host = secureButton and secureButton:GetParent()
	check("the target overlay is up before combat", host ~= nil and host:IsShown())
	clearProblems()

	local row = targetRow()
	M.SetCombat(true)
	M.RunFrames(3)
	check("the open menu's Add friend entry greys out when combat starts",
		row ~= nil and row.__wtwEnabled == false and row.label.__wtwRole == "textDisabled",
		row and tostring(row.label.__wtwRole))
	check("combat starting takes the target overlay down on its own",
		host ~= nil and not host:IsShown(),
		"a live secure button left over a closed menu acts on whoever it last named")
	check("and that touched nothing protected from addon code", #clearProblems() == 0)

	ns.Menu.Close()
	M.RunFrames(2)
	check("closing a menu that was armed before combat is clean", #clearProblems() == 0,
		"the menu, the overlay's host and anything anchored to it are all locked now")
	check("and leaves no overlay behind", not host:IsShown())

	-- Pressing Escape is the other way a menu closes, and it goes through the
	-- client's own CloseSpecialWindows, then into the addon's OnHide hook.
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
	M.RunFrames(2)
	_G.WhatTheWhisperContextMenu:Hide()
	M.RunFrames(2)
	check("closing it with Escape in combat is clean too", #clearProblems() == 0)

	M.SetCombat(false)
	M.RunFrames(3)
	check("leaving combat does not bring a stale overlay back", not host:IsShown())
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
	M.RunFrames(2)
	check("and the next menu out of combat arms it again",
		host:IsShown() and secureButton:GetAttribute("macrotext") == "/friend Thrall",
		tostring(secureButton:GetAttribute("macrotext")))
	ns.Menu.Close()
	check("all of that out of combat is clean", #clearProblems() == 0)
end

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
