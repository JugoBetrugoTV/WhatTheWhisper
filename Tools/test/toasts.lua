-- The notification card: where it appears, how big it is, and trying it out.
--
-- Four corners were all there was. Now the card can be dragged anywhere -- a
-- sample follows the mouse and is remembered where it is let go -- it has a
-- size, and there is a button that shows one without waiting for a whisper.

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
		print("FAIL [toasts] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end
local function near(label, got, want)
	check(label, type(got) == "number" and math.abs(got - want) < 0.51,
		("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local CM, Toast = ns.ConversationManager, ns.Toast
ns.Options.Set("messages.openOnWhisper", false)
ns.Options.Set("notifications.summarise", false)

local line = 700
local function whisper(text, sender)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "",
		0, line, "G-" .. sender)
	M.RunTimers(1)
	M.RunFrames(2)
end
local function settle()
	M.RunFrames(4)
end
local function clear()
	Toast.DismissAll()
	M.RunTimers(1)
	M.RunFrames(8)
end

--------------------------------------------------------------------------------
-- As it was
--------------------------------------------------------------------------------

whisper("hallo", "Thrall")
local first = Toast.Active()[1]
check("a whisper with the window closed shows a card", first ~= nil)
eq("in the top right corner out of the box", first and (first:GetPoint(1)), "TOPRIGHT")
eq("at its normal size", first and first:GetScale(), 1)
clear()

--------------------------------------------------------------------------------
-- A test notification
--------------------------------------------------------------------------------

ns.Options.Set("notifications.toasts", false)
local sample = Toast.ShowSample()
settle()
check("the test button shows a card even with notifications off",
	sample ~= nil and sample:IsShown())
eq("it reads as a whisper would", sample and sample.body:GetText(),
	ns.L["Hello! This is a test."])
if sample then
	sample._scripts.OnMouseUp(sample, "LeftButton")
	settle()
end
check("clicking it does not open the messenger on a thread that does not exist",
	not ns.UI.IsShown())
ns.Options.Set("notifications.toasts", true)
clear()

--------------------------------------------------------------------------------
-- Size
--------------------------------------------------------------------------------

ns.Options.Set("notifications.scale", 1.4)
whisper("größer", "Jaina")
local big = Toast.Active()[1]
eq("the size setting scales the card", big and big:GetScale(), 1.4)
ns.Options.Set("notifications.scale", 1)
settle()
eq("and a card on screen follows a change", big and big:GetScale(), 1)
clear()

--------------------------------------------------------------------------------
-- Moving
--------------------------------------------------------------------------------

Toast.StartMoving()
settle()
local mover = _G.WhatTheWhisperToastMover
check("Move shows a sample to drag", mover ~= nil and mover:IsShown())
check("which says what to do", mover and mover.name:GetText() == ns.L["Drag to move"] and mover.body:GetText() ==
	ns.L["Right-click when done."], mover and mover.body:GetText())
local special = false
for _, name in ipairs(_G.UISpecialFrames or {}) do
	if name == "WhatTheWhisperToastMover" then special = true end
end
check("and Escape puts it away", special)

-- The player drags it to the left side, a little above the middle.
local screenH = UIParent:GetHeight()
mover:ClearAllPoints()
mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 200, screenH * 0.7)
settle()
mover._scripts.OnDragStop(mover)
eq("letting go chooses the player's own position",
	ns.Setting("notifications.position"), "custom")
local anchor = ns.Setting("notifications.anchor")
near("remembered where it was let go (left)", anchor and anchor.x, 200)
near("and (top)", anchor and anchor.y, screenH * 0.7)
mover._scripts.OnMouseUp(mover, "RightButton")
check("a right click puts the sample away", not mover:IsShown())

whisper("hier", "Anduin")
whisper("und hier", "Varian")
local a, b = Toast.Active()[1], Toast.Active()[2]
near("the next whisper appears where the sample was left", a and a:GetLeft(), 200)
near("top edge too", a and a:GetTop(), screenH * 0.7)
check("above the middle, the next card stacks below it",
	a and b and b:GetTop() < a:GetTop(), b and b:GetTop())
clear()

-- A bigger card keeps its corner where it was put.
ns.Options.Set("notifications.scale", 1.5)
whisper("groß", "Anduin")
local scaled = Toast.Active()[1]
near("at another size the corner stays put (left)",
	scaled and scaled:GetLeft() * scaled:GetScale(), 200)
near("(top)", scaled and scaled:GetTop() * scaled:GetScale(), screenH * 0.7)
ns.Options.Set("notifications.scale", 1)
clear()

-- Below the middle the stack grows upward, so it never runs off the screen.
Toast.StartMoving()
mover:ClearAllPoints()
mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 200, screenH * 0.3)
mover._scripts.OnDragStop(mover)
Toast.StopMoving()
whisper("unten", "Thrall")
whisper("unten auch", "Jaina")
a, b = Toast.Active()[1], Toast.Active()[2]
check("below the middle, the next card stacks above",
	a and b and b:GetTop() > a:GetTop(), b and b:GetTop())
clear()

-- The corners still work, and picking one leaves the dragged place alone.
ns.Options.Set("notifications.position", "bottomleft")
whisper("ecke", "Thrall")
eq("a corner picked afterwards is used", Toast.Active()[1] and (Toast.Active()[1]:GetPoint(1)),
	"BOTTOMLEFT")
check("and the dragged place is kept for later", ns.Setting("notifications.anchor") ~= nil)
clear()

--------------------------------------------------------------------------------
-- In the settings
--------------------------------------------------------------------------------

local rows = {}
for _, category in ipairs(ns.Options.BuildSchema()) do
	for _, card in ipairs(category.cards or {}) do
		for _, row in ipairs(card.rows or {}) do
			rows[#rows + 1] = row
		end
	end
end
local function rowWith(field, value)
	for _, row in ipairs(rows) do
		if row[field] == value then return row end
	end
end
check("the settings have a Move button", rowWith("label", ns.L["Move notifications"]) ~= nil)
check("a size slider", rowWith("path", "notifications.scale") ~= nil)
check("and a test button", rowWith("label", ns.L["Show a test notification"]) ~= nil)
local positions = rowWith("path", "notifications.position")
local hasCustom = false
for _, option in ipairs(positions and positions.options or {}) do
	if option.value == "custom" then hasCustom = true end
end
check("and the position list names the player's own place", hasCustom)

local moveRow = rowWith("label", ns.L["Move notifications"])
if moveRow then
	moveRow.onClick()
	settle()
	check("the Move button shows the sample", Toast.IsMoving())
	moveRow.onClick()
	settle()
	check("and pressing it again puts it away", not Toast.IsMoving())
end

-- A reset profile goes back to the corner.
ns.db:ResetProfile()
settle()
eq("a reset puts them back in the corner", ns.Setting("notifications.position"), "topright")
eq("at the normal size", ns.Setting("notifications.scale"), 1)

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
