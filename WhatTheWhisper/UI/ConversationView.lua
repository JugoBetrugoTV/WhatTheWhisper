-- WhatTheWhisper -- Header + messages + composer.
--
-- Used unchanged by the main window and by every popout, which is what keeps a
-- detached conversation looking like the same product rather than a second,
-- cheaper window.

local _, ns = ...
local Theme, W, Anim, Text = ns.Theme, ns.Widgets, ns.Anim, ns.Text
local CM, Compat = ns.ConversationManager, ns.Compat
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local ConversationView = {}
ns.ConversationView = ConversationView

local V = {}

local SEARCHBAR_H = 40

function ConversationView.New(parent, opts)
	opts = opts or {}
	local v = CreateFrame("Frame", nil, parent)
	for k, value in pairs(V) do v[k] = value end
	v.opts = opts

	v.surface = W.Surface(v, { color = "bg2" })

	------------------------------------------------------------------- header
	local header = CreateFrame("Frame", nil, v)
	header:SetHeight(opts.headerHeight or ns.SZ.HEADER_H)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.surface = W.Surface(header, { color = "headerBg" })
	header.divider = W.Hairline(header, "horizontal", { anchor = "BOTTOM", color = "borderSubtle" })
	v.header = header

	header.avatar = ns.Avatar.New(header, ns.SZ.AVATAR_MD)
	header.avatar:SetPoint("LEFT", header, "LEFT", ns.S.LG, 0)
	header.avatar:SetSurfaceRole("headerBg")

	header.name = W.Text(header, "TITLE", "textPrimary")
	header.name:SetPoint("TOPLEFT", header.avatar, "TOPRIGHT", ns.S.MD, -1)
	header.status = W.Text(header, "MICRO", "textMuted")
	header.status:SetPoint("BOTTOMLEFT", header.avatar, "BOTTOMRIGHT", ns.S.MD, 1)

	-- Header actions live in an ordered list and are laid out right to left, so
	-- a popout can append its own without any of the built-ins moving.
	header.actions = {}

	--------------------------------------------------------------- search bar
	local bar = CreateFrame("Frame", nil, v)
	bar:SetHeight(SEARCHBAR_H)
	bar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	bar.surface = W.Surface(bar, { color = "bg3" })
	bar.divider = W.Hairline(bar, "horizontal", { anchor = "BOTTOM", color = "borderSubtle" })
	bar:Hide()
	v.searchBar = bar

	bar.box = ns.Controls.SearchBox(bar, {
		placeholder = L["Search messages"], height = 26,
		onChange = function(value) v:RunSearch(value) end,
	})
	bar.box:SetPoint("LEFT", bar, "LEFT", ns.S.MD, 0)

	bar.count = W.Text(bar, "MICRO", "textMuted")
	bar.count:SetJustifyH("RIGHT")

	bar.close = ns.Button.Icon(bar, {
		icon = "close", size = 26, glyph = 12,
		onClick = function() v:ToggleSearch(false) end,
	})
	bar.close:SetPoint("RIGHT", bar, "RIGHT", -ns.S.SM, 0)

	bar.next = ns.Button.Icon(bar, {
		icon = "chevron_down", size = 26, glyph = 12,
		onClick = function() v:StepSearch(1) end,
	})
	bar.next:SetPoint("RIGHT", bar.close, "LEFT", -ns.S.XS, 0)

	bar.prev = ns.Button.Icon(bar, {
		icon = "chevron_up", size = 26, glyph = 12,
		onClick = function() v:StepSearch(-1) end,
	})
	bar.prev:SetPoint("RIGHT", bar.next, "LEFT", 0, 0)

	bar.count:SetPoint("RIGHT", bar.prev, "LEFT", -ns.S.SM, 0)
	bar.count:SetWidth(58)
	bar.box:SetPoint("RIGHT", bar.count, "LEFT", -ns.S.SM, 0)

	------------------------------------------------------------------ content
	v.composer = ns.Composer.New(v, {
		onResize = function() v:Relayout() end,
	})
	v.composer:SetPoint("BOTTOMLEFT")
	v.composer:SetPoint("BOTTOMRIGHT")

	v.list = ns.MessageList.New(v)
	v.list:SetPoint("LEFT")
	v.list:SetPoint("RIGHT")

	-------------------------------------------------------------- empty state
	v.empty = CreateFrame("Frame", nil, v)
	v.empty:SetAllPoints()
	v.emptyIcon = W.Icon(v.empty, "message", 44, "textMuted")
	v.emptyIcon:SetPoint("CENTER", v.empty, "CENTER", 0, 36)
	v.emptyIcon:SetAlpha(0.22)
	v.emptyTitle = W.Text(v.empty, "DISPLAY", "textSecondary")
	v.emptyTitle:SetPoint("TOP", v.emptyIcon, "BOTTOM", 0, -ns.S.LG)
	v.emptyTitle:SetJustifyH("CENTER")
	v.emptyTitle:SetWidth(340)
	v.emptyBody = W.Text(v.empty, "SMALL", "textMuted")
	v.emptyBody:SetPoint("TOP", v.emptyTitle, "BOTTOM", 0, -ns.S.SM)
	v.emptyBody:SetJustifyH("CENTER")
	v.emptyBody:SetWidth(340)
	v.emptyTitle:SetText(L["Pick a conversation"])
	v.emptyBody:SetText(L["Your whispers are kept here, one thread per player."])

	v:AddHeaderButton("search", L["Search messages"], function() v:ToggleSearch() end)
	v.header.search = v.header.actions[#v.header.actions].button
	if opts.showPopout ~= false then
		v:AddHeaderButton("popout", L["Pop out"], function()
			if v.conv then ns.UI.TogglePopout(v.conv.id) end
		end)
		v.header.popout = v.header.actions[#v.header.actions].button
	end
	v:AddHeaderButton("dots", L["Settings"], function(button)
		v:OpenConversationMenu(button)
	end)
	v.header.more = v.header.actions[#v.header.actions].button

	v:Relayout()
	v:SetConversation(nil)
	return v
end

--------------------------------------------------------------------------------
-- Header actions
--------------------------------------------------------------------------------

function V:AddHeaderButton(icon, tooltip, onClick)
	local button = ns.Button.Icon(self.header, {
		icon = icon, tooltip = tooltip,
		size = self.opts.compactHeader and 26 or ns.SZ.ICON_BTN,
		glyph = self.opts.compactHeader and 13 or ns.SZ.ICON_GLYPH,
		onClick = function(self2) ns.Guard("HeaderButton", onClick, self2) end,
	})
	self.header.actions[#self.header.actions + 1] = { icon = icon, button = button }
	self:RelayoutHeaderActions()
	return button
end

function V:RelayoutHeaderActions()
	local actions = self.header.actions
	local previous
	for i = #actions, 1, -1 do
		local button = actions[i].button
		button:ClearAllPoints()
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", -ns.S.XS, 0)
		else
			button:SetPoint("RIGHT", self.header, "RIGHT", -ns.S.MD, 0)
		end
		previous = button
	end
	self.headerActionWidth = #actions * (ns.SZ.ICON_BTN + ns.S.XS) + ns.S.MD
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function V:Relayout()
	local top = (self.opts.headerHeight or ns.SZ.HEADER_H)
	if self.searchBar:IsShown() then top = top + SEARCHBAR_H end
	self.list:ClearAllPoints()
	self.list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
	self.list:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -top)
	self.list:SetPoint("BOTTOM", self.composer, "TOP", 0, 0)
end

--------------------------------------------------------------------------------
-- Binding
--------------------------------------------------------------------------------

function V:SetConversation(conv)
	self.conv = conv
	self.list:SetConversation(conv)
	self.composer:SetConversation(conv)

	local hasConv = conv ~= nil
	self.header:SetShown(hasConv)
	self.list:SetShown(hasConv)
	self.composer:SetShown(hasConv)
	self.empty:SetShown(not hasConv)
	if not hasConv then
		self:ToggleSearch(false)
		return
	end

	self:RefreshHeader()
end

function V:RefreshHeader()
	local conv = self.conv
	if not conv then return end
	local header = self.header

	header.avatar:SetConversation(conv)

	local nameColor = Theme.ClassColor(conv.class, "headerBg")
	header.name:SetText(conv.name or conv.id)
	if nameColor then
		header.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3], 1)
	else
		W.SetTextRole(header.name, "textPrimary")
	end

	local status
	if conv.isBN then
		status = L["Battle.net"]
	else
		status = ns.PlayerInfo.StatusLine(conv.id)
	end
	if conv.muted then
		status = status and (status .. " \194\183 " .. L["Muted"]) or L["Muted"]
	end
	header.status:SetText(status or "")

	-- Truncate rather than overlap the action buttons.
	local available = (header:GetWidth() or 400)
		- (ns.S.LG + ns.SZ.AVATAR_MD + ns.S.MD)
		- (self.headerActionWidth or (ns.SZ.ICON_BTN * 3 + ns.S.MD))
	if available > 40 then
		header.name:SetWidth(0)
		if (header.name:GetStringWidth() or 0) > available then
			Text.Ellipsize(header.name, conv.name or conv.id, available)
		end
		header.status:SetWidth(math.max(20, available))
		header.status:SetWordWrap(false)
	end
end

--------------------------------------------------------------------------------
-- Search inside the conversation
--------------------------------------------------------------------------------

function V:ToggleSearch(force)
	local show = force
	if show == nil then show = not self.searchBar:IsShown() end
	self.searchBar:SetShown(show)
	self.header.search:SetSelectedState(show)
	self:Relayout()
	if show then
		self.searchBar.box:Focus()
	else
		self.searchBar.box:SetText("")
		self.searchResults = nil
		self.searchIndex = nil
		self.searchBar.count:SetText("")
		self.list.flashIndex = nil
		self.list:UpdateVisible()
	end
end

function V:RunSearch(query)
	local conv = self.conv
	self.searchResults = nil
	self.searchIndex = nil
	if not conv or not query or #query < 2 then
		self.searchBar.count:SetText("")
		self.list.flashIndex = nil
		self.list:UpdateVisible()
		return
	end
	local results = {}
	local messages = conv.messages
	for i = 1, #messages do
		if Text.Contains(messages[i][ns.MSG_TEXT], query) then
			results[#results + 1] = i
		end
	end
	self.searchResults = results
	if #results == 0 then
		self.searchBar.count:SetText("0")
		W.SetTextRole(self.searchBar.count, "textMuted")
		self.list.flashIndex = nil
		self.list:UpdateVisible()
		return
	end
	self.searchIndex = #results   -- newest match first
	self:JumpToCurrentMatch()
end

function V:StepSearch(delta)
	if not self.searchResults or #self.searchResults == 0 then return end
	local count = #self.searchResults
	self.searchIndex = ((self.searchIndex or 1) - 1 + delta) % count + 1
	self:JumpToCurrentMatch()
end

function V:JumpToCurrentMatch()
	local results = self.searchResults
	if not results or not self.searchIndex then return end
	local messageIndex = results[self.searchIndex]
	self.searchBar.count:SetText(("%d/%d"):format(self.searchIndex, #results))
	W.SetTextRole(self.searchBar.count, "textSecondary")
	self.list:ScrollToMessage(messageIndex, true)
end

--------------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------------

function V:OpenConversationMenu(anchor)
	if not self.conv then return end
	ns.Menu.Open(ns.UI.BuildConversationMenu(self.conv), {
		anchorTo = anchor, point = "TOPRIGHT", relPoint = "BOTTOMRIGHT", y = -ns.S.XS,
	})
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function V:OnMessageAdded(conv, msg, index)
	if conv ~= self.conv then return end
	self.list:OnMessageAdded(conv, msg, index)
end

function V:OnMessageUpdated(conv, msg)
	if conv ~= self.conv then return end
	self.list:OnMessageUpdated(conv, msg)
end

function V:OnConversationUpdated(conv)
	if conv ~= self.conv then return end
	self:RefreshHeader()
end

function V:Focus()
	self.composer:Focus()
end

function V:IsComposerFocused()
	return self.composer:HasFocus()
end

function V:ApplyTheme()
	self.surface:ApplyTheme()
	self.header.surface:ApplyTheme()
	self.header.divider:ApplyTheme()
	self.header.avatar:ApplyTheme()
	W.RefreshText(self.header.name)
	W.RefreshText(self.header.status)
	for i = 1, #self.header.actions do
		self.header.actions[i].button:ApplyTheme()
	end

	self.searchBar.surface:ApplyTheme()
	self.searchBar.divider:ApplyTheme()
	self.searchBar.box:ApplyTheme()
	self.searchBar.close:ApplyTheme()
	self.searchBar.next:ApplyTheme()
	self.searchBar.prev:ApplyTheme()
	W.RefreshText(self.searchBar.count)

	self.list:ApplyTheme()
	self.composer:ApplyTheme()
	W.RefreshIcon(self.emptyIcon)
	W.RefreshText(self.emptyTitle)
	W.RefreshText(self.emptyBody)
	self:RefreshHeader()
	self:Relayout()
end
