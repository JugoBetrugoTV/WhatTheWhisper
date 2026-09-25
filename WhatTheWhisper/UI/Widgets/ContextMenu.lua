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
-- an explanation instead of silently doing nothing, and the secure button is
-- taken down by the secure environment itself (see ensureSecureButton).

local _, ns = ...
local Theme, W, Anim, Pool = ns.Theme, ns.Widgets, ns.Anim, ns.Pool

local Menu = {}
ns.Menu = Menu

local max = math.max

local frame, catcher, itemPool, secureButton, secureHost

-- The size a menu entry is drawn at, named once. The width of the panel is
-- worked out by measuring the entries, and that measurement has to be taken at
-- the size they are actually set in: it was taken at SMALL while the rows drew
-- at BODY, so every menu came out about a sixth too narrow -- invisible at the
-- default font size and, three steps up, two entries wrapping into each other.
local ITEM_FONT = "BODY"

-- Comfortable room around the entry's text, never less than the design's row
-- height. Like everything else here it follows the font rather than fixing it.
local function itemHeight()
	return math.max(ns.SZ.MENU_ITEM_H, math.ceil(Theme.FontSize(ITEM_FONT)) + ns.S.MD)
end
-- The panel's own padding above the first item and below the last, and the
-- inset an item's hover wash is drawn with inside that. Both come off the
-- spacing scale rather than being the two numbers that happened to look right.
local PAD_Y = ns.S.SM
local ITEM_INSET = ns.S.XS
-- The label leads and the mark trails, which is the way round iOS and macOS set
-- a menu: you read what the entry does, and the icon is there to recognise it by
-- once you know. Icon-first is the Windows and Android arrangement, and it makes
-- every menu a column of symbols with words after them.
local LABEL_X = ns.S.MD + ITEM_INSET
local ICON_PAD = ns.S.MD + ITEM_INSET
-- The gap kept between the longest label and the mark beyond it.
local LABEL_ICON_GAP = ns.S.LG
local SEP_H = ns.S.MD

--------------------------------------------------------------------------------
-- Item construction
--------------------------------------------------------------------------------

local function createItem()
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(itemHeight())
	row.surface = W.Surface(row, {
		radius = ns.R.MD, insets = { ITEM_INSET, ITEM_INSET, 0, 0 },
	})
	row.icon = W.Icon(row, "bullet", ns.SZ.MENU_ICON, "textSecondary")
	row.icon:SetPoint("RIGHT", row, "RIGHT", -ICON_PAD, 0)
	row.label = W.Text(row, ITEM_FONT, "textPrimary")
	-- One line. A menu entry that wraps is an entry printed over the one below
	-- it: the rows are a fixed height and the panel is sized to hold them all.
	row.label:SetWordWrap(false)
	row.label:SetJustifyH("LEFT")
	row.label:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
	row.label:SetPoint("RIGHT", row.icon, "LEFT", -ns.S.SM, 0)

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
	row.entry = nil
	row.danger = nil
	row.secure = nil
	row.isSeparator = nil
	row.__wtwTooltip = nil
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

-- The secure button sits on a host of its own, and neither of them is tied to
-- the menu. Blizzard's rule is that "control restrictions on protected frames
-- are also applied to their parents and any frames they are anchored to": had
-- the host been a child of the menu, or anchored to a row, a menu that was open
-- when combat started could no longer be closed, hidden or re-laid out by addon
-- code at all -- every one of those calls would be blocked.
--
-- So the host hangs off UIParent, is placed by absolute coordinates copied from
-- the row, and is itself a SecureHandlerStateTemplate with a combat state
-- driver: the moment combat starts, the secure environment hides it. Nothing in
-- addon code has to reach for it in combat, and nothing does -- it is only ever
-- shown, moved or given a macro outside combat.
local function ensureSecureButton()
	if secureButton then return secureButton end
	secureHost = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
	secureHost:SetFrameStrata(frame:GetFrameStrata())
	secureHost:Hide()
	secureHost:SetAttribute("_onstate-combat", [[
		if newstate == "on" then self:Hide() end
	]])
	RegisterStateDriver(secureHost, "combat", "[combat] on; off")
	secureButton = CreateFrame("Button", "WhatTheWhisperSecureTarget", secureHost,
		"SecureActionButtonTemplate")
	secureButton:RegisterForClicks("AnyUp")
	secureButton:SetAllPoints(secureHost)
	secureButton:SetAttribute("type", "macro")
	secureButton:HookScript("OnClick", function() Menu.Close() end)
	return secureButton
end

-- The entry as it looks when it cannot act: greyed out, with a tooltip that
-- says why rather than a click that silently does nothing.
local function showBlocked(row)
	row:SetEnabled(false)
	row.secure = nil
	W.SetTextRole(row.label, "textDisabled")
	W.SetIconRole(row.icon, "textDisabled")
	W.SetTooltip(row, row.entry and (row.entry.combatTooltip or row.entry.tooltip))
end

local function attachSecure(row, macroText)
	-- SetAttribute is forbidden in combat.
	if InCombatLockdown() then return false end
	local btn = ensureSecureButton()
	-- The row's rectangle, in the host's own coordinate space (UIParent's).
	local left, bottom, width, height = row:GetLeft(), row:GetBottom(), row:GetWidth(), row:GetHeight()
	if not (left and bottom) then return false end
	local k = row:GetEffectiveScale() / secureHost:GetEffectiveScale()
	secureHost:ClearAllPoints()
	secureHost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * k, bottom * k)
	secureHost:SetSize(width * k, height * k)
	secureHost:SetFrameLevel(row:GetFrameLevel() + 2)
	btn:SetAttribute("type", "macro")
	btn:SetAttribute("macrotext", macroText)
	btn:SetScript("OnEnter", function() row.__wtwHover = true row.UpdateVisualState() end)
	btn:SetScript("OnLeave", function() row.__wtwHover = false row.UpdateVisualState() end)
	secureHost:Show()
	row.secure = true
	return true
end

-- Combat started with the menu open: the state driver has taken the button
-- away, so the entry must stop looking as if it could still be clicked.
local function onCombatChanged(inCombat)
	if not (inCombat and itemPool and Menu.IsOpen()) then return end
	for row in itemPool:EnumerateActive() do
		if row.secure then showBlocked(row) end
	end
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
	-- A panel floating over the window: raised surface, soft corners, a shadow,
	-- and the faintest possible edge so it still has a boundary on a light
	-- theme where the shadow alone would not give it one.
	frame.surface = W.Surface(frame, {
		color = "bg3", border = "borderSubtle", radius = ns.R.LG, shadow = 18,
	})
	frame:HookScript("OnHide", function()
		if not Menu.closing then Menu.Close() end
	end)

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

	itemPool = Pool.New(createItem, resetItem, "menu.item")
	ns.Bus.Register(ns.EV.COMBAT_STATE_CHANGED, "ContextMenu", onCombatChanged)
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

	local measure = Theme.Measure(ITEM_FONT)
	local width = opts.minWidth or ns.SZ.MENU_MIN_W
	local height = PAD_Y * 2
	local shown = {}

	for i = 1, #entries do
		local entry = entries[i]
		if entry.separator and not entry.hidden then
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
		elseif not entry.hidden then
			local row = itemPool:Acquire()
			row:SetHeight(itemHeight())
			row.danger = entry.danger
			row.onClick = entry.onClick
			-- A row may be written in a script the theme font cannot draw; the
			-- language picker is the one place that happens.
			W.SetTextFont(row.label, entry.font)
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
			W.SetTextFont(measure, entry.font)
			measure:SetText(entry.text or "")
			-- The label's own width, the padding either side of it, and the room
			-- the trailing mark needs. Reserved whether or not this entry has a
			-- mark: a menu whose width depends on which of its rows carry icons
			-- is a menu that changes width when an entry is hidden.
			width = max(width, measure:GetStringWidth() + LABEL_X + LABEL_ICON_GAP
				+ ns.SZ.MENU_ICON + ICON_PAD)

			shown[#shown + 1] = row
			height = height + itemHeight()
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
		row:SetHeight(row.isSeparator and SEP_H or itemHeight())
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
			if not attachSecure(row, row.entry.secureMacro) then showBlocked(row) end
		end
	end

	Anim.SlideIn(frame, 0, 4, Theme.Duration("FAST"))
end

function Menu.Close()
	if not frame then return end
	-- In combat the host is already down -- its state driver saw to that -- and
	-- addon code may not touch it; out of combat it is put away here.
	if secureHost and not InCombatLockdown() then
		secureHost:Hide()
		secureButton:SetScript("OnEnter", nil)
		secureButton:SetScript("OnLeave", nil)
	end
	if itemPool then itemPool:ReleaseAll() end
	catcher:Hide()
	Anim.StopAll(frame)
	-- A guard rather than clearing the script. SetScript("OnHide", nil) removes
	-- every handler on that frame, hooks included, and the drop shadow follows
	-- its window by hooking exactly this -- so wiping it left the shadow of a
	-- closed menu sitting on the screen.
	Menu.closing = true
	frame:Hide()
	Menu.closing = false
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
