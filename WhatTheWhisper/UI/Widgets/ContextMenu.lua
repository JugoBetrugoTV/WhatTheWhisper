-- WhatTheWhisper -- Context menus.
--
-- Own implementation rather than UIDropDownMenu: that API is a well known taint
-- source, it cannot be styled, and its item frames leak across addons. This one
-- pools its rows, closes on any outside click or Escape, and styles destructive
-- entries differently.
--
-- One special case: "Target" cannot be done from insecure Lua at all, so that
-- entry is backed by a real SecureActionButton with a /target macro. Attributes
-- are only ever written outside combat; inside combat the entry is disabled with
-- an explanation instead of silently doing nothing.

local _, ns = ...
local Theme, W, Anim, Pool = ns.Theme, ns.Widgets, ns.Anim, ns.Pool

local Menu = {}
ns.Menu = Menu

local max = math.max

local frame, catcher, itemPool, secureButton
local items = {}
local currentItems

local ITEM_H = ns.SZ.MENU_ITEM_H
local PAD_Y = 6
local ICON_X = 10
local LABEL_X = ICON_X + ns.SZ.MENU_ICON + ns.S.SM
local SEP_H = 9

--------------------------------------------------------------------------------
-- Item construction
--------------------------------------------------------------------------------

local function createItem()
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(ITEM_H)
	row.surface = W.Surface(row, { radius = ns.R.SM, insets = { 4, 4, 0, 0 } })
	row.icon = W.Icon(row, "dot", ns.SZ.MENU_ICON, "textSecondary")
	row.icon:SetPoint("LEFT", row, "LEFT", ICON_X, 0)
	row.label = W.Text(row, "SMALL", "textPrimary")
	row.label:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -ns.S.MD, 0)

	row.separator = row:CreateTexture(nil, "ARTWORK")
	row.separator:SetHeight(1)
	row.separator:SetPoint("LEFT", row, "LEFT", ns.S.SM, 0)
	row.separator:SetPoint("RIGHT", row, "RIGHT", -ns.S.SM, 0)
	row.separator:Hide()

	W.MakeInteractive(row, function(state, instant)
		if row.isSeparator or not row.__wtwEnabled then
			row.surface:SetColorOverride(0, 0, 0, 0)
			return
		end
		local role = (state == "pressed" and "pressed") or (state == "hover" and "hover") or nil
		if row.danger and role then
			local d = Theme.Get("danger")
			row.surface:SetColorOverride(d[1], d[2], d[3], state == "pressed" and 0.26 or 0.16)
		elseif role then
			W.FadeSurfaceTo(row.surface, row, role, instant and 0 or Theme.Duration("FAST"))
		else
			W.FadeSurfaceTo(row.surface, row, nil, instant and 0 or Theme.Duration("FAST"))
		end
	end)

	row:HookScript("OnMouseUp", function(self)
		if self.isSeparator or not self.__wtwEnabled or not self:IsMouseOver() then return end
		if self.secure then return end   -- the secure button handles its own click
		local onClick = self.onClick
		Menu.Close()
		if onClick then ns.Guard("Menu.onClick", onClick) end
	end)

	return row
end

local function resetItem(_, row)
	row:Hide()
	row:ClearAllPoints()
	row.onClick = nil
	row.danger = nil
	row.secure = nil
	row.isSeparator = nil
	row:SetSelectedState(false)
	row:SetEnabled(true)
	row.separator:Hide()
	row.icon:Show()
	row.label:Show()
	row.surface:SetColorOverride(0, 0, 0, 0)
end

--------------------------------------------------------------------------------
-- Secure "Target" support
--------------------------------------------------------------------------------

local function ensureSecureButton()
	if secureButton then return secureButton end
	secureButton = CreateFrame("Button", "WhatTheWhisperSecureTarget", frame,
		"SecureActionButtonTemplate")
	secureButton:RegisterForClicks("AnyUp")
	secureButton:SetAttribute("type", "macro")
	secureButton:Hide()
	secureButton:HookScript("OnClick", function() Menu.Close() end)
	return secureButton
end

local function attachSecure(row, macroText)
	if InCombatLockdown() then
		-- SetAttribute is forbidden in combat; say so rather than doing nothing.
		row:SetEnabled(false)
		row.blockedByCombat = true
		return false
	end
	local btn = ensureSecureButton()
	btn:SetParent(frame)
	btn:ClearAllPoints()
	btn:SetAllPoints(row)
	btn:SetFrameLevel(row:GetFrameLevel() + 2)
	btn:SetAttribute("type", "macro")
	btn:SetAttribute("macrotext", macroText)
	btn:SetScript("OnEnter", function() row.__wtwHover = true row.UpdateVisualState() end)
	btn:SetScript("OnLeave", function() row.__wtwHover = false row.UpdateVisualState() end)
	btn:Show()
	row.secure = true
	return true
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function build()
	if frame then return end

	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(50)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:Hide()
	catcher:SetScript("OnMouseDown", function() Menu.Close() end)

	frame = CreateFrame("Frame", "WhatTheWhisperContextMenu", UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(60)
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame.surface = W.Surface(frame, {
		color = "bg3", border = "borderStrong", radius = ns.R.MD, shadow = 16,
	})
	frame:SetScript("OnHide", function() Menu.Close() end)

	-- Escape closes it, exactly like every other panel in the game.
	if type(_G.UISpecialFrames) == "table" then
		local found
		for i = 1, #_G.UISpecialFrames do
			if _G.UISpecialFrames[i] == "WhatTheWhisperContextMenu" then found = true break end
		end
		if not found then
			table.insert(_G.UISpecialFrames, "WhatTheWhisperContextMenu")
		end
	end

	itemPool = Pool.New(createItem, resetItem)
end

--------------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------------

-- entries: array of
--   { text, icon, onClick, disabled, danger, checked, separator, secureMacro, tooltip }
-- opts: { anchorTo, point, relPoint, x, y, minWidth }
function Menu.Open(entries, opts)
	build()
	Menu.Close()
	opts = opts or {}
	currentItems = entries

	local measure = Theme.Measure("SMALL")
	local width = opts.minWidth or ns.SZ.MENU_MIN_W
	local height = PAD_Y * 2
	local shown = {}

	for i = 1, #entries do
		local entry = entries[i]
		if entry.hidden then
			-- skipped entirely
		elseif entry.separator then
			local row = itemPool:Acquire()
			row.isSeparator = true
			row:SetHeight(SEP_H)
			row.icon:Hide()
			row.label:Hide()
			local c = Theme.Get("borderSubtle")
			row.separator:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
			row.separator:SetHeight(ns.Pixel.Size(frame))
			row.separator:Show()
			row:SetEnabled(false)
			shown[#shown + 1] = row
			height = height + SEP_H
		else
			local row = itemPool:Acquire()
			row:SetHeight(ITEM_H)
			row.danger = entry.danger
			row.onClick = entry.onClick
			row.label:SetText(entry.text or "")
			W.SetTextRole(row.label, entry.danger and "danger"
				or (entry.disabled and "textDisabled") or "textPrimary")
			if entry.icon then
				ns.Draw.SetIcon(row.icon, entry.icon)
				row.icon.__wtwIcon = entry.icon
				W.SetIconRole(row.icon, entry.danger and "danger"
					or (entry.disabled and "textDisabled") or "textSecondary")
				row.icon:Show()
			else
				row.icon:Hide()
			end
			row:SetEnabled(not entry.disabled)
			if entry.tooltip then W.SetTooltip(row, entry.tooltip) else W.SetTooltip(row, nil) end

			measure:SetWidth(0)
			measure:SetText(entry.text or "")
			width = max(width, measure:GetStringWidth() + LABEL_X + ns.S.MD + ns.S.SM)

			shown[#shown + 1] = row
			height = height + ITEM_H
			row.entry = entry
		end
	end

	-- Layout
	local y = -PAD_Y
	for i = 1, #shown do
		local row = shown[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y)
		row:Show()
		y = y - row:GetHeight()
	end

	frame:SetSize(width, height)
	frame:ClearAllPoints()
	if opts.anchorTo then
		frame:SetPoint(opts.point or "TOPLEFT", opts.anchorTo,
			opts.relPoint or "BOTTOMLEFT", opts.x or 0, opts.y or -ns.S.XS)
	else
		local scale = UIParent:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
	end

	frame.surface:Layout()
	catcher:Show()
	frame:Show()

	-- Secure entries need the row's real position, so attach after layout.
	for i = 1, #shown do
		local row = shown[i]
		if row.entry and row.entry.secureMacro then
			if not attachSecure(row, row.entry.secureMacro) then
				W.SetTextRole(row.label, "textDisabled")
				W.SetIconRole(row.icon, "textDisabled")
				W.SetTooltip(row, row.entry.combatTooltip or row.entry.tooltip)
			end
		end
	end

	Anim.SlideIn(frame, 0, 4, Theme.Duration("FAST"))
	items = shown
end

function Menu.Close()
	if not frame then return end
	if secureButton and not InCombatLockdown() then
		secureButton:Hide()
		secureButton:ClearAllPoints()
		secureButton:SetScript("OnEnter", nil)
		secureButton:SetScript("OnLeave", nil)
	elseif secureButton then
		secureButton:Hide()
	end
	if itemPool then itemPool:ReleaseAll() end
	items = {}
	currentItems = nil
	catcher:Hide()
	Anim.StopAll(frame)
	frame:SetScript("OnHide", nil)
	frame:Hide()
	frame:SetScript("OnHide", function() Menu.Close() end)
	ns.Tooltip.Hide()
end

function Menu.IsOpen()
	return frame and frame:IsShown()
end

function Menu.ApplyTheme()
	if not frame then return end
	frame.surface:ApplyTheme()
	if itemPool then
		for row in itemPool:EnumerateActive() do
			row.surface:ApplyTheme()
			W.RefreshText(row.label)
			W.RefreshIcon(row.icon)
		end
		for _, row in ipairs(itemPool.free) do
			row.surface:ApplyTheme()
			W.RefreshText(row.label)
			W.RefreshIcon(row.icon)
		end
	end
end
