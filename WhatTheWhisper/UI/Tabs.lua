-- WhatTheWhisper -- Tab strip.
--
-- Browser style, not Blizzard registers: the active tab is raised to the canvas
-- colour so it visually merges with the conversation below it. Tabs can be
-- dragged to reorder and overflow into a menu rather than shrinking to nothing.

local _, ns = ...
local Theme, W, Anim, Pool, Text = ns.Theme, ns.Widgets, ns.Anim, ns.Pool, ns.Text
local CM = ns.ConversationManager

local Tabs = {}
ns.Tabs = Tabs

local max, min, floor, abs = math.max, math.min, math.floor, math.abs

local T = {}
local DOT = 6
-- The close button on a tab, and the vertical inset of the divider between two
-- of them. The close size was written once here and once inside the width
-- arithmetic that reserves room for it, with nothing tying the two together.
local CLOSE_SIZE = 18
local SEPARATOR_INSET = ns.S.SM

--------------------------------------------------------------------------------
-- Tab frames
--------------------------------------------------------------------------------

local function createTab(strip)
	local tab = CreateFrame("Frame", nil, strip)
	tab:SetHeight(ns.SZ.TAB_H)
	tab.surface = W.Surface(tab, { radius = ns.R.MD })
	tab.surface:SetCorners(true, true, false, false)

	-- Which tab you are on cannot rest on the raised fill alone. That fill is
	-- bg2 against the strip's bg1, and several skins put those within a percent
	-- of each other -- in Minimal they are the same colour, so the active tab
	-- was invisible. An accent bar along the top edge says it whatever the
	-- palette does, the way every editor with tabs does.
	tab.marker = CreateFrame("Frame", nil, tab)
	tab.marker:SetHeight(ns.SZ.ACCENT_BAR_W)
	tab.marker:SetPoint("TOPLEFT", tab, "TOPLEFT", ns.R.MD, 0)
	tab.marker:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -ns.R.MD, 0)
	tab.marker.surface = W.Surface(tab.marker, {
		color = "accent", radius = ns.SZ.ACCENT_BAR_W / 2, layer = "ARTWORK",
	})
	tab.marker:Hide()

	tab.dot = tab:CreateTexture(nil, "OVERLAY")
	tab.dot:SetTexture(ns.Draw.TEX_ROUND, "CLAMP", "CLAMP")
	tab.dot:SetSize(DOT, DOT)
	tab.dot:SetPoint("LEFT", tab, "LEFT", ns.S.MD, 0)
	tab.dot:Hide()

	tab.label = W.Text(tab, "SMALL", "textSecondary")
	tab.label:SetPoint("LEFT", tab, "LEFT", ns.S.MD, 0)

	tab.close = ns.Button.Icon(tab, {
		icon = "close", size = CLOSE_SIZE, glyph = 9, radius = CLOSE_SIZE / 2,
		onClick = function() if tab.conv then ns.UI.CloseConversation(tab.conv.id) end end,
	})
	tab.close:SetPoint("RIGHT", tab, "RIGHT", -ns.S.SM, 0)
	tab.close:Hide()

	-- Tabs sit edge to edge with no gap, which without a divider leaves two
	-- resting tabs reading as one strip of floating text rather than as tabs.
	-- The divider disappears next to the tab you are on or pointing at, the way
	-- a browser does it, so the raised tab keeps a clean edge.
	tab.divider = W.Hairline(tab, "vertical", {
		anchor = "RIGHT", color = "borderSubtle",
		insetStart = SEPARATOR_INSET, insetEnd = SEPARATOR_INSET,
	})
	tab.divider:SetShown(false)

	W.MakeInteractive(tab, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role
		if tab.active then
			role = "bg2"
		elseif state == "hover" or state == "pressed" then
			role = "hover"
		end
		W.FadeSurfaceTo(tab.surface, tab, role, duration)
		W.SetTextRole(tab.label, tab.active and "textPrimary"
			or (state == "hover" and "textPrimary" or "textSecondary"))
		tab.close:SetShown(tab.active or state == "hover" or state == "pressed")
		tab.marker:SetShown(tab.active and true or false)
		tab.hovered = (state == "hover" or state == "pressed") or nil
		strip:RefreshDividers()
	end)

	tab:HookScript("OnMouseUp", function(self, button)
		if self.dragging then return end
		if not self:IsMouseOver() or not self.conv then return end
		if button == "RightButton" then
			ns.Menu.Open(ns.UI.BuildConversationMenu(self.conv))
		elseif button == "MiddleButton" then
			ns.UI.CloseConversation(self.conv.id)
		else
			CM.Select(self.conv.id)
		end
	end)

	-- Drag to reorder.
	tab:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		self.dragStartX = select(1, GetCursorPosition()) / (self:GetEffectiveScale() or 1)
		self.dragging = false
		self:SetScript("OnUpdate", function()
			local x = select(1, GetCursorPosition()) / (self:GetEffectiveScale() or 1)
			if not self.dragging and abs(x - self.dragStartX) < 6 then return end
			self.dragging = true
			strip:DragTo(self, x)
		end)
	end)
	local function endDrag(self)
		self:SetScript("OnUpdate", nil)
		if self.dragging then
			self.dragging = false
			strip:Refresh()
		end
	end
	tab:HookScript("OnMouseUp", endDrag)
	tab:HookScript("OnHide", endDrag)

	return tab
end

local function resetTab(_, tab)
	tab:Hide()
	tab:ClearAllPoints()
	tab.divider:SetShown(false)
	tab.marker:Hide()
	tab.hovered = nil
	tab.conv = nil
	tab.active = nil
	tab.dragging = false
	tab:SetScript("OnUpdate", nil)
	tab.close:Hide()
	tab.dot:Hide()
end

--------------------------------------------------------------------------------
-- Strip
--------------------------------------------------------------------------------

function Tabs.New(parent)
	local strip = CreateFrame("Frame", nil, parent)
	for k, v in pairs(T) do strip[k] = v end
	strip:SetHeight(ns.SZ.TAB_H)

	strip.surface = W.Surface(strip, { color = "bg1" })
	strip.divider = W.Hairline(strip, "horizontal", { anchor = "BOTTOM", color = "borderSubtle" })
	strip.pool = Pool.New(function() return createTab(strip) end, resetTab, "tab")
	strip.rendered = {}

	strip.overflow = ns.Button.Icon(strip, {
		icon = "dots", size = 26, glyph = 14,
		onClick = function(self) strip:OpenOverflow(self) end,
	})
	strip.overflow:SetPoint("RIGHT", strip, "RIGHT", -ns.S.XS, 0)
	strip.overflow:Hide()

	strip:HookScript("OnSizeChanged", function() strip:Refresh() end)
	return strip
end

function T:VisibleCapacity(count)
	local available = (self:GetWidth() or 400) - ns.S.XS * 2
	if count == 0 then return 0, ns.SZ.TAB_MIN_W end
	local width = min(ns.SZ.TAB_MAX_W, available / count)
	if width >= ns.SZ.TAB_MIN_W then
		return count, width
	end
	-- Not everything fits: reserve room for the overflow button.
	available = available - (26 + ns.S.XS)
	local fit = max(1, floor(available / ns.SZ.TAB_MIN_W))
	return min(count, fit), ns.SZ.TAB_MIN_W
end

function T:Refresh()
	self.pool:ReleaseAll()
	wipe(self.rendered)

	local order = ns.UI.GetTabOrder()
	local count = #order
	if count == 0 then
		self.overflow:Hide()
		return
	end

	local shownCount, tabWidth = self:VisibleCapacity(count)
	self.overflow:SetShown(shownCount < count)
	self.hidden = {}

	local x = ns.S.XS
	local selectedID = CM.SelectedID()
	for i = 1, count do
		local conv = CM.Get(order[i])
		if conv then
			if i <= shownCount then
				local tab = self.pool:Acquire()
				tab.conv = conv
				tab.index = i
				tab.active = (conv.id == selectedID)
				tab:SetWidth(tabWidth)
				tab:ClearAllPoints()
				tab:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
				self:PaintTab(tab, conv, tabWidth)
				tab:Show()
				self.rendered[#self.rendered + 1] = tab
				x = x + tabWidth
			else
				self.hidden[#self.hidden + 1] = conv
			end
		end
	end
	self:RefreshDividers()
end

-- A divider belongs between two tabs that are both at rest. Next to the active
-- one, or the one under the cursor, it would cut into a raised edge.
function T:RefreshDividers()
	local rendered = self.rendered
	for i = 1, #rendered do
		local tab, next = rendered[i], rendered[i + 1]
		local quiet = not tab.active and not tab.hovered
		local nextQuiet = next ~= nil and not next.active and not next.hovered
		tab.divider:SetShown(quiet and nextQuiet)
	end
end

function T:PaintTab(tab, conv, width)
	local unread = conv.unread > 0
	tab.dot:SetShown(unread)
	if unread then
		local c = Theme.Get(conv.muted and "textMuted" or "accent")
		tab.dot:SetVertexColor(c[1], c[2], c[3], 1)
		tab.label:ClearAllPoints()
		tab.label:SetPoint("LEFT", tab.dot, "RIGHT", ns.S.SM - 1, 0)
	else
		tab.label:ClearAllPoints()
		tab.label:SetPoint("LEFT", tab, "LEFT", ns.S.MD, 0)
	end

	local reserved = ns.S.MD + (unread and (DOT + ns.S.SM - 1) or 0)
		+ CLOSE_SIZE + ns.S.SM * 2
	Text.Ellipsize(tab.label, CM.DisplayName(conv), max(20, width - reserved))
	tab.UpdateVisualState(true)

	if unread and ns.db.profile.layout.tabBlink and not tab.active and not conv.muted then
		Anim.Pulse(tab.dot, 0.3)
	end
end

function T:DragTo(tab, cursorX)
	local order = ns.UI.GetTabOrder()
	local width = tab:GetWidth() or ns.SZ.TAB_MIN_W
	local left = self:GetLeft() or 0
	local target = max(1, min(#order, floor((cursorX - left - ns.S.XS) / width) + 1))
	if target == tab.index then return end
	ns.UI.MoveTab(tab.conv.id, target)
	tab.index = target
	self:Refresh()
end

function T:OpenOverflow(anchor)
	local entries = {}
	local hidden = self.hidden or {}
	for i = 1, #hidden do
		local conv = hidden[i]
		entries[#entries + 1] = {
			text = conv.name .. (conv.unread > 0 and ("  (" .. conv.unread .. ")") or ""),
			icon = conv.unread > 0 and "dot" or nil,
			onClick = function() CM.Select(conv.id) end,
		}
	end
	if #entries == 0 then return end
	ns.Menu.Open(entries, {
		anchorTo = anchor, point = "TOPRIGHT", relPoint = "BOTTOMRIGHT", y = -ns.S.XS,
	})
end

function T:ApplyTheme()
	self.surface:ApplyTheme()
	self.divider:ApplyTheme()
	self.overflow:ApplyTheme()
	local function refresh(tab)
		tab.surface:ApplyTheme()
		tab.surface:SetCorners(true, true, false, false)
		tab.marker.surface:ApplyTheme()
		tab.divider:ApplyTheme()
		W.RefreshText(tab.label)
		tab.close:ApplyTheme()
	end
	for tab in self.pool:EnumerateActive() do refresh(tab) end
	for _, tab in ipairs(self.pool.free) do refresh(tab) end
	self:Refresh()
end
