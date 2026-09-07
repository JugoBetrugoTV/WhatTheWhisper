-- WhatTheWhisper -- Minimap button.
--
-- Deliberately not LibDBIcon: that library is not in the library folder this
-- addon was pointed at, and a single draggable button is not worth a hard
-- dependency. It shows the unread count, which the LDB version could not.
--
-- The button rides the *outside* of the minimap ring. Sitting on the ring, or
-- inside it, covers the map and fights every other addon's buttons for the same
-- pixels; a full button width clear of the edge is where a tray belongs.

local _, ns = ...
local Theme, W, Anim = ns.Theme, ns.Widgets, ns.Anim
local CM = ns.ConversationManager
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local MinimapButton = {}
ns.Minimap = MinimapButton

local button
local SIZE = 26
-- Clearance between the minimap's own edge and the near edge of the button.
local ORBIT_GAP = 3
-- Fallback for the rare client where the minimap has not been sized yet.
local MINIMAP_FALLBACK_W = 140
-- How far the cursor has to travel before a press counts as a drag rather than
-- a click. Without this the first OnUpdate after any press declared a drag, and
-- the click that ended it was swallowed -- so the button could not be clicked
-- at all.
local DRAG_SLOP = 4
-- At most this many names in the jump list and the tooltip. Beyond that the
-- list stops being a glance and starts being the sidebar.
local MAX_LISTED = 8

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

-- Measured rather than assumed: the minimap is not the same size on every
-- client, and players scale it. Half the map, the gap, half the button -- so the
-- button's near edge clears the ring by exactly ORBIT_GAP whatever the size.
local function orbitRadius()
	local minimap = _G.Minimap
	local width = minimap and minimap:GetWidth() or 0
	if not width or width <= 0 then width = MINIMAP_FALLBACK_W end
	return width / 2 + ORBIT_GAP + SIZE / 2
end

local function positionAt(angle)
	local minimap = _G.Minimap
	if not minimap or not button then return end
	local radians = math.rad(angle)
	local radius = orbitRadius()
	button:ClearAllPoints()
	button:SetPoint("CENTER", minimap, "CENTER",
		math.cos(radians) * radius, math.sin(radians) * radius)
end

--------------------------------------------------------------------------------
-- Who is waiting
--------------------------------------------------------------------------------

-- Threads with something unread, newest first. This is what the badge counts,
-- what the tooltip names and what the jump list offers.
local function unreadConversations()
	local out = {}
	-- Keyed by id, not an array: iterated with pairs, ordered here.
	for _, conv in pairs(CM.All()) do
		if (conv.unread or 0) > 0 then out[#out + 1] = conv end
	end
	-- Newest first, with the name as a tie break: two whispers can land in the
	-- same second, and a comparator that calls both orders equal is one
	-- table.sort is entitled to raise an error over.
	table.sort(out, function(a, b)
		local left, right = a.lastActivity or 0, b.lastActivity or 0
		if left ~= right then return left > right end
		return (a.id or "") < (b.id or "")
	end)
	return out
end

local function refreshTooltip(waiting)
	if not button then return end
	if #waiting == 0 then
		W.SetTooltip(button, L["WhatTheWhisper"], L["/wtw - toggle the messenger"])
		return
	end
	local lines = {}
	for i = 1, math.min(#waiting, MAX_LISTED) do
		local conv = waiting[i]
		lines[#lines + 1] = ("%s  %d"):format(CM.DisplayName(conv), conv.unread)
	end
	if #waiting > MAX_LISTED then
		lines[#lines + 1] = ("+%d"):format(#waiting - MAX_LISTED)
	end
	lines[#lines + 1] = L["Right-click for the list"]
	W.SetTooltip(button, L["WhatTheWhisper"], table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- Clicks
--------------------------------------------------------------------------------

local function openConversation(id)
	ns.UI.Show()
	CM.Select(id)
	ns.UI.EnsureConversationOpen(id, false)
end

-- Left click. Opening straight into the thread that is waiting is the whole
-- point of a badge with a number on it: the player already knows there is
-- something to read, and one click should be enough to read it.
local function onLeftClick()
	if ns.UI.IsShown() then
		ns.UI.Toggle()
		return
	end
	local waiting = unreadConversations()
	if #waiting > 0 then
		openConversation(waiting[1].id)
	else
		ns.UI.Toggle()
	end
end

-- Right click: the names, then the rest. Everything the button can do is here,
-- so nothing depends on the player guessing a modifier.
local function onRightClick()
	local entries = {}
	local waiting = unreadConversations()
	for i = 1, math.min(#waiting, MAX_LISTED) do
		local conv = waiting[i]
		local id = conv.id
		entries[#entries + 1] = {
			text = ("%s  (%d)"):format(CM.DisplayName(conv), conv.unread),
			icon = "message",
			onClick = function() openConversation(id) end,
		}
	end
	if #entries > 0 then
		entries[#entries + 1] = { separator = true }
		entries[#entries + 1] = { text = L["Mark all as read"], icon = "check",
			onClick = function()
				local all = unreadConversations()
				for i = 1, #all do CM.MarkRead(all[i].id) end
			end }
		entries[#entries + 1] = { separator = true }
	end
	entries[#entries + 1] = { text = L["Open"], icon = "logo",
		onClick = function() ns.UI.Show() end }
	entries[#entries + 1] = { text = L["Settings"], icon = "gear",
		onClick = function() ns.SettingsUI.Toggle() end }
	entries[#entries + 1] = { text = L["Hide minimap button"], icon = "close",
		onClick = function()
			ns.Options.Set("advanced.minimap.hide", true)
		end }
	ns.Menu.Open(entries, { anchorTo = button, point = "TOPRIGHT",
		relPoint = "BOTTOMRIGHT", y = -ns.S.XS })
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function build()
	if button then return button end
	local minimap = _G.Minimap
	if not minimap then return nil end

	button = CreateFrame("Frame", "WhatTheWhisperMinimapButton", minimap)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata(minimap:GetFrameStrata())
	button:SetFrameLevel((minimap:GetFrameLevel() or 1) + 8)
	button:EnableMouse(true)
	button:SetMovable(true)

	button.surface = W.Surface(button, {
		color = "bg0", border = "borderStrong", radius = SIZE / 2, shadow = 6,
	})
	button.icon = W.Icon(button, "logo", 14, "accent")
	button.icon:SetPoint("CENTER")

	button.badge = ns.Controls.Badge(button, { height = 14 })
	button.badge:SetPoint("CENTER", button, "TOPRIGHT", -2, -2)

	W.MakeInteractive(button, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role = (state == "pressed" and "selected")
			or (state == "hover" and "hover") or "bg0"
		W.FadeSurfaceTo(button.surface, button, role, duration)
	end)
	W.SetTooltip(button, L["WhatTheWhisper"], L["/wtw - toggle the messenger"])

	button:HookScript("OnMouseUp", function(self, mouseButton)
		if self.dragging or not self:IsMouseOver() then return end
		if mouseButton == "RightButton" then
			onRightClick()
		else
			onLeftClick()
		end
	end)

	-- Drag around the minimap edge. The press only becomes a drag once the
	-- cursor has actually moved, so an ordinary click stays an ordinary click.
	button:SetScript("OnMouseDown", function(self, mouseButton)
		if mouseButton ~= "LeftButton" then return end
		self.dragging = false
		local startX, startY = GetCursorPosition()
		self:SetScript("OnUpdate", function()
			local minimapFrame = _G.Minimap
			local scale = minimapFrame:GetEffectiveScale() or 1
			local cx, cy = GetCursorPosition()
			if not self.dragging then
				local dx, dy = cx - (startX or cx), cy - (startY or cy)
				if (dx * dx + dy * dy) < (DRAG_SLOP * DRAG_SLOP) then return end
				self.dragging = true
			end
			cx, cy = cx / scale, cy / scale
			local mx, my = minimapFrame:GetCenter()
			if not mx then return end
			local angle = math.deg(math.atan2(cy - my, cx - mx))
			ns.db.profile.advanced.minimap.angle = angle
			positionAt(angle)
		end)
	end)
	local function endDrag(self)
		self:SetScript("OnUpdate", nil)
		if self.dragging then
			-- Swallow the click that ended a drag.
			Anim.After(0, function() self.dragging = false end)
		end
	end
	button:HookScript("OnMouseUp", endDrag)
	button:HookScript("OnHide", endDrag)

	return button
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function MinimapButton.Update()
	if not ns.db then return end
	local hide = ns.db.profile.advanced.minimap.hide
	if hide then
		if button then
			Anim.Attention(button.badge, false)
			button:Hide()
		end
		return
	end
	if not build() then return end
	positionAt(ns.db.profile.advanced.minimap.angle or 205)

	local waiting = unreadConversations()
	local count = ns.db.profile.notifications.badge and CM.TotalUnread() or 0
	button.badge:SetCount(count)
	-- Breathing, not flashing. Something is waiting; it is not an emergency.
	Anim.Attention(button.badge, count > 0)
	refreshTooltip(count > 0 and waiting or {})

	button:Show()
end

function MinimapButton.ApplyTheme()
	if not button then return end
	button.surface:SetRadius(SIZE / 2)
	button.surface:ApplyTheme()
	W.RefreshIcon(button.icon)
	button.badge:ApplyTheme()
	button.UpdateVisualState(true)
end
