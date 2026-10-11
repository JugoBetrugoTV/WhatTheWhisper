-- Gradients, and the skin that uses them.
--
-- A rounded shape is seven textures, so a gradient across it is seven, each told
-- the colours the gradient has at its own top and bottom edge. If any piece is
-- off, the shape shows a seam. And a gradient has to be a gift, never a
-- requirement: a client with neither gradient call, and a skin that has none,
-- both still draw the right colour.

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
		print("FAIL [gradient] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function near(label, got, want, tol)
	check(label, got ~= nil and math.abs(got - want) <= (tol or 0.01),
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

local Compat, Draw, Theme, Options = ns.Compat, ns.Draw, ns.Theme, ns.Options

--------------------------------------------------------------------------------
-- Compat.SetGradient: both of the client's calls, and neither
--------------------------------------------------------------------------------

local function fakeTexture()
	local t = { calls = {} }
	function t.SetGradient(_, orientation, a, b)
		t.calls[#t.calls + 1] = { "new", orientation, a, b }
	end
	function t.SetGradientAlpha(_, orientation, ...)
		t.calls[#t.calls + 1] = { "old", orientation, ... }
	end
	function t.SetVertexColor(_, ...) t.calls[#t.calls + 1] = { "flat", ... } end
	return t
end
local realCreateColor = _G.CreateColor
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local realAPI = Compat.gradientAPI
Compat.gradientAPI = "new"
local t = fakeTexture()
check("the current call is used where there is one",
	Compat.SetGradient(t, "VERTICAL", 0, 0, 0, 1, 1, 1, 1, 1) == true and t.calls[1][1] == "new")
check("with its two colours as objects", t.calls[1][3].r == 0 and t.calls[1][4].r == 1)

Compat.gradientAPI = "old"
t = fakeTexture()
Compat.SetGradient(t, "VERTICAL", 0.2, 0.4, 0.6, 1, 0.8, 0.6, 0.4, 0.5)
check("the old call where that is what the client has", t.calls[1][1] == "old")
check("with eight numbers", t.calls[1][3] == 0.2 and t.calls[1][10] == 0.5)

Compat.gradientAPI = nil
t = fakeTexture()
check("with neither it says so", Compat.SetGradient(t, "VERTICAL", 0, 0, 0, 1, 1, 1, 1, 1) == false)
near("and leaves the texture the average, which is the right colour", t.calls[1][2], 0.5)
Compat.gradientAPI = realAPI
_G.CreateColor = realCreateColor

--------------------------------------------------------------------------------
-- A rounded shape
--------------------------------------------------------------------------------

local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(200, 100)
local shape = Draw.NewRounded(host, "BACKGROUND", 0)
shape:SetRadius(16)
shape:SetGradient({ 1, 0, 0, 1 }, { 0, 0, 1, 1 })
M.RunFrames(1)

-- What the mock records is what the client would be told: orientation, then the
-- colour at the piece's bottom edge, then the one at its top.
local function ends(piece)
	local g = piece._gradient
	if not g then return nil end
	return g[2], g[3]    -- bottom, top
end
local bottom, top = ends(shape.top)
check("every piece has a gradient", shape.tl._gradient and shape.mid._gradient and shape.br._gradient
	and shape.top._gradient and shape.bottom._gradient and shape.tr._gradient and shape.bl._gradient)
near("the very top is the first colour (red)", top and top[1], 1)
near("and has none of the second", top and top[3], 0)
local _, midTop = ends(shape.mid)
local midBottom = ends(shape.mid)
near("the middle begins where the top row ends", midTop and midTop[1], 1 - 16 / 100)
near("and ends where the bottom row begins", midBottom and midBottom[3], 1 - 16 / 100)
local lowBottom = ends(shape.bottom)
near("the very bottom is the second colour (blue)", lowBottom and lowBottom[3], 1)
local tlBottom = ends(shape.tl)
check("a corner has the colours of the row it is in", tlBottom and bottom and
	math.abs(tlBottom[1] - bottom[1]) < 1e-6)

-- A flat colour afterwards takes the gradient away.
shape:SetColor(0.3, 0.3, 0.3, 1)
check("a flat colour replaces it, on every piece", shape.mid._gradient == nil
	and shape.tl._gradient == nil and shape.bottom._gradient == nil)

-- With no radius there is one piece.
shape:SetRadius(0)
shape:SetGradient({ 1, 1, 1, 1 }, { 0, 0, 0, 1 })
M.RunFrames(1)
local flatBottom, flatTop = ends(shape.mid)
near("a square one is one gradient from top", flatTop and flatTop[1], 1)
near("to bottom", flatBottom and flatBottom[1], 0)

--------------------------------------------------------------------------------
-- Skins
--------------------------------------------------------------------------------

check("Aurora is what a new profile has", ns.db.profile.appearance.skin == "aurora")
for _, id in ipairs(ns.Skins.order) do
	Options.Set("appearance.skin", id)
	local out, outTo = Theme.Get("bubbleOut"), Theme.Get("bubbleOutTo")
	check(id .. ": the bubble gradient has both ends", type(out) == "table" and type(outTo) == "table")
	local role = ns.Skins.Get(id).colors.bubbleOutTo
	if role then
		check(id .. ": says its own far end", outTo[1] == role[1] and outTo[3] == role[3])
	else
		check(id .. ": without one, the far end is the near end (flat)",
			outTo[1] == out[1] and outTo[2] == out[2] and outTo[3] == out[3])
	end
	for _, to in ipairs({ "accentTo", "bg2To" }) do
		local c = Theme.Get(to)
		-- An unresolved role comes back magenta, on purpose, so it cannot be missed.
		check(id .. ": " .. to .. " resolves to a real colour",
			type(c) == "table" and not (c[1] == 1 and c[2] == 0 and c[3] == 1))
	end
end

--------------------------------------------------------------------------------
-- A bubble
--------------------------------------------------------------------------------

local CM, UI = ns.ConversationManager, ns.UI
ns.Options.Set("messages.openOnWhisper", false)
M.guids = { ["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" } }
M.FireEvent("CHAT_MSG_WHISPER", "hallo", "Jaina", "Common", "", "Jaina", "", 0, 0, "", 0, 41, "G-JAINA")
M.RunTimers(1)
local jaina = ns.Compat.NormalizeName("Jaina")
CM.SendMessage(jaina, "hi zurück")
M.RunTimers(1)
UI.Show()
CM.Select(jaina)
M.RunFrames(20)

local function bubbleOf(dir)
	for _, f in ipairs(M.frames) do
		if f.surface and f.msg and f.msg[ns.MSG_DIR] == dir and f:IsVisible() then return f end
	end
end

Options.Set("appearance.skin", "aurora")
M.RunFrames(10)
local mine, theirs = bubbleOf(ns.DIR_OUT), bubbleOf(ns.DIR_IN)
check("a message of yours is on screen, and one of theirs", mine and theirs)
if mine and theirs then
	check("yours fades in Aurora", mine.surface.rect.fill.mid._gradient ~= nil)
	check("theirs is flat", theirs.surface.rect.fill.mid._gradient == nil)
end

Options.Set("appearance.skin", "midnight")
M.RunFrames(10)
mine = bubbleOf(ns.DIR_OUT)
check("in a skin without one, yours is flat", mine and mine.surface.rect.fill.mid._gradient == nil)

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
