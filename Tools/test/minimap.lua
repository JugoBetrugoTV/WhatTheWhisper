-- The minimap button: where it sits, and what happens when it is clicked.
--
-- Every check here came out of an in-game report. The button could not be
-- clicked at all, because the drag handler declared a drag on the first frame
-- after any press and the click that ended it was then swallowed; and it sat on
-- top of the map rather than outside it.

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

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local CM = ns.ConversationManager
M.guids = {
	["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}

local function whisper(text, sender, guid)
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "", 0, 1, guid)
	M.RunTimers(2)
end

-- The window opening on its own would mark everything read before the button
-- was ever looked at, and that is a different test's subject.
ns.db.profile.messages.openOnWhisper = false
ns.db.profile.messages.openOnCompose = false

ns.Minimap.Update()
M.RunFrames(4)
local button = _G.WhatTheWhisperMinimapButton
check("the button was built", button ~= nil and button:IsShown())

--------------------------------------------------------------------------------
-- Outside the ring, not on it
--------------------------------------------------------------------------------

-- A button centred inside the minimap's radius covers the map and collides with
-- every other addon's tray. Its near edge has to clear the ring.
local minimap = _G.Minimap
for _, width in ipairs({ 140, 100, 200 }) do
	minimap:SetSize(width, width)
	for _, angle in ipairs({ 0, 45, 90, 180, 205, 300 }) do
		ns.db.profile.advanced.minimap.angle = angle
		ns.Minimap.Update()
		M.RunFrames(2)
		local bx, by = button:GetCenter()
		local mx, my = minimap:GetCenter()
		local distance = math.sqrt((bx - mx) ^ 2 + (by - my) ^ 2)
		local nearEdge = distance - button:GetWidth() / 2
		check(("minimap %d, angle %d: the button clears the ring"):format(width, angle),
			nearEdge > width / 2,
			("near edge at %.1f, ring at %.1f"):format(nearEdge, width / 2))
		-- And not so far out that it is floating in space unattached.
		check(("minimap %d, angle %d: and stays beside it"):format(width, angle),
			nearEdge < width / 2 + button:GetWidth(),
			("%.1f"):format(nearEdge))
	end
end
minimap:SetSize(140, 140)
ns.db.profile.advanced.minimap.angle = 205
ns.Minimap.Update()
M.RunFrames(2)

--------------------------------------------------------------------------------
-- Always on top of the map, whatever else is installed
--------------------------------------------------------------------------------

-- Sharing the minimap's strata puts the button in the same pile as the zone
-- text, the clock and every other addon's icon, where a higher frame level
-- anywhere in that pile hides it.
local STRATA_ORDER = {
	BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
	DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
check("the button sits above the minimap's own band",
	STRATA_ORDER[button._strata or "MEDIUM"] > STRATA_ORDER[minimap._strata or "LOW"],
	tostring(button._strata) .. " vs " .. tostring(minimap._strata))

-- A crowded minimap: something else claims a high level in the map's own band.
local intruder = CreateFrame("Frame", nil, minimap)
intruder:SetFrameStrata(minimap:GetFrameStrata())
intruder:SetFrameLevel((minimap:GetFrameLevel() or 1) + 200)
ns.Minimap.Update()
M.RunFrames(2)
check("and still above a neighbour that raised itself",
	STRATA_ORDER[button._strata or "MEDIUM"] > STRATA_ORDER[intruder._strata or "LOW"])

-- A world transition rebuilds the minimap; the button has to come back with it.
M.FireEvent("PLAYER_ENTERING_WORLD")
M.RunFrames(4)
check("it survives a loading screen", button:IsShown())

--------------------------------------------------------------------------------
-- Left click opens it
--------------------------------------------------------------------------------

-- A real click spans at least one frame, which is where this used to break: the
-- drag handler's OnUpdate ran in between, declared a drag with the cursor
-- exactly where it started, and the release was discarded.
check("the messenger starts closed", ns.UI.IsShown() == false)
M.Click(button, "LeftButton")
M.RunFrames(8)
check("left click opens the messenger", ns.UI.IsShown())

M.Click(button, "LeftButton")
M.RunFrames(12)
check("and clicking again closes it", ns.UI.IsShown() == false)

-- Held longer, still a click as long as the cursor has not moved.
M.Click(button, "LeftButton", 10)
M.RunFrames(8)
check("a slow click still opens it", ns.UI.IsShown())
ns.UI.Hide()
M.RunFrames(12)

-- Moving the cursor is what makes it a drag, and a drag must not open anything.
local angleBefore = ns.db.profile.advanced.minimap.angle
local cursorX, cursorY = 500, 500
_G.GetCursorPosition = function() return cursorX, cursorY end
button:Fire("OnMouseDown", "LeftButton")
cursorX, cursorY = 640, 380
M.RunFrames(3)
button:Fire("OnMouseUp", "LeftButton")
M.RunFrames(8)
check("dragging moved the button",
	ns.db.profile.advanced.minimap.angle ~= angleBefore)
check("and did not open the messenger", ns.UI.IsShown() == false)
M.RunFrames(8)
_G.GetCursorPosition = function() return 500, 500 end

--------------------------------------------------------------------------------
-- The badge, and the names behind it
--------------------------------------------------------------------------------

eq("nothing waiting, no badge", button.badge:IsShown(), false)

whisper("bist du da?", "Thrall", "G-THRALL")
whisper("und du?", "Jaina", "G-JAINA")
whisper("noch was", "Jaina", "G-JAINA")
ns.Minimap.Update()
M.RunFrames(4)

check("the badge appears", button.badge:IsShown())
eq("with the total count", button.badge.count, 3)
check("and it is blinking", button.badge.__wtwAttentionOn == true)

-- The tooltip names who is waiting, so the count is not a riddle.
local tip = button.__wtwTooltip
check("the tooltip lists the senders", tip ~= nil and tip.subtext ~= nil)
check("Thrall is named", tip.subtext:find("Thrall", 1, true) ~= nil, tip.subtext)
check("Jaina is named", tip.subtext:find("Jaina", 1, true) ~= nil, tip.subtext)
check("with her two messages", tip.subtext:find("Jaina  2", 1, true) ~= nil, tip.subtext)
-- Newest first: Jaina wrote last.
check("newest first", tip.subtext:find("Jaina") < tip.subtext:find("Thrall"), tip.subtext)

--------------------------------------------------------------------------------
-- Clicking a name
--------------------------------------------------------------------------------

M.Click(button, "RightButton")
M.RunFrames(6)
check("right click opens the list", ns.Menu.IsOpen())

-- The rows are pooled, so the menu is read back off the frame the player sees.
local menuFrame = _G.WhatTheWhisperContextMenu
local rows = {}
for i = 1, #M.frames do
	local frame = M.frames[i]
	if frame._parent == menuFrame and frame:IsShown() and frame.label then
		rows[#rows + 1] = frame
	end
end
local jaina
for i = 1, #rows do
	if (rows[i].label:GetText() or ""):find("Jaina", 1, true) then jaina = rows[i] end
end
check("Jaina is in the list", jaina ~= nil)

if jaina then
	local onClick = jaina.onClick
	check("her row does something", type(onClick) == "function")
	ns.Menu.Close()
	onClick()
	M.RunFrames(8)
	check("clicking her name opens the messenger", ns.UI.IsShown())
	eq("on her thread", CM.SelectedID(), ns.Compat.NormalizeName("Jaina"))
	eq("which clears her unread mark", CM.Get(ns.Compat.NormalizeName("Jaina")).unread, 0)
end

ns.Menu.Close()
M.RunFrames(4)

-- Once everything is read the badge stops asking for attention rather than
-- sitting there half faded forever.
CM.MarkRead(ns.Compat.NormalizeName("Thrall"))
ns.Minimap.Update()
M.RunFrames(4)
eq("badge gone when nothing is waiting", button.badge:IsShown(), false)
check("and the blink is off", button.badge.__wtwAttentionOn ~= true)
eq("full opacity restored", button.badge:GetAlpha(), 1)

--------------------------------------------------------------------------------

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
