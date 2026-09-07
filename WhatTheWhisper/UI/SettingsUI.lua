-- WhatTheWhisper -- Settings window.
--
-- Renders the declarative schema from Core/Options.lua: navigation on the left,
-- cards on the right, one control per row. Appearance changes apply live to the
-- messenger behind the panel, so you can see what a slider does while you drag
-- it rather than closing the window to find out.

local _, ns = ...
local Theme, W, Anim, Pool, Text = ns.Theme, ns.Widgets, ns.Anim, ns.Pool, ns.Text
local Options, Controls = ns.Options, ns.Controls
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local SettingsUI = {}
ns.SettingsUI = SettingsUI

local max, min = math.max, math.min

local ROW_H = 34
local ROW_GAP = ns.S.SM
local CARD_PAD = ns.S.LG
local CARD_GAP = ns.S.XL
local CONTROL_W = 190
-- The section label sits above its card, the way settings panes in modern
-- desktop apps do. Inside the card it competed with the first row's label,
-- which reads as two headings for the same thing.
local SECTION_H = 22

local frame, schema, activeCategory

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

local function createNavRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ns.SZ.SETTINGS_ROW_H)
	row.surface = W.Surface(row, { radius = ns.R.MD, insets = { ns.S.SM, ns.S.SM, 0, 0 } })
	row.accent = CreateFrame("Frame", nil, row)
	row.accent:SetWidth(3)
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -6)
	row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 6)
	row.accent.surface = W.Surface(row.accent, { color = "accent", radius = 1.5, layer = "ARTWORK" })
	row.accent:Hide()
	row.icon = W.Icon(row, "dot", ns.SZ.ICON_GLYPH_SM, "textMuted")
	row.icon:SetPoint("LEFT", row, "LEFT", ns.S.LG, 0)
	row.label = W.Text(row, "SMALL", "textSecondary")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", ns.S.MD, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -ns.S.MD, 0)

	W.MakeInteractive(row, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role = (state == "selected" and "selected")
			or ((state == "hover" or state == "pressed") and "hover") or nil
		W.FadeSurfaceTo(row.surface, row, role, duration)
		row.accent:SetShown(state == "selected")
		W.SetTextRole(row.label, state == "selected" and "textPrimary" or "textSecondary")
		W.SetIconRole(row.icon, state == "selected" and "accent" or "textMuted")
	end)
	row:HookScript("OnMouseUp", function(self)
		if self:IsMouseOver() and self.categoryID then
			SettingsUI.SelectCategory(self.categoryID)
		end
	end)
	return row
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function createRowFrame(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.label = W.Text(row, "SMALL", "textPrimary")
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	row.caption = W.Text(row, "MICRO", "textMuted")
	row.caption:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
	row.caption:SetJustifyV("TOP")
	row.caption:SetWordWrap(true)
	return row
end

local function resetRowFrame(_, row)
	row:Hide()
	row:ClearAllPoints()
	row.spec = nil
	if row.control then
		row.control:Hide()
		row.control = nil
	end
end

--------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------

local function createCard(parent)
	local card = CreateFrame("Frame", nil, parent)
	card.surface = W.Surface(card, { color = "bg3", border = "borderSubtle", radius = ns.R.LG })
	card.title = W.Text(card, "SMALL", "textMuted")
	card.title:SetPoint("BOTTOMLEFT", card, "TOPLEFT", 2, ns.S.SM)
	return card
end

local function resetCard(_, card)
	card:Hide()
	card:ClearAllPoints()
end

--------------------------------------------------------------------------------
-- Control factory
--------------------------------------------------------------------------------

local controlPools = {}

local function acquireControl(kind, parent, factory)
	local pool = controlPools[kind]
	if not pool then
		pool = Pool.New(function() return factory(parent) end, function(_, control)
			control:Hide()
			control:ClearAllPoints()
			-- The schema is rebuilt on every open; a pooled control must not
			-- pin the previous one.
			control.spec = nil
		end)
		controlPools[kind] = pool
	end
	return pool:Acquire()
end

local function readValue(spec)
	local value = Options.Get(spec.path)
	if spec.invert then return not value end
	return value
end

local function writeValue(spec, value)
	if spec.invert then value = not value end
	Options.Set(spec.path, value)
end

-- Controls are pooled, so a callback cannot close over the spec it was built
-- for. Each factory instead reads control.spec, which Refresh sets every time
-- the control is handed out.
local factories = {}

function factories.toggle(parent)
	local control
	control = Controls.Toggle(parent, {
		onChange = function(value)
			if control and control.spec then
				writeValue(control.spec, value)
				SettingsUI.RefreshSoon()
			end
		end,
	})
	return control
end

function factories.slider(parent)
	local control
	control = Controls.Slider(parent, {
		format = function(value)
			-- Called once during construction, before `control` is assigned.
			local spec = control and control.spec
			return spec and spec.format and spec.format(value) or tostring(value)
		end,
		onChange = function(value)
			if control and control.spec then Options.Set(control.spec.path, value) end
		end,
	})
	return control
end

function factories.dropdown(parent)
	local control
	control = Controls.Dropdown(parent, {
		onChange = function(value)
			if control and control.spec then
				writeValue(control.spec, value)
				SettingsUI.RefreshSoon()
			end
		end,
	})
	return control
end

function factories.button(parent)
	local control
	control = ns.Button.Text(parent, {
		text = "", variant = "subtle", minWidth = 150, autoWidth = false,
		onClick = function()
			local spec = control and control.spec
			if spec and spec.onClick then ns.Guard("Settings.button", spec.onClick) end
		end,
	})
	control:SetWidth(CONTROL_W)
	return control
end

function factories.input(parent)
	local control
	control = ns.Input.New(parent, {
		minHeight = 26, fontToken = "MICRO", radius = ns.R.SM,
		onChange = function(value)
			if control and control.spec then Options.Set(control.spec.path, value) end
		end,
	})
	return control
end

function factories.color(parent)
	local swatch = CreateFrame("Frame", nil, parent)
	swatch:SetSize(46, 22)
	swatch.surface = W.Surface(swatch, { border = "borderStrong", radius = ns.R.SM })
	W.MakeInteractive(swatch, function(state)
		swatch:SetAlpha(state == "hover" and 0.85 or 1)
	end)
	swatch:HookScript("OnMouseUp", function(self)
		local spec = self.spec
		if not self:IsMouseOver() or not spec then return end
		local current = Options.Get(spec.path) or Theme.Get(spec.defaultRole or "accent")
		local function commit(r, g, b)
			Options.Set(spec.path, { r, g, b })
			SettingsUI.RefreshSoon()
		end
		ns.Compat.ShowColorPicker(current[1], current[2], current[3], 1, commit, commit)
	end)
	function swatch:ApplyTheme()
		swatch.surface:ApplyTheme()
	end
	return swatch
end

function factories.info(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(CONTROL_W, 20)
	holder.text = W.Text(holder, "MICRO", "textSecondary")
	holder.text:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	holder.text:SetJustifyH("RIGHT")
	function holder:ApplyTheme() W.RefreshText(holder.text) end
	return holder
end

local function buildControl(spec, parent)
	local factory = factories[spec.type]
	if not factory then return nil end
	local control = acquireControl(spec.type, parent, factory)
	control:SetParent(parent)
	control.spec = spec

	if spec.type == "toggle" then
		control:SetValue(readValue(spec) and true or false, false)
	elseif spec.type == "slider" then
		control.minValue, control.maxValue, control.step = spec.minValue, spec.maxValue, spec.step
		control:SetWidth(CONTROL_W)
		control:SetValue(tonumber(readValue(spec)) or spec.minValue, false)
	elseif spec.type == "dropdown" then
		control:SetWidth(CONTROL_W)
		control:SetOptions(spec.options)
		control:SetValue(readValue(spec), false)
	elseif spec.type == "button" then
		control:SetText(spec.buttonText or spec.label)
		control:SetVariant(spec.danger and "danger" or "subtle")
	elseif spec.type == "input" then
		control:SetWidth(CONTROL_W)
		control:SetText(Options.Get(spec.path) or "")
	elseif spec.type == "color" then
		local value = Options.Get(spec.path) or Theme.Get(spec.defaultRole or "accent")
		control.surface:SetColorOverride(value[1], value[2], value[3], 1)
	elseif spec.type == "info" then
		control:SetWidth(CONTROL_W)
		control.text:SetText(spec.value and spec.value() or "")
	end
	return control
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function build()
	if frame then return frame end

	frame = CreateFrame("Frame", "WhatTheWhisperSettings", UIParent)
	frame:SetSize(ns.SZ.SETTINGS_W, ns.SZ.SETTINGS_H)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame.surface = W.Surface(frame, {
		color = "bg0", border = "borderSubtle", radius = ns.R.LG, shadow = 18,
	})

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(ns.SZ.TITLEBAR_H + 6)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:EnableMouse(true)
	header.divider = W.Hairline(header, "horizontal", { anchor = "BOTTOM", color = "borderSubtle" })
	W.MakeWindowHandle(header, {
		onStartMove = function() frame:StartMoving() frame.moving = true end,
		onStopMove = function()
			if frame.moving then frame.moving = false frame:StopMovingOrSizing() end
		end,
	})
	frame.header = header

	header.title = W.Text(header, "TITLE", "textPrimary")
	header.title:SetPoint("LEFT", header, "LEFT", ns.S.LG, 0)
	header.title:SetText(L["Settings"])

	header.close = ns.Button.Icon(header, {
		icon = "close", size = 26, glyph = 13, onClick = function() SettingsUI.Hide() end,
	})
	header.close:SetPoint("RIGHT", header, "RIGHT", -ns.S.SM, 0)

	-- Navigation column
	local nav = CreateFrame("Frame", nil, frame)
	nav:SetWidth(ns.SZ.SETTINGS_NAV_W)
	nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	nav:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
	nav.surface = W.Surface(nav, { color = "bg1" })
	nav.divider = W.Hairline(nav, "vertical", { anchor = "RIGHT", color = "borderSubtle" })
	frame.nav = nav

	nav.search = Controls.SearchBox(nav, {
		placeholder = L["Search settings"], height = 28,
		onChange = function(value) SettingsUI.SetFilter(value) end,
	})
	nav.search:SetPoint("TOPLEFT", nav, "TOPLEFT", ns.S.MD, -ns.S.MD)
	nav.search:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -ns.S.MD, -ns.S.MD)

	nav.rows = {}

	-- Content column
	local content = ns.Scroll.New(frame, { barInset = ns.S.SM })
	content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	content.OnScrollChanged = function() SettingsUI.Reflow() end
	frame.content = content

	frame.cardPool = Pool.New(function() return createCard(content.viewport) end, resetCard)
	frame.rowPool = Pool.New(function() return createRowFrame(content.viewport) end, resetRowFrame)

	frame:HookScript("OnSizeChanged", function() SettingsUI.Refresh() end)

	if type(_G.UISpecialFrames) == "table" then
		local found
		for i = 1, #_G.UISpecialFrames do
			if _G.UISpecialFrames[i] == "WhatTheWhisperSettings" then found = true break end
		end
		if not found then table.insert(_G.UISpecialFrames, "WhatTheWhisperSettings") end
	end

	return frame
end

--------------------------------------------------------------------------------
-- Navigation rendering
--------------------------------------------------------------------------------

local function renderNav()
	local nav = frame.nav
	for i = 1, #nav.rows do nav.rows[i]:Hide() end

	local y = -(ns.S.MD + 28 + ns.S.MD)
	for i = 1, #schema do
		local category = schema[i]
		local row = nav.rows[i]
		if not row then
			row = createNavRow(nav)
			nav.rows[i] = row
		end
		row.categoryID = category.id
		row.label:SetText(category.label)
		ns.Draw.SetIcon(row.icon, category.icon or "dot")
		row.icon.__wtwIcon = category.icon or "dot"
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, y)
		row:SetSelectedState(category.id == activeCategory)
		row:Show()
		y = y - ns.SZ.SETTINGS_ROW_H - 2
	end
end

--------------------------------------------------------------------------------
-- Content rendering
--------------------------------------------------------------------------------

local function rowMatchesFilter(spec, filter)
	if not filter or filter == "" then return true end
	return Text.Contains(spec.label, filter) or Text.Contains(spec.caption, filter)
end

function SettingsUI.Refresh()
	if not frame or not frame:IsShown() then return end
	frame.cardPool:ReleaseAll()
	frame.rowPool:ReleaseAll()
	for _, pool in pairs(controlPools) do pool:ReleaseAll() end

	local category
	for i = 1, #schema do
		if schema[i].id == activeCategory then category = schema[i] break end
	end
	if not category then return end

	local viewport = frame.content.viewport
	local available = min(ns.SZ.SETTINGS_MAX_CONTENT,
		(viewport:GetWidth() or 600) - ns.S.XXL * 2)
	local left = max(ns.S.XL, ((viewport:GetWidth() or 600) - available) / 2)
	local filter = frame.filter

	local y = ns.S.XL
	for c = 1, #category.cards do
		local cardSpec = category.cards[c]

		local rows = {}
		for r = 1, #cardSpec.rows do
			if rowMatchesFilter(cardSpec.rows[r], filter) then
				rows[#rows + 1] = cardSpec.rows[r]
			end
		end
		if #rows > 0 then
			local card = frame.cardPool:Acquire()
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", viewport, "TOPLEFT", left,
				-(y + SECTION_H - frame.content:GetOffset()))
			card:SetWidth(available)
			card.title:SetText(cardSpec.title or "")

			local rowY = CARD_PAD
			for r = 1, #rows do
				local spec = rows[r]
				local row = frame.rowPool:Acquire()
				row.spec = spec
				row:SetParent(card)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -rowY)
				row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -rowY)

				row.label:SetText(spec.label or "")
				local labelWidth = available - CARD_PAD * 2 - CONTROL_W - ns.S.LG
				row.label:SetWidth(max(60, labelWidth))
				row.caption:SetWidth(max(60, labelWidth))
				row.caption:SetText(spec.caption or "")
				row.caption:SetShown((spec.caption or "") ~= "")

				local control = buildControl(spec, card)
				row.control = control
				if control then
					control:ClearAllPoints()
					control:SetPoint("RIGHT", row, "RIGHT", 0, 0)
					control:Show()
				end

				local height = ROW_H
				if (spec.caption or "") ~= "" then
					height = max(height, 20 + (row.caption:GetStringHeight() or 12) + 6)
				end
				row:SetHeight(height)
				row:Show()
				rowY = rowY + height + ROW_GAP
			end

			local cardHeight = rowY - ROW_GAP + CARD_PAD
			card:SetHeight(cardHeight)
			card.surface:Layout()
			card:Show()
			y = y + SECTION_H + cardHeight + CARD_GAP
		end
	end

	frame.content:SetContentHeight(y + ns.S.XL, false)
end

function SettingsUI.Reflow()
	SettingsUI.Refresh()
end

-- Re-rendering from inside a control's own callback would release that control
-- while it is still running, so the refresh is deferred by one frame.
function SettingsUI.RefreshSoon()
	if SettingsUI.refreshPending then return end
	SettingsUI.refreshPending = true
	Anim.After(0, function()
		SettingsUI.refreshPending = false
		SettingsUI.Refresh()
	end)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function SettingsUI.SelectCategory(id)
	activeCategory = id
	frame.content:ScrollToTop(false)
	renderNav()
	SettingsUI.Refresh()
end

function SettingsUI.SetFilter(value)
	frame.filter = value
	SettingsUI.Refresh()
end

function SettingsUI.Show()
	build()
	schema = Options.BuildSchema()
	activeCategory = activeCategory or schema[1].id
	frame:Show()
	renderNav()
	SettingsUI.Refresh()
	Anim.PopIn(frame, Theme.Duration("WINDOW"), 0.98)
end

function SettingsUI.Hide()
	if frame then frame:Hide() end
end

function SettingsUI.Toggle()
	if frame and frame:IsShown() then
		SettingsUI.Hide()
	else
		SettingsUI.Show()
	end
end

function SettingsUI.IsShown()
	return frame and frame:IsShown()
end

function SettingsUI.ApplyTheme()
	if not frame then return end
	frame.surface:ApplyTheme()
	frame.header.divider:ApplyTheme()
	W.RefreshText(frame.header.title)
	frame.header.close:ApplyTheme()
	frame.nav.surface:ApplyTheme()
	frame.nav.divider:ApplyTheme()
	frame.nav.search:ApplyTheme()
	for i = 1, #frame.nav.rows do
		local row = frame.nav.rows[i]
		row.surface:ApplyTheme()
		row.accent.surface:ApplyTheme()
		W.RefreshText(row.label)
		W.RefreshIcon(row.icon)
	end
	frame.content:ApplyTheme()
	for _, pool in pairs(controlPools) do
		for control in pool:EnumerateActive() do
			if control.ApplyTheme then control:ApplyTheme() end
		end
		for _, control in ipairs(pool.free) do
			if control.ApplyTheme then control:ApplyTheme() end
		end
	end
	if frame:IsShown() then SettingsUI.Refresh() end
end
