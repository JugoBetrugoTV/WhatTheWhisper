-- WhatTheWhisper -- Scrolling.
--
-- Not a Blizzard ScrollFrame: this owns a clipped viewport and a scroll offset,
-- and leaves item placement to the caller. That is what makes the message list
-- able to virtualise -- only the rows inside the viewport exist as frames, no
-- matter how many thousand messages are behind them.
--
-- The scrollbar is 4 px, hidden at rest, and fades in while you are scrolling or
-- hovering the list.

local _, ns = ...
local Theme, W, Anim, Compat = ns.Theme, ns.Widgets, ns.Anim, ns.Compat

local Scroll = {}
ns.Scroll = Scroll

local max, min, abs, floor = math.max, math.min, math.abs, math.floor

local FADE_DELAY = 0.9
local WHEEL_STEP = 58

local SA = {}

function Scroll.New(parent, opts)
	opts = opts or {}
	local sa = CreateFrame("Frame", nil, parent)
	sa.contentHeight = 0
	sa.offset = 0
	sa.barVisible = false
	sa.gutter = opts.gutter ~= false and (ns.SZ.SCROLLBAR_HIT) or 0

	-- Viewport: the clipped window onto the content.
	--
	-- SetClipsChildren is the direct route and exists on all four supported
	-- clients. If a client ever lacks it, a ScrollFrame clips its scroll child
	-- just as well, so the list is wrapped in one instead of spilling over its
	-- own edges.
	local viewport
	if Compat.hasClipsChildren then
		viewport = CreateFrame("Frame", nil, sa)
		viewport:SetPoint("TOPLEFT", sa, "TOPLEFT", 0, 0)
		viewport:SetPoint("BOTTOMRIGHT", sa, "BOTTOMRIGHT", 0, 0)
		Compat.SetClipsChildren(viewport, true)
	else
		local clipper = CreateFrame("ScrollFrame", nil, sa)
		clipper:SetPoint("TOPLEFT", sa, "TOPLEFT", 0, 0)
		clipper:SetPoint("BOTTOMRIGHT", sa, "BOTTOMRIGHT", 0, 0)
		viewport = CreateFrame("Frame", nil, clipper)
		viewport:SetSize(clipper:GetWidth() or 1, clipper:GetHeight() or 1)
		clipper:SetScrollChild(viewport)
		clipper:SetScript("OnSizeChanged", function(_, width, height)
			viewport:SetSize(math.max(1, width or 1), math.max(1, height or 1))
		end)
		sa.clipper = clipper
	end
	viewport:EnableMouseWheel(true)
	-- Content taller than this frame is the point of a scroll area, not a layout
	-- fault; the marker lets an audit tell the two apart. The client clips here
	-- either way, so nothing actually draws outside it.
	viewport.__wtwViewport = true
	sa.viewport = viewport

	-- Track and thumb.
	local track = CreateFrame("Frame", nil, sa)
	track:SetWidth(ns.SZ.SCROLLBAR_HIT)
	track:SetPoint("TOPRIGHT", sa, "TOPRIGHT", 0, -(opts.barInset or 0))
	track:SetPoint("BOTTOMRIGHT", sa, "BOTTOMRIGHT", 0, opts.barInset or 0)
	track:EnableMouse(true)
	track:SetAlpha(0)
	track:Hide()
	sa.track = track

	-- The thumb is centred in the wider grab track; deriving the inset rather
	-- than writing it down means changing either constant keeps it centred.
	local THUMB_INSET = (ns.SZ.SCROLLBAR_HIT - ns.SZ.SCROLLBAR_W) / 2
	local thumb = CreateFrame("Frame", nil, track)
	thumb:SetWidth(ns.SZ.SCROLLBAR_W)
	thumb:SetPoint("RIGHT", track, "RIGHT", -THUMB_INSET, 0)
	thumb:EnableMouse(true)
	-- The pill is 4px because a fat scrollbar is ugly; the thing you grab is the
	-- full track. Negative insets grow the hit rect outwards, so the visible bar
	-- stays thin while the target is the width the hand expects.
	thumb:SetHitRectInsets(-THUMB_INSET, -THUMB_INSET, 0, 0)
	sa.thumb = thumb
	sa.thumbSurface = W.Surface(thumb, { color = "scrollbar", radius = ns.SZ.SCROLLBAR_W / 2 })

	for k, v in pairs(SA) do sa[k] = v end

	--------------------------------------------------------------------- input
	viewport:SetScript("OnMouseWheel", function(_, delta)
		local step = WHEEL_STEP * (IsShiftKeyDown() and 3 or 1)
		sa:ScrollBy(-delta * step, ns.db.profile.animations.smoothScroll)
		sa:FlashBar()
	end)

	sa:HookScript("OnEnter", function() sa:FlashBar() end)
	viewport:SetScript("OnEnter", function() sa:FlashBar() end)

	thumb:SetScript("OnMouseDown", function(self)
		local _, cursorY = GetCursorPosition()
		self.dragFrom = cursorY / (self:GetEffectiveScale() or 1)
		self.dragOffset = sa.offset
		self.dragging = true
		sa:FlashBar(true)
		self:SetScript("OnUpdate", function()
			if not self.dragging then return end
			local _, y = GetCursorPosition()
			y = y / (self:GetEffectiveScale() or 1)
			local trackHeight = track:GetHeight() or 1
			local thumbHeight = thumb:GetHeight() or 1
			local travel = max(1, trackHeight - thumbHeight)
			local delta = (self.dragFrom - y) / travel * sa:MaxOffset()
			sa:SetOffset(self.dragOffset + delta, false)
		end)
	end)
	local function endDrag(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		sa:FlashBar()
	end
	thumb:SetScript("OnMouseUp", endDrag)
	thumb:SetScript("OnHide", endDrag)

	track:SetScript("OnMouseDown", function()
		local _, y = GetCursorPosition()
		y = y / (track:GetEffectiveScale() or 1)
		local thumbTop = thumb:GetTop()
		local thumbBottom = thumb:GetBottom()
		if not thumbTop or not thumbBottom then return end
		local page = sa:GetViewHeight() * 0.9
		if y > thumbTop then
			sa:ScrollBy(-page, true)
		elseif y < thumbBottom then
			sa:ScrollBy(page, true)
		end
	end)

	sa:HookScript("OnSizeChanged", function() sa:UpdateBar() end)
	sa:UpdateBar()
	return sa
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

function SA:GetViewHeight()
	return self.viewport:GetHeight() or 0
end

function SA:MaxOffset()
	return max(0, self.contentHeight - self:GetViewHeight())
end

function SA:SetContentHeight(height, keepBottom)
	local wasAtBottom = keepBottom and self:IsAtBottom(2)
	self.contentHeight = max(0, height or 0)
	if wasAtBottom then
		self:SetOffset(self:MaxOffset(), false)
	else
		self:SetOffset(self.offset, false)
	end
	self:UpdateBar()
end

function SA:GetOffset()
	return self.offset
end

function SA:SetOffset(value, animated)
	local target = min(max(0, value or 0), self:MaxOffset())
	if animated and Theme.AnimationsEnabled() then
		Anim.To(self, Theme.Duration("BASE"), self.offset, target, function(v)
			self.offset = v
			self:Emit()
		end, { ease = Anim.Ease.outCubic })
	else
		Anim.Stop(self)
		if abs(target - self.offset) < 0.01 and self.everEmitted then return end
		self.offset = target
		self:Emit()
	end
end

function SA:ScrollBy(delta, animated)
	local base = Anim.IsRunning(self) and self.scrollTarget or self.offset
	self.scrollTarget = min(max(0, base + delta), self:MaxOffset())
	self:SetOffset(self.scrollTarget, animated)
end

function SA:ScrollToBottom(animated)
	self.scrollTarget = self:MaxOffset()
	self:SetOffset(self.scrollTarget, animated)
end

function SA:ScrollToTop(animated)
	self.scrollTarget = 0
	self:SetOffset(0, animated)
end

function SA:IsAtBottom(tolerance)
	return self.offset >= self:MaxOffset() - (tolerance or 4)
end

function SA:Emit()
	self.everEmitted = true
	self:UpdateBar()
	if self.OnScrollChanged then
		ns.Guard("Scroll.OnScrollChanged", self.OnScrollChanged, self, self.offset)
	end
end

--------------------------------------------------------------------------------
-- Scrollbar
--------------------------------------------------------------------------------

function SA:UpdateBar()
	local maxOffset = self:MaxOffset()
	local view = self:GetViewHeight()
	if maxOffset <= 0 or view <= 0 then
		self.track:Hide()
		return
	end
	self.track:Show()
	local trackHeight = self.track:GetHeight() or view
	local ratio = view / max(view, self.contentHeight)
	local thumbHeight = max(ns.SZ.SCROLLBAR_MIN_THUMB, floor(trackHeight * ratio))
	self.thumb:SetHeight(thumbHeight)
	local travel = max(0, trackHeight - thumbHeight)
	local progress = maxOffset > 0 and (self.offset / maxOffset) or 0
	self.thumb:ClearAllPoints()
	self.thumb:SetPoint("TOP", self.track, "TOP", 0, -(travel * progress))
	self.thumb:SetWidth(ns.SZ.SCROLLBAR_W)
	self.thumb:SetPoint("RIGHT", self.track, "RIGHT",
		-(ns.SZ.SCROLLBAR_HIT - ns.SZ.SCROLLBAR_W) / 2, 0)
end

-- Shows the bar, then fades it out again once the list has been still for a
-- moment. No timer runs while the bar is already hidden.
function SA:FlashBar(hold)
	if self:MaxOffset() <= 0 then return end
	self.barToken = (self.barToken or 0) + 1
	local token = self.barToken
	if not self.barVisible then
		self.barVisible = true
		Anim.FadeIn(self.track, Theme.Duration("FAST"))
	else
		self.track:SetAlpha(1)
	end
	if hold then return end
	Anim.After(FADE_DELAY, function()
		if token ~= self.barToken then return end
		if self.thumb.dragging then return end
		if self:IsMouseOver() then
			self:FlashBar()
			return
		end
		self.barVisible = false
		Anim.FadeOut(self.track, Theme.Duration("SLOW"))
	end)
end

function SA:ApplyTheme()
	self.thumbSurface:ApplyTheme()
	self:UpdateBar()
end
