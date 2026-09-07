-- WhatTheWhisper -- The conversation list.
--
-- Rows are pooled and virtualised on a fixed row height, so the list stays at a
-- dozen frames whether you have three threads or two hundred.
--
-- Narrow the sidebar past SIDEBAR_COMPACT_AT and it collapses to an avatar rail
-- instead of squashing the text, which is the difference between "responsive"
-- and "resizable".

local _, ns = ...
local Theme, W, Pool, Text = ns.Theme, ns.Widgets, ns.Pool, ns.Text
local CM, Format = ns.ConversationManager, ns.Format
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Sidebar = {}
ns.Sidebar = Sidebar

local max, min, floor = math.max, math.min, math.floor

local ACCENT_BAR_W = 3
local S = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function createRow(sidebar)
	local row = CreateFrame("Frame", nil, sidebar.list.viewport)
	row.surface = W.Surface(row, {
		radius = ns.R.MD, insets = { ns.S.SM, ns.S.SM, 1, 1 },
	})

	row.accent = CreateFrame("Frame", nil, row)
	row.accent:SetWidth(ACCENT_BAR_W)
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -ns.S.MD)
	row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, ns.S.MD)
	row.accent.surface = W.Surface(row.accent, {
		color = "accent", radius = ACCENT_BAR_W / 2, layer = "ARTWORK",
	})
	row.accent:Hide()

	row.avatar = ns.Avatar.New(row, ns.SZ.AVATAR_LG)
	row.avatar:SetSurfaceRole("bg1")

	row.name = W.Text(row, "BODY", "textPrimary")
	row.preview = W.Text(row, "SMALL", "textMuted")
	row.time = W.Text(row, "MICRO", "textMuted")
	row.time:SetJustifyH("RIGHT")

	row.pin = W.Icon(row, "pin_filled", 10, "textMuted")
	row.mute = W.Icon(row, "bell_off", 11, "textMuted")

	row.badge = ns.Controls.Badge(row)

	W.MakeInteractive(row, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role
		if state == "selected" then role = "selected"
		elseif state == "pressed" then role = "selected"
		elseif state == "hover" then role = "hover" end
		W.FadeSurfaceTo(row.surface, row, role, duration)
		row.accent:SetShown(state == "selected" and (Theme.m.accentBar ~= false))
	end)

	row:HookScript("OnMouseUp", function(self, button)
		if not self:IsMouseOver() or not self.conv then return end
		if button == "RightButton" then
			ns.Menu.Open(ns.UI.BuildConversationMenu(self.conv))
		elseif button == "MiddleButton" then
			ns.UI.CloseConversation(self.conv.id)
		else
			CM.Select(self.conv.id)
		end
	end)

	return row
end

local function resetRow(_, row)
	row:Hide()
	row:ClearAllPoints()
	row.conv = nil
	row:SetSelectedState(false)
	row.badge:Hide()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Sidebar.New(parent)
	local sb = CreateFrame("Frame", nil, parent)
	for k, v in pairs(S) do sb[k] = v end

	sb.surface = W.Surface(sb, { color = "bg1" })
	sb.divider = W.Hairline(sb, "vertical", { anchor = "RIGHT", color = "borderSubtle" })

	------------------------------------------------------------------- header
	local header = CreateFrame("Frame", nil, sb)
	header:SetHeight(ns.SZ.SIDEBAR_HEADER_H)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	sb.header = header

	header.newChat = ns.Button.Icon(header, {
		icon = "message_plus", tooltip = L["New conversation"],
		onClick = function(self) ns.UI.PromptNewConversation(self) end,
	})
	header.newChat:SetPoint("RIGHT", header, "RIGHT", -ns.S.SM, 0)

	header.search = ns.Controls.SearchBox(header, {
		placeholder = L["Search conversations"], height = 30,
		onChange = function(value) sb:SetFilter(value) end,
	})
	header.search:SetPoint("LEFT", header, "LEFT", ns.S.MD, 0)
	header.search:SetPoint("RIGHT", header.newChat, "LEFT", -ns.S.XS, 0)

	--------------------------------------------------------------------- list
	sb.list = ns.Scroll.New(sb, { barInset = ns.S.XS })
	sb.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	sb.list:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	sb.list:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
	sb.list.OnScrollChanged = function() sb:UpdateVisible() end

	sb.rowPool = Pool.New(function() return createRow(sb) end, resetRow)
	sb.filtered = {}
	sb.filter = ""

	--------------------------------------------------------------------- empty
	sb.empty = CreateFrame("Frame", nil, sb.list.viewport)
	sb.empty:SetAllPoints()
	sb.emptyIcon = W.Icon(sb.empty, "message", 34, "textMuted")
	sb.emptyIcon:SetPoint("CENTER", sb.empty, "CENTER", 0, 28)
	sb.emptyIcon:SetAlpha(0.22)
	sb.emptyTitle = W.Text(sb.empty, "SMALL", "textSecondary")
	sb.emptyTitle:SetPoint("TOP", sb.emptyIcon, "BOTTOM", 0, -ns.S.MD)
	sb.emptyTitle:SetJustifyH("CENTER")
	sb.emptyBody = W.Text(sb.empty, "MICRO", "textMuted")
	sb.emptyBody:SetPoint("TOP", sb.emptyTitle, "BOTTOM", 0, -ns.S.XS)
	sb.emptyBody:SetJustifyH("CENTER")

	sb:HookScript("OnSizeChanged", function()
		sb:UpdateCompactMode()
		sb:UpdateVisible()
	end)

	sb:Refresh()
	return sb
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

function S:SetFilter(value)
	self.filter = value or ""
	self:Refresh()
	self.list:ScrollToTop(false)
end

function S:Refresh()
	ns.Search.FilterConversations(self.filter, self.filtered)
	local rowHeight = Theme.RowHeight()
	self.rowHeight = rowHeight
	self.list:SetContentHeight(#self.filtered * rowHeight, false)
	self:UpdateEmptyState()
	self:UpdateVisible()
end

function S:UpdateEmptyState()
	local isEmpty = #self.filtered == 0
	self.empty:SetShown(isEmpty)
	if not isEmpty then return end
	if self.filter ~= "" then
		self.emptyTitle:SetText(L["No matches"])
		self.emptyBody:SetText(L["Try a different name or word."])
	else
		self.emptyTitle:SetText(L["No conversations yet"])
		self.emptyBody:SetText(L["Whisper someone to start a conversation."])
	end
	local width = max(120, (self:GetWidth() or 260) - ns.S.HUGE)
	self.emptyTitle:SetWidth(width)
	self.emptyBody:SetWidth(width)
end

--------------------------------------------------------------------------------
-- Compact rail
--------------------------------------------------------------------------------

function S:UpdateCompactMode()
	local compact = (self:GetWidth() or ns.SZ.SIDEBAR_W) < ns.SZ.SIDEBAR_COMPACT_AT
	if compact == self.compact then return end
	self.compact = compact
	self.header.search:SetShown(not compact)
	if compact then
		self.header.newChat:ClearAllPoints()
		self.header.newChat:SetPoint("CENTER", self.header, "CENTER", 0, 0)
	else
		self.header.newChat:ClearAllPoints()
		self.header.newChat:SetPoint("RIGHT", self.header, "RIGHT", -ns.S.SM, 0)
	end
	self:Refresh()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function layoutRow(sb, row, compact)
	local pad = ns.S.LG
	local avatarSize = compact and ns.SZ.AVATAR_MD or ns.SZ.AVATAR_LG

	row.avatar:SetAvatarSize(avatarSize)
	row.avatar:ClearAllPoints()
	if compact then
		row.avatar:SetPoint("CENTER", row, "CENTER", 0, 0)
	else
		row.avatar:SetPoint("LEFT", row, "LEFT", pad, 0)
	end

	row.name:SetShown(not compact)
	row.preview:SetShown(not compact)
	row.time:SetShown(not compact)

	if compact then
		row.badge:ClearAllPoints()
		row.badge:SetPoint("TOPRIGHT", row.avatar, "TOPRIGHT", 6, 4)
		row.pin:Hide()
		row.mute:Hide()
		return
	end

	local textLeft = pad + avatarSize + ns.S.MD
	row.name:ClearAllPoints()
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -(ns.S.MD + 1))

	row.time:ClearAllPoints()
	row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -pad, -(ns.S.MD + 2))
	row.time:SetWidth(56)

	row.preview:ClearAllPoints()
	row.preview:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", textLeft, ns.S.MD + 1)

	row.badge:ClearAllPoints()
	row.badge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -pad, ns.S.MD)
end

function S:RenderRow(conv, index)
	local row = self.rowPool:Acquire()
	local compact = self.compact
	local rowHeight = self.rowHeight or Theme.RowHeight()

	row.conv = conv
	row:SetHeight(rowHeight)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.list.viewport, "TOPLEFT", 0,
		-((index - 1) * rowHeight - self.list:GetOffset()))
	row:SetPoint("TOPRIGHT", self.list.viewport, "TOPRIGHT", 0,
		-((index - 1) * rowHeight - self.list:GetOffset()))

	layoutRow(self, row, compact)

	row.avatar:SetConversation(conv)
	row:SetSelectedState(CM.SelectedID() == conv.id)

	if not compact then
		local unread = conv.unread > 0
		local nameColor = Theme.ClassColor(conv.class, "bg1")
		if nameColor then
			row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3], 1)
		else
			W.SetTextRole(row.name, conv.muted and "textSecondary" or "textPrimary")
		end

		-- Reserve room for whichever indicators this row actually shows.
		local indicatorWidth = 0
		row.pin:SetShown(conv.pinned)
		row.mute:SetShown(conv.muted)
		if conv.pinned then indicatorWidth = indicatorWidth + 14 end
		if conv.muted then indicatorWidth = indicatorWidth + 15 end

		local textLeft = ns.S.LG + ns.SZ.AVATAR_LG + ns.S.MD
		local available = max(30, (self:GetWidth() or 280) - textLeft - ns.S.LG - 56 - indicatorWidth)
		Text.Ellipsize(row.name, conv.name or conv.id, available)

		local anchor = row.name
		if conv.pinned then
			row.pin:ClearAllPoints()
			row.pin:SetPoint("LEFT", anchor, "RIGHT", ns.S.XS + 1, 0)
			anchor = row.pin
		end
		if conv.muted then
			row.mute:ClearAllPoints()
			row.mute:SetPoint("LEFT", anchor, "RIGHT", ns.S.XS + 1, -1)
		end

		row.time:SetText(Format.ListStamp(conv.lastActivity))
		W.SetTextRole(row.time, unread and "accent" or "textMuted")

		local preview, direction = CM.Preview(conv)
		if preview then
			if direction == ns.DIR_OUT then
				preview = L["You"] .. ": " .. preview
			end
		else
			preview = ""
		end
		W.SetTextRole(row.preview, unread and "textSecondary" or "textMuted")
		local previewWidth = max(30, (self:GetWidth() or 280) - textLeft - ns.S.LG
			- (unread and 30 or 0))
		Text.Ellipsize(row.preview, preview, previewWidth)
	end

	row.badge:SetCount(conv.unread, conv.muted)
	row:Show()
	return row
end

function S:UpdateVisible()
	self.rowPool:ReleaseAll()
	local rowHeight = self.rowHeight or Theme.RowHeight()
	local count = #self.filtered
	if count == 0 then return end

	local offset = self.list:GetOffset()
	local viewHeight = self.list:GetViewHeight()
	local first = max(1, floor(offset / rowHeight) + 1)
	local last = min(count, floor((offset + viewHeight) / rowHeight) + 1)

	for i = first, last do
		self:RenderRow(self.filtered[i], i)
	end
end

function S:ScrollToConversation(id)
	for i = 1, #self.filtered do
		if self.filtered[i].id == id then
			local rowHeight = self.rowHeight or Theme.RowHeight()
			local top = (i - 1) * rowHeight
			local offset = self.list:GetOffset()
			local view = self.list:GetViewHeight()
			if top < offset then
				self.list:SetOffset(top, true)
			elseif top + rowHeight > offset + view then
				self.list:SetOffset(top + rowHeight - view, true)
			end
			return
		end
	end
end

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

function S:ApplyTheme()
	self.surface:ApplyTheme()
	self.divider:ApplyTheme()
	self.header.search:ApplyTheme()
	self.header.newChat:ApplyTheme()
	self.list:ApplyTheme()
	W.RefreshIcon(self.emptyIcon)
	W.RefreshText(self.emptyTitle)
	W.RefreshText(self.emptyBody)

	local function refresh(row)
		row.surface:ApplyTheme()
		row.accent.surface:ApplyTheme()
		row.avatar:ApplyTheme()
		W.RefreshText(row.name)
		W.RefreshText(row.preview)
		W.RefreshText(row.time)
		W.RefreshIcon(row.pin)
		W.RefreshIcon(row.mute)
		row.badge:ApplyTheme()
	end
	for row in self.rowPool:EnumerateActive() do refresh(row) end
	for _, row in ipairs(self.rowPool.free) do refresh(row) end

	self.compact = nil
	self:UpdateCompactMode()
	self:Refresh()
end
