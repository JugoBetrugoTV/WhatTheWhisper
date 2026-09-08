-- WhatTheWhisper -- The message canvas.
--
-- This is a fully virtualised list: the layout array holds a height and a Y for
-- every element, and only the elements inside the viewport ever exist as frames.
-- Ten messages and ten thousand messages cost the same number of frames.
--
-- Layout elements, in the order they appear:
--   sep     a date separator
--   header  a group header (avatar + name + time, or just the time for your own)
--   bubble  one message
--
-- Grouping follows DESIGN.md §4.3: same sender, same kind, within GROUP_WINDOW.

local _, ns = ...
local Theme, W, Draw, Anim, Pool = ns.Theme, ns.Widgets, ns.Draw, ns.Anim, ns.Pool
local Text, Format = ns.Text, ns.Format
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local MessageList = {}
ns.MessageList = MessageList

local MSG_TS, MSG_DIR, MSG_TEXT, MSG_KIND, MSG_STATUS =
	ns.MSG_TS, ns.MSG_DIR, ns.MSG_TEXT, ns.MSG_KIND, ns.MSG_STATUS

local max, min, floor, abs = math.max, math.min, math.floor, math.abs

local SEP_H = 26
local HEADER_H = 18
local AVATAR = ns.SZ.AVATAR_SM
local AVATAR_GAP = ns.S.SM

-- Rendered text and measured geometry, keyed by the message table itself so it
-- is collected with the message.
local metrics = setmetatable({}, { __mode = "k" })
local metricsStamp = 0

function MessageList.InvalidateMetrics()
	metricsStamp = metricsStamp + 1
end

--------------------------------------------------------------------------------
-- Measurement
--------------------------------------------------------------------------------

local function measure(msg, maxContentW)
	local cached = metrics[msg]
	if cached and cached.maxW == maxContentW and cached.stamp == metricsStamp then
		return cached
	end

	local raw = msg[MSG_TEXT] or ""
	local processed = ns.URLs.Process(raw)
	processed = ns.Emoticons.Process(processed, Theme.FontSize("BODY"))

	local fs = Theme.Measure("BODY")
	fs:SetWordWrap(true)
	if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
	fs:SetWidth(0)
	fs:SetText(processed)
	local natural = fs:GetStringWidth() or 0

	local contentW, textH
	if natural <= maxContentW then
		contentW = max(16, natural)
		fs:SetWidth(contentW + 1)
		textH = fs:GetStringHeight() or Theme.FontSize("BODY")
	else
		contentW = maxContentW
		fs:SetWidth(contentW)
		textH = fs:GetStringHeight() or Theme.FontSize("BODY")
	end

	cached = {
		text = processed,
		maxW = maxContentW,
		stamp = metricsStamp,
		contentW = contentW,
		textH = textH,
		bubbleW = contentW + ns.SZ.BUBBLE_PAD_X * 2,
		bubbleH = textH + ns.SZ.BUBBLE_PAD_Y * 2,
	}
	metrics[msg] = cached
	return cached
end

--------------------------------------------------------------------------------
-- Element pools
--------------------------------------------------------------------------------

local function createSeparator(list)
	local f = CreateFrame("Frame", nil, list.content)
	f:SetHeight(SEP_H)
	f.surface = W.Surface(f, { color = "bg3", radius = ns.R.PILL })
	f.label = W.Text(f, "MICRO", "textMuted")
	f.label:ClearAllPoints()
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.label:SetJustifyH("CENTER")
	return f
end

-- The line that separates one group of messages from the next.
--
-- It carries a time and nothing else. A whisper thread has exactly two people
-- in it, the avatar beside every incoming bubble is already class coloured, and
-- the person's name is in the header above -- so repeating that name over every
-- group is the one thing that made this read as a chat log rather than as a
-- messenger. Every desktop messenger omits it in a one-to-one conversation for
-- the same reason.
local function createHeader(list)
	local f = CreateFrame("Frame", nil, list.content)
	f:SetHeight(HEADER_H)
	-- One font string, anchored to whichever side the group sits on, so incoming
	-- and outgoing are treated identically instead of one carrying a name and a
	-- time on the left and the other a bare time on the right.
	f.time = W.Text(f, "MICRO", "textMuted")
	f.time:SetPoint("LEFT", f, "LEFT", 0, 0)
	return f
end

local function createBubble(list)
	local f = CreateFrame("Frame", nil, list.content)
	f.surface = W.Surface(f, { color = "bubbleIn", radius = ns.R.LG })
	f.text = W.Text(f, "BODY", "bubbleInText")
	f.text:ClearAllPoints()
	f.text:SetPoint("TOPLEFT", f, "TOPLEFT", ns.SZ.BUBBLE_PAD_X, -ns.SZ.BUBBLE_PAD_Y)
	f.text:SetJustifyV("TOP")
	f.text:SetWordWrap(true)
	if f.text.SetNonSpaceWrap then f.text:SetNonSpaceWrap(true) end
	f.text:SetSpacing(ns.LINE_SPACING)

	f.avatar = ns.Avatar.New(f, AVATAR)
	f.avatar:SetPoint("TOPRIGHT", f, "TOPLEFT", -AVATAR_GAP, 0)
	f.avatar:Hide()

	f.stamp = W.Text(f, "MICRO", "textMuted")
	f.stamp:Hide()

	f.status = f:CreateTexture(nil, "OVERLAY")
	f.status:SetSize(ns.SZ.STATUS_ICON, ns.SZ.STATUS_ICON)
	f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", ns.S.XS, 1)
	f.status:Hide()

	f:EnableMouse(true)
	ns.Compat.SetHyperlinksEnabled(f, true)

	f:SetScript("OnHyperlinkClick", function(_, link, linkText, button)
		list:HandleLink(link, linkText, button)
	end)
	f:SetScript("OnHyperlinkEnter", function(self, link)
		list:HandleLinkEnter(self, link)
	end)
	f:SetScript("OnHyperlinkLeave", function()
		list:HandleLinkLeave()
	end)
	f:SetScript("OnEnter", function(self)
		if self.showStamp then
			self.stamp:Show()
			Anim.FadeIn(self.stamp, Theme.Duration("FAST"))
		end
	end)
	f:SetScript("OnLeave", function(self)
		if self.showStamp then Anim.FadeOut(self.stamp, Theme.Duration("FAST")) end
	end)
	f:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then list:OpenMessageMenu(self) end
	end)
	return f
end

local function resetElement(_, f)
	f:Hide()
	f:ClearAllPoints()
	if f.avatar then f.avatar:Hide() end
	if f.status then f.status:Hide() end
	if f.stamp then f.stamp:Hide() end
	-- Drop every reference: a pooled bubble holding the last pointer to a
	-- message would keep it alive after the thread was cleared.
	f.entry = nil
	f.msg = nil
	f.showStamp = nil
	f.__wtwTooltip = nil
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local ML = {}

function MessageList.New(parent)
	local list = ns.Scroll.New(parent, { barInset = ns.S.SM })
	for k, v in pairs(ML) do list[k] = v end

	list.content = list.viewport
	list.layout = {}
	list.totalHeight = 0
	list.pendingNew = 0

	list.sepPool = Pool.New(function() return createSeparator(list) end, resetElement, "list.separator")
	list.headerPool = Pool.New(function() return createHeader(list) end, resetElement, "list.header")
	list.bubblePool = Pool.New(function() return createBubble(list) end, resetElement, "list.bubble")
	list.visible = {}

	list.OnScrollChanged = function(self)
		self:UpdateVisible()
		if self:IsAtBottom(6) and self.pendingNew > 0 then
			self:ClearPending()
		end
	end

	-- Empty state
	list.empty = CreateFrame("Frame", nil, list.viewport)
	list.empty:SetPoint("TOPLEFT")
	list.empty:SetPoint("BOTTOMRIGHT")
	list.empty:Hide()
	list.emptyIcon = W.Icon(list.empty, "message", 40, "textMuted")
	list.emptyIcon:SetPoint("CENTER", list.empty, "CENTER", 0, 34)
	list.emptyIcon:SetAlpha(0.25)
	list.emptyTitle = W.Text(list.empty, "DISPLAY", "textSecondary")
	list.emptyTitle:SetPoint("TOP", list.emptyIcon, "BOTTOM", 0, -ns.S.LG)
	list.emptyTitle:SetJustifyH("CENTER")
	list.emptyTitle:SetWidth(320)
	list.emptyBody = W.Text(list.empty, "SMALL", "textMuted")
	list.emptyBody:SetPoint("TOP", list.emptyTitle, "BOTTOM", 0, -ns.S.SM)
	list.emptyBody:SetJustifyH("CENTER")
	list.emptyBody:SetWidth(320)

	-- "N new messages" pill
	list.pill = ns.Button.Text(list, {
		text = "", variant = "primary", height = 28, radius = ns.R.PILL,
		icon = "arrow_down", glyph = ns.SZ.ICON_GLYPH_SM, minWidth = 120,
		onClick = function() list:ScrollToBottom(true) list:ClearPending() end,
	})
	list.pill:SetPoint("BOTTOM", list, "BOTTOM", 0, ns.S.MD)
	list.pill:Hide()

	list:HookScript("OnSizeChanged", function()
		list:ScheduleRebuild()
	end)

	list:UpdateEmptyState()
	return list
end

--------------------------------------------------------------------------------
-- Layout construction
--------------------------------------------------------------------------------

function ML:MaxBubbleWidth()
	local width = (self.viewport:GetWidth() or 400)
	local available = width - ns.SZ.LIST_PAD_X * 2 - AVATAR - AVATAR_GAP - ns.SZ.SCROLLBAR_HIT
	local cap = min(available, ns.SZ.BUBBLE_MAX_ABS,
		width * (ns.SZ.BUBBLE_MAX_PCT or 0.66))
	return max(80, cap)
end

local function startsNewGroup(prev, msg)
	if not prev then return true end
	if not ns.db.profile.appearance.grouping then return true end
	if prev[MSG_DIR] ~= msg[MSG_DIR] then return true end
	if prev[MSG_KIND] ~= msg[MSG_KIND] then return true end
	if (msg[MSG_TS] or 0) - (prev[MSG_TS] or 0) > ns.GROUP_WINDOW then return true end
	return false
end

-- Appends the elements for message `index` to the layout array.
function ML:AppendEntries(index, maxContentW)
	local conv = self.conv
	local messages = conv.messages
	local msg = messages[index]
	if not msg then return end
	local prev = messages[index - 1]
	local layout = self.layout
	local ap = ns.db.profile.appearance

	local newGroup = startsNewGroup(prev, msg)
	local newDay = ap.dateSeparators and
		(not prev or not Format.IsSameDay(prev[MSG_TS] or 0, msg[MSG_TS] or 0))

	local y = self.totalHeight
	if #layout == 0 then
		y = ns.SZ.LIST_PAD_Y
	elseif newDay then
		y = y + Theme.MessageSpacing(ns.SZ.MSG_GAP_DATE)
	elseif newGroup then
		y = y + Theme.MessageSpacing(ns.SZ.MSG_GAP_GROUP)
	else
		y = y + ns.SZ.MSG_GAP_TIGHT
	end

	if newDay then
		layout[#layout + 1] = { kind = "sep", y = y, h = SEP_H, ts = msg[MSG_TS] }
		y = y + SEP_H + Theme.MessageSpacing(ns.S.MD)
	end

	if newGroup then
		layout[#layout + 1] = {
			kind = "header", y = y, h = HEADER_H, index = index,
			dir = msg[MSG_DIR], ts = msg[MSG_TS],
		}
		y = y + HEADER_H + 2
	end

	local m = measure(msg, maxContentW)
	layout[#layout + 1] = {
		kind = "bubble", y = y, h = m.bubbleH, index = index,
		dir = msg[MSG_DIR], groupStart = newGroup,
	}
	self.totalHeight = y + m.bubbleH
end

function ML:Rebuild(keepPosition)
	local previousOffset = self:GetOffset()
	local wasAtBottom = self:IsAtBottom(6)

	wipe(self.layout)
	self.totalHeight = 0
	self.rangeFirst, self.rangeLast = nil, nil

	local conv = self.conv
	if conv then
		local maxContentW = self:MaxBubbleWidth() - ns.SZ.BUBBLE_PAD_X * 2
		self.maxContentW = maxContentW
		local messages = conv.messages
		for i = 1, #messages do
			self:AppendEntries(i, maxContentW)
		end
	end

	self:SetContentHeight(self.totalHeight + ns.SZ.LIST_PAD_Y, false)
	self:UpdateEmptyState()

	if wasAtBottom or not keepPosition then
		self:ScrollToBottom(false)
	else
		self:SetOffset(previousOffset, false)
	end
	self:UpdateVisible()
end

function ML:ScheduleRebuild()
	if self.rebuildScheduled then return end
	self.rebuildScheduled = true
	Anim.After(0.02, function()
		self.rebuildScheduled = false
		if not self:IsVisible() then return end
		local width = self.viewport:GetWidth() or 0
		if abs(width - (self.lastWidth or 0)) < 0.5 and not self.forceRebuild then
			self:UpdateVisible()
			return
		end
		self.lastWidth = width
		self.forceRebuild = false
		self:Rebuild(true)
	end)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- Scroll offset with the short-conversation push-down folded in.
function ML:ContentShift()
	return self:GetOffset() - (self.pushDown or 0)
end

-- Anchoring is identical for all three element kinds, which is what lets a
-- scroll that does not change the visible range skip re-rendering entirely and
-- just move what is already there.
function ML:PositionElement(f, entry)
	local shift = self:ContentShift()
	local pad = ns.SZ.LIST_PAD_X
	f:ClearAllPoints()
	if entry.kind == "sep" then
		f:SetPoint("TOP", self.content, "TOP",
			-ns.SZ.SCROLLBAR_HIT / 2, -(entry.y - shift))
	elseif entry.dir == ns.DIR_OUT then
		f:SetPoint("TOPRIGHT", self.content, "TOPRIGHT",
			-(pad + ns.SZ.SCROLLBAR_HIT), -(entry.y - shift))
	else
		f:SetPoint("TOPLEFT", self.content, "TOPLEFT",
			pad + AVATAR + AVATAR_GAP, -(entry.y - shift))
	end
end

function ML:RepositionVisible()
	local pools = { self.sepPool, self.headerPool, self.bubblePool }
	for i = 1, #pools do
		for f in pools[i]:EnumerateActive() do
			if f.entry then self:PositionElement(f, f.entry) end
		end
	end
end

local function bubbleColors(dir)
	if dir == ns.DIR_OUT then
		return "bubbleOut", "bubbleOutText"
	end
	return "bubbleIn", "bubbleInText"
end

function ML:RenderSeparator(entry)
	local f = self.sepPool:Acquire()
	f.entry = entry
	f.label:SetText(Format.DayLabel(entry.ts))
	local width = (f.label:GetStringWidth() or 40) + ns.S.MD * 2
	f:SetSize(width, SEP_H - 6)
	self:PositionElement(f, entry)
	f.surface:SetRadius((SEP_H - 6) / 2)
	f.surface:ApplyTheme()
	f.surface:SetAlphaScale(0.55)
	f:Show()
	return f
end

function ML:RenderHeader(entry)
	local f = self.headerPool:Acquire()
	f.entry = entry
	self:PositionElement(f, entry)

	local outgoing = entry.dir == ns.DIR_OUT
	f.time:SetText(ns.db.profile.appearance.timestamps and Format.Clock(entry.ts) or "")
	f.time:ClearAllPoints()
	if outgoing then
		f.time:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		f.time:SetJustifyH("RIGHT")
	else
		f.time:SetPoint("LEFT", f, "LEFT", 0, 0)
		f.time:SetJustifyH("LEFT")
	end
	f:SetWidth(120)
	f:SetHeight(HEADER_H)
	f:Show()
	return f
end

local STATUS_ICON = {
	[ns.SEND_PENDING] = { icon = "dot", role = "textMuted", alpha = 0.5 },
	[ns.SEND_OK] = { icon = "check", role = "textMuted", alpha = 0.9 },
	[ns.SEND_FAILED] = { icon = "x_circle", role = "danger", alpha = 1 },
}

function ML:RenderBubble(entry)
	local conv = self.conv
	local msg = conv.messages[entry.index]
	if not msg then return nil end
	local f = self.bubblePool:Acquire()
	f.entry = entry
	f.msg = msg

	local m = measure(msg, self.maxContentW)
	local fillRole, textRole = bubbleColors(entry.dir)
	local ap = ns.db.profile.appearance

	f:SetSize(m.bubbleW, m.bubbleH)
	f.text:SetWidth(m.contentW + 1)
	f.text:SetText(m.text)
	f.text:SetFontObject(Theme.Font("BODY"))
	f.text:SetSpacing(ns.LINE_SPACING)

	if ap.bubbles then
		f.surface:SetColorRole(fillRole)
		if self.flashIndex == entry.index then
			-- Search jump highlight: blend the bubble towards the accent so the
			-- match is obvious without moving anything.
			local blended = ns.Color.Mix(Theme.Get(fillRole), Theme.Get("accent"), 0.45)
			f.surface:SetColorOverride(blended[1], blended[2], blended[3], blended[4])
		else
			f.surface:SetColorOverride(nil)
		end
		f.surface:SetRadius(Theme.BubbleRadius())
		-- The corner facing the group's spine is tightened into a tail.
		if entry.dir == ns.DIR_OUT then
			f.surface:SetCorners(true, not entry.groupStart, true, true)
		else
			f.surface:SetCorners(not entry.groupStart, true, true, true)
		end
		f.surface:SetShown(true)
	else
		f.surface:SetShown(false)
	end
	W.SetTextRole(f.text, ap.bubbles and textRole or "textPrimary")

	self:PositionElement(f, entry)

	-- Avatar only on the first bubble of an incoming group.
	if entry.groupStart and entry.dir == ns.DIR_IN and ap.avatars then
		f.avatar:SetAvatarSize(AVATAR)
		f.avatar:SetSurfaceRole("bg2")
		f.avatar:SetConversation(conv)
		f.avatar:Show()
	else
		f.avatar:Hide()
	end

	-- The meta row (delivery state and the hover timestamp) always sits on the
	-- outer side of the bubble, bottom aligned, so the two can never collide and
	-- neither can push into the scrollbar gutter.
	local status = msg[MSG_STATUS]
	local hasStatus = false
	if entry.dir == ns.DIR_OUT and status and ns.db.profile.messages.deliveryStatus then
		local spec = STATUS_ICON[status]
		if spec then
			hasStatus = true
			Draw.SetIcon(f.status, spec.icon)
			local c = Theme.Get(spec.role)
			f.status:SetVertexColor(c[1], c[2], c[3], spec.alpha)
			local size = (status == ns.SEND_PENDING) and 6 or ns.SZ.STATUS_ICON
			f.status:SetSize(size, size)
			f.status:ClearAllPoints()
			f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -ns.S.SM, 2)
			f.status:Show()
			if status == ns.SEND_FAILED then
				-- Two different failures, and the difference matters: one is
				-- worth retrying later, the other means the name is wrong.
				local who = ns.ConversationManager.DisplayName(conv)
				W.SetTooltip(f, L["Not delivered"], conv.notFound
					and L["There is no character named %s."]:format(who)
					or L["%s is not online"]:format(who))
			else
				W.SetTooltip(f, nil)
			end
		end
	end
	if not hasStatus then
		f.status:Hide()
		W.SetTooltip(f, nil)
	end

	f.showStamp = ap.hoverTimestamp and ap.timestamps and not entry.groupStart
	if f.showStamp then
		f.stamp:SetText(Format.Clock(msg[MSG_TS]))
		f.stamp:ClearAllPoints()
		if entry.dir == ns.DIR_OUT then
			if hasStatus then
				f.stamp:SetPoint("RIGHT", f.status, "LEFT", -ns.S.XS, 0)
			else
				f.stamp:SetPoint("RIGHT", f, "LEFT", -ns.S.SM, 0)
			end
		else
			f.stamp:SetPoint("LEFT", f, "RIGHT", ns.S.SM, 0)
		end
		f.stamp:SetAlpha(0)
		f.stamp:Hide()
	end

	f:Show()
	return f
end

-- Binary search for the first element whose bottom is below the viewport top.
local function firstVisible(layout, top)
	local lo, hi, result = 1, #layout, #layout + 1
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local entry = layout[mid]
		if entry.y + entry.h >= top then
			result = mid
			hi = mid - 1
		else
			lo = mid + 1
		end
	end
	return result
end

function ML:UpdateVisible()
	local layout = self.layout
	if not self.conv or #layout == 0 then
		self.sepPool:ReleaseAll()
		self.headerPool:ReleaseAll()
		self.bubblePool:ReleaseAll()
		self.pushDown = 0
		self.rangeFirst, self.rangeLast = nil, nil
		return
	end

	local offset = self:GetOffset()
	local viewHeight = self:GetViewHeight()
	local previousPush = self.pushDown

	-- A conversation shorter than the canvas is pushed down so it rests on the
	-- composer. Text starting at the top of an empty canvas is the single most
	-- obvious "this is a list widget, not a chat" tell.
	self.pushDown = max(0, viewHeight - (self.totalHeight + ns.SZ.LIST_PAD_Y))
	if previousPush ~= self.pushDown then self.rangeFirst = nil end
	local top, bottom = offset - self.pushDown, offset + viewHeight - self.pushDown

	local first = firstVisible(layout, top)
	local last = first - 1
	while last + 1 <= #layout and layout[last + 1].y <= bottom do
		last = last + 1
	end

	-- Scrolling within the same set of elements only needs new anchors; the
	-- text, colours and measurements are already correct.
	if first == self.rangeFirst and last == self.rangeLast then
		self:RepositionVisible()
		return
	end
	self.rangeFirst, self.rangeLast = first, last

	self.sepPool:ReleaseAll()
	self.headerPool:ReleaseAll()
	self.bubblePool:ReleaseAll()

	for i = first, last do
		local entry = layout[i]
		if entry.kind == "sep" then
			self:RenderSeparator(entry)
		elseif entry.kind == "header" then
			self:RenderHeader(entry)
		else
			self:RenderBubble(entry)
		end
	end
end

--------------------------------------------------------------------------------
-- Conversation binding
--------------------------------------------------------------------------------

function ML:SetConversation(conv)
	if self.conv == conv then
		self:UpdateEmptyState()
		return
	end
	self.conv = conv
	self.pendingNew = 0
	self.pill:Hide()
	self.lastWidth = self.viewport:GetWidth()
	self:Rebuild(false)
	self:ScrollToBottom(false)
end

function ML:UpdateEmptyState()
	local conv = self.conv
	local hasMessages = conv and #conv.messages > 0
	self.empty:SetShown(not hasMessages)
	if hasMessages then return end
	if not conv then
		self.emptyTitle:SetText(L["Pick a conversation"])
		self.emptyBody:SetText(L["Your whispers are kept here, one thread per player."])
	elseif ns.db.profile.history.retention == "off" then
		self.emptyTitle:SetText(L["History is off"])
		self.emptyBody:SetText(L["Enable it in Settings > History to keep messages."])
	else
		self.emptyTitle:SetText(L["Start the conversation"])
		self.emptyBody:SetText(L["Say hi to %s."]:format(
			ns.ConversationManager.DisplayName(conv)))
	end
end

-- Incremental append: one message costs one layout entry, not a full rebuild.
function ML:OnMessageAdded(conv, _, index)
	if conv ~= self.conv then return end
	local atBottom = self:IsAtBottom(8)
	self:AppendEntries(index, self.maxContentW or (self:MaxBubbleWidth() - ns.SZ.BUBBLE_PAD_X * 2))
	self:SetContentHeight(self.totalHeight + ns.SZ.LIST_PAD_Y, false)
	self:UpdateEmptyState()

	if atBottom then
		self:ScrollToBottom(Theme.AnimationsEnabled())
		self:ClearPending()
	else
		self.pendingNew = self.pendingNew + 1
		self:UpdatePill()
	end
	self.rangeFirst, self.rangeLast = nil, nil
	self:UpdateVisible()
end

function ML:OnMessageUpdated(conv, msg)
	if conv ~= self.conv then return end
	for f in self.bubblePool:EnumerateActive() do
		if f.msg == msg then
			self:RenderBubbleInPlace(f)
			return
		end
	end
end

function ML:RenderBubbleInPlace(f)
	local entry = f.entry
	if not entry then return end
	self.bubblePool:Release(f)
	self:RenderBubble(entry)
	-- The active set changed identity, so a later scroll must not take the
	-- reposition-only path against a stale range.
	self.rangeFirst, self.rangeLast = nil, nil
end

--------------------------------------------------------------------------------
-- New message pill
--------------------------------------------------------------------------------

function ML:UpdatePill()
	if self.pendingNew <= 0 then
		self.pill:Hide()
		return
	end
	local label = self.pendingNew == 1 and L["1 new message"]
		or L["%d new messages"]:format(self.pendingNew)
	self.pill:SetText(label)
	if not self.pill:IsShown() then
		Anim.SlideIn(self.pill, 0, -8, Theme.Duration("SLOW"))
	end
end

function ML:ClearPending()
	if self.pendingNew == 0 then return end
	self.pendingNew = 0
	Anim.FadeOut(self.pill, Theme.Duration("FAST"))
end

--------------------------------------------------------------------------------
-- Jumping to a message (used by in-conversation search)
--------------------------------------------------------------------------------

function ML:FindEntryForMessage(index)
	local layout = self.layout
	for i = 1, #layout do
		local entry = layout[i]
		if entry.kind == "bubble" and entry.index == index then return entry end
	end
	return nil
end

function ML:ScrollToMessage(index, flash)
	local entry = self:FindEntryForMessage(index)
	if not entry then return false end
	local target = entry.y - (self:GetViewHeight() - entry.h) / 2
	self:SetOffset(target, Theme.AnimationsEnabled())
	if flash then
		self.flashIndex = index
		self:UpdateVisible()
		self.flashToken = (self.flashToken or 0) + 1
		local token = self.flashToken
		Anim.After(1.4, function()
			if token ~= self.flashToken then return end
			self.flashIndex = nil
			self:UpdateVisible()
		end)
	end
	return true
end

--------------------------------------------------------------------------------
-- Links and message menu
--------------------------------------------------------------------------------

function ML:HandleLink(link, linkText, button)
	if ns.URLs.IsOurLink(link) then
		local url = ns.URLs.URLFromLink(link)
		if button == "RightButton" then
			ns.Menu.Open({
				{ text = L["Copy URL"], icon = "copy",
					onClick = function() ns.Dialogs.ShowCopy(url, L["Copy URL"]) end },
			})
		else
			ns.Dialogs.ShowCopy(url, L["Copy URL"], L["Press Ctrl+C to copy, then Esc to close."])
		end
		return
	end
	-- Real game links keep Blizzard's behaviour, which is the correct one here.
	ns.Compat.ShowGameLink(link, linkText, button)
end

function ML:HandleLinkEnter(owner, link)
	if ns.URLs.IsOurLink(link) then
		ns.Tooltip.Show(owner, {
			text = ns.URLs.URLFromLink(link),
			subtext = L["Press Ctrl+C to copy, then Esc to close."],
		})
		return
	end
	local tooltip = _G.GameTooltip
	if tooltip then
		tooltip:SetOwner(owner, "ANCHOR_CURSOR")
		if ns.Compat.SetTooltipHyperlink(tooltip, link) then
			tooltip:Show()
		else
			tooltip:Hide()
		end
	end
end

function ML:HandleLinkLeave()
	ns.Tooltip.Hide()
	if _G.GameTooltip then _G.GameTooltip:Hide() end
end

function ML:OpenMessageMenu(bubble)
	local msg = bubble.msg
	local conv = self.conv
	if not msg or not conv then return end
	local links = ns.URLs.Extract(msg[MSG_TEXT])
	local entries = {
		{ text = L["Copy message"], icon = "copy", onClick = function()
			ns.Dialogs.ShowCopy(ns.Export.PlainMessage(msg), L["Copy message"])
		end },
		{ text = L["Copy conversation"], icon = "export", onClick = function()
			ns.Dialogs.ShowExport(conv)
		end },
	}
	if links then
		entries[#entries + 1] = { separator = true }
		for i = 1, min(#links, 4) do
			local url = links[i]
			entries[#entries + 1] = {
				text = Text.Sub(url, 1, 34) .. (Text.Len(url) > 34 and "..." or ""),
				icon = "globe",
				onClick = function() ns.Dialogs.ShowCopy(url, L["Copy URL"]) end,
			}
		end
	end
	ns.Menu.Open(entries)
end

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

function ML:ApplyTheme()
	self.thumbSurface:ApplyTheme()
	W.RefreshIcon(self.emptyIcon)
	W.RefreshText(self.emptyTitle)
	W.RefreshText(self.emptyBody)
	self.pill:ApplyTheme()

	local function refresh(pool, fn)
		for element in pool:EnumerateActive() do fn(element) end
		for _, element in ipairs(pool.free) do fn(element) end
	end
	refresh(self.sepPool, function(f)
		f.surface:ApplyTheme()
		W.RefreshText(f.label)
	end)
	refresh(self.headerPool, function(f)
		W.RefreshText(f.time)
	end)
	refresh(self.bubblePool, function(f)
		f.surface:ApplyTheme()
		W.RefreshText(f.text)
		W.RefreshText(f.stamp)
		f.avatar:ApplyTheme()
	end)

	MessageList.InvalidateMetrics()
	self.forceRebuild = true
	self:ScheduleRebuild()
end
