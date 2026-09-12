-- WhatTheWhisper -- The main window.
--
-- Title bar, sidebar, optional tab strip and the conversation view, plus the
-- window behaviour people expect from a desktop app: drag, resize from any edge,
-- a draggable splitter, remembered geometry, Escape to close.

local _, ns = ...
local Theme, W, Anim, Pixel, Compat = ns.Theme, ns.Widgets, ns.Anim, ns.Pixel, ns.Compat
local CM = ns.ConversationManager
local L = ns.L

local MainWindow = {}
ns.MainWindow = MainWindow

local max, min = math.max, math.min

local M = {}

local frame

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- Returns the window only if it has already been built. Used by the event
-- handlers so a player who never opens the messenger never pays for its ~250
-- frames; the window catches up with a full refresh the first time it is shown.
function MainWindow.Existing()
	return frame
end

function MainWindow.Get()
	if frame then return frame end

	frame = CreateFrame("Frame", "WhatTheWhisperFrame", UIParent)
	for k, v in pairs(M) do frame[k] = v end

	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	Compat.SetResizeBounds(frame,
		ns.SZ.WINDOW_MIN_W, ns.SZ.WINDOW_MIN_H, ns.SZ.WINDOW_MAX_W, ns.SZ.WINDOW_MAX_H)

	frame.surface = W.Surface(frame, {
		color = "bg0", border = "borderSubtle", radius = ns.R.LG, shadow = 18,
	})

	------------------------------------------------------------------ titlebar
	local title = CreateFrame("Frame", nil, frame)
	title:SetHeight(ns.SZ.TITLEBAR_H)
	title:SetPoint("TOPLEFT")
	title:SetPoint("TOPRIGHT")
	title:EnableMouse(true)
	title.divider = W.Hairline(title, "horizontal", { anchor = "BOTTOM", color = "borderSubtle" })
	frame.titlebar = title

	title.mark = W.Icon(title, "logo", ns.SZ.ICON_LOGO, "accent")
	title.mark:SetPoint("LEFT", title, "LEFT", ns.S.MD + 1, 0)

	title.label = W.Text(title, "SMALL", "textSecondary")
	title.label:SetPoint("LEFT", title.mark, "RIGHT", ns.S.SM, 0)
	title.label:SetText(L["WhatTheWhisper"])

	title.badge = ns.Controls.Badge(title, { height = 16 })
	title.badge:SetPoint("LEFT", title.label, "RIGHT", ns.S.SM, 0)

	local function titleButton(icon, tooltip, onClick, tooltipSub)
		return ns.Button.Icon(title, {
			icon = icon, size = ns.SZ.ICON_BTN_SM, glyph = ns.SZ.ICON_GLYPH_SM,
			tooltip = tooltip, tooltipSub = tooltipSub, onClick = onClick,
		})
	end

	title.close = titleButton("close", L["Close"], function() ns.UI.Hide() end)
	title.close:SetPoint("RIGHT", title, "RIGHT", -ns.S.SM, 0)

	title.minimize = titleButton("minimize", L["Minimize"], function() ns.UI.Minimize() end)
	title.minimize:SetPoint("RIGHT", title.close, "LEFT", -2, 0)

	title.settings = titleButton("sliders", L["Settings"], function() ns.SettingsUI.Toggle() end)
	title.settings:SetPoint("RIGHT", title.minimize, "LEFT", -2, 0)

	-- Named for what it shows rather than for the effect it uses, and only there
	-- when there is more than one window to show. "Overview" on its own, on a
	-- session with a single window, is a button that darkens the screen and puts
	-- that window in the middle of it -- which reads as a bug, not a feature.
	title.expose = titleButton("grid", L["All windows"], function() ns.Expose.Toggle() end,
		L["Show every open conversation window side by side."])
	title.expose:SetPoint("RIGHT", title.settings, "LEFT", -2, 0)
	title.expose:Hide()

	W.MakeWindowHandle(title, {
		canMove = function() return not ns.db.profile.layout.locked end,
		onStartMove = function()
			frame:StartMoving()
			frame.moving = true
		end,
		onStopMove = function()
			if not frame.moving then return end
			frame.moving = false
			frame:StopMovingOrSizing()
			frame:SavePosition()
		end,
		onDoubleClick = function() ns.UI.Minimize() end,
	})

	-------------------------------------------------------------------- body
	frame.sidebar = ns.Sidebar.New(frame)
	frame.sidebar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
	frame.sidebar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
	frame.sidebar:SetWidth(ns.db and ns.db.profile.layout.sidebarWidth or ns.SZ.SIDEBAR_W)

	-- Straddles the boundary so half the grab area is over each panel, and sits
	-- above both so the handle wins the cursor there. Neither panel is inset for
	-- it: a dead strip between the list and the thread would be visible.
	frame.splitter = CreateFrame("Frame", nil, frame)
	frame.splitter:SetWidth(ns.SZ.SPLITTER_HIT)
	frame.splitter:SetPoint("TOP", frame.sidebar, "TOPRIGHT", 0, 0)
	frame.splitter:SetPoint("BOTTOM", frame.sidebar, "BOTTOMRIGHT", 0, 0)
	frame.splitter:SetFrameLevel(frame.sidebar:GetFrameLevel() + 10)
	frame.splitter:EnableMouse(true)
	frame.splitter:SetScript("OnEnter", function() frame:SetSplitterHighlight(true) end)
	frame.splitter:SetScript("OnLeave", function() frame:SetSplitterHighlight(false) end)
	frame.splitter:SetScript("OnMouseDown", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", function()
			local x = select(1, GetCursorPosition()) / (frame:GetEffectiveScale() or 1)
			frame:SetSidebarWidth(x - (frame:GetLeft() or 0))
		end)
	end)
	local function endSplit(self)
		if not self.dragging then return end
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		ns.db.profile.layout.sidebarWidth = frame.sidebar:GetWidth()
	end
	frame.splitter:SetScript("OnMouseUp", endSplit)
	frame.splitter:SetScript("OnHide", endSplit)

	frame.tabs = ns.Tabs.New(frame)
	frame.tabs:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 0, 0)
	frame.tabs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -ns.SZ.TITLEBAR_H)

	frame.view = ns.ConversationView.New(frame)
	frame.view:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.view:SetPoint("LEFT", frame.sidebar, "RIGHT", 0, 0)

	-------------------------------------------------------------- resize grips
	frame.grip = CreateFrame("Frame", nil, frame)
	frame.grip:SetSize(ns.SZ.RESIZE_GRIP, ns.SZ.RESIZE_GRIP)
	frame.grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	frame.grip:EnableMouse(true)
	frame.gripIcon = W.Icon(frame.grip, "sort", ns.SZ.ICON_MARK, "textMuted")
	frame.gripIcon:SetPoint("CENTER")
	frame.gripIcon:SetAlpha(0.5)
	frame.grip:SetScript("OnMouseDown", function()
		if ns.db.profile.layout.locked then return end
		frame:StartSizing("BOTTOMRIGHT")
		frame.sizing = true
	end)
	frame.grip:SetScript("OnMouseUp", function()
		if not frame.sizing then return end
		frame.sizing = false
		frame:StopMovingOrSizing()
		frame:SaveGeometry()
	end)

	frame:HookScript("OnSizeChanged", function()
		frame:Relayout()
	end)
	frame:SetScript("OnMouseDown", function() frame:Raise() end)

	-- Escape closes the window, exactly like every other panel in the game.
	if type(_G.UISpecialFrames) == "table" then
		local found
		for i = 1, #_G.UISpecialFrames do
			if _G.UISpecialFrames[i] == "WhatTheWhisperFrame" then found = true break end
		end
		if not found then table.insert(_G.UISpecialFrames, "WhatTheWhisperFrame") end
	end

	frame:RestoreGeometry()
	frame:Relayout()
	return frame
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function M:SetSplitterHighlight(on)
	if not self.splitterTex then
		self.splitterTex = self.splitter:CreateTexture(nil, "OVERLAY")
		self.splitterTex:SetPoint("TOP", self.sidebar, "TOPRIGHT", 0, 0)
		self.splitterTex:SetPoint("BOTTOM", self.sidebar, "BOTTOMRIGHT", 0, 0)
		self.splitterTex:SetAlpha(0)
	end
	-- Two physical pixels, recomputed on every call: the UI scale can change
	-- between hovers and a hairline frozen at the old scale looks blurry.
	self.splitterTex:SetWidth(Pixel.Size(self.splitter) * 2)
	local c = Theme.Get("accent")
	self.splitterTex:SetColorTexture(c[1], c[2], c[3], 1)
	Anim.FadeTo(self.splitterTex, on and 0.9 or 0, Theme.Duration("FAST"))
end

function M:SetSidebarWidth(width)
	local maxWidth = min(ns.SZ.SIDEBAR_MAX_W, (self:GetWidth() or 900) - 320)
	width = min(max(width, ns.SZ.SIDEBAR_RAIL_W), max(ns.SZ.SIDEBAR_RAIL_W, maxWidth))
	-- Snap through the compact threshold so the rail feels intentional.
	if width > ns.SZ.SIDEBAR_RAIL_W + 16 and width < ns.SZ.SIDEBAR_COMPACT_AT then
		width = ns.SZ.SIDEBAR_COMPACT_AT
	elseif width <= ns.SZ.SIDEBAR_RAIL_W + 16 then
		width = ns.SZ.SIDEBAR_RAIL_W
	end
	self.sidebar:SetWidth(width)
end

function M:Relayout()
	local mode = (ns.db and ns.db.profile.layout.mode) or "sidebar"

	local showSidebar = (mode ~= "tabbed")
	local showTabs = (mode ~= "sidebar")

	self.sidebar:SetShown(showSidebar)
	self.splitter:SetShown(showSidebar)
	self.tabs:SetShown(showTabs)

	self.view:ClearAllPoints()
	self.view:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	if showSidebar then
		self.view:SetPoint("LEFT", self.sidebar, "RIGHT", 0, 0)
	else
		self.view:SetPoint("LEFT", self, "LEFT", 0, 0)
	end
	if showTabs then
		self.tabs:ClearAllPoints()
		self.tabs:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -ns.SZ.TITLEBAR_H)
		if showSidebar then
			self.tabs:SetPoint("TOPLEFT", self.sidebar, "TOPRIGHT", 0, 0)
		else
			self.tabs:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -ns.SZ.TITLEBAR_H)
		end
		self.view:SetPoint("TOP", self.tabs, "BOTTOM", 0, 0)
	else
		self.view:SetPoint("TOP", self, "TOP", 0, -ns.SZ.TITLEBAR_H)
	end

	-- Round whichever surfaces touch the window's own corners.
	self.view:SetOuterCorners(false, false, not showSidebar, true)
	self.sidebar.surface:SetRadius(ns.R.LG)
	self.sidebar.surface:SetCorners(false, false, showSidebar, false)

	-- Give the conversation room before the sidebar gets its ideal width.
	if showSidebar then
		local available = (self:GetWidth() or ns.SZ.WINDOW_W) - 320
		if (self.sidebar:GetWidth() or 0) > available then
			self.sidebar:SetWidth(max(ns.SZ.SIDEBAR_RAIL_W, available))
		end
	end
end

--------------------------------------------------------------------------------
-- Geometry persistence
--------------------------------------------------------------------------------

function M:SavePosition()
	if not ns.db.profile.layout.remember then return end
	local left, top = self:GetLeft(), self:GetTop()
	if not left or not top then return end
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	ns.db.profile.layout.point = { left = left, top = top }
end

function M:SaveGeometry()
	self:SavePosition()
	if not ns.db.profile.layout.remember then return end
	ns.db.profile.layout.width = self:GetWidth()
	ns.db.profile.layout.height = self:GetHeight()
end

function M:RestoreGeometry()
	local layout = ns.db.profile.layout
	self:SetSize(
		min(max(layout.width or ns.SZ.WINDOW_W, ns.SZ.WINDOW_MIN_W), ns.SZ.WINDOW_MAX_W),
		min(max(layout.height or ns.SZ.WINDOW_H, ns.SZ.WINDOW_MIN_H), ns.SZ.WINDOW_MAX_H))
	self:ClearAllPoints()
	local point = layout.point
	if point and point.left and point.top then
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", point.left, point.top)
	else
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	self:SetSidebarWidth(layout.sidebarWidth or ns.SZ.SIDEBAR_W)
end

function M:ResetGeometry()
	ns.db.profile.layout.point = nil
	ns.db.profile.layout.width = ns.SZ.WINDOW_W
	ns.db.profile.layout.height = ns.SZ.WINDOW_H
	ns.db.profile.layout.sidebarWidth = ns.SZ.SIDEBAR_W
	self:RestoreGeometry()
	self:Relayout()
end

--------------------------------------------------------------------------------
-- Refresh hooks
--------------------------------------------------------------------------------

function M:RefreshUnreadBadge()
	self.titlebar.badge:SetCount(CM.TotalUnread())
end

-- The overview only exists when there is more than one window to lay out, so
-- the button that opens it only exists then too.
function M:RefreshWindowButtons()
	local windows = 1
	ns.Popout.Each(function() windows = windows + 1 end)
	self.titlebar.expose:SetShown(windows > 1)
end

-- The player changed the language. Everything below was written once, when the
-- frame was built, which is exactly why none of it can notice on its own.
function M:Relocalize()
	local title = self.titlebar
	title.label:SetText(L["WhatTheWhisper"])
	W.SetTooltip(title.close, L["Close"])
	W.SetTooltip(title.minimize, L["Minimize"])
	W.SetTooltip(title.settings, L["Settings"])
	W.SetTooltip(title.expose, L["All windows"],
		L["Show every open conversation window side by side."])
	self.sidebar:Relocalize()
	self.view:Relocalize()
end

function M:ApplyTheme()
	self.surface:ApplyTheme()
	self.titlebar.divider:ApplyTheme()
	W.RefreshIcon(self.titlebar.mark)
	W.RefreshText(self.titlebar.label)
	self.titlebar.badge:ApplyTheme()
	self.titlebar.close:ApplyTheme()
	self.titlebar.minimize:ApplyTheme()
	self.titlebar.settings:ApplyTheme()
	self.titlebar.expose:ApplyTheme()
	W.RefreshIcon(self.gripIcon)
	self.sidebar:ApplyTheme()
	self.tabs:ApplyTheme()
	self.view:ApplyTheme()
	self:Relayout()
end
