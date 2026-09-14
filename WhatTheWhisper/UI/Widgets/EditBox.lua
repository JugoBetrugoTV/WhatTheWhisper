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

-- Below this a field has not been laid out yet and its width means nothing.
-- Narrower than any field the addon actually builds, so a real one is never
-- mistaken for an unresolved one.
local MIN_FIT_WIDTH = 60

local PAD_X = ns.S.MD
-- Half the difference between a 40px field and the line of text in it, near
-- enough. Written as a step off the scale rather than as the number it works out
-- to, so it moves with the scale if the scale moves.
local PAD_Y = ns.S.SM + 2

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

	-- No border unless one is asked for. A filled field on a darker panel is
	-- already unmistakably a field, and an outline around it is the single
	-- clearest tell that something was drawn with a game toolkit: every native
	-- messenger's input is a shape, not a shape with a line around it.
	container.surface = W.Surface(container, {
		color = "inputBg",
		border = opts.border,
		radius = opts.radius or ns.R.MD,
	})

	-- Focus glow sits outside the field so the ring reads without moving layout.
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

	-- Anchored on both sides in either mode. A placeholder is "Message <name>",
	-- and a name plus a realm is long enough that an unbounded font string runs
	-- straight out of the composer and over whatever is next to it.
	container.placeholder = W.Text(container, opts.fontToken or "BODY", "textMuted")
	container.placeholder:SetPoint("RIGHT", container, "RIGHT", -PAD_X, 0)
	if opts.multiline then
		container.placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", PAD_X, -PAD_Y)
		container.placeholder:SetJustifyV("TOP")
	else
		container.placeholder:SetPoint("LEFT", container, "LEFT", PAD_X, 0)
	end
	container.placeholder:SetWordWrap(false)

	-- Fitted to the field rather than left to run out of it. "Message
	-- Sylvanas-Blackrock..." is longer than a popout's composer is wide, and a
	-- placeholder that does not wrap simply keeps going -- over the thread above
	-- it in the mock, and clipped mid-word in the game. Neither is readable.
	function container:FitPlaceholder()
		local text = container.placeholderText or ""
		local room = (container:GetWidth() or 0) - PAD_X * 2
		-- The caret's own inset, where something has shifted the text right to
		-- make room for a glyph -- the search field's magnifier.
		local textLeft = select(4, container.editBox:GetPoint(1))
		if type(textLeft) == "number" and textLeft > PAD_X then
			room = room - (textLeft - PAD_X)
		end
		-- A field whose width is not settled yet reports a useless one, and
		-- fitting to that would shorten the placeholder to "Search c..." and
		-- leave it there. Shortening is only ever right against a real width, so
		-- until there is one the text stays whole and the next fit does the job.
		if room < MIN_FIT_WIDTH then
			container.placeholder:SetText(text)
			container.placeholder.__wtwTruncated = false
			return
		end
		ns.Text.Ellipsize(container.placeholder, text, room)
	end

	-- Re-fitted whenever the field's width changes and again when it becomes
	-- visible. A field built inside a window that has not been laid out yet
	-- reports a width that means nothing, and the fit it produces from that is
	-- wrong and permanent -- the settings pane's "Search set..." was exactly
	-- that. By the time it is on screen the width is real.
	container:HookScript("OnSizeChanged", function()
		container:FitPlaceholder()
	end)
	container:HookScript("OnShow", function()
		container:FitPlaceholder()
	end)

	container.placeholderText = opts.placeholder or ""
	container:FitPlaceholder()

	----------------------------------------------------------------- behaviour
	local lastText = ""

	local function updatePlaceholder()
		local empty = editBox:GetText() == ""
		-- Re-fitted on the way in, when the field's width is settled: this runs
		-- on every text change and on every conversation change, which is every
		-- moment the placeholder is about to be looked at.
		if empty then container:FitPlaceholder() end
		container.placeholder:SetShown(empty)
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

	-- How tall this field is when it holds exactly one line.
	--
	-- Not minHeight: that is a floor, and at a larger font scale a single line
	-- is taller than it. Anything lining something up with the field -- the
	-- composer's two buttons -- has to ask for this rather than assume the
	-- floor, or it is a pixel out at the default scale and further at every
	-- other one.
	--
	-- Measured through measureHeight rather than beside it, so the answer is
	-- produced by the same code that decides the field's real height. Two
	-- measurements of the same thing disagree eventually, and the disagreement
	-- is exactly one pixel of misalignment that nobody can find.
	function container:SingleLineHeight()
		return measureHeight("Ag")
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

	-- Focus is mostly the field getting lighter, and only faintly a ring around
	-- it. The other way round -- a bright outline on an unchanged fill -- is how
	-- a form control announces itself; this is how a messenger does it.
	local function setFocusVisual(focused)
		local duration = Theme.Duration("FAST")
		local base = Theme.Get("inputBg")
		if focused then
			local lifted = ns.Color.Mix(base, Theme.Get("textPrimary"), 0.06)
			W.FadeSurfaceToColor(container.surface, container,
				lifted[1], lifted[2], lifted[3], base[4] or 1, duration)
			local ring = Theme.Get("focusRing")
			container.glow:SetColor(ring[1], ring[2], ring[3], 0)
			container.glow:Show()
			Anim.To(container.glow, duration, 0, 0.18, function(v)
				container.glow:SetColor(ring[1], ring[2], ring[3], v)
			end)
		else
			W.FadeSurfaceToColor(container.surface, container,
				base[1], base[2], base[3], base[4] or 1, duration)
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
		-- The whole string is kept; what goes on the font string is whatever
		-- fits the field right now, and it is re-derived from this every time
		-- the field or the font changes.
		container.placeholderText = value or ""
		container:FitPlaceholder()
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
		-- From the whole string, not from whatever is currently on the font
		-- string: the font just changed, and re-fitting an already-shortened
		-- placeholder only ever shortens it again. It never grows back.
		container:FitPlaceholder()
		setFocusVisual(editBox:HasFocus())
		applyHeight(editBox:GetText())
	end

	updatePlaceholder()
	setFocusVisual(false)
	return container
end
