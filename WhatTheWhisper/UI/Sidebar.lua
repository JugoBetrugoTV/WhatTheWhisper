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
local L = ns.L

local Sidebar = {}
ns.Sidebar = Sidebar

local max, min, floor = math.max, math.min, math.floor

-- Room for the longest thing a timestamp column ever holds -- "Yesterday" in the
-- longest translation -- so the name's truncation point does not move as the
-- clock does.
local STAMP_W = 68

-- The row's margins. The avatar's left inset is the module's one horizontal
-- reference: the text column starts after it, the separator starts with it, and
-- the timestamp column ends symmetrically opposite.
local ROW_PAD_X = ns.S.LG
-- Between the avatar and the text. Slightly wider than the outer margin because
-- the avatar is a solid shape and reads as heavier than the panel edge.
local AVATAR_GAP = ns.S.MD

local S = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function createRow(sidebar)
	local row = CreateFrame("Frame", nil, sidebar.list.viewport)

	-- Full bleed, no card. A rounded rectangle inside the sidebar, inside the
	-- window, is the box-inside-a-box look that says "addon" before anything has
	-- been read -- and it costs the row the eight pixels either side that the
	-- text actually wants. What marks a row now is the surface under it changing
	-- colour, which is all a desktop messenger has ever needed.
	row.surface = W.Surface(row, { layer = "BACKGROUND" })

	-- A hairline between rows, starting where the text starts rather than at the
	-- panel edge: a full-width rule reads as a table, an indented one reads as a
	-- list. It belongs to the row above it, so the last row has none.
	row.separator = W.Hairline(row, "horizontal", {
		anchor = "BOTTOM", color = "borderSubtle",
		insetStart = ROW_PAD_X + ns.SZ.AVATAR_LG + AVATAR_GAP,
	})

	row.avatar = ns.Avatar.New(row, ns.SZ.AVATAR_LG)
	row.avatar:SetSurfaceRole("bg1")

	row.name = W.Text(row, "BODY", "textPrimary")
	row.preview = W.Text(row, "SMALL", "textMuted")
	row.time = W.Text(row, "MICRO", "textMuted")
	row.time:SetJustifyH("RIGHT")

	-- These two are the only marks on a row that mean something rather than
	-- decorate it, and at textMuted on a busy list they were easy to miss.
	row.pin = W.Icon(row, "pin", ns.SZ.ICON_MARK, "textSecondary")
	row.mute = W.Icon(row, "mute", ns.SZ.ICON_MARK, "textSecondary")

	row.badge = ns.Controls.Badge(row)

	-- One place decides whether the hairline under this row is drawn, because
	-- two places deciding it is how it ended up never drawn at all: the layout
	-- pass and the interaction callback each had their own expression, and the
	-- layout one ran last and was wrong.
	--
	-- It is drawn between two resting rows and nowhere else -- not under the row
	-- you are on or pointing at, where it would cut across the wash, and not
	-- under the last row, where it would be a line with nothing after it.
	function row:WantsSeparator()
		if self.compactRow or self.lastInList then return false end
		local state = self.__wtwState or "rest"
		return state == "rest" or state == "disabled"
	end

	W.MakeInteractive(row, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role
		if state == "selected" then role = "selected"
		elseif state == "pressed" then role = "selected"
		elseif state == "hover" then role = "hover" end
		W.FadeSurfaceTo(row.surface, row, role, duration)
		row.separator:SetShown(row:WantsSeparator())
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
	row.rowIndex = nil
	row.lastInList = nil
	row.compactRow = nil
	row.separator:SetShown(false)
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

	-- The one creative action in the sidebar. As a ghost glyph beside the search
	-- field it read as decoration; filled, it reads as the button it is -- the
	-- same weight the send button carries in the composer, for the same reason.
	header.newChat = ns.Button.Icon(header, {
		icon = "newchat", tooltip = L["New conversation"],
		variant = "primary", radius = ns.SZ.ICON_BTN / 2,
		onClick = function(self) ns.UI.PromptNewConversation(self) end,
	})
	header.newChat:SetPoint("RIGHT", header, "RIGHT", -ns.S.MD, 0)

	header.search = ns.Controls.SearchBox(header, {
		placeholder = L["Search conversations"],
		onChange = function(value) sb:SetFilter(value) end,
	})
	header.search:SetPoint("LEFT", header, "LEFT", ns.S.MD, 0)
	header.search:SetPoint("RIGHT", header.newChat, "LEFT", -ns.S.SM, 0)

	--------------------------------------------------------------------- list
	sb.list = ns.Scroll.New(sb, { barInset = ns.S.XS })
	sb.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	sb.list:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	sb.list:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
	sb.list.OnScrollChanged = function() sb:UpdateVisible() end

	sb.rowPool = Pool.New(function() return createRow(sb) end, resetRow, "sidebar.row")
	sb.filtered = {}
	sb.filter = ""

	--------------------------------------------------------------------- empty
	sb.empty = CreateFrame("Frame", nil, sb.list.viewport)
	sb.empty:SetAllPoints()
	sb.emptyIcon = W.Icon(sb.empty, "chat", ns.SZ.EMPTY_ICON_SM, "textMuted")
	sb.emptyIcon:SetPoint("CENTER", sb.empty, "CENTER", 0, 28)
	sb.emptyIcon:SetAlpha(0.22)
	sb.emptyTitle = W.Text(sb.empty, "BODY", "textSecondary")
	sb.emptyTitle:SetPoint("TOP", sb.emptyIcon, "BOTTOM", 0, -ns.S.MD)
	sb.emptyTitle:SetJustifyH("CENTER")
	sb.emptyBody = W.Text(sb.empty, "SMALL", "textMuted")
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
	self.rangeFirst, self.rangeLast = nil, nil
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
		self.header.newChat:SetPoint("RIGHT", self.header, "RIGHT", -ns.S.MD, 0)
	end
	self:Refresh()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- Where the text column starts, which is the one number the whole row hangs off.
local function textLeftFor(avatarSize)
	return ROW_PAD_X + avatarSize + AVATAR_GAP
end

local function layoutRow(row, compact)
	local avatarSize = compact and ns.SZ.AVATAR_MD or ns.SZ.AVATAR_LG
	row.compactRow = compact

	row.avatar:SetAvatarSize(avatarSize)
	row.avatar:ClearAllPoints()
	if compact then
		row.avatar:SetPoint("CENTER", row, "CENTER", 0, 0)
	else
		row.avatar:SetPoint("LEFT", row, "LEFT", ROW_PAD_X, 0)
	end

	row.name:SetShown(not compact)
	row.preview:SetShown(not compact)
	row.time:SetShown(not compact)
	row.separator:SetShown(row:WantsSeparator())

	if compact then
		row.badge:ClearAllPoints()
		row.badge:SetPoint("TOPRIGHT", row.avatar, "TOPRIGHT", ns.S.XS + 2, ns.S.XS)
		row.pin:Hide()
		row.mute:Hide()
		return
	end

	-- The two text lines are a block, centred on the avatar rather than pinned
	-- to the row's top and bottom edges. Pinning them made the gap between name
	-- and preview a function of the row height: at the larger font scales the
	-- two lines drifted apart until the row read as two unrelated things.
	local block = (row.name:GetStringHeight() or ns.T.BODY)
		+ ns.S.XS + (row.preview:GetStringHeight() or ns.T.SMALL)
	local top = ((row:GetHeight() or ns.SZ.ROW_H) - block) / 2

	local textLeft = textLeftFor(avatarSize)
	row.name:ClearAllPoints()
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -top)

	-- The timestamp is a smaller face than the name; offsetting it by the ascent
	-- difference puts the two on one baseline instead of one top edge.
	row.time:ClearAllPoints()
	row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_PAD_X,
		-(top + W.BaselineOffset(row.time, row.name.__wtwToken)))
	row.time:SetWidth(STAMP_W)

	row.preview:ClearAllPoints()
	row.preview:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -ns.S.XS)

	-- The badge sits on the preview's line, not on the row's bottom edge, so it
	-- reads as belonging to the message it counts.
	row.badge:ClearAllPoints()
	row.badge:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD_X, 0)
	row.badge:SetPoint("TOP", row.preview, "TOP", 0, ns.S.XS / 2)
end

function S:PositionRow(row, index)
	local rowHeight = self.rowHeight or Theme.RowHeight()
	local y = -((index - 1) * rowHeight - self.list:GetOffset())
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.list.viewport, "TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", self.list.viewport, "TOPRIGHT", 0, y)
end

function S:RenderRow(conv, index)
	local row = self.rowPool:Acquire()
	local compact = self.compact
	local rowHeight = self.rowHeight or Theme.RowHeight()

	row.conv = conv
	row.rowIndex = index
	row.lastInList = index >= #self.filtered
	row:SetHeight(rowHeight)
	self:PositionRow(row, index)

	layoutRow(row, compact)

	row.avatar:SetConversation(conv)
	row:SetSelectedState(CM.SelectedID() == conv.id)

	if not compact then
		local unread = conv.unread > 0
		local nameColor = Theme.ClassColor(conv.class, "bg1")
		if nameColor then
			-- A muted thread has to look muted even when class colours are on,
			-- so the class colour is pulled towards the muted text colour.
			if conv.muted then
				nameColor = ns.Color.Mix(nameColor, Theme.Get("textMuted"), 0.55)
			end
			row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3], 1)
		else
			W.SetTextRole(row.name, conv.muted and "textSecondary" or "textPrimary")
		end

		-- Reserve room for whichever indicators this row actually shows. Each is
		-- its own glyph plus the gap before it, computed rather than guessed:
		-- the two numbers used to be 15 and 16 for no reason anyone could name.
		local indicatorWidth = 0
		row.pin:SetShown(conv.pinned)
		row.mute:SetShown(conv.muted)
		local MARK = ns.SZ.ICON_MARK + ns.S.XS
		if conv.pinned then indicatorWidth = indicatorWidth + MARK end
		if conv.muted then indicatorWidth = indicatorWidth + MARK end

		local textLeft = textLeftFor(ns.SZ.AVATAR_LG)
		local width = self:GetWidth() or ns.SZ.SIDEBAR_W
		local available = max(30, width
			- textLeft - ROW_PAD_X - STAMP_W - ns.S.SM - indicatorWidth)
		Text.Ellipsize(row.name, CM.DisplayName(conv), available)

		local anchor = row.name
		if conv.pinned then
			row.pin:ClearAllPoints()
			row.pin:SetPoint("LEFT", anchor, "RIGHT", ns.S.XS, 0)
			anchor = row.pin
		end
		if conv.muted then
			row.mute:ClearAllPoints()
			row.mute:SetPoint("LEFT", anchor, "RIGHT", ns.S.XS, -1)
		end

		row.time:SetText(Format.ListStamp(conv.lastActivity))
		-- Unread is carried by three quiet changes rather than one loud one: the
		-- time takes the accent, the preview steps up a level, and the badge
		-- appears. Any one of them alone would be missable in a long list; all
		-- three at once, and the row still does not shout.
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
		local badgeWidth = unread and (row.badge:GetWidth() or ns.SZ.BADGE_H) + ns.S.SM or 0
		local previewWidth = max(30, width - textLeft - ROW_PAD_X - badgeWidth)
		Text.Ellipsize(row.preview, preview, previewWidth)
	end

	-- Counted before the preview is measured above on the next render, which is
	-- fine: the badge's width only changes when the count crosses a digit, and
	-- the row is re-rendered whenever the count changes at all.
	row.badge:SetCount(conv.unread, conv.muted)
	row:Show()
	return row
end

function S:UpdateVisible()
	local rowHeight = self.rowHeight or Theme.RowHeight()
	local count = #self.filtered
	if count == 0 then
		self.rowPool:ReleaseAll()
		self.rangeFirst, self.rangeLast = nil, nil
		return
	end

	local offset = self.list:GetOffset()
	local viewHeight = self.list:GetViewHeight()
	local first = max(1, floor(offset / rowHeight) + 1)
	local last = min(count, floor((offset + viewHeight) / rowHeight) + 1)

	-- Scrolling inside the same set of rows only needs new anchors. Re-rendering
	-- would redo two ellipsised strings per row on every animation frame.
	if first == self.rangeFirst and last == self.rangeLast then
		for row in self.rowPool:EnumerateActive() do
			if row.rowIndex then self:PositionRow(row, row.rowIndex) end
		end
		return
	end
	self.rangeFirst, self.rangeLast = first, last

	self.rowPool:ReleaseAll()
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

-- The player changed the language. Everything below was written once, when the
-- frame was built, which is exactly why none of it can notice on its own.
function S:Relocalize()
	W.SetTooltip(self.header.newChat, L["New conversation"])
	self.header.search.input:SetPlaceholder(L["Search conversations"])
	self:Refresh()
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
		row.separator:ApplyTheme()
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
