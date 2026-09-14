-- WhatTheWhisper -- Settings window.
--
-- Renders the declarative schema from Core/Options.lua: navigation on the left,
-- cards on the right, one control per row. Appearance changes apply live to the
-- messenger behind the panel, so you can see what a slider does while you drag
-- it rather than closing the window to find out.

local _, ns = ...
local Theme, W, Anim, Pool, Text = ns.Theme, ns.Widgets, ns.Anim, ns.Pool, ns.Text
local Options, Controls = ns.Options, ns.Controls
local L = ns.L

local SettingsUI = {}
ns.SettingsUI = SettingsUI

local max, min = math.max, math.min

-- Rows inside a group touch, the way they do in a native settings pane, and are
-- told apart by a hairline rather than by a gap. Gaps between rows inside a card
-- make each row look like its own card, which is the box-inside-a-box problem
-- one level further down.
local ROW_H = ns.SZ.SETTINGS_ROW_H
local ROW_GAP = 0
local CARD_PAD = ns.S.LG
-- Vertical padding is smaller than horizontal: the first and last rows already
-- carry their own height, so a full CARD_PAD above them would read as a gap the
-- rows between them do not have.
local CARD_PAD_Y = ns.S.XS
local CARD_GAP = ns.SZ.SETTINGS_GROUP_GAP
-- How much of a settings row the control on the right may take. Wide enough
-- for four segments to be readable, which is the widest control here.
local CONTROL_W = ns.SZ.SEGMENT_MIN_W * 3 + ns.S.XXL
-- The section label sits above its card, the way settings panes in modern
-- desktop apps do. Inside the card it competed with the first row's label,
-- which reads as two headings for the same thing.
local SECTION_H = ns.T.SMALL + ns.S.SM
-- The settings search box, and the gap between navigation rows. Both were bare
-- numbers written twice: the box height had to match the one passed to
-- SearchBox, and nothing said so.
local NAV_SEARCH_H = ns.SZ.SEARCH_H - ns.S.XS
local NAV_ROW_GAP = 2

local frame, schema, activeCategory

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

-- A destination in the category list: a glyph, a label, and a quiet filled pill
-- when it is the one you are looking at. No marker bar down the side -- the
-- selected row is already a different surface, and the bar was the one thing in
-- the settings pane that could only have come from a game addon.
local function createNavRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ns.SZ.SETTINGS_NAV_ROW_H)
	row.surface = W.Surface(row, { radius = ns.R.MD, insets = { ns.S.SM, ns.S.SM, 0, 0 } })
	row.icon = W.Icon(row, "bullet", ns.SZ.ICON_GLYPH_SM, "textSecondary")
	row.icon:SetPoint("LEFT", row, "LEFT", ns.S.LG, 0)
	row.label = W.Text(row, "BODY", "textSecondary")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", ns.S.MD, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -ns.S.MD, 0)

	W.MakeInteractive(row, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role = (state == "selected" and "selected")
			or ((state == "hover" or state == "pressed") and "hover") or nil
		W.FadeSurfaceTo(row.surface, row, role, duration)
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
	-- The label is the row's voice, so it is set at body size like everything
	-- else a person reads rather than at the smaller size a control label used
	-- to get. The description under it steps down one level, not two.
	row.label = W.Text(row, "BODY", "textPrimary")
	row.caption = W.Text(row, "SMALL", "textMuted")
	row.caption:SetJustifyV("TOP")
	row.caption:SetWordWrap(true)
	-- Between this row and the next one in the same group. Indented to the
	-- label, so the group reads as a column of rows rather than a table.
	row.separator = W.Hairline(row, "horizontal", {
		anchor = "BOTTOM", color = "borderSubtle",
	})
	return row
end

local function resetRowFrame(_, row)
	row:Hide()
	row:ClearAllPoints()
	row.spec = nil
	row.separator:SetShown(false)
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
	-- A raised surface and nothing else. The outline round a card that is already
	-- lighter than the panel behind it adds a line and no information.
	card.surface = W.Surface(card, { color = "bg3", radius = ns.R.LG })
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
		end, "settings.control." .. tostring(kind))
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

-- A dropdown with few enough short options is built as a row of segments
-- instead, so the choice is readable without opening anything. The rule lives
-- here rather than in the schema because it is a presentation decision: the
-- schema says "one of these values", and how many of them fit side by side is
-- not something a settings author should have to think about.
local SEGMENT_MAX_OPTIONS = 4
local SEGMENT_MAX_LABEL = 14

local function suitsSegments(spec)
	local options = spec.options
	if type(options) ~= "table" then return false end
	if #options < 2 or #options > SEGMENT_MAX_OPTIONS then return false end
	for i = 1, #options do
		local label = options[i].label
		if type(label) ~= "string" or #label > SEGMENT_MAX_LABEL then return false end
	end
	return true
end

function factories.segmented(parent)
	local control
	control = Controls.Segmented(parent, {
		options = {},
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
	-- One schema entry, two possible controls. `kind` is what is actually built;
	-- `spec.type` stays what the schema said, because every other consumer of
	-- the schema -- search, the audit, the row layout -- reasons about the
	-- declared type and not about how it happened to be rendered.
	local kind = spec.type
	if kind == "dropdown" and suitsSegments(spec) then kind = "segmented" end

	local factory = factories[kind]
	if not factory then return nil end
	local control = acquireControl(kind, parent, factory)
	control:SetParent(parent)
	control.spec = spec

	if kind == "segmented" then
		control:SetWidth(CONTROL_W)
		control:SetOptions(spec.options)
		control:SetValue(readValue(spec), false)
	elseif spec.type == "toggle" then
		control:SetValue(readValue(spec) and true or false, false)
	elseif spec.type == "slider" then
		-- Width first, then the range, then the value: every one of those is an
		-- input to where the thumb sits, and the control lays itself out on each.
		control:SetWidth(CONTROL_W)
		control:SetRange(spec.minValue, spec.maxValue, spec.step)
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
		icon = "close", size = ns.SZ.ICON_BTN_SM, glyph = ns.SZ.ICON_GLYPH_SM,
		onClick = function() SettingsUI.Hide() end,
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
		placeholder = L["Search settings"], height = NAV_SEARCH_H,
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

	-- Sits over the scroll viewport rather than inside it: it is not content, it
	-- is the absence of content, and it should not scroll away from the player.
	local empty = CreateFrame("Frame", nil, frame)
	empty:SetPoint("TOPLEFT", content, "TOPLEFT")
	empty:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
	empty:Hide()
	frame.empty = empty
	frame.emptyIcon = W.Icon(empty, "search", ns.SZ.EMPTY_ICON, "textMuted")
	frame.emptyIcon:SetPoint("CENTER", empty, "CENTER", 0, ns.S.XXL)
	frame.emptyIcon:SetAlpha(0.22)
	frame.emptyTitle = W.Text(empty, "BODY", "textSecondary")
	frame.emptyTitle:ClearAllPoints()
	frame.emptyTitle:SetPoint("TOP", frame.emptyIcon, "BOTTOM", 0, -ns.S.LG)
	frame.emptyTitle:SetJustifyH("CENTER")
	frame.emptyTitle:SetWidth(ns.SZ.EMPTY_TEXT_W)
	frame.emptyBody = W.Text(empty, "SMALL", "textMuted")
	frame.emptyBody:ClearAllPoints()
	frame.emptyBody:SetPoint("TOP", frame.emptyTitle, "BOTTOM", 0, -ns.S.SM)
	frame.emptyBody:SetJustifyH("CENTER")
	frame.emptyBody:SetWidth(ns.SZ.EMPTY_TEXT_W)

	frame.cardPool = Pool.New(function() return createCard(content.viewport) end, resetCard, "settings.card")
	frame.rowPool = Pool.New(function() return createRowFrame(content.viewport) end, resetRowFrame, "settings.row")

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

	local y = -(ns.S.MD + NAV_SEARCH_H + ns.S.MD)
	for i = 1, #schema do
		local category = schema[i]
		local row = nav.rows[i]
		if not row then
			row = createNavRow(nav)
			nav.rows[i] = row
		end
		row.categoryID = category.id
		row.label:SetText(category.label)
		ns.Draw.SetIcon(row.icon, category.icon or "bullet")
		row.icon.__wtwIcon = category.icon or "bullet"
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, y)
		row:SetSelectedState(category.id == activeCategory)
		row:Show()
		y = y - ns.SZ.SETTINGS_NAV_ROW_H - NAV_ROW_GAP
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

	local viewport = frame.content.viewport
	local available = min(ns.SZ.SETTINGS_MAX_CONTENT,
		(viewport:GetWidth() or 600) - ns.S.XXL * 2)
	local left = max(ns.S.XL, ((viewport:GetWidth() or 600) - available) / 2)
	local filter = frame.filter
	local searching = filter ~= nil and filter ~= ""

	-- Searching looks everywhere. Filtering only the category the player happens
	-- to be standing in meant typing "sound" while on Appearance found nothing,
	-- and the box gave no hint that the answer was one click away.
	local categories = {}
	if searching then
		for i = 1, #schema do categories[#categories + 1] = schema[i] end
	else
		for i = 1, #schema do
			if schema[i].id == activeCategory then categories[1] = schema[i] break end
		end
	end
	if #categories == 0 then return end

	local y = ns.S.XL
	local shownRows = 0
	for k = 1, #categories do
	local category = categories[k]
	for c = 1, #category.cards do
		local cardSpec = category.cards[c]

		local rows = {}
		for r = 1, #cardSpec.rows do
			if rowMatchesFilter(cardSpec.rows[r], filter) then
				rows[#rows + 1] = cardSpec.rows[r]
			end
		end
		if #rows > 0 then
			shownRows = shownRows + #rows
			local card = frame.cardPool:Acquire()
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", viewport, "TOPLEFT", left,
				-(y + SECTION_H - frame.content:GetOffset()))
			card:SetWidth(available)
			-- While searching, a card has to say which category it came from or
			-- the results are a list of headings with no context.
			card.title:SetText(searching
				and ((category.label or "") .. " \194\183 " .. (cardSpec.title or ""))
				or (cardSpec.title or ""))

			local rowY = CARD_PAD_Y
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
				local hasCaption = (spec.caption or "") ~= ""
				row.caption:SetShown(hasCaption)

				local control = buildControl(spec, card)
				row.control = control
				if control then
					control:ClearAllPoints()
					control:SetPoint("RIGHT", row, "RIGHT", 0, 0)
					control:Show()
				end

				-- The label, or the label and its description, centred as one
				-- block against the control beside it. Anchoring the label to the
				-- row's top edge left a described row looking top-heavy next to
				-- an undescribed one.
				local labelH = row.label:GetStringHeight() or ns.T.BODY
				local captionH = hasCaption and (row.caption:GetStringHeight() or ns.T.SMALL) or 0
				local blockH = labelH + (hasCaption and (ns.S.XS / 2 + captionH) or 0)
				local height = max(ROW_H, blockH + ns.S.MD * 2)
				local top = (height - blockH) / 2

				row.label:ClearAllPoints()
				row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -top)
				row.caption:ClearAllPoints()
				row.caption:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -ns.S.XS / 2)

				row:SetHeight(height)
				row.separator:SetShown(r < #rows)
				row:Show()
				rowY = rowY + height + ROW_GAP
			end

			local cardHeight = rowY - ROW_GAP + CARD_PAD_Y
			card:SetHeight(cardHeight)
			card.surface:Layout()
			card:Show()
			y = y + SECTION_H + cardHeight + CARD_GAP
		end
	end
	end

	-- A search that finds nothing used to leave a blank panel, which reads as a
	-- broken window rather than an answer.
	frame.empty:SetShown(shownRows == 0)
	if shownRows == 0 then
		frame.emptyTitle:SetText(searching and L["No settings match your search"]
			or L["Nothing here yet"])
		frame.emptyBody:SetText(searching and L["Try a shorter word, or clear the search."] or "")
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

-- Read by the suite: whether the panel is currently showing its empty state,
-- and the pool the visible rows come from. Both are things the window already
-- knows and nothing else can see from outside.
function SettingsUI.IsEmptyShown()
	return frame ~= nil and frame.empty ~= nil and frame.empty:IsShown()
end

function SettingsUI.RowPool()
	return frame and frame.rowPool
end

function SettingsUI.Frame()
	return frame
end

function SettingsUI.SetFilter(value)
	frame.filter = value
	SettingsUI.Refresh()
end

-- Build the schema again, not just render it again. Every label, caption and
-- option in it was resolved when the window opened, so a plain refresh lays out
-- the same answers -- which is wrong after a language change, and wrong after a
-- setting that decides whether a row exists at all.
function SettingsUI.Rebuild()
	if not frame or not frame:IsShown() then return end
	schema = Options.BuildSchema()
	renderNav()
	SettingsUI.Refresh()
end

-- The player changed the language. Everything above, plus the window's own
-- chrome, which was written once when it was built.
function SettingsUI.Relocalize()
	if not frame then return end
	frame.header.title:SetText(L["Settings"])
	frame.nav.search.input:SetPlaceholder(L["Search settings"])
	SettingsUI.Rebuild()
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
		W.RefreshText(row.label)
		W.RefreshIcon(row.icon)
	end
	frame.content:ApplyTheme()
	W.RefreshIcon(frame.emptyIcon)
	W.RefreshText(frame.emptyTitle)
	W.RefreshText(frame.emptyBody)
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
