-- Does the interface survive the font-size slider?
--
-- Every box that holds text is a promise that the text will fit in it, and a box
-- sized by a constant only keeps that promise at one font size. Turn the slider
-- up and the constants stay put while the words grow: labels run over their
-- neighbours, values get cut to "5 secon...", and a row of segments turns into
-- one illegible smear.
--
-- So the whole interface is built at every font scale the setting offers and
-- measured. Two things must hold at all of them:
--
--   1. No two pieces of text overlap. There is no layout where that is correct.
--   2. Nothing is truncated that had room to be shown. A name too long for the
--      sidebar is legitimately shortened; a four-word setting value squeezed
--      into 42 pixels is a container that was never measured.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
dofile(ROOT .. "Tools/test/client.lua").Setup("retail")

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

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local CM = ns.ConversationManager

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
local softErrors = {}
ns.SoftError = function(c, e) softErrors[#softErrors + 1] = c .. ": " .. tostring(e) end

local function whisper(text, from)
	M.FireEvent("CHAT_MSG_WHISPER", text, from, "Common", "", from, "", 0, 0, "", 0, 1,
		"G-" .. from)
end
whisper("hey", "Thrall")
whisper("Are you around for the raid tonight?", "Thrall")
whisper("kurz", "Jaina")
whisper("kommst du?", "Sylvanas")
-- A name long enough that "Message <name>..." does not fit a popout's composer.
-- The placeholder has to shorten itself rather than run out of the field, and
-- with only short names in the fixture nothing ever asked it to.
whisper("na?", "Bartholomaeuszwerg")
ns.UI.Show()
CM.Select(ns.Compat.NormalizeName("Thrall"))
CM.SendMessage(ns.Compat.NormalizeName("Thrall"), "on my way")
M.RunFrames(6)

-- Text the addon is allowed to shorten: things whose length belongs to somebody
-- else. A player's name can be longer than any column, a message longer than
-- any preview, and a placeholder is a hint rather than a value. Everything else
-- -- a setting's name, a control's value, a menu entry -- is the addon's own
-- words in the addon's own box, and shortening those means the box is wrong.
local function isSomebodyElsesText(node)
	local parent = node._parent
	if not parent then return false end
	return parent.name == node or parent.preview == node or parent.body == node
		or parent.value == node or parent.placeholder == node
end

local function rect(f)
	local l, b, w, h = M.Geometry(f)
	return l, b, w, h, l + w, b + h
end

local function describe(node)
    local trail, up, hops = {}, node, 0
    while up and hops < 8 do
        trail[#trail + 1] = up._name or up._wtwTag or up._kind or "?"
        up = up._parent
        hops = hops + 1
    end
    return table.concat(trail, "<")
end

-- Every font string the player can actually see, with the rectangle it is
-- actually painted in.
--
-- Not the rectangle it was anchored at: text inside a scrolling list is trimmed
-- to the list's viewport, and a message scrolled below the composer is not a
-- message drawn on top of the composer.
local function labels(root)
	local out = {}
	local nodes = M.Descendants(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if node._kind == "FontString" and (node._text or "") ~= ""
			and M.EffectivelyShown(node, root) then
			local l, b, w, h, r, t = M.VisibleRect(node, root)
			if l and w > 0 and h > 0 then
				out[#out + 1] = { node = node, l = l, b = b, r = r, t = t }
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- The audits
--------------------------------------------------------------------------------

-- Two labels sharing pixels. The screenshots that started this: four segment
-- captions, each wider than the segment it was given, printed on top of each
-- other.
local function checkNoOverlap(root, where)
	local list = labels(root)
	local worst
	local overlaps = 0
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			-- A label nested inside another's frame is a different thing from
			-- two labels colliding; only compare ones that are not related.
			local related = false
			local up = a.node._parent
			while up do
				if up == b.node._parent then related = false break end
				up = up._parent
			end
			if not related
				and a.l < b.r - 0.5 and b.l < a.r - 0.5
				and a.b < b.t - 0.5 and b.b < a.t - 0.5 then
				overlaps = overlaps + 1
				worst = worst or ("%q at %.0f,%.0f and %q at %.0f,%.0f (%s / %s)"):format(
					tostring(a.node._text), a.l, a.b,
					tostring(b.node._text), b.l, b.b,
					describe(a.node), describe(b.node))
			end
		end
	end
	check(where .. ": no two labels are drawn on top of each other",
		overlaps == 0, worst)
	return #list
end

-- A control whose value has been cut short. Truncating a player's name to fit a
-- sidebar column is right; truncating "Bottom right" in a settings row means the
-- column was sized for a font nobody is using.
-- Asked of the font string rather than of its text: Text.Ellipsize records
-- whether it actually had to shorten anything, which is the only way to tell a
-- cut-off label from one that ends in dots because somebody wrote it that way
-- ("Message Thrall..." is the composer's placeholder, working correctly).
local function checkNotTruncated(root, where, exempt)
	local list = labels(root)
	local cut, worst = 0, nil
	for i = 1, #list do
		local node = list[i].node
		if node.__wtwTruncated and not (exempt and exempt(node)) then
			cut = cut + 1
			worst = worst or ("%q (%s)"):format(tostring(node._text), describe(node))
		end
	end
	check(where .. ": no control value is cut short", cut == 0, worst)
end

-- A label given a width narrower than the words in it. Nothing overlaps -- the
-- engine simply wraps it onto a second line the box has no room for, or cuts it
-- off -- so the overlap audit never sees it, and the player sees "5 secon".
--
-- Only labels that were given an explicit width are judged: one left to size
-- itself is as wide as its text by definition, and one that is meant to wrap
-- says so.
local function checkNotClipped(root, where, exempt)
	local list = labels(root)
	local clipped, worst = 0, nil
	for i = 1, #list do
		local entry = list[i]
		local node = entry.node
		-- Only labels that have been told not to wrap. One left to wrap is
		-- meant to take a second line, and one sized to its own content is as
		-- wide as its text by definition -- neither can be squeezed.
		--
		-- The box is the one it is drawn in, whether that came from SetWidth or
		-- from being anchored to both sides of its parent. Reading only the
		-- explicit width missed every label held between two anchors, which is
		-- most of them.
		if node._wordWrap == false and not (exempt and exempt(node)) then
			local boxed = entry.r - entry.l
			local natural = node:GetStringWidth() or 0
			if boxed > 0 and natural > boxed + 0.5 then
				clipped = clipped + 1
				worst = worst or ("%q wants %.0fpx in a %.0fpx box (%s)"):format(
					tostring(node._text), natural, boxed, describe(node))
			end
		end
	end
	check(where .. ": no label is squeezed into a box too small for it",
		clipped == 0, worst)
end

--------------------------------------------------------------------------------

local SCALES = { -2, 0, 2, 4, 6 }
local window = ns.MainWindow.Get()

for _, scale in ipairs(SCALES) do
	ns.Options.Set("appearance.fontScale", scale)
	M.RunFrames(6)
	local where = ("font %+d"):format(scale)

	local counted = checkNoOverlap(window, where .. " messenger")
	check(where .. ": there was text to measure", counted > 8, tostring(counted))

	-- In the messenger, the names and previews are legitimately shortened -- a
	-- sidebar column cannot be as wide as the longest name there is. Everything
	-- else in it is a number or a word the addon chose, and those have no
	-- business being cut.
	checkNotTruncated(window, where .. " messenger", isSomebodyElsesText)

	-- Every other surface the addon draws. Each is measured at every font size
	-- too, because "check the settings pane" is how the first version of this
	-- audit missed the profile panel walking into itself.
	--
	-- Each one is found by watching what appears under UIParent when it opens,
	-- rather than by asking the addon for a handle on it. A toast and a dialog
	-- have no business exposing their frames, and a test is not a reason to make
	-- them start.
	local thrall = ns.Compat.NormalizeName("Thrall")
	local conv = CM.Get(thrall)

	-- What is on screen under UIParent that was not there a moment ago. A
	-- surface that is opened for the second time reuses its frame rather than
	-- building another, so "new" alone is not enough: anything shown that was
	-- hidden before counts too.
	local function shownChildren()
		local set = {}
		for _, child in ipairs(M.Children(UIParent)) do
			if M.EffectivelyShown(child, UIParent) then set[child] = true end
		end
		return set
	end

	local function auditSurface(name, open, close, exempt)
		local before = shownChildren()
		open()
		-- Generously: a popout builds a header, a thread and a composer, and
		-- measuring one mid-layout would report a fault that is really a frame
		-- that has not settled.
		M.RunFrames(8)
		local found = 0
		for child in pairs(shownChildren()) do
			if not before[child] then
				found = found + 1
				checkNoOverlap(child, where .. " " .. name)
				checkNotClipped(child, where .. " " .. name)
				checkNotTruncated(child, where .. " " .. name, exempt)
			end
		end
		check(where .. ": the " .. name .. " opened", found > 0)
		close()
		M.RunFrames(3)
	end

	-- The fixture's own whispers already put toasts on screen, and a second
	-- whisper from the same person updates the toast that is there rather than
	-- adding one -- so the frame is never new and the audit below would find
	-- nothing. Cleared before the snapshot, not inside the open.
	ns.Toast.DismissAll()
	M.RunFrames(4)

	auditSurface("toast",
		function()
			local jaina = CM.Get(ns.Compat.NormalizeName("Jaina"))
			ns.Toast.Show(jaina, jaina.messages[#jaina.messages], false)
		end,
		function() ns.Toast.DismissAll() end,
		isSomebodyElsesText)

	auditSurface("popout",
		function() ns.UI.TogglePopout(thrall) end,
		function() ns.UI.DockConversation(thrall) end)

	-- The same window for somebody with a long name, which is where the
	-- composer's placeholder has to give ground.
	local longName = ns.Compat.NormalizeName("Bartholomaeuszwerg")
	auditSurface("popout (long name)",
		function() ns.UI.TogglePopout(longName) end,
		function() ns.UI.DockConversation(longName) end,
		isSomebodyElsesText)

	auditSurface("context menu",
		function() ns.Menu.Open(ns.UI.BuildConversationMenu(conv)) end,
		function() ns.Menu.Close() end)

	auditSurface("export dialog",
		function() ns.Dialogs.ShowExport(conv) end,
		function() ns.Dialogs.HideAll() end)

	-- The tab strip, which is a second way to show the same conversations.
	ns.Options.Set("layout.mode", "tabbed")
	M.RunFrames(4)
	checkNoOverlap(window, where .. " tabbed layout")
	ns.Options.Set("layout.mode", "sidebar")
	M.RunFrames(3)

	-- The settings window, every category, which is where the fixed-width
	-- control column lives.
	ns.SettingsUI.Show()
	M.RunFrames(4)
	local settings = ns.SettingsUI.Frame()
	for _, category in ipairs(ns.Options.BuildSchema()) do
		ns.SettingsUI.SelectCategory(category.id)
		M.RunFrames(3)
		if settings then
			local at = where .. " settings/" .. category.id
			checkNoOverlap(settings, at)
			-- Conversation names and message previews are allowed to shorten;
			-- nothing in the settings window is.
			checkNotTruncated(settings, at)
			checkNotClipped(settings, at)
		end
	end
	ns.SettingsUI.Hide()
	M.RunFrames(2)
end

ns.Options.Set("appearance.fontScale", 0)
M.RunFrames(4)

check("nothing raised while resizing the font", #softErrors == 0,
	table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))
check("nothing errored", #M.errors == 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 4)))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
