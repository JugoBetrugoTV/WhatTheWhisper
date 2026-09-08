-- WhatTheWhisper -- Copy, export and confirmation dialogs.
--
-- There is no clipboard API in WoW. What works, and what this does, is put the
-- text into an EditBox that already has focus and is already fully selected, so
-- the only thing left is Ctrl+C.

local _, ns = ...
local Theme, W, Anim, Export = ns.Theme, ns.Widgets, ns.Anim, ns.Export
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Dialogs = {}
ns.Dialogs = Dialogs

local max, min = math.max, math.min

-- An EditBox with hundreds of thousands of characters will stall the client, so
-- exports are capped and the dialog says so rather than freezing.
local MAX_CHARS = 30000
-- The scroll child's size before it has any text, and the room left under the
-- last line so a descender is never clipped by the viewport edge.
local EDIT_MIN_W, EDIT_MIN_H = 500, 40
local EDIT_SLACK = 8
local SCROLL_STEP = 40

local copyDialog, confirmDialog

--------------------------------------------------------------------------------
-- Shared chrome
--------------------------------------------------------------------------------

local function makeDialog(globalName, width, height)
	local d = CreateFrame("Frame", globalName, UIParent)
	d:SetSize(width, height)
	d:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	d:SetFrameStrata("FULLSCREEN_DIALOG")
	d:SetToplevel(true)
	d:EnableMouse(true)
	d:SetMovable(true)
	d:Hide()
	d.surface = W.Surface(d, {
		color = "bg1", border = "borderStrong", radius = ns.R.LG, shadow = 20,
	})

	d.header = CreateFrame("Frame", nil, d)
	d.header:SetHeight(ns.SZ.TITLEBAR_H + 4)
	d.header:SetPoint("TOPLEFT")
	d.header:SetPoint("TOPRIGHT")
	d.header:EnableMouse(true)
	d.header.divider = W.Hairline(d.header, "horizontal",
		{ anchor = "BOTTOM", color = "borderSubtle" })
	W.MakeWindowHandle(d.header, {
		onStartMove = function() d:StartMoving() d.moving = true end,
		onStopMove = function()
			if d.moving then d.moving = false d:StopMovingOrSizing() end
		end,
	})

	d.title = W.Text(d.header, "TITLE", "textPrimary")
	d.title:SetPoint("LEFT", d.header, "LEFT", ns.S.LG, 0)

	d.close = ns.Button.Icon(d.header, {
		icon = "close", size = ns.SZ.ICON_BTN_SM, glyph = ns.SZ.ICON_GLYPH_SM,
		onClick = function() d:Hide() end,
	})
	d.close:SetPoint("RIGHT", d.header, "RIGHT", -ns.S.SM, 0)

	if type(_G.UISpecialFrames) == "table" and globalName then
		local found
		for i = 1, #_G.UISpecialFrames do
			if _G.UISpecialFrames[i] == globalName then found = true break end
		end
		if not found then table.insert(_G.UISpecialFrames, globalName) end
	end
	return d
end

--------------------------------------------------------------------------------
-- Copy / export dialog
--------------------------------------------------------------------------------

local function buildCopy()
	if copyDialog then return copyDialog end
	local d = makeDialog("WhatTheWhisperCopyDialog", 560, 420)

	d.formats = ns.Controls.Dropdown(d, {
		width = 160, height = 28, options = {},
		onChange = function(value)
			d.format = value
			d.savedNote = nil
			if d.conv then d:SetContent(Export.Conversation(d.conv, value)) end
		end,
	})
	d.formats:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -ns.S.MD)

	-- There is no clipboard and no way to write a file the player picks, but
	-- saved variables *are* a file on disk. This puts the export there, where it
	-- can be opened in any editor after a reload -- which is what most people
	-- mean by "export" and what Ctrl+C alone never gave them.
	d.saveFile = ns.Button.Text(d, {
		text = L["Save to file"], variant = "subtle", minWidth = 118, height = 28,
		icon = "export",
		onClick = function() d:SaveToFile() end,
	})
	d.saveFile:SetPoint("LEFT", d.formats, "RIGHT", ns.S.SM, 0)
	d.saveFile:Hide()

	d.hint = W.Text(d, "MICRO", "textMuted")
	d.hint:SetPoint("LEFT", d.saveFile, "RIGHT", ns.S.MD, 0)
	d.hint:SetPoint("RIGHT", d, "RIGHT", -ns.S.LG, 0)
	d.hint:SetJustifyH("RIGHT")

	local box = CreateFrame("Frame", nil, d)
	box:SetPoint("TOPLEFT", d.formats, "BOTTOMLEFT", 0, -ns.S.MD)
	box:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)
	box.surface = W.Surface(box, { color = "inputBg", border = "borderSubtle", radius = ns.R.MD })
	d.box = box

	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", ns.S.MD, -ns.S.SM)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -ns.S.MD, ns.S.SM)
	scroll:EnableMouseWheel(true)
	d.scroll = scroll

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(Theme.Font("SMALL"))
	edit:SetMaxLetters(0)
	if edit.SetCountInvisibleLetters then edit:SetCountInvisibleLetters(false) end
	-- A scroll child needs a real size, and this one was created with none: a
	-- frame is 0x0 until told otherwise, and a 0-height child inside a scroll
	-- frame has nothing to draw and nothing to scroll. That is why the export
	-- box came up empty however much text was in it.
	edit:SetSize(EDIT_MIN_W, EDIT_MIN_H)
	edit:SetScript("OnEscapePressed", function() d:Hide() end)
	-- Read-only in practice: any edit is reverted, so the selection stays intact.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and d.content and self:GetText() ~= d.content then
			self:SetText(d.content)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	d.edit = edit

	-- The height has to be measured, not guessed: the client wraps the text and
	-- an export is mostly long lines. A hidden font string of the same face and
	-- width gives the real answer.
	function d:ResizeContent()
		local width = scroll:GetWidth() or 0
		if width <= 0 then width = EDIT_MIN_W end
		edit:SetWidth(width)
		local measure = Theme.Measure("SMALL")
		measure:SetWidth(width)
		measure:SetText(d.content or "")
		local height = math.max(scroll:GetHeight() or 0,
			(measure:GetStringHeight() or 0) + EDIT_SLACK, EDIT_MIN_H)
		edit:SetHeight(height)
		d.scrollRange = math.max(0, height - (scroll:GetHeight() or 0))
		if (scroll:GetVerticalScroll() or 0) > d.scrollRange then
			scroll:SetVerticalScroll(d.scrollRange)
		end
	end

	scroll:SetScript("OnSizeChanged", function() d:ResizeContent() end)
	-- Copying never needs the wheel -- everything is selected whatever is on
	-- screen -- but reading it before you copy does.
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = d.scrollRange or 0
		if range <= 0 then return end
		local at = (self:GetVerticalScroll() or 0) - delta * SCROLL_STEP
		self:SetVerticalScroll(math.max(0, math.min(range, at)))
	end)

	function d:SetContent(text)
		text = text or ""
		-- Cut on a character and escape boundary, not on a byte. A plain
		-- sub() here splits multi-byte characters in any non-English thread
		-- and can sever a |H...|h link, leaking raw markup into the box the
		-- player is about to copy.
		local truncated
		text, truncated = ns.Text.SafeByteLimit(text, MAX_CHARS)
		d.content = text
		edit:SetText(text)
		d.truncated = truncated
		d:RefreshHint()
		d:ResizeContent()
		d.scroll:SetVerticalScroll(0)
		if d:IsShown() then d:FocusContent() end
	end

	-- The whole dialog is one gesture: everything selected, keyboard focus in
	-- the box, Ctrl+C. All three only take on an edit box that is already on
	-- screen -- the client ignores SetFocus on a hidden one -- so this is never
	-- called before the window is up, and it is called again on every show.
	function d:FocusContent()
		edit:SetCursorPosition(0)
		edit:HighlightText()
		edit:SetFocus()
	end

	d:HookScript("OnShow", function() d:FocusContent() end)
	-- A focused edit box swallows the movement keys, so the focus goes back to
	-- the world the moment the dialog does.
	d:HookScript("OnHide", function() edit:ClearFocus() end)

	function d:SaveToFile()
		if not d.conv then return end
		local ok, detail = Export.ToFile(d.conv, d.format or "text")
		if ok then
			d.savedNote = L["Saved. It is in %s after your next reload or logout."]
				:format(Export.FilePath())
		elseif detail == "toobig" then
			d.savedNote = L["That conversation is too large to save."]
		else
			d.savedNote = L["There was nothing to save."]
		end
		d:RefreshHint()
	end

	function d:RefreshHint()
		-- What just happened beats what you could do next.
		if d.savedNote then
			d.hint:SetText(d.savedNote)
			W.SetTextRole(d.hint, "success")
			return
		end
		W.SetTextRole(d.hint, "textMuted")
		local hint = d.baseHint or L["Press Ctrl+C to copy, then Esc to close."]
		if d.truncated then
			hint = hint .. "  (" .. MAX_CHARS .. "+ )"
		end
		d.hint:SetText(hint)
	end

	function d:ApplyTheme()
		d.surface:ApplyTheme()
		d.header.divider:ApplyTheme()
		W.RefreshText(d.title)
		W.RefreshText(d.hint)
		d.close:ApplyTheme()
		d.formats:ApplyTheme()
		d.saveFile:ApplyTheme()
		box.surface:ApplyTheme()
		edit:SetFontObject(Theme.Font("SMALL"))
		local c = Theme.Get("textSecondary")
		edit:SetTextColor(c[1], c[2], c[3], 1)
	end

	copyDialog = d
	return d
end

function Dialogs.ShowCopy(text, title, hint)
	local d = buildCopy()
	d.conv = nil
	d.savedNote = nil
	d.formats:Hide()
	d.saveFile:Hide()
	d.title:SetText(title or L["Copy"])
	d.baseHint = hint or L["Press Ctrl+C to copy, then Esc to close."]
	d.hint:ClearAllPoints()
	d.hint:SetPoint("TOPRIGHT", d.header, "BOTTOMRIGHT", -ns.S.LG, -ns.S.MD - 6)
	d.hint:SetPoint("LEFT", d, "LEFT", ns.S.LG, 0)
	d.hint:SetJustifyH("RIGHT")
	d.box:ClearAllPoints()
	d.box:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -(ns.S.MD + ns.S.XL))
	d.box:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)
	local lines = select(2, text:gsub("\n", "")) + 1
	d:SetSize(560, min(420, max(180, 120 + lines * 16)))
	-- Shown first, filled second: see FocusContent.
	d:Show()
	d:SetContent(text)
	Anim.PopIn(d, Theme.Duration("SLOW"), 0.98)
end

function Dialogs.ShowExport(conv)
	if not conv then return end
	local d = buildCopy()
	d.conv = conv
	d.savedNote = nil
	d.saveFile:Show()
	d.baseHint = L["Press Ctrl+C to copy, or save it to a file."]
	d.title:SetText(L["Export"] .. " \194\183 " .. (conv.name or conv.id))
	d.formats:Show()
	d.formats:SetOptions(Export.FORMATS and (function()
		local options = {}
		for i = 1, #Export.FORMATS do
			options[i] = { value = Export.FORMATS[i].id, label = Export.FORMATS[i].label }
		end
		return options
	end)() or {})
	d.formats:SetValue(d.format or "text", false)
	d.hint:ClearAllPoints()
	d.hint:SetPoint("LEFT", d.saveFile, "RIGHT", ns.S.MD, 0)
	d.hint:SetPoint("RIGHT", d, "RIGHT", -ns.S.LG, 0)
	d.box:ClearAllPoints()
	d.box:SetPoint("TOPLEFT", d.formats, "BOTTOMLEFT", 0, -ns.S.MD)
	d.box:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)
	d:SetSize(620, 460)
	d:Show()
	d:SetContent(Export.Conversation(conv, d.format or "text"))
	Anim.PopIn(d, Theme.Duration("SLOW"), 0.98)
end

--------------------------------------------------------------------------------
-- Confirmation
--------------------------------------------------------------------------------

local function buildConfirm()
	if confirmDialog then return confirmDialog end
	local d = makeDialog("WhatTheWhisperConfirmDialog", 400, 190)

	d.body = W.Text(d, "SMALL", "textSecondary")
	d.body:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -ns.S.LG)
	d.body:SetPoint("TOPRIGHT", d.header, "BOTTOMRIGHT", -ns.S.LG, -ns.S.LG)
	d.body:SetJustifyH("LEFT")
	d.body:SetJustifyV("TOP")
	d.body:SetWordWrap(true)

	d.confirm = ns.Button.Text(d, {
		text = L["Confirm"], variant = "primary", minWidth = 96,
		onClick = function()
			local callback = d.callback
			d:Hide()
			if callback then ns.Guard("Dialogs.confirm", callback) end
		end,
	})
	d.confirm:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)

	d.cancel = ns.Button.Text(d, {
		text = L["Cancel"], variant = "ghost", minWidth = 88,
		onClick = function() d:Hide() end,
	})
	d.cancel:SetPoint("RIGHT", d.confirm, "LEFT", -ns.S.SM, 0)

	function d:ApplyTheme()
		d.surface:ApplyTheme()
		d.header.divider:ApplyTheme()
		W.RefreshText(d.title)
		W.RefreshText(d.body)
		d.close:ApplyTheme()
		d.confirm:ApplyTheme()
		d.cancel:ApplyTheme()
	end

	confirmDialog = d
	return d
end

function Dialogs.Confirm(title, body, confirmLabel, onConfirm, danger)
	local d = buildConfirm()
	d.title:SetText(title or "")
	d.body:SetText(body or "")
	d.callback = onConfirm
	d.confirm:SetText(confirmLabel or L["Confirm"])
	d.confirm:SetVariant(danger and "danger" or "primary")
	local bodyHeight = d.body:GetStringHeight() or 20
	d:SetHeight(ns.SZ.TITLEBAR_H + 4 + ns.S.LG + bodyHeight + ns.S.XXL + 32 + ns.S.LG)
	d:Show()
	Anim.PopIn(d, Theme.Duration("SLOW"), 0.98)
end

function Dialogs.ApplyTheme()
	if copyDialog then copyDialog:ApplyTheme() end
	if confirmDialog then confirmDialog:ApplyTheme() end
	if ns.Dialogs.promptDialog then ns.Dialogs.promptDialog:ApplyTheme() end
end

--------------------------------------------------------------------------------
-- Single-line prompt
--------------------------------------------------------------------------------

local promptDialog

-- Two lines of MICRO text, reserved whether or not there is anything to say, so
-- that a rejected name does not make the dialog jump under the cursor.
local PROMPT_ERROR_H = 30

function Dialogs.Prompt(title, label, placeholder, acceptLabel, onAccept, validate)
	if not promptDialog then
		local d = makeDialog("WhatTheWhisperPromptDialog", 380, 180 + PROMPT_ERROR_H)
		d.label = W.Text(d, "SMALL", "textSecondary")
		d.label:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -ns.S.LG)

		d.input = ns.Input.New(d, { minHeight = 32, radius = ns.R.MD,
			onEnter = function() d.accept:GetScript("OnMouseUp")(d.accept, "LeftButton") end,
			-- Typing is the player answering the complaint, so the complaint goes
			-- away as they do it rather than sitting there being wrong.
			onChange = function() d:SetError(nil) end })
		d.input:SetPoint("TOPLEFT", d.label, "BOTTOMLEFT", 0, -ns.S.SM)
		d.input:SetPoint("RIGHT", d, "RIGHT", -ns.S.LG, 0)

		d.error = W.Text(d, "MICRO", "danger")
		d.error:SetPoint("TOPLEFT", d.input, "BOTTOMLEFT", ns.S.XS, -ns.S.SM)
		d.error:SetPoint("RIGHT", d, "RIGHT", -ns.S.LG, 0)
		d.error:SetHeight(PROMPT_ERROR_H - ns.S.SM)
		d.error:SetJustifyH("LEFT")
		d.error:SetJustifyV("TOP")
		d.error:SetWordWrap(true)
		d.error:Hide()

		function d:SetError(message)
			d.error:SetText(message or "")
			d.error:SetShown(message ~= nil and message ~= "")
		end

		d.accept = ns.Button.Text(d, {
			text = "", variant = "primary", minWidth = 96,
			onClick = function()
				local value = ns.Text.Trim(d.input:GetText())
				if value == "" then return end
				-- Refused here rather than three frames later in the chat
				-- stream, where a name that cannot exist looks exactly like a
				-- message that was delivered.
				if d.validate then
					local complaint = d.validate(value)
					if complaint then
						d:SetError(complaint)
						d.input:Focus()
						return
					end
				end
				local callback = d.callback
				d:Hide()
				if callback then ns.Guard("Dialogs.prompt", callback, value) end
			end,
		})
		d.accept:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)

		d.cancel = ns.Button.Text(d, {
			text = L["Cancel"], variant = "ghost", minWidth = 88,
			onClick = function() d:Hide() end,
		})
		d.cancel:SetPoint("RIGHT", d.accept, "LEFT", -ns.S.SM, 0)

		function d:ApplyTheme()
			d.surface:ApplyTheme()
			d.header.divider:ApplyTheme()
			W.RefreshText(d.title)
			W.RefreshText(d.label)
			W.RefreshText(d.error)
			d.close:ApplyTheme()
			d.input:ApplyTheme()
			d.accept:ApplyTheme()
			d.cancel:ApplyTheme()
		end

		promptDialog = d
		ns.Dialogs.promptDialog = d
	end

	local d = promptDialog
	d.title:SetText(title or "")
	d.label:SetText(label or "")
	d.input:SetPlaceholder(placeholder or "")
	d.input:SetText("")
	d.accept:SetText(acceptLabel or L["Open"])
	d.callback = onAccept
	d.validate = validate
	d:SetError(nil)
	d:Show()
	Anim.PopIn(d, Theme.Duration("SLOW"), 0.98)
	d.input:Focus()
end
