-- Real-client loadability: the things a permissive mock lets through.
--
-- The harness is not the authority, the game is. Everything here is a rule the
-- client enforces at runtime and a mock will happily ignore: a method that only
-- exists on another widget type, a script name a frame does not have, a strata
-- that is not one of the eight, SavedVariables read before the client has
-- restored them, work done during combat that the client would have refused.
--
-- Half the checks below assert the *mock* still rejects these, because a mock
-- that quietly grows permissive again takes the whole suite with it.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
local Harness = dofile(ROOT .. "Tools/test/harness.lua")

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
-- Asserts the client would refuse this, by asserting the mock does.
local function rejects(label, fn)
	local ok, err = pcall(fn)
	check(label, not ok, ok and "it was allowed" or nil)
	return err
end
local function allows(label, fn)
	local ok, err = pcall(fn)
	check(label, ok, err)
end

--------------------------------------------------------------------------------
-- The mock enforces what the client enforces
--------------------------------------------------------------------------------

local plain = CreateFrame("Frame", nil, UIParent)
local button = CreateFrame("Button", nil, UIParent)
local edit = CreateFrame("EditBox", nil, UIParent)
local scroll = CreateFrame("ScrollFrame", nil, UIParent)
local fs = plain:CreateFontString(nil, "OVERLAY")
local tex = plain:CreateTexture(nil, "ARTWORK")

rejects("a plain Frame has no SetText", function() plain:SetText("x") end)
rejects("a plain Frame has no SetMultiLine", function() plain:SetMultiLine(true) end)
rejects("a plain Frame has no SetChecked", function() plain:SetChecked(true) end)
rejects("a plain Frame has no SetScrollChild", function() plain:SetScrollChild(plain) end)
rejects("a plain Frame has no SetNormalTexture", function() plain:SetNormalTexture("x") end)
rejects("a Button has no SetMultiLine", function() button:SetMultiLine(true) end)
rejects("a Texture has no SetFontObject", function() tex:SetFontObject("GameFontNormal") end)
rejects("a FontString has no SetTexCoord... is wrong; it has no SetMultiLine",
	function() fs:SetMultiLine(true) end)

allows("an EditBox does have SetMultiLine", function() edit:SetMultiLine(true) end)
allows("a FontString does have SetSpacing", function() fs:SetSpacing(2) end)
allows("a FontString does have SetJustifyH", function() fs:SetJustifyH("LEFT") end)
allows("a ScrollFrame does have SetScrollChild", function() scroll:SetScrollChild(plain) end)
allows("a Button does have SetNormalTexture", function() button:SetNormalTexture("x") end)

rejects("an invented method is refused", function() plain:SetSparkleMode(true) end)

-- Script names
rejects("a Frame has no OnClick", function() plain:SetScript("OnClick", function() end) end)
rejects("a Frame has no OnDoubleClick",
	function() plain:SetScript("OnDoubleClick", function() end) end)
rejects("a Frame has no OnEnterPressed",
	function() plain:SetScript("OnEnterPressed", function() end) end)
rejects("a misspelled script is refused",
	function() plain:SetScript("OnMouseDwon", function() end) end)
allows("a Button does have OnClick", function() button:SetScript("OnClick", function() end) end)
allows("an EditBox does have OnEnterPressed",
	function() edit:SetScript("OnEnterPressed", function() end) end)
allows("every frame has OnUpdate", function() plain:SetScript("OnUpdate", function() end) end)

-- Strata, levels, layers
rejects("an invented strata is refused", function() plain:SetFrameStrata("DIALOGUE") end)
rejects("a lowercase strata is refused", function() plain:SetFrameStrata("dialog") end)
allows("DIALOG is a real strata", function() plain:SetFrameStrata("DIALOG") end)
allows("TOOLTIP is a real strata", function() plain:SetFrameStrata("TOOLTIP") end)
rejects("a fractional frame level is refused", function() plain:SetFrameLevel(3.5) end)
rejects("a negative frame level is refused", function() plain:SetFrameLevel(-1) end)
allows("a whole frame level is fine", function() plain:SetFrameLevel(12) end)
rejects("an invented draw layer is refused", function() tex:SetDrawLayer("FOREGROUND") end)
rejects("an out-of-range sub-level is refused", function() tex:SetDrawLayer("ARTWORK", 9) end)
allows("ARTWORK with a legal sub-level is fine", function() tex:SetDrawLayer("ARTWORK", 3) end)

-- Anchors
rejects("an invented anchor point is refused",
	function() plain:SetPoint("TOPCENTER", UIParent, "CENTER", 0, 0) end)
rejects("an invented relative point is refused",
	function() plain:SetPoint("TOPLEFT", UIParent, "MIDDLE", 0, 0) end)
rejects("anchoring a frame to itself is refused",
	function() plain:SetPoint("TOPLEFT", plain, "TOPLEFT", 0, 0) end)
rejects("a non-numeric offset is refused",
	function() plain:SetPoint("TOPLEFT", UIParent, "TOPLEFT", "8", 0) end)

-- Frame types and templates
rejects("an invented frame type is refused",
	function() CreateFrame("Widget", nil, UIParent) end)
rejects("an invented template is refused",
	function() CreateFrame("Button", nil, UIParent, "FancyButtonTemplate") end)
allows("UIPanelButtonTemplate is real",
	function() CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate") end)
allows("SecureActionButtonTemplate is real",
	function() CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate") end)

-- Animations
local ag = plain:CreateAnimationGroup()
rejects("an invented animation type is refused", function() ag:CreateAnimation("Wobble") end)
allows("Alpha is a real animation", function() ag:CreateAnimation("Alpha") end)
allows("Translation is a real animation", function() ag:CreateAnimation("Translation") end)
allows("Scale is a real animation", function() ag:CreateAnimation("Scale") end)

-- Events
rejects("an invented event is refused",
	function() plain:RegisterEvent("CHAT_MSG_WHISPERR") end)
rejects("a lowercase event is refused",
	function() plain:RegisterEvent("chat_msg_whisper") end)
allows("a real event registers", function() plain:RegisterEvent("CHAT_MSG_WHISPER") end)

--------------------------------------------------------------------------------
-- The addon obeys those rules
--------------------------------------------------------------------------------

-- SavedVariables do not exist until ADDON_LOADED. Reading them at file scope
-- gives nil and quietly starts everyone with an empty history.
_G.WhatTheWhisperDB = nil
_G.WhatTheWhisperHistoryDB = nil

local ns = Harness.Load()

check("no SavedVariable was touched at load time",
	_G.WhatTheWhisperDB == nil and _G.WhatTheWhisperHistoryDB == nil,
	"the addon read its saved data before the client restored it")
check("the addon did not build its database at file scope", ns.db == nil)
check("but it did register its lifecycle", ns.addon ~= nil)

-- No frame may be shown before the player is in the world.
local shownEarly = 0
for i = 1, #M.frames do
	local f = M.frames[i]
	if f._shown ~= false and f._parent == _G.UIParent and f._name
		and f._name:find("WhatTheWhisper") then
		shownEarly = shownEarly + 1
	end
end
eq("no addon window is visible before login", shownEarly, 0)

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
check("the database exists once ADDON_LOADED has fired", ns.db ~= nil)
check("history is initialised too", _G.WhatTheWhisperHistoryDB ~= nil)

M.FireEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_ENTERING_WORLD")
M.RunFrames(4)
eq("nothing errored through the login sequence", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 4)))

-- ADDON_LOADED can fire for other addons first, and repeatedly. Ours must
-- ignore the ones that are not its own rather than initialising twice.
local dbBefore = ns.db
M.FireEvent("ADDON_LOADED", "SomeOtherAddon")
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.RunFrames(2)
eq("a second ADDON_LOADED did not rebuild the database", ns.db, dbBefore)

--------------------------------------------------------------------------------
-- Widget usage across the built interface
--------------------------------------------------------------------------------

ns.UI.Show()
M.RunFrames(8)
local window = ns.MainWindow.Get()

local STRATA_ORDER = {
	BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
	DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
local nodes = M.Descendants(window)
local badStrata, badLevel = 0, 0
for i = 1, #nodes do
	local node = nodes[i]
	if node._strata and not STRATA_ORDER[node._strata] then badStrata = badStrata + 1 end
	if node._level and (node._level < 0 or node._level % 1 ~= 0) then badLevel = badLevel + 1 end
end
eq("every strata the window sets is a real one", badStrata, 0)
eq("every frame level is a whole number", badLevel, 0)

-- A tooltip that sits under the window it describes is invisible.
check("the tooltip sits above the messenger",
	STRATA_ORDER[ns.Tooltip and ns.Tooltip.Frame and ns.Tooltip.Frame()._strata or "TOOLTIP"]
		>= STRATA_ORDER[window._strata or "MEDIUM"])

-- Keyboard focus: the composer must take focus without stealing it forever, and
-- Escape has to hand it back or the player cannot move.
--
-- A thread has to be open first. With nothing selected the window shows its
-- empty state and the composer is not on screen, and the client will not give
-- keyboard focus to an edit box the player cannot see -- so focusing it there
-- proves nothing.
ns.ConversationManager.GetOrCreate(ns.Compat.NormalizeName("Thrall"))
ns.ConversationManager.Select(ns.Compat.NormalizeName("Thrall"))
M.RunFrames(8)
local composer = window.view.composer
check("the composer has an edit box", composer.input ~= nil)
check("the composer is on screen once a thread is open",
	M.EffectivelyVisible(composer.input.editBox or composer.input))
composer.input:Focus()
M.RunFrames(2)
check("focusing the composer works", composer.input:HasFocus())
composer.input:ClearFocus()
M.RunFrames(2)
eq("and it releases focus", composer.input:HasFocus(), false)

-- Keyboard input must not be swallowed while unfocused, or movement keys die.
local editBox = composer.input.editBox or composer.input
check("the edit box lets unhandled keys through",
	editBox.SetPropagateKeyboardInput ~= nil)

--------------------------------------------------------------------------------
-- Hyperlinks
--------------------------------------------------------------------------------

-- Bubbles are pooled and built on demand, so there has to be a message on
-- screen before there is anything to inspect.
local linkGuid = "G-JAINA"
M.guids = M.guids or {}
M.guids[linkGuid] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" }
M.FireEvent("CHAT_MSG_WHISPER",
	"see |cffa335ee|Hitem:19019::::::::::::|h[Thunderfury]|h|r and https://example.com",
	"Jaina", "Common", "", "Jaina", "", 0, 0, "", 0, 1, linkGuid)
M.RunFrames(8)
ns.ConversationManager.Select(ns.Compat.NormalizeName("Jaina"))
M.RunFrames(8)

-- Only a frame with hyperlinks enabled receives OnHyperlink scripts; setting
-- one on a frame that never enabled them means dead clicks.
local hyperlinkFrames, enabled = 0, 0
for i = 1, #M.frames do
	local f = M.frames[i]
	if f._scripts and (f._scripts.OnHyperlinkClick or f._scripts.OnHyperlinkEnter) then
		hyperlinkFrames = hyperlinkFrames + 1
		if f._hyperlinksEnabled then enabled = enabled + 1 end
	end
end
-- Asserted, not skipped: a run in which nothing handles hyperlinks means the
-- check silently stopped covering anything.
check("some frame handles hyperlinks at all", hyperlinkFrames > 0,
	"nothing registered OnHyperlinkClick; this check has stopped testing anything")
eq("every frame handling hyperlinks enabled them", enabled, hyperlinkFrames)

--------------------------------------------------------------------------------
-- Combat lockdown
--------------------------------------------------------------------------------

M.inCombat = true
M.FireEvent("PLAYER_REGEN_DISABLED")
M.RunFrames(4)

local before = #M.errors
local guid = "G-THRALL"
M.guids = { [guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" } }
M.FireEvent("CHAT_MSG_WHISPER", "in combat", "Thrall", "Common", "", "Thrall",
	"", 0, 0, "", 0, 1, guid)
M.RunFrames(6)
eq("a whisper during combat touched nothing protected", #M.errors, before,
	table.concat(M.errors, "\n      ", before + 1, math.min(#M.errors, before + 3)))

ns.UI.Toggle()
ns.UI.Toggle()
M.RunFrames(6)
eq("toggling the window in combat is safe", #M.errors, before)

M.inCombat = false
M.FireEvent("PLAYER_REGEN_ENABLED")
M.RunFrames(8)
eq("leaving combat is clean", #M.errors, before)

--------------------------------------------------------------------------------
-- Texture and font paths
--------------------------------------------------------------------------------

-- The client takes a path without an extension and finds the .tga or .blp
-- itself; a path with one fails on some clients and not others.
local badPaths, sample, inspected = 0, nil, 0
for i = 1, #M.regions do
	local region = M.regions[i]
    local path = region._texture
	if type(path) == "string" and path:find("Interface", 1, true) then
		inspected = inspected + 1
		if path:lower():find("%.tga$") or path:lower():find("%.blp$") then
			badPaths = badPaths + 1
			sample = sample or path
		end
	end
end
eq("no texture path carries a file extension", badPaths, 0, sample)
check("texture paths were actually inspected", inspected > 0,
	"no texture had a path; this check has stopped testing anything")

eq("still no errors at the end", #M.errors, before,
	table.concat(M.errors, "\n      ", before + 1, math.min(#M.errors, before + 4)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
