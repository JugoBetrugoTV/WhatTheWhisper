-- WhatTheWhisper -- Badges, toggles, sliders, dropdowns and the search field.
--
-- These are the controls the settings panel and the chrome are built from. They
-- share the widget foundation so a toggle in Settings behaves exactly like the
-- one in a popout header.

local _, ns = ...
local Theme, W, Draw, Anim, Text = ns.Theme, ns.Widgets, ns.Draw, ns.Anim, ns.Text
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Controls = {}
ns.Controls = Controls

local max, min, floor = math.max, math.min, math.floor

--------------------------------------------------------------------------------
-- Unread badge
--------------------------------------------------------------------------------

function Controls.Badge(parent, opts)
	opts = opts or {}
	local b = CreateFrame("Frame", nil, parent)
	local h = opts.height or ns.SZ.BADGE_H
	b:SetSize(h, h)
	b.surface = W.Surface(b, { color = "accent", radius = h / 2 })
	b.label = W.Text(b, "MICRO", "onAccent")
	b.label:ClearAllPoints()
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetJustifyH("CENTER")
	b.height = h
	b:Hide()

	function b:SetCount(count, muted)
		if not count or count <= 0 then
			b:Hide()
			b.count = 0
			return
		end
		local wasZero = (b.count or 0) == 0
		b.count = count
		local textValue = count > 99 and "99+" or tostring(count)
		b.label:SetText(textValue)
		local width = max(h, b.label:GetStringWidth() + ns.S.SM + 2)
		b:SetWidth(width)
		b.surface:SetRadius(h / 2)
		b.surface:SetColorRole(muted and "textMuted" or "accent")
		W.SetTextRole(b.label, muted and "bg1" or "onAccent")
		b:Show()
		if wasZero then
			Anim.Pulse(b, 0.22)
		end
	end

	function b:ApplyTheme()
		b.surface:SetRadius(b.height / 2)
		b.surface:ApplyTheme()
		W.RefreshText(b.label)
		if b.count and b.count > 0 then b:SetCount(b.count, b.muted) end
	end

	return b
end

--------------------------------------------------------------------------------
-- Toggle switch
--------------------------------------------------------------------------------

function Controls.Toggle(parent, opts)
	opts = opts or {}
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(ns.SZ.TOGGLE_W, ns.SZ.TOGGLE_H)
	t.value = false

	t.surface = W.Surface(t, { color = "hover", radius = ns.SZ.TOGGLE_H / 2 })

	t.knob = CreateFrame("Frame", nil, t)
	t.knob:SetSize(ns.SZ.TOGGLE_KNOB, ns.SZ.TOGGLE_KNOB)
	t.knob.surface = W.Surface(t.knob, {
		color = "textSecondary", radius = ns.SZ.TOGGLE_KNOB / 2, layer = "ARTWORK",
	})
	t.knob:SetPoint("LEFT", t, "LEFT", 2, 0)

	local travel = ns.SZ.TOGGLE_W - ns.SZ.TOGGLE_KNOB - 4

	local function paint(instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local trackRole = t.value and "accent" or "hover"
		local knobRole = t.value and "onAccent" or "textSecondary"
		if not t.__wtwEnabled then
			trackRole = "hover"
			knobRole = "textDisabled"
		end
		W.FadeSurfaceTo(t.surface, t, trackRole, duration)
		local knobColor = Theme.Get(knobRole)
		t.knob.surface:SetColorOverride(knobColor[1], knobColor[2], knobColor[3], knobColor[4] or 1)

		local target = t.value and travel or 0
		local currentPoint = select(4, t.knob:GetPoint(1)) or 0
		if duration <= 0 then
			Anim.Stop(t.knob)
			t.knob:SetPoint("LEFT", t, "LEFT", 2 + target, 0)
		else
			Anim.To(t.knob, duration, currentPoint - 2, target, function(v)
				t.knob:SetPoint("LEFT", t, "LEFT", 2 + v, 0)
			end)
		end
	end

	W.MakeInteractive(t, function(state, instant)
		paint(instant)
		t:SetAlpha(state == "disabled" and 0.5 or 1)
	end)

	t:HookScript("OnMouseUp", function(self)
		if not self.__wtwEnabled or not self:IsMouseOver() then return end
		t:SetValue(not t.value, true)
	end)

	function t:SetValue(value, fireCallback)
		value = value and true or false
		if t.value == value and not fireCallback then
			paint(true)
			return
		end
		t.value = value
		paint(false)
		if fireCallback and opts.onChange then
			ns.Guard("Toggle.onChange", opts.onChange, value)
		end
	end

	function t:GetValue() return t.value end

	function t:ApplyTheme()
		t.surface:SetRadius(ns.SZ.TOGGLE_H / 2)
		t.surface:ApplyTheme()
		t.knob.surface:SetRadius(ns.SZ.TOGGLE_KNOB / 2)
		t.knob.surface:ApplyTheme()
		paint(true)
	end

	paint(true)
	return t
end

--------------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------------

-- opts: minValue, maxValue, step, format(value) -> string, onChange(value)
function Controls.Slider(parent, opts)
	opts = opts or {}
	local s = CreateFrame("Frame", nil, parent)
	s:SetHeight(ns.SZ.SLIDER_THUMB + 8)
	s.minValue = opts.minValue or 0
	s.maxValue = opts.maxValue or 1
	s.step = opts.step or 0
	s.value = s.minValue

	s.track = CreateFrame("Frame", nil, s)
	s.track:SetHeight(ns.SZ.SLIDER_TRACK)
	s.track:SetPoint("LEFT", s, "LEFT", ns.SZ.SLIDER_THUMB / 2, 0)
	s.track:SetPoint("RIGHT", s, "RIGHT", -(ns.SZ.SLIDER_THUMB / 2 + 46), 0)
	s.track.surface = W.Surface(s.track, { color = "hover", radius = ns.SZ.SLIDER_TRACK / 2 })

	s.fill = CreateFrame("Frame", nil, s.track)
	s.fill:SetHeight(ns.SZ.SLIDER_TRACK)
	s.fill:SetPoint("LEFT", s.track, "LEFT", 0, 0)
	s.fill:SetWidth(1)
	s.fill.surface = W.Surface(s.fill, {
		color = "accent", radius = ns.SZ.SLIDER_TRACK / 2, layer = "ARTWORK",
	})

	s.thumb = CreateFrame("Frame", nil, s)
	s.thumb:SetSize(ns.SZ.SLIDER_THUMB, ns.SZ.SLIDER_THUMB)
	s.thumb.surface = W.Surface(s.thumb, {
		color = "textPrimary", radius = ns.SZ.SLIDER_THUMB / 2, layer = "OVERLAY",
	})

	s.valueLabel = W.Text(s, "SMALL", "textSecondary")
	s.valueLabel:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.valueLabel:SetJustifyH("RIGHT")
	s.valueLabel:SetWidth(42)

	local function snap(value)
		value = min(max(value, s.minValue), s.maxValue)
		if s.step and s.step > 0 then
			value = s.minValue + floor((value - s.minValue) / s.step + 0.5) * s.step
			value = min(max(value, s.minValue), s.maxValue)
		end
		return value
	end

	local function layout()
		local width = s.track:GetWidth() or 1
		local range = s.maxValue - s.minValue
		local progress = range > 0 and (s.value - s.minValue) / range or 0
		s.fill:SetWidth(max(1, width * progress))
		s.thumb:ClearAllPoints()
		s.thumb:SetPoint("CENTER", s.track, "LEFT", width * progress, 0)
		s.valueLabel:SetText(opts.format and opts.format(s.value) or tostring(s.value))
	end
	s.Layout = layout

	local function valueFromCursor()
		local scale = s.track:GetEffectiveScale() or 1
		local cursorX = select(1, GetCursorPosition()) / scale
		local left = s.track:GetLeft() or 0
		local width = s.track:GetWidth() or 1
		local progress = min(max((cursorX - left) / width, 0), 1)
		return snap(s.minValue + progress * (s.maxValue - s.minValue))
	end

	local function beginDrag(self)
		self.dragging = true
		s:SetValue(valueFromCursor(), true)
		self:SetScript("OnUpdate", function()
			if not self.dragging then return end
			s:SetValue(valueFromCursor(), true)
		end)
	end
	local function endDrag(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
	end

	for _, region in ipairs({ s.track, s.thumb }) do
		region:EnableMouse(true)
		region:SetScript("OnMouseDown", beginDrag)
		region:SetScript("OnMouseUp", endDrag)
		region:SetScript("OnHide", endDrag)
	end

	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(_, delta)
		local step = (s.step and s.step > 0) and s.step or (s.maxValue - s.minValue) / 20
		s:SetValue(snap(s.value + delta * step), true)
	end)

	s:HookScript("OnSizeChanged", layout)

	function s:SetValue(value, fireCallback)
		local snapped = snap(value)
		if snapped == s.value then
			layout()
			return
		end
		s.value = snapped
		layout()
		if fireCallback and opts.onChange then
			ns.Guard("Slider.onChange", opts.onChange, snapped)
		end
	end

	function s:GetValue() return s.value end

	function s:ApplyTheme()
		s.track.surface:ApplyTheme()
		s.fill.surface:ApplyTheme()
		s.thumb.surface:ApplyTheme()
		W.RefreshText(s.valueLabel)
		layout()
	end

	layout()
	return s
end

--------------------------------------------------------------------------------
-- Dropdown
--------------------------------------------------------------------------------

-- opts: options = { {value, label, icon} }, onChange(value), width
function Controls.Dropdown(parent, opts)
	opts = opts or {}
	local d = CreateFrame("Frame", nil, parent)
	d:SetHeight(opts.height or 30)
	if opts.width then d:SetWidth(opts.width) end
	d.options = opts.options or {}

	d.surface = W.Surface(d, { color = "inputBg", border = "borderSubtle", radius = ns.R.MD })
	d.label = W.Text(d, "SMALL", "textPrimary")
	d.label:SetPoint("LEFT", d, "LEFT", ns.S.MD, 0)
	d.label:SetPoint("RIGHT", d, "RIGHT", -(ns.S.MD + ns.SZ.ICON_GLYPH_SM), 0)
	d.chevron = W.Icon(d, "chevron_down", ns.SZ.ICON_GLYPH_SM, "textMuted")
	d.chevron:SetPoint("RIGHT", d, "RIGHT", -ns.S.SM, 0)

	W.MakeInteractive(d, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role = (state == "pressed" or state == "selected") and "pressed"
			or (state == "hover") and "hover" or "inputBg"
		W.FadeSurfaceTo(d.surface, d, role, duration)
		W.SetTextRole(d.label, state == "disabled" and "textDisabled" or "textPrimary")
	end)

	local function labelFor(value)
		for i = 1, #d.options do
			if d.options[i].value == value then return d.options[i].label end
		end
		return tostring(value)
	end

	d:HookScript("OnMouseUp", function(self)
		if not self.__wtwEnabled or not self:IsMouseOver() then return end
		local entries = {}
		for i = 1, #d.options do
			local option = d.options[i]
			entries[#entries + 1] = {
				text = option.label,
				icon = option.value == d.value and "check" or nil,
				onClick = function() d:SetValue(option.value, true) end,
			}
		end
		ns.Menu.Open(entries, {
			anchorTo = d, point = "TOPLEFT", relPoint = "BOTTOMLEFT",
			y = -ns.S.XS, minWidth = max(ns.SZ.MENU_MIN_W, d:GetWidth() or 0),
		})
	end)

	function d:SetOptions(options)
		d.options = options or {}
		d.label:SetText(labelFor(d.value))
	end

	function d:SetValue(value, fireCallback)
		d.value = value
		d.label:SetText(labelFor(value))
		if fireCallback and opts.onChange then
			ns.Guard("Dropdown.onChange", opts.onChange, value)
		end
	end

	function d:GetValue() return d.value end

	function d:ApplyTheme()
		d.surface:ApplyTheme()
		W.RefreshText(d.label)
		W.RefreshIcon(d.chevron)
		d.UpdateVisualState(true)
	end

	return d
end

--------------------------------------------------------------------------------
-- Search field
--------------------------------------------------------------------------------

-- opts: placeholder, onChange(text), height
function Controls.SearchBox(parent, opts)
	opts = opts or {}
	local box = CreateFrame("Frame", nil, parent)
	box:SetHeight(opts.height or 30)

	box.input = ns.Input.New(box, {
		placeholder = opts.placeholder or L["Search conversations"],
		minHeight = opts.height or 30,
		radius = ns.R.MD,
		fontToken = "SMALL",
		onChange = function(value)
			box.clear:SetShown(value ~= "")
			if opts.onChange then ns.Guard("SearchBox.onChange", opts.onChange, value) end
		end,
		onEscape = function()
			if box.input:GetText() ~= "" then
				box.input:SetText("")
				if opts.onChange then ns.Guard("SearchBox.onChange", opts.onChange, "") end
			end
		end,
	})
	box.input:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
	box.input:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)

	-- Shift the caret and placeholder right to make room for the glyph.
	box.input.editBox:SetPoint("TOPLEFT", box.input, "TOPLEFT", ns.S.HUGE, 0)
	box.input.placeholder:SetPoint("LEFT", box.input, "LEFT", ns.S.HUGE, 0)

	box.icon = W.Icon(box, "search", ns.SZ.ICON_GLYPH_SM, "textMuted", "OVERLAY")
	box.icon:SetPoint("LEFT", box, "LEFT", ns.S.MD, 0)

	box.clear = ns.Button.Icon(box, {
		icon = "close", size = 22, glyph = 10, radius = 11,
		onClick = function()
			box.input:SetText("")
			box.clear:Hide()
			if opts.onChange then ns.Guard("SearchBox.onChange", opts.onChange, "") end
		end,
	})
	box.clear:SetPoint("RIGHT", box, "RIGHT", -ns.S.XS, 0)
	box.clear:Hide()

	function box:GetText() return box.input:GetText() end
	function box:SetText(value) box.input:SetText(value) box.clear:SetShown((value or "") ~= "") end
	function box:Focus() box.input:Focus() end
	function box:ClearFocus() box.input:ClearFocus() end

	function box:ApplyTheme()
		box.input:ApplyTheme()
		W.RefreshIcon(box.icon)
		box.clear:ApplyTheme()
	end

	return box
end
