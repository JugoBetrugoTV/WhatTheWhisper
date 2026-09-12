-- WhatTheWhisper -- Small, quiet tooltips.
--
-- Deliberately not GameTooltip: that frame is shared with the whole game, is a
-- classic taint vector, and carries Blizzard's border art. Real game hyperlinks
-- (items, spells) still use GameTooltip, because there it is the correct tool.

local _, ns = ...
local Theme, W, Anim = ns.Theme, ns.Widgets, ns.Anim

local Tooltip = {}
ns.Tooltip = Tooltip

local DELAY = 0.35
local PAD_X, PAD_Y = ns.S.SM, 5
local MAX_W = 260

local frame, surface, titleFS, subFS
local pendingOwner, pendingToken = nil, 0
local currentOwner

local function build()
	if frame then return end
	frame = CreateFrame("Frame", "WhatTheWhisperTooltip", UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:SetAlpha(0)

	surface = W.Surface(frame, {
		color = "bg3", border = "borderStrong", radius = ns.R.SM + 2, shadow = 10,
	})
	titleFS = W.Text(frame, "MICRO", "textPrimary")
	titleFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD_X, -PAD_Y)
	titleFS:SetJustifyV("TOP")
	subFS = W.Text(frame, "MICRO", "textMuted")
	subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -2)
	subFS:SetJustifyV("TOP")
end

local function layout(text, subtext)
	titleFS:SetWidth(0)
	titleFS:SetText(text)
	local w = math.min(MAX_W, titleFS:GetStringWidth())
	titleFS:SetWidth(w)

	local h = titleFS:GetStringHeight()
	if subtext and subtext ~= "" then
		subFS:SetWidth(0)
		subFS:SetText(subtext)
		local sw = math.min(MAX_W, subFS:GetStringWidth())
		subFS:SetWidth(sw)
		w = math.max(w, sw)
		h = h + subFS:GetStringHeight() + 2
		subFS:Show()
	else
		subFS:SetText("")
		subFS:Hide()
	end

	frame:SetSize(w + PAD_X * 2, h + PAD_Y * 2)
end

-- Prefers below the owner, flips above when there is no room.
local function position(owner)
	frame:ClearAllPoints()
	local bottom = owner:GetBottom()
	local height = frame:GetHeight()
	if bottom and bottom - height - ns.S.SM < 0 then
		frame:SetPoint("BOTTOM", owner, "TOP", 0, ns.S.XS + 2)
	else
		frame:SetPoint("TOP", owner, "BOTTOM", 0, -(ns.S.XS + 2))
	end
end

function Tooltip.Show(owner, info)
	build()
	if not info or not info.text then return end
	currentOwner = owner
	layout(info.text, info.subtext)
	position(owner)
	surface:Layout()
	Anim.FadeIn(frame, Theme.Duration("FAST"))
end

function Tooltip.Schedule(owner, info)
	build()
	pendingToken = pendingToken + 1
	local token = pendingToken
	pendingOwner = owner
	Anim.After(DELAY, function()
		if token ~= pendingToken then return end
		if not owner:IsVisible() or not owner.__wtwHover then return end
		Tooltip.Show(owner, info)
	end)
end

function Tooltip.Cancel(owner)
	if owner and pendingOwner and owner ~= pendingOwner and owner ~= currentOwner then return end
	pendingToken = pendingToken + 1
	pendingOwner = nil
	if frame and frame:IsShown() then
		currentOwner = nil
		Anim.FadeOut(frame, Theme.Duration("FAST"))
	end
end

function Tooltip.Hide()
	pendingToken = pendingToken + 1
	pendingOwner = nil
	currentOwner = nil
	if frame then
		Anim.StopAll(frame)
		frame:Hide()
		frame:SetAlpha(0)
	end
end

function Tooltip.ApplyTheme()
	if not frame then return end
	surface:ApplyTheme()
	W.RefreshText(titleFS)
	W.RefreshText(subFS)
end
