-- WhatTheWhisper -- Detached conversation windows.
--
-- Same design language as the main window, same ConversationView inside, so a
-- popout is the product in a smaller frame rather than a second, worse UI.
-- Windows snap to each other and to the main window while dragging.

local _, ns = ...
local Theme, W, Anim, Compat = ns.Theme, ns.Widgets, ns.Anim, ns.Compat
local CM = ns.ConversationManager
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Popout = {}
ns.Popout = Popout

local max, abs = math.max, math.abs

local windows = {}
local P = {}

Popout.windows = windows

--------------------------------------------------------------------------------
-- Snapping
--------------------------------------------------------------------------------

local function snapTargets(exclude)
	local targets = {}
	for _, win in pairs(windows) do
		if win ~= exclude and win:IsShown() then targets[#targets + 1] = win end
	end
	local mainWindow = ns.MainWindow and ns.MainWindow.Get()
	if mainWindow and mainWindow:IsShown() and mainWindow ~= exclude then
		targets[#targets + 1] = mainWindow
	end
	return targets
end

-- Moves `win` to the nearest edge alignment within SNAP_DISTANCE.
local function applySnap(win)
	if not ns.db.profile.layout.snap then return end
	local left, right = win:GetLeft(), win:GetRight()
	local top, bottom = win:GetTop(), win:GetBottom()
	if not left or not top then return end
	local d = ns.SZ.SNAP_DISTANCE
	local dx, dy = 0, 0
	local bestX, bestY = d + 1, d + 1

	for _, other in ipairs(snapTargets(win)) do
		local ol, orr = other:GetLeft(), other:GetRight()
		local ot, ob = other:GetTop(), other:GetBottom()
		if ol and ot then
			-- horizontal edges
			local candidates = {
				{ left - orr, orr - left },      -- our left to their right
				{ right - ol, ol - right },      -- our right to their left
				{ left - ol, 0 },                -- align lefts
				{ right - orr, 0 },              -- align rights
			}
			for _, candidate in ipairs(candidates) do
				local delta = candidate[1]
				if abs(delta) < bestX then
					bestX = abs(delta)
					dx = -delta
				end
			end
			local vcandidates = {
				top - ob, bottom - ot, top - ot, bottom - ob,
			}
			for _, delta in ipairs(vcandidates) do
				if abs(delta) < bestY then
					bestY = abs(delta)
					dy = -delta
				end
			end
		end
	end

	if bestX <= d or bestY <= d then
		local newLeft = left + (bestX <= d and dx or 0)
		local newTop = top + (bestY <= d and dy or 0)
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
	end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function create(conv)
	local win = CreateFrame("Frame", nil, UIParent)
	for k, v in pairs(P) do win[k] = v end
	win.convID = conv.id

	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetMovable(true)
	win:SetResizable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	Compat.SetResizeBounds(win, ns.SZ.POPOUT_MIN_W, ns.SZ.POPOUT_MIN_H, 900, 900)

	win.surface = W.Surface(win, {
		color = "bg0", border = "borderSubtle", radius = ns.R.LG, shadow = 14,
	})

	win.view = ns.ConversationView.New(win, {
		headerHeight = ns.SZ.POPOUT_HEADER_H,
		showPopout = false,
		compactHeader = true,
	})
	win.view:SetAllPoints()
	win.view:SetOuterCorners(true, true, true, true)

	win.view:AddHeaderButton("dock", L["Dock"], function()
		ns.UI.DockConversation(win.convID)
	end)
	win.view:AddHeaderButton("pin", L["Pin"], function(button)
		win:TogglePin(button)
	end)
	win.view:AddHeaderButton("minimize", L["Minimize"], function()
		win:ToggleMinimized()
	end)
	win.view:AddHeaderButton("close", L["Close"], function()
		ns.UI.CloseConversation(win.convID)
	end)

	-- The header doubles as the drag handle.
	W.MakeWindowHandle(win.view.header, {
		canMove = function() return not (win.locked or ns.db.profile.layout.locked) end,
		onStartMove = function()
			win:StartMoving()
			win.moving = true
		end,
		onStopMove = function()
			if not win.moving then return end
			win.moving = false
			win:StopMovingOrSizing()
			applySnap(win)
			win:SaveGeometry()
		end,
		onDoubleClick = function() win:ToggleMinimized() end,
	})

	win.grip = CreateFrame("Frame", nil, win)
	win.grip:SetSize(ns.SZ.RESIZE_GRIP, ns.SZ.RESIZE_GRIP)
	win.grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
	win.grip:EnableMouse(true)
	win.grip:SetScript("OnMouseDown", function()
		if win.locked or ns.db.profile.layout.locked then return end
		win:StartSizing("BOTTOMRIGHT")
		win.sizing = true
	end)
	win.grip:SetScript("OnMouseUp", function()
		if not win.sizing then return end
		win.sizing = false
		win:StopMovingOrSizing()
		win:SaveGeometry()
	end)

	win:SetScript("OnMouseDown", function() win:Raise() end)
	win:RestoreGeometry()
	win.view:SetConversation(conv)
	return win
end

--------------------------------------------------------------------------------
-- Window behaviour
--------------------------------------------------------------------------------

function P:StoreKey()
	return self.convID
end

function P:SaveGeometry()
	local store = ns.db.profile.popouts
	local left, top = self:GetLeft(), self:GetTop()
	if not left or not top then return end
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	store[self:StoreKey()] = {
		left = left, top = top,
		width = self:GetWidth(), height = self.minimized and self.restoreHeight or self:GetHeight(),
		pinned = self.pinned or nil,
		minimized = self.minimized or nil,
	}
end

function P:RestoreGeometry()
	local saved = ns.db.profile.popouts[self:StoreKey()]
	local width = (saved and saved.width) or ns.SZ.POPOUT_W
	local height = (saved and saved.height) or ns.SZ.POPOUT_H
	self:SetSize(max(width, ns.SZ.POPOUT_MIN_W), max(height, ns.SZ.POPOUT_MIN_H))
	self:ClearAllPoints()
	if saved and saved.left and saved.top then
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.left, saved.top)
	else
		-- Cascade new windows so they never land exactly on top of each other.
		local count = 0
		for _ in pairs(windows) do count = count + 1 end
		self:SetPoint("CENTER", UIParent, "CENTER", 160 + count * 24, 40 - count * 24)
	end
	self.pinned = saved and saved.pinned or false
	if saved and saved.minimized then
		self.restoreHeight = height
		self:ToggleMinimized(true)
	end
end

function P:ToggleMinimized(force)
	local minimize = force
	if minimize == nil then minimize = not self.minimized end
	if minimize == self.minimized then return end
	self.minimized = minimize
	if minimize then
		self.restoreHeight = self:GetHeight()
		self.view.list:Hide()
		self.view.composer:Hide()
		self:SetHeight(ns.SZ.POPOUT_HEADER_H)
	else
		self.view.list:Show()
		self.view.composer:Show()
		self:SetHeight(self.restoreHeight or ns.SZ.POPOUT_H)
	end
	self.view:SetHeaderIsBottom(minimize)
	self:SaveGeometry()
end

function P:TogglePin(button)
	self.pinned = not self.pinned
	self.locked = self.pinned
	if button then
		button:SetSelectedState(self.pinned)
		button:SetIcon(self.pinned and "pin_filled" or "pin")
	end
	self:SaveGeometry()
end

function P:ApplyTheme()
	self.surface:ApplyTheme()
	self.view:ApplyTheme()
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

function Popout.Open(id)
	local conv = CM.Get(id)
	if not conv then return nil end
	local win = windows[id]
	if not win then
		win = create(conv)
		windows[id] = win
	end
	conv.poppedOut = true
	win:Show()
	Anim.PopIn(win, Theme.Duration("WINDOW"))
	return win
end

function Popout.Close(id)
	local win = windows[id]
	if not win then return end
	local conv = CM.Get(id)
	if conv then conv.poppedOut = false end
	win:SaveGeometry()
	Anim.FadeOut(win, Theme.Duration("FAST"), function()
		win:Hide()
	end)
end

function Popout.Get(id)
	return windows[id]
end

function Popout.IsOpen(id)
	local win = windows[id]
	return win and win:IsShown() or false
end

function Popout.Each(fn)
	for id, win in pairs(windows) do
		if win:IsShown() then fn(id, win) end
	end
end

function Popout.CloseAll()
	for id in pairs(windows) do Popout.Close(id) end
end

function Popout.ApplyTheme()
	for _, win in pairs(windows) do win:ApplyTheme() end
end

function Popout.OnMessageAdded(conv, msg, index)
	local win = windows[conv.id]
	if win and win:IsShown() then win.view:OnMessageAdded(conv, msg, index) end
end

function Popout.OnMessageUpdated(conv, msg)
	local win = windows[conv.id]
	if win and win:IsShown() then win.view:OnMessageUpdated(conv, msg) end
end

function Popout.OnConversationUpdated(conv)
	local win = windows[conv.id]
	if win and win:IsShown() then win.view:OnConversationUpdated(conv) end
end
