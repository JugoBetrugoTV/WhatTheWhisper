-- Leak and churn verification: repeating an operation must not keep creating
-- frames, and nothing may leave an OnUpdate or a tween running at rest.

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
local softErrors = {}
ns.SoftError = function(context, err) softErrors[#softErrors + 1] = context .. ": " .. tostring(err) end

local CM = ns.ConversationManager
ns.Options.Set("history.retention", "forever")

local function frames() return #M.frames end
-- Only frames that are actually shown can tick. The tween driver keeps its
-- handler attached permanently and hides itself when the queue empties, which is
-- exactly the intended design.
local function liveOnUpdate()
	local n = 0
	for i = 1, #M.frames do
		local f = M.frames[i]
		if f._shown ~= false and f._scripts and f._scripts.OnUpdate then n = n + 1 end
	end
	return n
end

--------------------------------------------------------------------------------
-- Warm up: build everything once so later counts measure churn, not creation.
--------------------------------------------------------------------------------

for c = 1, 12 do
	for i = 1, 40 do
		CM.AddMessage("Freund" .. c .. "-Blackrock", i % 2,
			"Nachricht " .. i .. " mit etwas Text dabei", ns.MSG_WHISPER, 1788000000 + i * 60)
	end
end
ns.UI.Show()
CM.Select("Freund1-Blackrock")
M.RunTimers(3)
ns.SettingsUI.Show()
ns.SettingsUI.Hide()
ns.UI.TogglePopout("Freund2-Blackrock")
ns.UI.DockConversation("Freund2-Blackrock")
ns.Menu.Open(ns.UI.BuildConversationMenu(CM.Get("Freund1-Blackrock")))
ns.Menu.Close()
ns.EmojiPicker.Open(ns.MainWindow.Get().view.composer.emoji,
	ns.MainWindow.Get().view.composer)
ns.EmojiPicker.Close()
ns.Toast.Show(CM.Get("Freund3-Blackrock"), CM.Get("Freund3-Blackrock").messages[1], false)
ns.Toast.DismissAll()
M.RunFrames(4)

local warm = frames()
print(("warm-up frames: %d"):format(warm))

--------------------------------------------------------------------------------
-- Repeating operations must not grow the frame count
--------------------------------------------------------------------------------

-- A pool legitimately grows to its steady size the first time an operation runs.
-- The leak question is whether a *second* identical pass creates anything, so
-- every measurement warms up first.
local function measure(label, times, action)
	for i = 1, times do action(i) end
	M.RunFrames(3)
	local before = frames()
	for i = 1, times do action(i) end
	M.RunFrames(3)
	local grew = frames() - before
	check(label .. " creates no frames when repeated", grew == 0,
		("%d new frames over %d repeats"):format(grew, times))
end

measure("switching conversations", 60, function(i)
	CM.Select("Freund" .. ((i % 12) + 1) .. "-Blackrock")
end)

measure("scrolling", 200, function(i)
	local list = ns.MainWindow.Get().view.list
	list:SetOffset((i * 17) % math.max(1, list:MaxOffset()), false)
end)

measure("scrolling the sidebar", 120, function(i)
	ns.MainWindow.Get().sidebar.list:SetOffset((i * 9) % 200, false)
end)

measure("receiving messages", 300, function(i)
	CM.AddMessage("Freund1-Blackrock", ns.DIR_IN, "neu " .. i, ns.MSG_WHISPER)
end)

measure("opening and closing the menu", 40, function()
	ns.Menu.Open(ns.UI.BuildConversationMenu(CM.Get("Freund1-Blackrock")))
	ns.Menu.Close()
end)

measure("popping out and docking", 30, function()
	ns.UI.TogglePopout("Freund2-Blackrock")
	ns.UI.DockConversation("Freund2-Blackrock")
end)

measure("showing and hiding the window", 40, function()
	ns.UI.Hide()
	ns.UI.Show()
end)

measure("opening the settings window", 20, function()
	ns.SettingsUI.Show()
	ns.SettingsUI.SelectCategory("appearance")
	ns.SettingsUI.SelectCategory("sounds")
	ns.SettingsUI.Hide()
end)

measure("toasting", 40, function(i)
	local conv = CM.Get("Freund" .. ((i % 12) + 1) .. "-Blackrock")
	ns.Toast.Show(conv, conv.messages[1], false)
	ns.Toast.DismissAll()
end)

measure("changing skin", 12, function(i)
	ns.Options.Set("appearance.skin", ns.Skins.order[(i % #ns.Skins.order) + 1])
end)
ns.Options.Set("appearance.skin", "midnight")

measure("filtering the sidebar", 60, function(i)
	ns.MainWindow.Get().sidebar:SetFilter(i % 2 == 0 and "freund" or "")
end)

measure("searching a conversation", 30, function(i)
	local view = ns.MainWindow.Get().view
	view:ToggleSearch(true)
	view:RunSearch("nachricht")
	view:StepSearch(1)
	view:ToggleSearch(false)
end)

--------------------------------------------------------------------------------
-- Nothing may be left running
--------------------------------------------------------------------------------

M.RunFrames(40)
eq("no tweens left running once the queue drains", ns.Anim.ActiveCount(), 0)
eq("nothing is left ticking at rest", liveOnUpdate(), 0)

--------------------------------------------------------------------------------
-- Pools recycle instead of growing
--------------------------------------------------------------------------------

local list = ns.MainWindow.Get().view.list
local createdBefore = select(1, list.bubblePool:Stats())
for i = 1, 500 do
	CM.AddMessage("Freund1-Blackrock", i % 2, "pool test " .. i, ns.MSG_WHISPER)
end
M.RunFrames(3)
local createdAfter, activeAfter = list.bubblePool:Stats()
check("bubble pool did not grow with 500 more messages",
	createdAfter == createdBefore, ("%d -> %d"):format(createdBefore, createdAfter))
check("only a viewport worth of bubbles is live", activeAfter < 40, activeAfter)

local conv = CM.Get("Freund1-Blackrock")
check("thread really is large", #conv.messages > 500, #conv.messages)

-- Released elements must not keep pointing at their content.
list.bubblePool:ReleaseAll()
local dirty = 0
for _, f in ipairs(list.bubblePool.free) do
	if f.entry ~= nil or f.msg ~= nil or f.__wtwTooltip ~= nil then dirty = dirty + 1 end
end
eq("released bubbles hold no references", dirty, 0)

local rowPool = ns.MainWindow.Get().sidebar.rowPool
rowPool:ReleaseAll()
dirty = 0
for _, row in ipairs(rowPool.free) do
	if row.conv ~= nil or row.rowIndex ~= nil then dirty = dirty + 1 end
end
eq("released sidebar rows hold no references", dirty, 0)

-- Releasing twice must not corrupt the pool.
local one = list.bubblePool:Acquire()
list.bubblePool:Release(one)
local freeAfterFirst = #list.bubblePool.free
list.bubblePool:Release(one)
eq("a double release is ignored", #list.bubblePool.free, freeAfterFirst)

check("no soft errors during the run", #softErrors == 0,
	table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))

print(("\nfinal frames: %d (warm-up %d)"):format(frames(), warm))
print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
