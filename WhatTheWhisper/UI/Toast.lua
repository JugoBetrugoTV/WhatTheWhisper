-- WhatTheWhisper -- Floating notifications.
--
-- One toast per conversation: a second message from the same person updates the
-- toast that is already on screen and restarts its timer instead of stacking, so
-- a chatty friend cannot bury the screen.

local _, ns = ...
local Theme, W, Anim, Pool, Text = ns.Theme, ns.Widgets, ns.Anim, ns.Pool, ns.Text
local CM, Format = ns.ConversationManager, ns.Format

local Toast = {}
ns.Toast = Toast

local active = {}     -- ordered list, newest last
local byConversation = {}
local pool

local CORNERS = {
	topright    = { point = "TOPRIGHT",    x = -ns.S.XL, y = -ns.S.XL, dir = -1, slideX = 24 },
	topleft     = { point = "TOPLEFT",     x = ns.S.XL,  y = -ns.S.XL, dir = -1, slideX = -24 },
	bottomright = { point = "BOTTOMRIGHT", x = -ns.S.XL, y = ns.S.XL,  dir = 1,  slideX = 24 },
	bottomleft  = { point = "BOTTOMLEFT",  x = ns.S.XL,  y = ns.S.XL,  dir = 1,  slideX = -24 },
}

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function createToast()
	local t = CreateFrame("Frame", nil, UIParent)
	t:SetSize(ns.SZ.TOAST_W, ns.SZ.TOAST_H)
	t:SetFrameStrata("DIALOG")
	t:EnableMouse(true)
	t:Hide()

	t.surface = W.Surface(t, {
		color = "bg3", border = "borderStrong", radius = ns.R.LG, shadow = 14,
	})

	t.avatar = ns.Avatar.New(t, ns.SZ.AVATAR_MD)
	t.avatar:SetPoint("LEFT", t, "LEFT", ns.S.MD, 0)
	t.avatar:SetSurfaceRole("bg3")

	t.name = W.Text(t, "BODY", "textPrimary")
	t.name:SetPoint("TOPLEFT", t.avatar, "TOPRIGHT", ns.S.MD, -1)

	t.time = W.Text(t, "MICRO", "textMuted")
	t.time:SetPoint("TOPRIGHT", t, "TOPRIGHT", -ns.S.MD, -ns.S.MD)
	t.time:SetJustifyH("RIGHT")

	t.body = W.Text(t, "SMALL", "textSecondary")
	t.body:SetPoint("BOTTOMLEFT", t.avatar, "BOTTOMRIGHT", ns.S.MD, 1)

	-- Hairline progress bar showing the remaining time.
	t.progress = CreateFrame("Frame", nil, t)
	t.progress:SetHeight(2)
	t.progress:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", ns.S.MD, 3)
	t.progress.surface = W.Surface(t.progress, { color = "accent", radius = 1, layer = "OVERLAY" })

	t:SetScript("OnEnter", function(self)
		self.paused = true
		Anim.Stop(self.progress)
	end)
	t:SetScript("OnLeave", function(self)
		self.paused = false
		Toast.StartTimer(self, 2)
	end)
	t:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			Toast.Dismiss(self)
			return
		end
		if self.convID then
			ns.UI.Show()
			CM.Select(self.convID)
		end
		Toast.Dismiss(self)
	end)
	return t
end

local function resetToast(_, t)
	t:Hide()
	t:ClearAllPoints()
	t.convID = nil
	t.paused = nil
	t.count = 0
	Anim.Stop(t.progress)
	Anim.StopAll(t)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function settings()
	return ns.db.profile.notifications
end

function Toast.Relayout()
	local corner = CORNERS[settings().position] or CORNERS.topright
	local y = corner.y
	for i = 1, #active do
		local t = active[i]
		t:ClearAllPoints()
		t:SetPoint(corner.point, UIParent, corner.point, corner.x, y)
		y = y + corner.dir * (ns.SZ.TOAST_H + ns.S.SM)
	end
end

--------------------------------------------------------------------------------
-- Timer
--------------------------------------------------------------------------------

function Toast.StartTimer(t, duration)
	duration = duration or settings().duration or 5
	t.timerToken = (t.timerToken or 0) + 1
	local token = t.timerToken
	local width = ns.SZ.TOAST_W - ns.S.MD * 2
	t.progress:SetWidth(width)
	Anim.To(t.progress, duration, width, 0, function(v)
		t.progress:SetWidth(math.max(1, v))
	end, {
		ease = Anim.Ease.linear,
		onDone = function()
			if token ~= t.timerToken or t.paused then return end
			Toast.Dismiss(t)
		end,
	})
	-- With animations off the bar cannot tick, so fall back to a plain timer.
	if not Theme.AnimationsEnabled() then
		Anim.After(duration, function()
			if token ~= t.timerToken or t.paused then return end
			Toast.Dismiss(t)
		end)
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function Toast.Show(conv, msg, isMention)
	if not pool then pool = Pool.New(createToast, resetToast) end
	local existing = byConversation[conv.id]

	local t = existing
	if not t then
		if #active >= (settings().maxVisible or 3) then
			Toast.Dismiss(active[1])
		end
		t = pool:Acquire()
		t.convID = conv.id
		t.count = 0
		active[#active + 1] = t
		byConversation[conv.id] = t
	end

	t.count = (t.count or 0) + 1
	t.avatar:SetConversation(conv)

	local nameColor = Theme.ClassColor(conv.class, "bg3")
	local displayName = CM.DisplayName(conv)
	t.name:SetText(displayName)
	if nameColor then
		t.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3], 1)
	else
		W.SetTextRole(t.name, "textPrimary")
	end
	t.time:SetText(Format.Clock(msg[ns.MSG_TS]))

	local preview = Text.Strip(msg[ns.MSG_TEXT] or ""):gsub("%s+", " ")
	if t.count > 1 and settings().summarise then
		preview = ("(%d) "):format(t.count) .. preview
	end
	local bodyWidth = ns.SZ.TOAST_W - ns.S.MD * 2 - ns.SZ.AVATAR_MD - ns.S.MD
	t.body:SetWidth(bodyWidth)
	t.body:SetWordWrap(false)
	Text.Ellipsize(t.body, preview, bodyWidth)
	W.SetTextRole(t.body, isMention and "accent" or "textSecondary")

	local nameWidth = bodyWidth - 44
	t.name:SetWidth(0)
	if (t.name:GetStringWidth() or 0) > nameWidth then
		Text.Ellipsize(t.name, displayName, nameWidth)
	end

	Toast.Relayout()
	if not existing then
		local corner = CORNERS[settings().position] or CORNERS.topright
		Anim.SlideIn(t, corner.slideX, 0, Theme.Duration("SLOW"))
	end
	Toast.StartTimer(t)
	return t
end

function Toast.Dismiss(t)
	if not t or not t.convID then return end
	byConversation[t.convID] = nil
	for i = #active, 1, -1 do
		if active[i] == t then table.remove(active, i) end
	end
	t.timerToken = (t.timerToken or 0) + 1
	Anim.FadeOut(t, Theme.Duration("BASE"), function()
		pool:Release(t)
		Toast.Relayout()
	end)
end

function Toast.DismissFor(convID)
	local t = byConversation[convID]
	if t then Toast.Dismiss(t) end
end

function Toast.DismissAll()
	for i = #active, 1, -1 do Toast.Dismiss(active[i]) end
end

function Toast.ApplyTheme()
	if not pool then return end
	local function refresh(t)
		t.surface:ApplyTheme()
		t.progress.surface:ApplyTheme()
		t.avatar:ApplyTheme()
		W.RefreshText(t.name)
		W.RefreshText(t.time)
		W.RefreshText(t.body)
	end
	for t in pool:EnumerateActive() do refresh(t) end
	for _, t in ipairs(pool.free) do refresh(t) end
	Toast.Relayout()
end
