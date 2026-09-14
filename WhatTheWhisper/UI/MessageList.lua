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
local L = ns.L

local MessageList = {}
ns.MessageList = MessageList

local MSG_TS, MSG_DIR, MSG_KIND, MSG_STATUS =
	ns.MSG_TS, ns.MSG_DIR, ns.MSG_KIND, ns.MSG_STATUS

local max, min, floor, abs = math.max, math.min, math.floor, math.abs

-- The date pill's row: the label's own line plus padding above and below it.
local SEP_H = ns.T.MICRO + ns.S.MD
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

-- The time, and for an outgoing message the delivery mark after it, tucked into
-- the bottom right corner of the bubble.
--
-- This is the single detail that most decides whether a thread reads as a
-- messenger or as a chat log. The alternative -- a timestamp on a line above
-- each group, and a tick floating in the margin outside the bubble -- is what a
-- log looks like, and it is what this used to be.
--
-- The width is deliberately not a function of the delivery state. Every state
-- has a mark, so reserving the same room for all of them keeps the bubble from
-- resizing under the player when a message goes from sending to sent, and keeps
-- the measurement cache from needing to know about delivery at all.
local function metaText(msg)
	if not ns.db.profile.appearance.timestamps then return "" end
	return Format.Clock(msg[MSG_TS])
end

-- Both dimensions, measured rather than assumed. A font's point size is not the
-- height of a line set in it -- it is smaller, by an amount that varies with the
-- face -- and reserving the point size left the last line of a wrapped message
-- overlapping its own timestamp by exactly that difference.
local function metaSize(msg, text)
	local width, height = 0, 0
	if text ~= "" then
		local fs = Theme.Measure("MICRO")
		fs:SetWordWrap(false)
		fs:SetWidth(0)
		fs:SetText(text)
		width = fs:GetStringWidth() or 0
		height = fs:GetStringHeight() or Theme.FontSize("MICRO")
	end
	if msg[MSG_DIR] == ns.DIR_OUT and ns.db.profile.messages.deliveryStatus then
		if width > 0 then width = width + ns.SZ.BUBBLE_META_TIGHT end
		width = width + ns.SZ.STATUS_ICON_W
		height = max(height, ns.SZ.STATUS_ICON)
	end
	return width, height
end

local function measure(msg, maxContentW)
	local cached = metrics[msg]
	if cached and cached.maxW == maxContentW and cached.stamp == metricsStamp
		and cached.censored == (msg[ns.MSG_CENSORED] == true) then
		return cached
	end

	local raw = ns.ConversationManager.MessageText(msg)
	local processed = ns.URLs.Process(raw)
	processed = ns.Emoticons.Process(processed, Theme.FontSize("BODY"))

	local meta = metaText(msg)
	local metaW, metaH = metaSize(msg, meta)

	local fs = Theme.Measure("BODY")
	fs:SetWordWrap(true)
	if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
	fs:SetWidth(0)
	fs:SetText(processed)
	local natural = fs:GetStringWidth() or 0

	-- Two shapes, and which one a message gets is decided by whether the time
	-- still fits beside it.
	--
	-- Short message: the time sits on the same line, after the last word, and
	-- the bubble is wide enough for both. This is the shape almost every
	-- whisper takes, and it is the one worth getting right.
	--
	-- Long message: the text has already used the full width, so the time drops
	-- to its own line under it, right aligned. Which is exactly what a wrapped
	-- message does in WhatsApp, for the same reason.
	local inlineRoom = maxContentW - metaW - ns.SZ.BUBBLE_META_GAP
	local inline = metaW > 0 and natural <= inlineRoom
	local contentW, textH

	if inline then
		contentW = max(16, natural)
		fs:SetWidth(contentW + 1)
		textH = fs:GetStringHeight() or Theme.FontSize("BODY")
	else
		contentW = min(maxContentW, max(16, natural))
		fs:SetWidth(contentW + (natural <= contentW and 1 or 0))
		textH = fs:GetStringHeight() or Theme.FontSize("BODY")
	end

	local bubbleW, bubbleH
	if inline then
		bubbleW = contentW + ns.SZ.BUBBLE_META_GAP + metaW + ns.SZ.BUBBLE_PAD_X * 2
		bubbleH = textH + ns.SZ.BUBBLE_PAD_Y * 2
	else
		bubbleW = max(contentW, metaW) + ns.SZ.BUBBLE_PAD_X * 2
		bubbleH = textH + metaH + ns.SZ.BUBBLE_PAD_Y * 2
	end

	cached = {
		text = processed,
		maxW = maxContentW,
		stamp = metricsStamp,
		-- Part of the key: a message the player has just revealed is a different
		-- length from the placeholder that stood in for it.
		censored = msg[ns.MSG_CENSORED] == true,
		contentW = contentW,
		textH = textH,
		meta = meta,
		metaW = metaW,
		metaInline = inline,
		bubbleW = bubbleW,
		bubbleH = bubbleH,
	}
	metrics[msg] = cached
	return cached
end

--------------------------------------------------------------------------------
-- Element pools
--------------------------------------------------------------------------------

-- "Today", in a small translucent pill in the middle of the thread. Not a rule
-- across the whole width with a word sitting in a gap in it: that is a document
-- divider, and this is a date stamp.
local function createSeparator(list)
	local f = CreateFrame("Frame", nil, list.content)
	f:SetHeight(SEP_H)
	f.surface = W.Surface(f, { color = "bg3", radius = ns.R.PILL })
	f.label = W.Text(f, "MICRO", "textSecondary")
	f.label:ClearAllPoints()
	f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.label:SetJustifyH("CENTER")
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

	-- The time, inside the bubble, bottom right. Not a hover affordance and not
	-- a header above the group: it is simply part of the message, the way it is
	-- in every messenger the last fifteen years.
	f.stamp = W.Text(f, "MICRO", "textMuted")
	f.stamp:SetJustifyH("RIGHT")
	-- Bottom, not middle: it is anchored to the bubble's lower edge on purpose,
	-- and calling it centred would be describing a different layout.
	f.stamp:SetJustifyV("BOTTOM")
	f.stamp:Hide()

	f.status = f:CreateTexture(nil, "OVERLAY")
	f.status:SetSize(ns.SZ.STATUS_ICON_W, ns.SZ.STATUS_ICON)
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
	list.emptyIcon = W.Icon(list.empty, "chat", ns.SZ.EMPTY_ICON_SM, "textMuted")
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
		icon = "down", glyph = ns.SZ.ICON_GLYPH_SM, minWidth = 120,
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

	-- A bubble learns it was the last of its group from the one after it, so the
	-- previous entry is corrected here rather than guessed at. Until the next
	-- message arrives, the newest bubble is the end of its group -- which is
	-- true, and stops being true at the moment the correction is made.
	local previousBubble = self.lastBubbleEntry
	if previousBubble then
		previousBubble.groupEnd = newGroup or newDay
	end

	local m = measure(msg, maxContentW)
	local entry = {
		kind = "bubble", y = y, h = m.bubbleH, index = index,
		dir = msg[MSG_DIR], groupStart = newGroup, groupEnd = true,
	}
	layout[#layout + 1] = entry
	self.lastBubbleEntry = entry
	self.totalHeight = y + m.bubbleH
end

function ML:Rebuild(keepPosition)
	local previousOffset = self:GetOffset()
	local wasAtBottom = self:IsAtBottom(6)

	wipe(self.layout)
	self.totalHeight = 0
	self.lastBubbleEntry = nil
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
	local pools = { self.sepPool, self.bubblePool }
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
	-- Wider padding than tall: a pill whose horizontal padding equals its
	-- vertical one reads as a circle with a word crushed into it.
	local height = SEP_H - ns.S.SM
	local width = (f.label:GetStringWidth() or 40) + ns.S.MD * 2
	f:SetSize(width, height)
	self:PositionElement(f, entry)
	f.surface:SetRadius(height / 2)
	f.surface:ApplyTheme()
	f.surface:SetAlphaScale(0.7)
	f:Show()
	return f
end

-- Read receipts, in the shape everybody already knows: one mark on its way, two
-- when the server has echoed it back, and a clear failure when it has not. The
-- drawings are ours; the vocabulary is not, and should not be.
local STATUS_ICON = {
	[ns.SEND_PENDING] = { icon = "sent", role = "bubbleOutText", alpha = 0.45 },
	[ns.SEND_OK] = { icon = "delivered", role = "bubbleOutText", alpha = 0.75 },
	[ns.SEND_FAILED] = { icon = "failed", role = "danger", alpha = 1 },
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
	-- Both dimensions, not just the width. An unsized font string reports
	-- whatever the engine last gave it, and the meta row's whole job is to sit
	-- clear of the text -- which cannot be checked against a height nobody set.
	f.text:SetWidth(m.contentW + 1)
	f.text:SetHeight(m.textH)
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
		-- Grouping, the way every messenger draws it: the corners facing the
		-- group's spine are square in the middle of a run and round at its ends,
		-- so a stack of three bubbles reads as one block with a rounded top and
		-- a rounded bottom. The outer edge stays fully round throughout.
		--
		-- No tail. A drawn tail on every bubble is a cartoon speech balloon, and
		-- the corner tightening already says which side the message came from.
		local spineTop = not entry.groupStart
		local spineBottom = not entry.groupEnd
		if entry.dir == ns.DIR_OUT then
			f.surface:SetCorners(true, not spineTop, true, not spineBottom)
		else
			f.surface:SetCorners(not spineTop, true, not spineBottom, true)
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

	-- The meta row, inside the bubble at the bottom right: the time, and after it
	-- the delivery mark on an outgoing message. Laid out from the right edge
	-- inwards so the two are always in the same order and can never collide,
	-- whichever of them is present.
	--
	-- `measure` already reserved the room for both, which is why nothing here
	-- resizes anything: a message going from sending to sent changes the mark
	-- and not the shape around it.
	local status = msg[MSG_STATUS]
	local showStatus = entry.dir == ns.DIR_OUT and status
		and ns.db.profile.messages.deliveryStatus and STATUS_ICON[status] ~= nil

	-- The same inset from the bottom and the right in both bubble shapes. A mark
	-- that sits three pixels lower on wrapped messages than on short ones is the
	-- kind of thing nobody can name and everybody can see.
	local metaBottom = ns.SZ.BUBBLE_PAD_Y
	local rightEdge = -ns.SZ.BUBBLE_PAD_X

	if showStatus then
		local spec = STATUS_ICON[status]
		Draw.SetIcon(f.status, spec.icon)
		local c = Theme.Get(ap.bubbles and spec.role or "textMuted")
		f.status:SetVertexColor(c[1], c[2], c[3], spec.alpha)
		f.status:SetSize(ns.SZ.STATUS_ICON_W, ns.SZ.STATUS_ICON)
		f.status:ClearAllPoints()
		f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", rightEdge, metaBottom)
		f.status:Show()
		rightEdge = rightEdge - ns.SZ.STATUS_ICON_W - ns.SZ.BUBBLE_META_TIGHT
		if status == ns.SEND_FAILED then
			-- Two different failures, and the difference matters: one is worth
			-- retrying later, the other means the name is wrong.
			local who = ns.ConversationManager.DisplayName(conv)
			W.SetTooltip(f, L["Not delivered"], conv.notFound
				and L["There is no character named %s."]:format(who)
				or L["%s is not online"]:format(who))
		else
			W.SetTooltip(f, nil)
		end
	else
		f.status:Hide()
		W.SetTooltip(f, nil)
	end

	-- With times switched off there is no meta row to tuck anything into, so the
	-- hover timestamp earns its keep again: it is the only way left to find out
	-- when something was said. It hangs outside the bubble, on the outer side,
	-- because no room was reserved for it inside one.
	f.showStamp = m.meta == "" and ap.hoverTimestamp and ap.timestamps ~= true
	if f.showStamp then
		f.stamp:SetText(Format.Clock(msg[MSG_TS]))
		W.SetTextRole(f.stamp, "textMuted")
		f.stamp:ClearAllPoints()
		if entry.dir == ns.DIR_OUT then
			f.stamp:SetPoint("RIGHT", f, "LEFT", -ns.S.SM, 0)
		else
			f.stamp:SetPoint("LEFT", f, "RIGHT", ns.S.SM, 0)
		end
		f.stamp:SetAlpha(0)
		f.stamp:Hide()
	elseif m.meta ~= "" then
		f.stamp:SetText(m.meta)
		-- Quiet, but part of the bubble rather than floating outside it, so it
		-- takes the bubble's own text colour dimmed rather than the panel's
		-- muted grey -- which on the accent-coloured outgoing bubble would be
		-- close to unreadable.
		local role = ap.bubbles
			and (entry.dir == ns.DIR_OUT and "bubbleOutText" or "bubbleInText")
			or "textMuted"
		local c = Theme.Get(role)
		f.stamp:SetTextColor(c[1], c[2], c[3], 0.6)
		f.stamp.__wtwRole = role
		f.stamp:ClearAllPoints()
		f.stamp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", rightEdge, metaBottom)
		f.stamp:SetAlpha(1)
		f.stamp:Show()
	else
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
	self.bubblePool:ReleaseAll()

	for i = first, last do
		local entry = layout[i]
		if entry.kind == "sep" then
			self:RenderSeparator(entry)
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

	-- The bubble before this one may have just stopped being the end of its
	-- group, which changes two of its corners. It is very likely on screen.
	self.rangeFirst, self.rangeLast = nil, nil

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
	local links = ns.URLs.Extract(ns.ConversationManager.MessageText(msg))
	local entries = {}
	-- Offered only while there is still a line to ask the client about: not after
	-- a reload, and not once the line has aged out of the client's own store.
	if ns.ConversationManager.CanReveal(msg) then
		entries[#entries + 1] = { text = L["Show hidden message"], icon = "reveal",
			onClick = function()
				if ns.ConversationManager.RevealMessage(conv, msg) then
					ns.MessageList.InvalidateMetrics()
					ns.UI.RefreshAll()
				end
			end }
		entries[#entries + 1] = { separator = true }
	end
	local more = {
		{ text = L["Copy message"], icon = "copy", onClick = function()
			ns.Dialogs.ShowCopy(ns.Export.PlainMessage(msg), L["Copy message"])
		end },
		{ text = L["Copy conversation"], icon = "export", onClick = function()
			ns.Dialogs.ShowExport(conv)
		end },
	}
	for i = 1, #more do entries[#entries + 1] = more[i] end
	if links then
		entries[#entries + 1] = { separator = true }
		for i = 1, min(#links, 4) do
			local url = links[i]
			entries[#entries + 1] = {
				text = Text.Sub(url, 1, 34) .. (Text.Len(url) > 34 and "..." or ""),
				icon = "link",
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
