-- WhatTheWhisper -- Overview (Exposé).
--
-- This moves and scales the *real* windows into a grid rather than drawing fake
-- previews, because WoW cannot render a frame to a texture and a mock-up would
-- show stale content. Each window keeps its own position and scale, which are
-- restored exactly on exit.

local _, ns = ...
local Theme, W, Anim, Pool = ns.Theme, ns.Widgets, ns.Anim, ns.Pool
local CM = ns.ConversationManager
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Expose = {}
ns.Expose = Expose

local max, min, ceil, floor, sqrt = math.max, math.min, math.ceil, math.floor, math.sqrt

local scrim, hint, overlayPool
local activeCards = {}
local isOpen = false

local MARGIN = 60
local GAP = ns.S.XL

--------------------------------------------------------------------------------
-- Overlay cards
--------------------------------------------------------------------------------

local function createOverlay()
	local o = CreateFrame("Frame", nil, UIParent)
	o:SetFrameStrata("FULLSCREEN")
	o:EnableMouse(true)
	o:Hide()
	o.ring = ns.Draw.NewOutlined(o, "OVERLAY", 2)
	o.ring:SetRadius(Theme.Radius(ns.R.LG))
	o.ring:SetColor(0, 0, 0, 0)
	o.label = W.Text(o, "SMALL", "textPrimary", "OVERLAY")
	o.label:ClearAllPoints()
	o.label:SetPoint("BOTTOM", o, "TOP", 0, ns.S.SM)
	o.label:SetJustifyH("CENTER")

	o:SetScript("OnEnter", function(self)
		local c = Theme.Get("accent")
		self.ring:SetBorder(2, c[1], c[2], c[3], 1)
		W.SetTextRole(self.label, "textPrimary")
	end)
	o:SetScript("OnLeave", function(self)
		self.ring:SetBorder(0)
		W.SetTextRole(self.label, "textSecondary")
	end)
	o:SetScript("OnMouseUp", function(self)
		Expose.Close(self.target, self.convID)
	end)
	return o
end

local function resetOverlay(_, o)
	o:Hide()
	o:ClearAllPoints()
	o.target = nil
	o.convID = nil
	o.ring:SetBorder(0)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function build()
	if scrim then return end
	scrim = CreateFrame("Frame", "WhatTheWhisperExpose", UIParent)
	scrim:SetAllPoints(UIParent)
	scrim:SetFrameStrata("FULLSCREEN")
	scrim:SetFrameLevel(1)
	scrim:EnableMouse(true)
	scrim:Hide()
	scrim.tex = scrim:CreateTexture(nil, "BACKGROUND")
	scrim.tex:SetAllPoints()
	scrim:SetScript("OnMouseDown", function() Expose.Close() end)

	hint = W.Text(scrim, "SMALL", "textSecondary")
	hint:SetPoint("TOP", scrim, "TOP", 0, -ns.S.HUGE)
	hint:SetJustifyH("CENTER")

	overlayPool = Pool.New(createOverlay, resetOverlay, "expose.overlay")

	if type(_G.UISpecialFrames) == "table" then
		local found
		for i = 1, #_G.UISpecialFrames do
			if _G.UISpecialFrames[i] == "WhatTheWhisperExpose" then found = true break end
		end
		if not found then table.insert(_G.UISpecialFrames, "WhatTheWhisperExpose") end
	end
	scrim:HookScript("OnHide", function()
		if isOpen then Expose.Close() end
	end)
end

--------------------------------------------------------------------------------
-- Collecting windows
--------------------------------------------------------------------------------

local function collectWindows()
	local list = {}
	local mainWindow = ns.MainWindow.Get()
	if mainWindow:IsShown() then
		list[#list + 1] = { frame = mainWindow, label = L["WhatTheWhisper"] }
	end
	ns.Popout.Each(function(id, win)
		local conv = CM.Get(id)
		list[#list + 1] = {
			frame = win, convID = id,
			label = conv and CM.DisplayName(conv) or id,
		}
	end)
	return list
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

function Expose.IsOpen()
	return isOpen
end

function Expose.Open()
	build()
	local windows = collectWindows()
	if #windows == 0 then
		ns.Print(L["Nothing to show"])
		return
	end

	isOpen = true
	activeCards = {}

	local c = Theme.Get("scrim")
	scrim.tex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.6)
	hint:SetText(L["Overview"])
	scrim:Show()
	Anim.FadeIn(scrim, Theme.Duration("BASE"))

	local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
	local count = #windows
	local columns = max(1, ceil(sqrt(count)))
	local rows = ceil(count / columns)
	local cellW = (screenW - MARGIN * 2 - GAP * (columns - 1)) / columns
	local cellH = (screenH - MARGIN * 2 - GAP * (rows - 1)) / rows

	for i = 1, count do
		local entry = windows[i]
		local win = entry.frame
		local column = (i - 1) % columns
		local row = floor((i - 1) / columns)

		-- Remember exactly where it was so exit is lossless.
		local point, relTo, relPoint, x, y = win:GetPoint(1)
		local saved = {
			point = point, relTo = relTo, relPoint = relPoint, x = x, y = y,
			scale = win:GetScale() or 1, level = win:GetFrameLevel(),
			strata = win:GetFrameStrata(),
		}
		win.__wtwExpose = saved

		local scale = min(1, cellW / max(1, win:GetWidth()), cellH / max(1, win:GetHeight()))
		local centreX = MARGIN + cellW / 2 + column * (cellW + GAP) - screenW / 2
		local centreY = screenH / 2 - (MARGIN + cellH / 2 + row * (cellH + GAP))

		win:SetFrameStrata("FULLSCREEN")
		win:SetFrameLevel(10 + i * 4)
		if win.surface then win.surface:SyncShadow() end
		win:ClearAllPoints()
		-- SetPoint offsets are expressed in the frame's own scaled space.
		win:SetScale(scale)
		win:SetPoint("CENTER", UIParent, "CENTER", centreX / scale, centreY / scale)

		local overlay = overlayPool:Acquire()
		overlay.target = win
		overlay.convID = entry.convID
		overlay:SetFrameLevel(12 + i * 4)
		overlay:ClearAllPoints()
		overlay:SetSize(win:GetWidth() * scale, win:GetHeight() * scale)
		overlay:SetPoint("CENTER", UIParent, "CENTER", centreX, centreY)
		overlay.label:SetText(entry.label)
		W.SetTextRole(overlay.label, "textSecondary")
		overlay.ring:SetRadius(Theme.Radius(ns.R.LG))
		overlay:Show()
		if Theme.IsFancy() then
			Anim.PopIn(overlay, Theme.Duration("WINDOW"), 0.94)
		end

		activeCards[#activeCards + 1] = win
	end
end

function Expose.Close(focusWindow, convID)
	if not isOpen then return end
	isOpen = false

	for i = 1, #activeCards do
		local win = activeCards[i]
		local saved = win.__wtwExpose
		if saved then
			win:SetScale(saved.scale)
			win:ClearAllPoints()
			if saved.point then
				win:SetPoint(saved.point, saved.relTo or UIParent, saved.relPoint, saved.x, saved.y)
			else
				win:SetPoint("CENTER")
			end
			win:SetFrameStrata(saved.strata or "HIGH")
			win:SetFrameLevel(saved.level or 1)
			if win.surface then win.surface:SyncShadow() end
			win.__wtwExpose = nil
		end
	end
	activeCards = {}

	if overlayPool then overlayPool:ReleaseAll() end
	scrim:SetScript("OnHide", nil)
	Anim.FadeOut(scrim, Theme.Duration("FAST"), function()
		scrim:SetScript("OnHide", function()
			if isOpen then Expose.Close() end
		end)
	end)

	if focusWindow then
		focusWindow:Raise()
		if convID then CM.Select(convID) end
	end
end

function Expose.Toggle()
	if isOpen then Expose.Close() else Expose.Open() end
end

function Expose.ApplyTheme()
	if not scrim then return end
	local c = Theme.Get("scrim")
	scrim.tex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.6)
	W.RefreshText(hint)
end
