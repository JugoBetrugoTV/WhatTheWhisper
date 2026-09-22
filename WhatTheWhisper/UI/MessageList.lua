-- WhatTheWhisper -- The message canvas.
--
-- This is a fully virtualised list: the layout array holds a height and a Y for
-- every element, and only the elements inside the viewport ever exist as frames.
-- Ten messages and ten thousand messages cost the same number of frames.
--
-- Layout elements, in the order they appear:
--   sep      a centred time marker, speaking for everything under it
--   bubble   one message
--   receipt  the delivery state of the newest message you sent
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

local max, min, floor, ceil, abs = math.max, math.min, math.floor, math.ceil, math.abs

local AVATAR = ns.SZ.AVATAR_SM
local AVATAR_GAP = ns.S.SM

-- The delivery states worth a line of their own, in the words Messages uses for
-- them. The mark before the word is ours: one check on its way, two when the
-- server has echoed it back, and a clear failure when it has not.
local RECEIPT = {
	[ns.SEND_PENDING] = { icon = "sent", label = "Sending", role = "textMuted", alpha = 0.75 },
	[ns.SEND_OK] = { icon = "delivered", label = "Delivered", role = "textMuted", alpha = 1 },
	[ns.SEND_FAILED] = { icon = "failed", label = "Not delivered", role = "danger", alpha = 1 },
}

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

-- One line set in the micro face, measured rather than assumed. A font's point
-- size is not the height of a line set in it -- it is smaller, by an amount that
-- varies with the face -- and both of the one-line elements in the thread, the
-- time marker and the receipt, are laid out from this number before either of
-- them exists as a frame.
local microLine, microLineStamp = 0, -1
local function microLineHeight()
	if microLineStamp ~= metricsStamp then
		local fs = Theme.Measure("MICRO")
		fs:SetWordWrap(false)
		fs:SetWidth(0)
		fs:SetText("Ag")
		microLine = fs:GetStringHeight() or Theme.FontSize("MICRO")
		microLineStamp = metricsStamp
	end
	return microLine
end

-- A centred time marker is its own line and nothing else: no pill, no rule, no
-- box. A pill around a date is a chip, and a chip is a thing you can press.
local function separatorHeight()
	return ceil(microLineHeight())
end

-- The receipt sets a word beside a mark, so it is as tall as the taller of them.
local function receiptHeight()
	return max(ceil(microLineHeight()), ns.SZ.STATUS_ICON)
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

	local fs = Theme.Measure("BODY")
	fs:SetWordWrap(true)
	if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
	fs:SetWidth(0)
	fs:SetText(processed)
	local natural = fs:GetStringWidth() or 0

	-- One shape. A bubble is its text and the padding around it, and nothing
	-- else is tucked inside it -- which is the whole of the change from a
	-- WhatsApp thread to a Messages one. The time moved to a marker above the
	-- group, the delivery state to a line under the newest message, and what is
	-- left is the sentence somebody wrote.
	local contentW = min(maxContentW, max(16, natural))
	-- The extra pixel is for the exact-fit case: a font string set to precisely
	-- its own measured width will occasionally wrap its last word.
	fs:SetWidth(contentW + (natural <= contentW and 1 or 0))
	local textH = fs:GetStringHeight() or Theme.FontSize("BODY")

	cached = {
		text = processed,
		maxW = maxContentW,
		stamp = metricsStamp,
		-- Part of the key: a message the player has just revealed is a different
		-- length from the placeholder that stood in for it.
		censored = msg[ns.MSG_CENSORED] == true,
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

-- "Today 9:41", centred, in the middle of the thread with air above and below
-- it and nothing drawn around it.
--
-- Not a pill and not a rule with a word in a gap in it. A pill is a chip and a
-- chip is something you can press; a rule is a document divider. This is a line
-- of small grey text that says when the conversation picked up again, which is
-- what it is and all it is.
--
-- Two strings rather than one. Messages sets the day in semibold and the time
-- in regular beside it, and the game ships no semibold face for most of the
-- fonts a player can pick -- so the day carries the brighter of the two quiet
-- greys and the time carries the quieter one. Same read, available typography.
local function createSeparator(list)
	local f = CreateFrame("Frame", nil, list.content)
	f.day = W.Text(f, "MICRO", "textSecondary")
	f.day:ClearAllPoints()
	f.day:SetJustifyH("LEFT")
	f.day:SetWordWrap(false)
	f.clock = W.Text(f, "MICRO", "textMuted")
	f.clock:ClearAllPoints()
	f.clock:SetJustifyH("LEFT")
	f.clock:SetWordWrap(false)
	return f
end

-- "Delivered", under the newest message you sent, right aligned to its edge.
local function createReceipt(list)
	local f = CreateFrame("Frame", nil, list.content)
	f.mark = f:CreateTexture(nil, "ARTWORK")
	f.mark:SetSize(ns.SZ.STATUS_ICON, ns.SZ.STATUS_ICON)
	f.mark:SetPoint("LEFT", f, "LEFT", 0, 0)
	f.label = W.Text(f, "MICRO", "textMuted")
	f.label:ClearAllPoints()
	f.label:SetPoint("LEFT", f.mark, "RIGHT", ns.SZ.RECEIPT_ICON_GAP, 0)
	f.label:SetJustifyH("LEFT")
	f.label:SetWordWrap(false)
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

	-- The time a single message was said, on hover, outside the bubble. With the
	-- markers switched off it is the only way left to find out, and it is what
	-- the drag-left gesture shows in Messages.
	f.stamp = W.Text(f, "MICRO", "textMuted")
	f.stamp:SetJustifyH("RIGHT")
	f.stamp:SetWordWrap(false)
	f.stamp:Hide()

	-- The mark beside a message that did not go. Outside the bubble: nothing is
	-- tucked inside one any more.
	f.status = f:CreateTexture(nil, "OVERLAY")
	f.status:SetSize(ns.SZ.STATUS_ICON, ns.SZ.STATUS_ICON)
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
	if f.mark then f.mark:Hide() end
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
	list.receiptPool = Pool.New(function() return createReceipt(list) end, resetElement, "list.receipt")
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
	if not ns.Setting("appearance.grouping") then return true end
	if prev[MSG_DIR] ~= msg[MSG_DIR] then return true end
	if prev[MSG_KIND] ~= msg[MSG_KIND] then return true end
	if (msg[MSG_TS] or 0) - (prev[MSG_TS] or 0) > ns.GROUP_WINDOW then return true end
	return false
end

-- What a time marker above `msg` would be able to say, given the two timestamp
-- settings. Both of them mean exactly what their labels say and neither is a
-- proxy for the other: "show timestamps" puts a clock in the thread, "show date
-- separators" puts a day in it, and a marker is only worth a line when at least
-- one of them has something to contribute.
local function stampParts(prev, msg)
	local ap = ns.Setting("appearance")
	local newDay = not prev or not Format.IsSameDay(prev[MSG_TS] or 0, msg[MSG_TS] or 0)
	-- Long enough since the last message that the conversation reads as having
	-- been picked up again rather than continued.
	local resumed = newDay or
		((msg[MSG_TS] or 0) - (prev[MSG_TS] or 0)) > ns.STAMP_WINDOW
	local wantsDay = newDay and ap.dateSeparators == true
	local wantsClock = resumed and ap.timestamps == true
	return newDay, (wantsDay or wantsClock), wantsDay, wantsClock
end

-- Appends the elements for message `index` to the layout array.
function ML:AppendEntries(index, maxContentW)
	local conv = self.conv
	local messages = conv.messages
	local msg = messages[index]
	if not msg then return end
	local prev = messages[index - 1]
	local layout = self.layout

	-- The receipt always trails the thread, so it is lifted off the end before
	-- anything is appended under it and put back afterwards. Appending a message
	-- underneath it and leaving it where it was would have it describing a
	-- message it is no longer beside.
	self:DropReceipt()

	local newGroup = startsNewGroup(prev, msg)
	local newDay, wantsSep, wantsDay, wantsClock = stampParts(prev, msg)

	local y = self.totalHeight
	if #layout == 0 then
		y = ns.SZ.LIST_PAD_Y
	elseif wantsSep then
		y = y + Theme.MessageSpacing(ns.SZ.MSG_GAP_DATE)
	elseif newGroup then
		y = y + Theme.MessageSpacing(ns.SZ.MSG_GAP_GROUP)
	else
		y = y + ns.SZ.MSG_GAP_TIGHT
	end

	if wantsSep then
		local h = separatorHeight()
		layout[#layout + 1] = {
			kind = "sep", y = y, h = h, ts = msg[MSG_TS],
			withDay = wantsDay, withClock = wantsClock,
		}
		y = y + h + Theme.MessageSpacing(ns.S.MD)
	end

	-- A bubble learns it was the last of its group from the one after it, so the
	-- previous entry is corrected here rather than guessed at. Until the next
	-- message arrives, the newest bubble is the end of its group -- which is
	-- true, and stops being true at the moment the correction is made.
	local previousBubble = self.lastBubbleEntry
	if previousBubble then
		previousBubble.groupEnd = newGroup or wantsSep or newDay
	end

	local m = measure(msg, maxContentW)
	local entry = {
		kind = "bubble", y = y, h = m.bubbleH, index = index,
		dir = msg[MSG_DIR], groupStart = newGroup, groupEnd = true,
	}
	layout[#layout + 1] = entry
	self.lastBubbleEntry = entry
	self.totalHeight = y + m.bubbleH

	self:AppendReceipt()
end

--------------------------------------------------------------------------------
-- The receipt
--------------------------------------------------------------------------------

-- Messages names the delivery state once, under the newest message you sent,
-- rather than marking every bubble. That reads better, and it is also the more
-- honest of the two: anything further back was either answered -- which is proof
-- it arrived -- or is still the last thing anybody said, in which case it is the
-- one this line is about.
--
-- A message that actually failed keeps its own mark for as long as it is in the
-- thread; see RenderBubble. This line is about the newest one only.
function ML:DropReceipt()
	local layout = self.layout
	if layout[#layout] and layout[#layout].kind == "receipt" then
		layout[#layout] = nil
		self.totalHeight = self.heightBeforeReceipt or self.totalHeight
	end
	self.receiptEntry = nil
end

function ML:AppendReceipt()
	self.heightBeforeReceipt = self.totalHeight
	self.receiptEntry = nil
	if not ns.Setting("messages.deliveryStatus") then return end

	local entry = self.lastBubbleEntry
	if not entry or entry.dir ~= ns.DIR_OUT then return end
	local conv = self.conv
	local msg = conv and conv.messages[entry.index]
	local status = msg and msg[MSG_STATUS]
	if not status or not RECEIPT[status] then return end

	local y = self.totalHeight + ns.SZ.RECEIPT_GAP
	local h = receiptHeight()
	local receipt = {
		kind = "receipt", y = y, h = h, index = entry.index,
		dir = ns.DIR_OUT, status = status,
	}
	self.layout[#self.layout + 1] = receipt
	self.receiptEntry = receipt
	self.totalHeight = y + h
end

function ML:Rebuild(keepPosition)
	local previousOffset = self:GetOffset()
	local wasAtBottom = self:IsAtBottom(6)

	wipe(self.layout)
	self.totalHeight = 0
	self.lastBubbleEntry = nil
	self.receiptEntry = nil
	self.heightBeforeReceipt = nil
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
-- just move what is already there. The receipt carries the outgoing direction
-- so that it lands on the same right edge as the bubble it speaks for.
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
	local pools = { self.sepPool, self.bubblePool, self.receiptPool }
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

-- The day and the time are read at render time, not stored on the entry: a
-- thread left open across midnight would otherwise still be saying "Today"
-- about yesterday.
function ML:RenderSeparator(entry)
	local f = self.sepPool:Acquire()
	f.entry = entry
	local day = entry.withDay and Format.DayLabel(entry.ts) or ""
	local clock = entry.withClock and Format.Clock(entry.ts) or ""

	f.day:SetFontObject(Theme.Font("MICRO"))
	f.clock:SetFontObject(Theme.Font("MICRO"))
	f.day:SetText(day)
	f.clock:SetText(clock)
	local dayW = day ~= "" and (f.day:GetStringWidth() or 0) or 0
	local clockW = clock ~= "" and (f.clock:GetStringWidth() or 0) or 0
	local gap = (dayW > 0 and clockW > 0) and ns.SZ.SEP_WORD_GAP or 0

	f.day:ClearAllPoints()
	f.clock:ClearAllPoints()
	f.day:SetPoint("LEFT", f, "LEFT", 0, 0)
	if dayW > 0 then
		f.clock:SetPoint("LEFT", f.day, "RIGHT", gap, 0)
	else
		f.clock:SetPoint("LEFT", f, "LEFT", 0, 0)
	end
	f.day:SetShown(dayW > 0)
	f.clock:SetShown(clockW > 0)

	f:SetSize(max(16, dayW + gap + clockW), entry.h)
	self:PositionElement(f, entry)
	f:Show()
	return f
end

function ML:RenderReceipt(entry)
	local spec = RECEIPT[entry.status]
	if not spec then return nil end
	local f = self.receiptPool:Acquire()
	f.entry = entry

	Draw.SetIcon(f.mark, spec.icon)
	f.mark:SetSize(ns.SZ.STATUS_ICON, ns.SZ.STATUS_ICON)
	local c = Theme.Get(spec.role)
	f.mark:SetVertexColor(c[1], c[2], c[3], spec.alpha)
	f.mark:Show()

	f.label:SetFontObject(Theme.Font("MICRO"))
	f.label:SetText(L[spec.label])
	W.SetTextRole(f.label, spec.role)
	f.label:SetAlpha(spec.alpha)

	f:SetSize(ns.SZ.STATUS_ICON + ns.SZ.RECEIPT_ICON_GAP
		+ (f.label:GetStringWidth() or 40), entry.h)
	self:PositionElement(f, entry)
	f:Show()
	return f
end

function ML:RenderBubble(entry)
	local conv = self.conv
	local msg = conv.messages[entry.index]
	if not msg then return nil end
	local f = self.bubblePool:Acquire()
	f.entry = entry
	f.msg = msg

	local m = measure(msg, self.maxContentW)
	local fillRole, textRole = bubbleColors(entry.dir)
	local ap = ns.Setting("appearance")

	f:SetSize(m.bubbleW, m.bubbleH)
	-- Both dimensions, not just the width. An unsized font string reports
	-- whatever the engine last gave it, which makes every measurement taken
	-- against it a measurement of the previous message.
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

	-- A message that did not go keeps a mark of its own for as long as it is in
	-- the thread, outside the bubble on the inner side. The receipt under the
	-- newest message only ever speaks for that one, so without this a failure
	-- four messages back would be silent.
	local status = msg[MSG_STATUS]
	local failed = entry.dir == ns.DIR_OUT and status == ns.SEND_FAILED
		and ns.Setting("messages.deliveryStatus") == true
	if failed then
		Draw.SetIcon(f.status, "failed")
		local c = Theme.Get("danger")
		f.status:SetVertexColor(c[1], c[2], c[3], 1)
		f.status:SetSize(ns.SZ.STATUS_ICON, ns.SZ.STATUS_ICON)
		f.status:ClearAllPoints()
		f.status:SetPoint("RIGHT", f, "LEFT", -ns.S.SM, 0)
		f.status:Show()
		-- Two different failures, and the difference matters: one is worth
		-- retrying later, the other means the name is wrong.
		local who = ns.ConversationManager.DisplayName(conv)
		W.SetTooltip(f, L["Not delivered"], conv.notFound
			and L["There is no character named %s."]:format(who)
			or L["%s is not online"]:format(who))
	else
		f.status:Hide()
		W.SetTooltip(f, nil)
	end

	-- With the markers switched off, nothing in the thread says when anything
	-- was said, so the hover time is the only way left to find out. It hangs
	-- outside the bubble on the outer side -- and clear of the failure mark,
	-- which is already parked there.
	f.showStamp = ap.hoverTimestamp == true and ap.timestamps ~= true
	if f.showStamp then
		f.stamp:SetFontObject(Theme.Font("MICRO"))
		f.stamp:SetText(Format.Clock(msg[MSG_TS]))
		W.SetTextRole(f.stamp, "textMuted")
		f.stamp:ClearAllPoints()
		if entry.dir == ns.DIR_OUT then
			local clearance = failed and (ns.SZ.STATUS_ICON + ns.S.XS) or 0
			f.stamp:SetPoint("RIGHT", f, "LEFT", -(ns.S.SM + clearance), 0)
		else
			f.stamp:SetPoint("LEFT", f, "RIGHT", ns.S.SM, 0)
		end
		f.stamp:SetAlpha(0)
		f.stamp:Hide()
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
		self.receiptPool:ReleaseAll()
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
	self.receiptPool:ReleaseAll()

	for i = first, last do
		local entry = layout[i]
		if entry.kind == "sep" then
			self:RenderSeparator(entry)
		elseif entry.kind == "receipt" then
			self:RenderReceipt(entry)
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
	elseif ns.Setting("history.retention") == "off" then
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

	-- A delivery state changing on the newest message is a change to the line
	-- under it as well as to the bubble, and the line can appear or disappear --
	-- so the tail of the layout is rebuilt rather than patched.
	local messages = conv.messages
	if messages[#messages] == msg and msg[MSG_DIR] == ns.DIR_OUT then
		local had = self.receiptEntry ~= nil
		self:DropReceipt()
		self:AppendReceipt()
		if had or self.receiptEntry then
			self:SetContentHeight(self.totalHeight + ns.SZ.LIST_PAD_Y, false)
			self.rangeFirst, self.rangeLast = nil, nil
			self:UpdateVisible()
			return
		end
	end

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
		W.RefreshText(f.day)
		W.RefreshText(f.clock)
	end)
	refresh(self.bubblePool, function(f)
		f.surface:ApplyTheme()
		W.RefreshText(f.text)
		W.RefreshText(f.stamp)
		f.avatar:ApplyTheme()
	end)
	refresh(self.receiptPool, function(f)
		W.RefreshText(f.label)
	end)

	MessageList.InvalidateMetrics()
	self.forceRebuild = true
	self:ScheduleRebuild()
end
