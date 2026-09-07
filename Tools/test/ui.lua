-- UI audit: measures what the addon actually builds.
--
-- Every check here reads geometry and colour off the constructed frames rather
-- than off the source, because the gap between "the code says 16" and "the pixel
-- is at 16" is exactly where layout bugs live. Four things are checked:
--
--   * containment  -- nothing sticks out of its parent, nothing lands off screen
--   * alignment    -- shared edges line up, and coordinates land on whole pixels
--   * targets      -- anything clickable is big enough to click
--   * contrast     -- every text colour is legible on the surface behind it
--
-- Run at three UI scales and across every skin, because a value that happens to
-- be integral at scale 1.0 usually is not at 0.64.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local failed = {}
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		if not failed[label] then
			failed[label] = true
			print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
		end
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

for _, path in ipairs({
	"Ace3/LibStub/LibStub.lua", "Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua",
	"Ace3/AceAddon-3.0/AceAddon-3.0.lua", "Ace3/AceEvent-3.0/AceEvent-3.0.lua",
	"Ace3/AceTimer-3.0/AceTimer-3.0.lua", "Ace3/AceHook-3.0/AceHook-3.0.lua",
	"Ace3/AceDB-3.0/AceDB-3.0.lua", "Ace3/AceLocale-3.0/AceLocale-3.0.lua",
	"Ace3/AceConsole-3.0/AceConsole-3.0.lua",
}) do assert(loadfile(ROOT .. path))(path, {}) end

local ns = {}
local xml = io.open(ROOT .. "WhatTheWhisper/WhatTheWhisper.xml"):read("*a")
for file in xml:gmatch('<Script file="([^"]+)"/>') do
	assert(loadfile(ROOT .. "WhatTheWhisper/" .. file:gsub("\\", "/")))("WhatTheWhisper", ns)
end

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local CM = ns.ConversationManager
local guid = "G-THRALL"
M.guids = {
	[guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}

--------------------------------------------------------------------------------
-- Build a populated interface to measure
--------------------------------------------------------------------------------

local function whisper(text, from, sender)
	M.FireEvent("CHAT_MSG_WHISPER", text, from, "Common", "", from, "", 0, 0, "", 0, 1, sender)
end

whisper("hey", "Thrall", guid)
whisper("Are you around for the raid tonight? We are short two healers.", "Thrall", guid)
whisper("kurz", "Jaina", "G-JAINA")
whisper("https://example.com/a/very/long/path/that/keeps/going and some words after it",
	"Jaina", "G-JAINA")
whisper("Übergrößenträger Straße ünnötig", "Thrall", guid)

ns.UI.Show()
local thrall = ns.Compat.NormalizeName("Thrall")
CM.Select(thrall)
CM.SendMessage(thrall, "on my way")
CM.SendMessage(thrall, "this one is a good deal longer, long enough to wrap onto a "
	.. "second line inside the bubble so the padding is measured on a multi-line body")
M.RunFrames(20)

local window = ns.MainWindow.Get()

--------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------

local function rect(f)
	local l, b, w, h = M.Geometry(f)
	return l, b, w, h, l + w, b + h
end

local function describe(node)
	local trail, hops = {}, 0
	local up = node
	while up and hops < 6 do
		trail[#trail + 1] = (up._name or up._wtwTag or up._kind or "?")
		up = up._parent
		hops = hops + 1
	end
	return ("%s[%s] text=%q at %.2f,%.2f %.2fx%.2f"):format(
		node._kind or "?", table.concat(trail, "<"), tostring(node._text or ""),
		select(1, rect(node)), select(2, rect(node)),
		select(3, rect(node)), select(4, rect(node)))
end

-- Nodes worth auditing: shown, sized, and actually under the window.
local function auditable(root)
	local out = {}
	local nodes = M.Descendants(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if M.EffectivelyShown(node, root) then
			local _, _, w, h = rect(node)
			if w > 1 and h > 1 then out[#out + 1] = node end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Containment: nothing may spill out of the window
--------------------------------------------------------------------------------

-- Shadows and glows are drawn deliberately outside their frame, and scroll
-- viewports hold content taller than themselves. Both are legitimate.
local function allowedOverflow(node)
	if node._kind ~= "Frame" and node._layer == "BACKGROUND" then return 40 end
	local parent = node._parent
	while parent do
		if parent._wtwScrollContent or parent._wtwViewport then return math.huge end
		parent = parent._parent
	end
	return 2
end

local function checkContainment(label, root)
	local rl, rb, rw, rh = rect(root)
	local rr, rt = rl + rw, rb + rh
	local worst, worstNode = 0, nil
	local nodes = auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		local l, b, w, h = rect(node)
		local slack = allowedOverflow(node)
		if slack ~= math.huge then
			local over = math.max(rl - l, rb - b, (l + w) - rr, (b + h) - rt) - slack
			if over > worst then worst, worstNode = over, node end
		end
	end
	check(label .. ": nothing spills out of the window", worst <= 0,
		worstNode and (describe(worstNode) .. " overflows by " .. ("%.2f"):format(worst)
			.. " (window " .. ("%.0f,%.0f %.0fx%.0f"):format(rl, rb, rw, rh) .. ")"))
end

checkContainment("main window", window)

--------------------------------------------------------------------------------
-- On screen: the window must never open where it cannot be grabbed
--------------------------------------------------------------------------------

local screenW, screenH = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
local wl, wb, ww, wh = rect(window)
check("the window opens on screen horizontally", wl < screenW and wl + ww > 0,
	("left %.0f width %.0f screen %.0f"):format(wl, ww, screenW))
check("the window opens on screen vertically", wb < screenH and wb + wh > 0,
	("bottom %.0f height %.0f screen %.0f"):format(wb, wh, screenH))
check("the title bar is reachable", wb + wh <= screenH + 1 and wb + wh > 0,
	("top %.0f screen %.0f"):format(wb + wh, screenH))

--------------------------------------------------------------------------------
-- Alignment: shared edges must actually be shared
--------------------------------------------------------------------------------

local EPS = 0.51

local function alignsX(label, a, b, edge)
	local av = edge == "left" and select(1, rect(a)) or select(5, rect(a))
	local bv = edge == "left" and select(1, rect(b)) or select(5, rect(b))
	check(label, math.abs(av - bv) < EPS, ("%.3f vs %.3f"):format(av, bv))
end

local sidebar, view = window.sidebar, window.view

alignsX("the sidebar and the header start at the same left edge",
	sidebar, window.titlebar, "left")
check("the conversation view begins exactly where the sidebar ends",
	math.abs(select(5, rect(sidebar)) - select(1, rect(view))) < EPS,
	("sidebar right %.3f, view left %.3f"):format(select(5, rect(sidebar)), select(1, rect(view))))
check("the view reaches the right edge of the window",
	math.abs(select(5, rect(view)) - select(5, rect(window))) < EPS)

local composer, list = view.composer, view.list
check("the composer sits at the bottom of the view",
	math.abs(select(2, rect(composer)) - select(2, rect(view))) < EPS)
check("the message list ends where the composer begins",
	select(2, rect(list)) >= select(6, rect(composer)) - EPS,
	("list bottom %.3f, composer top %.3f"):format(
		select(2, rect(list)), select(6, rect(composer))))
check("the list and the composer share a left edge",
	math.abs(select(1, rect(list)) - select(1, rect(view))) < EPS)

--------------------------------------------------------------------------------
-- Hit targets
--------------------------------------------------------------------------------

-- 20px at scale 1.0 is roughly a 5mm target on a 1080p 24" display. Anything
-- smaller is a coin toss with a mouse.
--
-- A drag strip is the exception, and a real one rather than a loophole: a
-- splitter or a scrollbar is aimed at along one axis only, so it needs height
-- but not width. Those get a 10px minor axis, which is what desktop toolkits
-- use, and only when the major axis is long enough to aim at.
local MIN_TARGET = 20
local MIN_STRIP_MINOR = 10
local MIN_STRIP_MAJOR = 100

local function targetIsBigEnough(w, h)
	if w >= MIN_TARGET and h >= MIN_TARGET then return true end
	local minor, major = math.min(w, h), math.max(w, h)
	return minor >= MIN_STRIP_MINOR and major >= MIN_STRIP_MAJOR
end

local function checkTargets(label, root)
	local small, sample = 0, nil
	local nodes = auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if node._kind == "Frame" and node._mouseEnabled then
			local _, _, w, h = rect(node)
			local hl, hr, ht, hb = node._hitLeft or 0, node._hitRight or 0,
				node._hitTop or 0, node._hitBottom or 0
			-- Negative hit-rect insets shrink; positive ones (WoW's convention
			-- for SetHitRectInsets is inward) are what the addon uses to grow a
			-- thin control's clickable area, stored negative.
			local tw, th = w - hl - hr, h - ht - hb
			if not targetIsBigEnough(tw, th) then
				small = small + 1
				sample = sample or (describe(node) .. (" target %.1fx%.1f"):format(tw, th))
			end
		end
	end
	check(label, small == 0, sample)
end

checkTargets("every clickable element is big enough to hit", window)

--------------------------------------------------------------------------------
-- Contrast
--------------------------------------------------------------------------------

-- WCAG relative luminance and contrast ratio. Body text wants 4.5:1, large or
-- secondary text 3:1; a chat client that fails these is unreadable at night.
local function luminance(c)
	local function channel(v)
		if v <= 0.03928 then return v / 12.92 end
		return ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end

local function contrast(fg, bg)
	local a, b = luminance(fg), luminance(bg)
	if a < b then a, b = b, a end
	return (a + 0.05) / (b + 0.05)
end

-- Alpha-blended roles (hover, borders) are composited over their base first,
-- otherwise the ratio is measured against a colour nobody ever sees.
local function over(fg, bg)
	local alpha = fg[4] or 1
	if alpha >= 1 then return fg end
	return {
		fg[1] * alpha + bg[1] * (1 - alpha),
		fg[2] * alpha + bg[2] * (1 - alpha),
		fg[3] * alpha + bg[3] * (1 - alpha), 1,
	}
end

local CONTRAST_PAIRS = {
	{ "textPrimary", "bg1", 4.5, "body text on the window" },
	{ "textPrimary", "bg2", 4.5, "body text on a panel" },
	{ "textSecondary", "bg1", 3.0, "secondary text on the window" },
	{ "textSecondary", "bg2", 3.0, "secondary text on a panel" },
	{ "textMuted", "bg1", 2.2, "muted text on the window" },
	{ "bubbleInText", "bubbleIn", 4.5, "incoming bubble text" },
	{ "bubbleOutText", "bubbleOut", 4.5, "outgoing bubble text" },
	{ "onAccent", "accent", 3.0, "text on an accent button" },
	{ "link", "bg1", 3.0, "links on the window" },
	{ "link", "bubbleIn", 3.0, "links in an incoming bubble" },
	{ "danger", "bg1", 3.0, "the danger colour" },
	{ "success", "bg1", 3.0, "the online dot" },
	{ "warning", "bg1", 3.0, "the away dot" },
}

for _, id in ipairs(ns.Skins.order) do
	ns.Options.Set("appearance.skin", id)
	ns.UI.RefreshAll()
	M.RunFrames(4)
	for _, pair in ipairs(CONTRAST_PAIRS) do
		local role, base, want, what = pair[1], pair[2], pair[3], pair[4]
		local bg = over(ns.Theme.Get(base), { 0, 0, 0, 1 })
		local fg = over(ns.Theme.Get(role), bg)
		local ratio = contrast(fg, bg)
		check(("%s: %s is legible"):format(id, what), ratio >= want,
			("%s on %s is %.2f:1, want %.1f:1"):format(role, base, ratio, want))
	end

	-- An unresolved colour role renders magenta on purpose; none may survive.
	for _, pair in ipairs(CONTRAST_PAIRS) do
		for _, role in ipairs({ pair[1], pair[2] }) do
			local c = ns.Theme.Get(role)
			check(("%s: %s is a real colour"):format(id, role),
				not (c[1] == 1 and c[2] == 0 and c[3] == 1),
				role .. " is unresolved in " .. id)
		end
	end
end

ns.Options.Set("appearance.skin", "midnight")
ns.UI.RefreshAll()
M.RunFrames(4)

--------------------------------------------------------------------------------
-- Pixel snapping across UI scales
--------------------------------------------------------------------------------

-- ns.Pixel.Size is the width of one physical pixel in the addon's coordinate
-- space; every border and divider has to be a whole multiple of it or it will
-- shimmer. The addon must produce a usable value at every scale the client
-- allows, not just at 1.0.
for _, scale in ipairs({ 0.64, 0.71, 0.85, 1.0 }) do

	_G.UIParent:SetScale(scale)
	ns.Compat.ResetPhysicalHeight()
	ns.Theme.Refresh()
	M.RunFrames(4)
	local px = ns.Pixel.Size(_G.UIParent)
	check(("scale %.2f: one pixel is a sane size"):format(scale),
		px > 0 and px < 4, tostring(px))
	check(("scale %.2f: snapping is idempotent"):format(scale),
		ns.Pixel.Snap(ns.Pixel.Snap(13.37, _G.UIParent), _G.UIParent)
			== ns.Pixel.Snap(13.37, _G.UIParent))
	local snapped = ns.Pixel.Snap(13.37, _G.UIParent)
	check(("scale %.2f: snapping lands on a pixel boundary"):format(scale),
		math.abs(snapped / px - math.floor(snapped / px + 0.5)) < 1e-6,
		("%.6f is %.4f pixels"):format(snapped, snapped / px))
	check(("scale %.2f: snapping moves a value less than one pixel"):format(scale),
		math.abs(snapped - 13.37) <= px)

	checkContainment(("scale %.2f"):format(scale), window)
end


_G.UIParent:SetScale(1)
ns.Compat.ResetPhysicalHeight()
ns.Theme.Refresh()
M.RunFrames(4)

--------------------------------------------------------------------------------
-- Density and font scale must not break containment either
--------------------------------------------------------------------------------

for _, density in ipairs({ "comfortable", "compact" }) do
	ns.Options.Set("appearance.density", density)
	ns.UI.RefreshLayout()
	ns.UI.RefreshAll()
	M.RunFrames(6)
	checkContainment("density " .. density, window)
	checkTargets("density " .. density .. ": targets stay clickable", window)
end
ns.Options.Set("appearance.density", "comfortable")

for _, fontScale in ipairs({ -2, 0, 4 }) do
	ns.Options.Set("appearance.fontScale", fontScale)
	ns.UI.RefreshAll()
	M.RunFrames(6)
	checkContainment("font scale " .. fontScale, window)
end
ns.Options.Set("appearance.fontScale", 0)
ns.UI.RefreshAll()
M.RunFrames(6)

--------------------------------------------------------------------------------
-- The window at its extremes
--------------------------------------------------------------------------------

for _, size in ipairs({
	{ ns.SZ.WINDOW_MIN_W, ns.SZ.WINDOW_MIN_H, "minimum" },
	{ ns.SZ.WINDOW_W, ns.SZ.WINDOW_H, "default" },
	{ ns.SZ.WINDOW_MAX_W, ns.SZ.WINDOW_MAX_H, "maximum" },
}) do
	ns.Options.Set("layout.width", size[1])
	ns.Options.Set("layout.height", size[2])
	ns.UI.RefreshLayout()
	ns.UI.RefreshAll()
	M.RunFrames(6)
	checkContainment("window at its " .. size[3], window)
	checkTargets(size[3] .. " window: targets stay clickable", window)
	check(size[3] .. " window: the sidebar keeps a usable width",
		select(3, rect(sidebar)) >= ns.SZ.SIDEBAR_RAIL_W - EPS,
		("%.1f"):format(select(3, rect(sidebar))))
	check(size[3] .. " window: the composer keeps a usable width",
		select(3, rect(composer)) >= 120,
		("%.1f"):format(select(3, rect(composer))))
end
ns.Options.Set("layout.width", ns.SZ.WINDOW_W)
ns.Options.Set("layout.height", ns.SZ.WINDOW_H)
ns.UI.RefreshLayout()
M.RunFrames(6)

--------------------------------------------------------------------------------
-- Other surfaces
--------------------------------------------------------------------------------

ns.SettingsUI.Show()
M.RunFrames(8)
local settings = ns.SettingsUI.Frame and ns.SettingsUI.Frame()
if settings then
	local schema = ns.Options.BuildSchema()
	for i = 1, #schema do
		ns.SettingsUI.SelectCategory(schema[i].id)
		M.RunFrames(4)
		checkContainment("settings: " .. schema[i].id, settings)
		checkTargets("settings: " .. schema[i].id .. " targets", settings)
	end
end
ns.SettingsUI.Hide()

ns.UI.TogglePopout(thrall)
M.RunFrames(8)
local popout = ns.Popout.Get(thrall)
check("a popout window exists", popout ~= nil)
if popout then
	checkContainment("popout", popout)
	checkTargets("popout targets", popout)
end
ns.UI.DockConversation(thrall)
M.RunFrames(6)

ns.Expose.Toggle()
M.RunFrames(8)
ns.Expose.Toggle()
M.RunFrames(8)

--------------------------------------------------------------------------------
-- Icon atlas: every icon the UI asks for has to be inside the sheet
--------------------------------------------------------------------------------

local atlas = ns.ICON_ATLAS
check("the icon atlas is loaded", type(atlas) == "table" and next(atlas) ~= nil)
if type(atlas) == "table" then
	local bad, sample = 0, nil
	local tooSmall, smallSample = 0, nil
	for name, c in pairs(atlas) do
		local l, r, t, b = c[1], c[2], c[3], c[4]
		if not (l >= 0 and r <= 1 and t >= 0 and b <= 1 and r > l and b > t) then
			bad = bad + 1
			sample = sample or (name .. " -> " .. table.concat(c, ", "))
		end
		-- A half-texel inset on each side is what stops a neighbouring icon
		-- bleeding in when the sheet is filtered; a zero-width icon means the
		-- generator and the lookup table disagree.
		if (r - l) <= 0 or (b - t) <= 0 then
			tooSmall = tooSmall + 1
			smallSample = smallSample or name
		end
	end
	eq("every icon's coordinates are inside the sheet", bad, 0)
	eq("no icon is degenerate", tooSmall, 0)
end

--------------------------------------------------------------------------------

eq("nothing errored while auditing", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
