-- WhatTheWhisper -- Header + messages + composer.
--
-- Used unchanged by the main window and by every popout, which is what keeps a
-- detached conversation looking like the same product rather than a second,
-- cheaper window.

local _, ns = ...
local Theme, W, Text = ns.Theme, ns.Widgets, ns.Text
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

	-- The name and the line under it are one block, with a fixed gap, centred
	-- on the avatar. Anchoring one to the avatar's top edge and the other to its
	-- bottom made that gap a function of the avatar's height instead: at the
	-- larger font scales the two lines walked into each other, and with no
	-- status line at all the name sat high in a header it should be centred in.
	header.name = W.Text(header, "TITLE", "textPrimary")
	header.status = W.Text(header, "MICRO", "textMuted")
	v:LayoutHeaderText(false)

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
	v.emptyIcon = W.Icon(v.empty, "message", ns.SZ.EMPTY_ICON, "textMuted")
	v.emptyIcon:SetPoint("CENTER", v.empty, "CENTER", 0, 36)
	v.emptyIcon:SetAlpha(0.22)
	v.emptyTitle = W.Text(v.empty, "DISPLAY", "textSecondary")
	v.emptyTitle:SetPoint("TOP", v.emptyIcon, "BOTTOM", 0, -ns.S.LG)
	v.emptyTitle:SetJustifyH("CENTER")
	v.emptyTitle:SetWidth(ns.SZ.EMPTY_TEXT_W)
	v.emptyBody = W.Text(v.empty, "SMALL", "textMuted")
	v.emptyBody:SetPoint("TOP", v.emptyTitle, "BOTTOM", 0, -ns.S.SM)
	v.emptyBody:SetJustifyH("CENTER")
	v.emptyBody:SetWidth(ns.SZ.EMPTY_TEXT_W)
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

-- The window plate is drawn with a corner radius, but the surfaces sitting on
-- top of it are rectangles and would square those corners off again. Whichever
-- child actually touches a window corner has to carry the rounding.
function V:SetOuterCorners(topLeft, topRight, bottomLeft, bottomRight, base)
	base = base or ns.R.LG
	self.surface:SetRadius(base)
	self.surface:SetCorners(topLeft, topRight, bottomLeft, bottomRight)
	self.header.surface:SetRadius(base)
	self.header.surface:SetCorners(topLeft, topRight, false, false)
	self.composer.surface:SetRadius(base)
	self.composer.surface:SetCorners(false, false, bottomLeft, bottomRight)
	self.outerCorners = { topLeft, topRight, bottomLeft, bottomRight, base }
end

-- While a popout is collapsed to its header, the header is the bottom edge too.
function V:SetHeaderIsBottom(isBottom)
	local o = self.outerCorners
	if not o then return end
	self.header.surface:SetCorners(o[1], o[2], isBottom and o[3], isBottom and o[4])
end

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

	-- Opening a thread is the moment to find out who this actually is. Guild,
	-- zone, and a level and class for somebody who is neither a friend nor a
	-- guildmate only ever come from a /who, and this is throttled hard enough
	-- that the player will never notice it happening.
	ns.PlayerInfo.EnsureDetails(conv.id, conv.isBN)
end

-- The gap between the name and the line under it.
local HEADER_LEADING = 2

-- Two states. With a status line the two labels are one block, centred on the
-- avatar as a block; with none the name is centred on its own.
--
-- Centring the *pair* is the part that is easy to get wrong. The two lines are
-- different heights, so splitting the leading evenly around the avatar's centre
-- leaves the block sitting high by half that difference -- close enough to look
-- like nothing in particular, and exactly the kind of thing that makes a header
-- feel slightly off without anyone being able to say why.
function V:LayoutHeaderText(hasStatus)
	local header = self.header
	header.name:ClearAllPoints()
	header.status:ClearAllPoints()
	if not hasStatus then
		header.name:SetPoint("LEFT", header.avatar, "RIGHT", ns.S.MD, 0)
		header.status:Hide()
		return
	end
	local nameHeight = header.name:GetStringHeight() or 0
	local statusHeight = header.status:GetStringHeight() or 0
	local offset = (HEADER_LEADING + statusHeight - nameHeight) / 2
	-- Whole pixels: a half-pixel baseline is a blurred one.
	offset = math.floor(offset + 0.5)
	header.name:SetPoint("BOTTOMLEFT", header.avatar, "RIGHT", ns.S.MD, offset)
	header.status:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -HEADER_LEADING)
	header.status:Show()
end

function V:RefreshHeader()
	local conv = self.conv
	if not conv then return end
	local header = self.header

	header.avatar:SetConversation(conv)

	local nameColor = Theme.ClassColor(conv.class, "headerBg")
	local displayName = ns.ConversationManager.DisplayName(conv)
	header.name:SetText(displayName)
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

	-- The dot is the only thing on screen that says whether they are there, so
	-- it says so in words too rather than relying on the player knowing what
	-- green means.
	local presence = conv.isBN and nil or ns.PlayerInfo.PresenceLabel(conv.id)
	W.SetTooltip(header.avatar, displayName,
		presence and L[presence == "online" and "Online" or "Offline"] or nil)

	-- Truncate rather than overlap the action buttons.
	local available = (header:GetWidth() or 400)
		- (ns.S.LG + ns.SZ.AVATAR_MD + ns.S.MD)
		- (self.headerActionWidth or (ns.SZ.ICON_BTN * 3 + ns.S.MD))
	if available > 40 then
		header.name:SetWidth(0)
		if (header.name:GetStringWidth() or 0) > available then
			Text.Ellipsize(header.name, displayName, available)
		end
		-- The status line carries a level, a class, a guild and a zone now, so
		-- it overruns far more often than it used to; clipping it mid word left
		-- a sentence that looked broken rather than shortened.
		header.status:SetWordWrap(false)
		header.status:SetWidth(0)
		if status and status ~= "" and (header.status:GetStringWidth() or 0) > available then
			Text.Ellipsize(header.status, status, available)
		end
		header.status:SetWidth(math.max(20, available))
	end

	-- Last, once both strings are final: the block's position depends on how
	-- tall they actually turned out to be.
	self:LayoutHeaderText(status ~= nil and status ~= "")
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
