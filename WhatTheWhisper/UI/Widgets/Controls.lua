-- WhatTheWhisper -- Badges, toggles, sliders, dropdowns and the search field.
--
-- These are the controls the settings panel and the chrome are built from. They
-- share the widget foundation so a toggle in Settings behaves exactly like the
-- one in a popout header.

local _, ns = ...
local Theme, W, Anim = ns.Theme, ns.Widgets, ns.Anim
local L = ns.L

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

	t.surface = W.Surface(t, { color = "trackBg", radius = ns.SZ.TOGGLE_H / 2 })

	t.knob = CreateFrame("Frame", nil, t)
	t.knob:SetSize(ns.SZ.TOGGLE_KNOB, ns.SZ.TOGGLE_KNOB)
	t.knob.surface = W.Surface(t.knob, {
		color = "onAccent", radius = ns.SZ.TOGGLE_KNOB / 2, layer = "ARTWORK",
	})
	-- The knob's rim inside the track, and the distance it travels. Two pixels
	-- either side is what makes the shape read as a switch rather than as a pill
	-- with a circle in it.
	local RIM = 2
	t.knob:SetPoint("LEFT", t, "LEFT", RIM, 0)

	local travel = ns.SZ.TOGGLE_W - ns.SZ.TOGGLE_KNOB - RIM * 2

	local function paint(instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		-- The knob stays light in both states and only the track changes, which
		-- is what every switch on every platform does: the eye reads the
		-- coloured half of the track, not the colour of the handle. Making the
		-- knob change too gave the off state a grey handle on a grey track,
		-- which is a switch you have to look for.
		local trackRole = t.value and "accent" or "trackBg"
		local knobRole = t.value and "onAccent" or "textSecondary"
		if not t.__wtwEnabled then
			trackRole = "trackBg"
			knobRole = "textDisabled"
		end
		W.FadeSurfaceTo(t.surface, t, trackRole, duration)
		local knobColor = Theme.Get(knobRole)
		t.knob.surface:SetColorOverride(knobColor[1], knobColor[2], knobColor[3], knobColor[4] or 1)

		local target = t.value and travel or 0
		local currentPoint = select(4, t.knob:GetPoint(1)) or 0
		if duration <= 0 then
			Anim.Stop(t.knob)
			t.knob:SetPoint("LEFT", t, "LEFT", RIM + target, 0)
		else
			Anim.To(t.knob, duration, currentPoint - RIM, target, function(v)
				t.knob:SetPoint("LEFT", t, "LEFT", RIM + v, 0)
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
-- The size a slider's readout is set in, named once so the measurement and the
-- drawing cannot disagree.
local VALUE_FONT = "SUBHEAD"

function Controls.Slider(parent, opts)
	opts = opts or {}
	local s = CreateFrame("Frame", nil, parent)
	s:SetHeight(ns.SZ.SLIDER_THUMB + 8)
	s.minValue = opts.minValue or 0
	s.maxValue = opts.maxValue or 1
	s.step = opts.step or 0
	s.value = s.minValue

	-- Anchored on the left only, and given its width. A track anchored on both
	-- sides has no width of its own: it has the one the layout engine works out
	-- later, and asking for it in the same frame the slider was resized gets you
	-- the width from before the resize -- or zero, the first time a pooled
	-- slider is used at all. Every position below is computed from that width,
	-- so the settings panel opened with each thumb parked at the far left while
	-- the number beside it read correctly.
	s.track = CreateFrame("Frame", nil, s)
	s.track:SetHeight(ns.SZ.SLIDER_TRACK)
	s.track:SetPoint("LEFT", s, "LEFT", ns.SZ.SLIDER_THUMB / 2, 0)
	s.track.surface = W.Surface(s.track, { color = "trackBg", radius = ns.SZ.SLIDER_TRACK / 2 })

	-- How wide the readout beside the track has to be.
	--
	-- Whatever the formatter produces at the ends of the range, measured at the
	-- font in use. A fixed column was fine for "50%" and cut "5 seconds" down to
	-- "5 secon" -- and would have cut "50%" too, two font sizes up. The extremes
	-- are enough: a formatter whose longest output is in the middle of its own
	-- range would be a strange thing to write.
	local valueColumn = ns.SZ.SLIDER_VALUE_W
	local function measureValueColumn()
		if not opts.format then
			valueColumn = ns.SZ.SLIDER_VALUE_W
			return
		end
		-- At the size the readout is drawn at. Measuring at one size and drawing
		-- at another is how a column ends up two pixels short of the words in
		-- it, which is exactly what happened to the context menu.
		local fs = Theme.Measure(VALUE_FONT)
		fs:SetWordWrap(false)
		fs:SetWidth(0)
		local widest = 0
		for _, value in ipairs({ s.minValue, s.maxValue, s.value }) do
			if type(value) == "number" then
				local ok, text = pcall(opts.format, value)
				if ok and type(text) == "string" then
					fs:SetText(text)
					widest = max(widest, fs:GetStringWidth() or 0)
				end
			end
		end
		valueColumn = max(ns.SZ.SLIDER_VALUE_W, math.ceil(widest))
		s.valueLabel:SetWidth(valueColumn)
	end

	-- The room left for the track once the thumb has its half-width at each end
	-- and the value label has its column. Derived from the slider's own width,
	-- which was set explicitly and is therefore true the moment it is set.
	local function trackWidth()
		return max(1, (s:GetWidth() or 0) - ns.SZ.SLIDER_THUMB - valueColumn
			- ns.SZ.SLIDER_VALUE_GAP)
	end

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

	s.valueLabel = W.Text(s, VALUE_FONT, "textSecondary")
	s.valueLabel:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.valueLabel:SetJustifyH("RIGHT")
	-- One line, always. It is a number with a unit after it, and wrapping it
	-- puts the unit on a line the slider is not tall enough to show.
	s.valueLabel:SetWordWrap(false)
	s.valueLabel:SetWidth(ns.SZ.SLIDER_VALUE_W)

	local function snap(value)
		value = min(max(value, s.minValue), s.maxValue)
		if s.step and s.step > 0 then
			value = s.minValue + floor((value - s.minValue) / s.step + 0.5) * s.step
			value = min(max(value, s.minValue), s.maxValue)
		end
		return value
	end

	local function layout()
		measureValueColumn()
		local width = trackWidth()
		s.track:SetWidth(width)
		local range = s.maxValue - s.minValue
		local progress = range > 0 and (s.value - s.minValue) / range or 0
		progress = min(max(progress, 0), 1)
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
		local width = trackWidth()
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

	-- The track is drawn 4px high because a fat bar looks clumsy, but clicking to
	-- jump along it has to be possible without taking aim. Negative insets grow
	-- the hit rect to a full-size target.
	--
	-- To MIN_HIT rather than to the thumb's height. Grown to the thumb it was
	-- 14px tall, which only counted as aimable because the track happened to be
	-- longer than 100px -- the allowance a scrollbar gets for being aimed at
	-- along one axis. A slider in a settings row is not that long, and the first
	-- time the column beside it grew, it stopped being aimable at all.
	local trackGrow = (ns.MIN_HIT - ns.SZ.SLIDER_TRACK) / 2
	s.track:SetHitRectInsets(0, 0, -trackGrow, -trackGrow)

	-- The thumb is a 14px dot, which is the right size to look at and too small
	-- to grab. Its hit rect is grown to a comfortable target without changing
	-- what is drawn.
	local thumbGrow = (ns.MIN_HIT - ns.SZ.SLIDER_THUMB) / 2
	s.thumb:SetHitRectInsets(-thumbGrow, -thumbGrow, -thumbGrow, -thumbGrow)

	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(_, delta)
		local step = (s.step and s.step > 0) and s.step or (s.maxValue - s.minValue) / 20
		s:SetValue(snap(s.value + delta * step), true)
	end)

	s:HookScript("OnSizeChanged", layout)

	-- Called before SetValue when a pooled control is handed a different setting.
	-- The old row's value is almost never legal in the new row's range, and a
	-- slider showing a number outside its own scale is worse than a wrong one.
	function s:SetRange(minValue, maxValue, step)
		s.minValue, s.maxValue, s.step = minValue or 0, maxValue or 1, step or 0
		s.value = snap(s.value)
		layout()
	end

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

	d.surface = W.Surface(d, { color = "inputBg", radius = ns.R.MD })
	d.label = W.Text(d, "SUBHEAD", "textPrimary")
	d.label:SetPoint("LEFT", d, "LEFT", ns.S.MD, 0)
	d.label:SetPoint("RIGHT", d, "RIGHT", -(ns.S.MD + ns.SZ.ICON_GLYPH_SM), 0)
	-- Secondary, not muted: this one says the row opens, and a hint you have to
	-- look for is not a hint.
	d.chevron = W.Icon(d, "down", ns.SZ.ICON_GLYPH_SM, "textSecondary")
	d.chevron:SetPoint("RIGHT", d, "RIGHT", -ns.S.SM, 0)

	W.MakeInteractive(d, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role = (state == "pressed" or state == "selected") and "pressed"
			or (state == "hover") and "hover" or "inputBg"
		W.FadeSurfaceTo(d.surface, d, role, duration)
		W.SetTextRole(d.label, state == "disabled" and "textDisabled" or "textPrimary")
	end)

	local function optionFor(value)
		for i = 1, #d.options do
			if d.options[i].value == value then return d.options[i] end
		end
		return nil
	end

	-- The label and the font it needs, together: an option written in a script
	-- the theme font cannot draw carries the font that can.
	local function showValue(value)
		local option = optionFor(value)
		W.SetTextFont(d.label, option and option.font or nil)
		d.label:SetText(option and option.label or tostring(value))
	end

	d:HookScript("OnMouseUp", function(self)
		if not self.__wtwEnabled or not self:IsMouseOver() then return end
		local entries = {}
		for i = 1, #d.options do
			local option = d.options[i]
			entries[#entries + 1] = {
				text = option.label,
				font = option.font,
				icon = option.value == d.value and "sent" or nil,
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
		showValue(d.value)
	end

	function d:SetValue(value, fireCallback)
		d.value = value
		showValue(value)
		if fireCallback and opts.onChange then
			ns.Guard("Dropdown.onChange", opts.onChange, value)
		end
	end

	function d:GetValue() return d.value end

	function d:ApplyTheme()
		d.surface:ApplyTheme()
		W.RefreshText(d.label)
		-- RefreshText puts the theme font back, which is right for every label
		-- but this one: the chosen option may be the one that needs its own.
		showValue(d.value)
		W.RefreshIcon(d.chevron)
		d.UpdateVisualState(true)
	end

	return d
end

--------------------------------------------------------------------------------
-- Segmented control
--------------------------------------------------------------------------------

-- Two to four mutually exclusive options, all visible at once, with a thumb
-- sliding between them.
--
-- It replaces a dropdown where the dropdown was hiding the answer behind a
-- click: "Comfortable / Compact" is two words, and a menu that has to be opened
-- to discover that costs more than it saves. Deliberately not used for long
-- lists -- eleven languages in a row of segments is a row of unreadable
-- slivers, and that is what the dropdown is still for.
--
-- opts: options { { value, label }, ... }, onChange(value)
-- The size a segment's caption is set in, named once so the width this control
-- asks for and the text it draws cannot disagree. They have disagreed three
-- times in this file's history, each time silently, and each time the symptom
-- was a caption a couple of pixels wider than the space reserved for it.
local SEGMENT_FONT = "SUBHEAD"

-- How wide a row of segments has to be for every caption to fit.
--
-- Measured at the font in use, not counted in characters. A rule like "no label
-- longer than fourteen letters" is a guess about how wide fourteen letters are,
-- and it was wrong at the default font size and wronger at every other one --
-- "Bottom right" is twelve characters and nearly twice the width of the segment
-- it was given.
function Controls.SegmentedNaturalWidth(options)
	if type(options) ~= "table" or #options == 0 then return 0 end
	local fs = Theme.Measure(SEGMENT_FONT)
	fs:SetWordWrap(false)
	fs:SetWidth(0)
	local widest = 0
	for i = 1, #options do
		fs:SetText(options[i].label or "")
		widest = max(widest, fs:GetStringWidth() or 0)
	end
	-- The caption, the padding either side of it, and the track's own rim.
	return math.ceil((widest + ns.S.MD) * #options) + ns.SZ.SEGMENT_RIM * 2
end

function Controls.Segmented(parent, opts)
	opts = opts or {}
	local options = opts.options or {}
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(ns.SZ.SEGMENT_H)
	seg.options = options
	seg.segments = {}

	seg.surface = W.Surface(seg, { color = "trackBg", radius = ns.R.PILL })

	local RIM = ns.SZ.SEGMENT_RIM
	seg.thumb = CreateFrame("Frame", nil, seg)
	seg.thumb:SetHeight(ns.SZ.SEGMENT_H - RIM * 2)
	seg.thumb.surface = W.Surface(seg.thumb, {
		color = "bg3", radius = ns.R.PILL, layer = "ARTWORK",
	})
	seg.thumb:SetPoint("LEFT", seg, "LEFT", RIM, 0)

	local function segmentWidth()
		local width = seg:GetWidth() or (ns.SZ.SEGMENT_MIN_W * #options)
		return (width - RIM * 2) / max(1, #options)
	end

	local function indexOf(value)
		for i = 1, #options do
			if options[i].value == value then return i end
		end
		return 1
	end

	local function paint(instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local index = indexOf(seg.value)
		local width = segmentWidth()
		seg.thumb:SetWidth(max(1, width))
		local target = RIM + (index - 1) * width
		local current = select(4, seg.thumb:GetPoint(1)) or target
		if duration <= 0 then
			Anim.Stop(seg.thumb)
			seg.thumb:SetPoint("LEFT", seg, "LEFT", target, 0)
		else
			Anim.To(seg.thumb, duration, current, target, function(v)
				seg.thumb:SetPoint("LEFT", seg, "LEFT", v, 0)
			end)
		end
		for i = 1, #seg.segments do
			local button = seg.segments[i]
			if i <= #options then
				button:SetWidth(max(1, width))
				button:ClearAllPoints()
				button:SetPoint("LEFT", seg, "LEFT", RIM + (i - 1) * width, 0)
				-- Fitted to the segment every time, because the segment's width
				-- is a share of the control's and the text's width is a function
				-- of the font -- and the player can change either. A caption
				-- wider than its share does not clip, it prints over the caption
				-- beside it, which is the one failure a row of segments must
				-- never have.
				ns.Text.Ellipsize(button.label, button.fullLabel or "",
					max(1, width - ns.S.SM))
				W.SetTextRole(button.label,
					(i == index and "textPrimary")
					or (button.hovered and "textSecondary")
					or "textMuted")
			end
		end
	end

	-- Segments are built on demand and kept: the control is pooled, so the same
	-- frame shows three options in one settings row and two in the next. Growing
	-- the list reuses what is there and adds to it; shrinking hides the excess
	-- rather than destroying frames that will be wanted again in a moment.
	function seg.SetOptions(_, list)
		options = list or {}
		seg.options = options
		for i = 1, #options do
			local button = seg.segments[i]
			if not button then
				button = CreateFrame("Frame", nil, seg)
				button:SetHeight(ns.SZ.SEGMENT_H - RIM * 2)
				button:EnableMouse(true)
				button.label = W.Text(button, SEGMENT_FONT, "textMuted")
				button.label:SetPoint("CENTER")
				button.label:SetJustifyH("CENTER")
				button.label:SetWordWrap(false)
				button:SetScript("OnEnter", function(self)
					self.hovered = true
					paint(true)
				end)
				button:SetScript("OnLeave", function(self)
					self.hovered = nil
					paint(true)
				end)
				button:SetScript("OnMouseUp", function(self)
					if not self:IsMouseOver() or not self.optionValue then return end
					seg:SetValue(self.optionValue, true)
				end)
				seg.segments[i] = button
			end
			button.optionValue = options[i].value
			-- Kept whole. The label drawn is fitted to the segment, and fitting
			-- an already-fitted string shortens it a little more every time the
			-- control is laid out.
			button.fullLabel = options[i].label or ""
			button:Show()
		end
		for i = #options + 1, #seg.segments do
			seg.segments[i]:Hide()
			seg.segments[i].optionValue = nil
		end
		paint(true)
	end

	function seg:SetValue(value, fireCallback)
		local changed = seg.value ~= value
		seg.value = value
		paint(not changed)
		if changed and fireCallback and opts.onChange then
			ns.Guard("Segmented.onChange", opts.onChange, value)
		end
	end

	function seg:GetValue() return seg.value end

	-- The narrowest this control can be drawn at and still read: the widest
	-- caption, plus its breathing room, in every segment.
	function seg.NaturalWidth(_, list)
		return Controls.SegmentedNaturalWidth(list or options)
	end

	function seg:ApplyTheme()
		seg.surface:SetRadius(ns.R.PILL)
		seg.surface:ApplyTheme()
		seg.thumb.surface:SetRadius(ns.R.PILL)
		seg.thumb.surface:ApplyTheme()
		for i = 1, #seg.segments do W.RefreshText(seg.segments[i].label) end
		paint(true)
	end


	seg:HookScript("OnSizeChanged", function() paint(true) end)
	seg:SetOptions(options)
	seg.value = options[1] and options[1].value
	paint(true)
	return seg
end

--------------------------------------------------------------------------------
-- Search field
--------------------------------------------------------------------------------

-- opts: placeholder, onChange(text), height
-- A pill with a magnifier in it and nothing else: no outline, no bevel, no
-- button-shaped anything. The one control in the addon that everybody has seen a
-- thousand times before, so it is the one where looking unfamiliar costs the
-- most.
function Controls.SearchBox(parent, opts)
	opts = opts or {}
	local height = opts.height or ns.SZ.SEARCH_H
	local box = CreateFrame("Frame", nil, parent)
	box:SetHeight(height)

	box.input = ns.Input.New(box, {
		placeholder = opts.placeholder or L["Search conversations"],
		minHeight = height,
		radius = ns.R.PILL,
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

	-- Shift the caret and placeholder right to make room for the glyph: the
	-- magnifier's own left margin, plus the glyph, plus a gap after it.
	local TEXT_LEFT = ns.S.MD + ns.SZ.ICON_GLYPH_SM + ns.S.SM
	box.input.editBox:SetPoint("TOPLEFT", box.input, "TOPLEFT", TEXT_LEFT, 0)
	box.input.placeholder:SetPoint("LEFT", box.input, "LEFT", TEXT_LEFT, 0)

	box.icon = W.Icon(box, "search", ns.SZ.ICON_GLYPH_SM, "textMuted", "OVERLAY")
	box.icon:SetPoint("LEFT", box, "LEFT", ns.S.MD, 0)

	box.clear = ns.Button.Icon(box, {
		icon = "close", size = ns.SZ.ICON_BTN_SM - ns.S.XS,
		glyph = ns.SZ.ICON_GLYPH_XS, radius = ns.R.PILL,
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
