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
		icon = "close", size = 26, glyph = 13,
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
			if d.conv then d:SetContent(Export.Conversation(d.conv, value)) end
		end,
	})
	d.formats:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -ns.S.MD)

	d.hint = W.Text(d, "MICRO", "textMuted")
	d.hint:SetPoint("LEFT", d.formats, "RIGHT", ns.S.MD, 0)
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
	d.scroll = scroll

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(Theme.Font("SMALL"))
	edit:SetMaxLetters(0)
	if edit.SetCountInvisibleLetters then edit:SetCountInvisibleLetters(false) end
	edit:SetWidth(500)
	edit:SetScript("OnEscapePressed", function() d:Hide() end)
	-- Read-only in practice: any edit is reverted, so the selection stays intact.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and d.content and self:GetText() ~= d.content then
			self:SetText(d.content)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnSizeChanged", function(_, width)
		if width and width > 0 then edit:SetWidth(width) end
	end)
	d.edit = edit

	function d:SetContent(text)
		text = text or ""
		local truncated = false
		if #text > MAX_CHARS then
			text = text:sub(1, MAX_CHARS)
			truncated = true
		end
		d.content = text
		edit:SetText(text)
		edit:SetCursorPosition(0)
		edit:HighlightText()
		edit:SetFocus()
		d.truncated = truncated
		d:RefreshHint()
	end

	function d:RefreshHint()
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
	d.formats:Hide()
	d.title:SetText(title or L["Copy"])
	d.baseHint = hint or L["Press Ctrl+C to copy, then Esc to close."]
	d.hint:ClearAllPoints()
	d.hint:SetPoint("TOPRIGHT", d.header, "BOTTOMRIGHT", -ns.S.LG, -ns.S.MD - 6)
	d.hint:SetJustifyH("RIGHT")
	d.box:ClearAllPoints()
	d.box:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -(ns.S.MD + ns.S.XL))
	d.box:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)
	local lines = select(2, text:gsub("\n", "")) + 1
	d:SetSize(560, min(420, max(180, 120 + lines * 16)))
	d:SetContent(text)
	d:Show()
	Anim.PopIn(d, Theme.Duration("SLOW"), 0.98)
end

function Dialogs.ShowExport(conv)
	if not conv then return end
	local d = buildCopy()
	d.conv = conv
	d.baseHint = L["Press Ctrl+C to copy, then Esc to close."]
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
	d.hint:SetPoint("LEFT", d.formats, "RIGHT", ns.S.MD, 0)
	d.hint:SetPoint("RIGHT", d, "RIGHT", -ns.S.LG, 0)
	d.box:ClearAllPoints()
	d.box:SetPoint("TOPLEFT", d.formats, "BOTTOMLEFT", 0, -ns.S.MD)
	d.box:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -ns.S.LG, ns.S.LG)
	d:SetSize(620, 460)
	d:SetContent(Export.Conversation(conv, d.format or "text"))
	d:Show()
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

function Dialogs.Prompt(title, label, placeholder, acceptLabel, onAccept)
	if not promptDialog then
		local d = makeDialog("WhatTheWhisperPromptDialog", 380, 180)
		d.label = W.Text(d, "SMALL", "textSecondary")
		d.label:SetPoint("TOPLEFT", d.header, "BOTTOMLEFT", ns.S.LG, -ns.S.LG)

		d.input = ns.Input.New(d, { minHeight = 32, radius = ns.R.MD,
			onEnter = function() d.accept:GetScript("OnMouseUp")(d.accept, "LeftButton") end })
		d.input:SetPoint("TOPLEFT", d.label, "BOTTOMLEFT", 0, -ns.S.SM)
		d.input:SetPoint("RIGHT", d, "RIGHT", -ns.S.LG, 0)

		d.accept = ns.Button.Text(d, {
			text = "", variant = "primary", minWidth = 96,
			onClick = function()
				local value = ns.Text.Trim(d.input:GetText())
				local callback = d.callback
				if value == "" then return end
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
	d:Show()
	Anim.PopIn(d, Theme.Duration("SLOW"), 0.98)
	d.input:Focus()
end
