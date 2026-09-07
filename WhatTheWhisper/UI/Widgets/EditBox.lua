-- WhatTheWhisper -- Text input.
--
-- Enter sends and Shift+Enter inserts a newline, which a multi-line WoW EditBox
-- does not support on its own: the engine never fires OnEnterPressed for a
-- multi-line box, it just inserts the character. So the box watches its own text
-- for a single newline appearing at the caret and decides there. Pasting several
-- lines at once adds more than one character and is left alone.

local _, ns = ...
local Theme, W, Draw, Anim = ns.Theme, ns.Widgets, ns.Draw, ns.Anim

local Input = {}
ns.Input = Input

local max, min = math.max, math.min

local PAD_X = ns.S.MD
local PAD_Y = 7

-- opts:
--   multiline    grow vertically, Enter sends, Shift+Enter newlines
--   placeholder  greyed text shown while empty
--   minHeight / maxHeight
--   onEnter(text) onChange(text) onEscape() onResize(height) onFocus(bool)
--   radius, fontToken
function Input.New(parent, opts)
	opts = opts or {}
	local container = CreateFrame("Frame", nil, parent)
	container.opts = opts
	container.minHeight = opts.minHeight or ns.SZ.COMPOSER_FIELD_H
	container.maxHeight = opts.maxHeight or container.minHeight
	container:SetHeight(container.minHeight)

	container.surface = W.Surface(container, {
		color = "inputBg",
		border = "borderSubtle",
		radius = opts.radius or ns.R.MD,
	})

	-- Focus glow sits outside the border so the ring reads without moving layout.
	container.glow = Draw.NewRounded(container, "BACKGROUND", -2)
	container.glow:SetInsets(-2, -2, -2, -2)
	container.glow:SetRadius(Theme.Radius((opts.radius or ns.R.MD) + 2))
	container.glow:Hide()

	local host, editBox
	if opts.multiline then
		host = CreateFrame("ScrollFrame", nil, container)
		host:SetPoint("TOPLEFT", container, "TOPLEFT", PAD_X, -PAD_Y)
		host:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -PAD_X, PAD_Y)
		editBox = CreateFrame("EditBox", nil, host)
		editBox:SetMultiLine(true)
		editBox:SetWidth(1)
		editBox:SetAllPoints()
		host:SetScrollChild(editBox)
		host:SetScript("OnSizeChanged", function(_, width)
			if width and width > 0 then editBox:SetWidth(width) end
		end)
		-- Keep the caret in view while typing past the bottom of the box.
		editBox:SetScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
			y = -y
			local offset = host:GetVerticalScroll()
			if y < offset then
				host:SetVerticalScroll(y)
			else
				local bottom = y + cursorHeight - host:GetHeight()
				if bottom > offset then host:SetVerticalScroll(max(0, bottom)) end
			end
		end)
	else
		editBox = CreateFrame("EditBox", nil, container)
		editBox:SetPoint("TOPLEFT", container, "TOPLEFT", PAD_X, 0)
		editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -PAD_X, 0)
	end

	container.host = host
	container.editBox = editBox

	editBox:SetAutoFocus(false)
	editBox:SetFontObject(Theme.Font(opts.fontToken or "BODY"))
	editBox:SetTextInsets(0, 0, 0, 0)
	editBox:SetMaxLetters(0)
	if editBox.SetCountInvisibleLetters then editBox:SetCountInvisibleLetters(false) end
	local tc = Theme.Get("textPrimary")
	editBox:SetTextColor(tc[1], tc[2], tc[3], 1)
	if editBox.SetSpacing then editBox:SetSpacing(2) end

	container.placeholder = W.Text(container, opts.fontToken or "BODY", "textMuted")
	container.placeholder:SetPoint("LEFT", container, "LEFT", PAD_X, 0)
	container.placeholder:SetPoint("RIGHT", container, "RIGHT", -PAD_X, 0)
	if opts.multiline then
		container.placeholder:ClearAllPoints()
		container.placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", PAD_X, -PAD_Y)
		container.placeholder:SetJustifyV("TOP")
	end
	container.placeholder:SetText(opts.placeholder or "")

	----------------------------------------------------------------- behaviour
	local lastText = ""

	local function updatePlaceholder()
		container.placeholder:SetShown(editBox:GetText() == "")
	end

	local function measureHeight(text)
		if not opts.multiline then return container.minHeight end
		local fs = Theme.Measure(opts.fontToken or "BODY")
		local width = max(1, (container:GetWidth() or 200) - PAD_X * 2)
		fs:SetWidth(width)
		fs:SetText(text ~= "" and text or " ")
		local h = fs:GetStringHeight() or 14
		return min(container.maxHeight, max(container.minHeight, h + PAD_Y * 2))
	end

	local function applyHeight(text)
		if not opts.multiline then return end
		local h = measureHeight(text)
		if math.abs(h - (container:GetHeight() or 0)) < 0.5 then return end
		container:SetHeight(h)
		if opts.onResize then ns.Guard("Input.onResize", opts.onResize, h) end
	end
	container.ApplyHeight = function() applyHeight(editBox:GetText()) end

	local function submit()
		local value = editBox:GetText()
		if opts.onEnter then ns.Guard("Input.onEnter", opts.onEnter, value) end
	end

	editBox:SetScript("OnTextChanged", function(self, userInput)
		local newText = self:GetText()

		if opts.multiline and userInput and #newText == #lastText + 1 then
			-- Exactly one character was typed. If it is a newline and Shift is
			-- not held, the user meant "send".
			local diffAt
			for i = 1, #newText do
				if newText:sub(i, i) ~= lastText:sub(i, i) then diffAt = i break end
			end
			if diffAt and newText:sub(diffAt, diffAt) == "\n" and not IsShiftKeyDown() then
				local stripped = newText:sub(1, diffAt - 1) .. newText:sub(diffAt + 1)
				lastText = stripped
				self:SetText(stripped)
				self:SetCursorPosition(#stripped)
				updatePlaceholder()
				applyHeight(stripped)
				submit()
				return
			end
		end

		lastText = newText
		updatePlaceholder()
		applyHeight(newText)
		if opts.onChange then ns.Guard("Input.onChange", opts.onChange, newText) end
	end)

	if not opts.multiline then
		editBox:SetScript("OnEnterPressed", function() submit() end)
	end

	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		if opts.onEscape then ns.Guard("Input.onEscape", opts.onEscape) end
	end)

	local function setFocusVisual(focused)
		local duration = Theme.Duration("FAST")
		if focused then
			local ring = Theme.Get("focusRing")
			container.surface.rect:SetBorder(
				Theme.Border(container) * 1.5, ring[1], ring[2], ring[3], 1)
			container.glow:SetColor(ring[1], ring[2], ring[3], 0)
			container.glow:Show()
			Anim.To(container.glow, duration, 0, 0.22, function(v)
				container.glow:SetColor(ring[1], ring[2], ring[3], v)
			end)
		else
			local b = Theme.Get("borderSubtle")
			container.surface.rect:SetBorder(Theme.Border(container), b[1], b[2], b[3], b[4])
			Anim.Stop(container.glow)
			container.glow:Hide()
		end
		if opts.onFocus then ns.Guard("Input.onFocus", opts.onFocus, focused) end
	end

	editBox:SetScript("OnEditFocusGained", function() setFocusVisual(true) end)
	editBox:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		setFocusVisual(false)
	end)

	-- Clicking anywhere in the padded field focuses the caret, like a real input.
	container:EnableMouse(true)
	container:SetScript("OnMouseDown", function() editBox:SetFocus() end)

	----------------------------------------------------------------- interface
	function container:GetText() return editBox:GetText() end

	function container:SetText(value)
		value = value or ""
		lastText = value
		editBox:SetText(value)
		editBox:SetCursorPosition(#value)
		updatePlaceholder()
		applyHeight(value)
	end

	function container:Clear() container:SetText("") end
	function container:Focus() editBox:SetFocus() end
	function container:ClearFocus() editBox:ClearFocus() end
	function container:HasFocus() return editBox:HasFocus() end
	function container:SetPlaceholder(value)
		container.placeholder:SetText(value or "")
		updatePlaceholder()
	end
	function container:Insert(value)
		if not value then return end
		editBox:Insert(value)
		editBox:SetFocus()
	end
	function container:HighlightAll()
		editBox:HighlightText()
	end

	function container:ApplyTheme()
		container.surface:ApplyTheme()
		container.glow:SetRadius(Theme.Radius((opts.radius or ns.R.MD) + 2))
		editBox:SetFontObject(Theme.Font(opts.fontToken or "BODY"))
		local c = Theme.Get("textPrimary")
		editBox:SetTextColor(c[1], c[2], c[3], 1)
		W.RefreshText(container.placeholder)
		setFocusVisual(editBox:HasFocus())
		applyHeight(editBox:GetText())
	end

	updatePlaceholder()
	setFocusVisual(false)
	return container
end
