-- WhatTheWhisper -- The message composer.
--
-- Enter sends, Shift+Enter starts a new line, Escape gives focus back to the
-- game. Input longer than a whisper is split into legal chunks and the composer
-- says so before you press Enter rather than after.

local _, ns = ...
local W, Text = ns.Widgets, ns.Text
local L = ns.L

local Composer = {}
ns.Composer = Composer

local PAD = ns.S.MD
-- Bytes of input after which the composer starts saying how much room is left.
local WARN_AT = 200
-- ...and how few remaining bytes make it worth colouring.
local CLOSE_TO_LIMIT = 20

local C = {}

function Composer.New(parent, opts)
	opts = opts or {}
	local c = CreateFrame("Frame", nil, parent)
	for k, v in pairs(C) do c[k] = v end
	c:SetHeight(ns.SZ.COMPOSER_MIN_H)
	c.opts = opts

	c.surface = W.Surface(c, { color = "composerBg" })
	c.divider = W.Hairline(c, "horizontal", { anchor = "TOP", color = "borderSubtle" })

	c.emoji = ns.Button.Icon(c, {
		icon = "smiley", size = ns.SZ.ICON_BTN, tooltip = L["Emoji"],
		onClick = function(self) ns.EmojiPicker.Toggle(self, c) end,
	})
	-- The composer sits on the same column as the thread above it: its left
	-- margin is the message list's padding, and its right margin is that plus
	-- the scrollbar gutter, so the send button lines up with the right edge of
	-- the outgoing bubbles instead of hanging past them.
	local LEFT_MARGIN = ns.SZ.LIST_PAD_X
	local RIGHT_MARGIN = ns.SZ.LIST_PAD_X + ns.SZ.SCROLLBAR_HIT

	-- Both buttons are shorter than the field beside them, so each is lifted by
	-- half the difference rather than by a number somebody eyeballed.
	local function centreOnField(height)
		return PAD + (ns.SZ.COMPOSER_FIELD_H - height) / 2
	end

	c.emoji:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT",
		LEFT_MARGIN, centreOnField(ns.SZ.ICON_BTN))

	c.send = ns.Button.Send(c, {
		tooltip = L["Send"],
		onClick = function() c:Submit() end,
	})
	c.send:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT",
		-RIGHT_MARGIN, centreOnField(ns.SZ.SEND_BTN))

	c.input = ns.Input.New(c, {
		multiline = true,
		placeholder = L["Type a message..."],
		minHeight = ns.SZ.COMPOSER_FIELD_H,
		maxHeight = ns.SZ.COMPOSER_MAX_H - PAD * 2,
		radius = ns.R.MD,
		onEnter = function() c:Submit() end,
		onChange = function(value) c:OnTextChanged(value) end,
		onResize = function() c:Relayout() end,
		onEscape = function()
			if ns.UI then ns.UI.OnComposerEscape() end
		end,
	})
	c.input:SetPoint("LEFT", c.emoji, "RIGHT", ns.S.SM, 0)
	c.input:SetPoint("RIGHT", c.send, "LEFT", -ns.S.SM, 0)
	c.input:SetPoint("BOTTOM", c, "BOTTOM", 0, PAD)

	-- Above the field, right aligned with it, and the composer grows to make
	-- room for it. It used to be tucked into the gap between the send button and
	-- the divider, where at the default font scale it stuck three pixels
	-- *through* the divider into the message list -- and further at every larger
	-- font scale, which is exactly when a player needs to read it.
	c.counter = W.Text(c, "MICRO", "textMuted")
	c.counter:SetPoint("BOTTOMRIGHT", c.input, "TOPRIGHT", 0, ns.S.XS)
	c.counter:SetJustifyH("RIGHT")
	c.counter:Hide()

	c:Relayout()
	return c
end

function C:Relayout()
	local inputHeight = self.input:GetHeight() or ns.SZ.COMPOSER_FIELD_H
	local counterHeight = 0
	if self.counter:IsShown() then
		counterHeight = (self.counter:GetStringHeight() or 0) + ns.S.XS
	end
	local height = math.min(ns.SZ.COMPOSER_MAX_H,
		math.max(ns.SZ.COMPOSER_MIN_H, inputHeight + PAD * 2 + counterHeight))
	if math.abs(height - (self:GetHeight() or 0)) > 0.5 then
		self:SetHeight(height)
		if self.opts.onResize then ns.Guard("Composer.onResize", self.opts.onResize, height) end
	end
end

function C:SetConversation(conv)
	if self.conv == conv then return end
	-- Keep the half-typed message with the thread it belongs to.
	if self.conv then
		ns.ConversationManager.SetDraft(self.conv.id, self.input:GetText())
	end
	self.conv = conv
	if conv then
		self.input:SetPlaceholder(L["Message %s..."]:format(
			ns.ConversationManager.DisplayName(conv)))
		self.input:SetText(conv.draft or "")
	else
		self.input:SetPlaceholder(L["Type a message..."])
		self.input:SetText("")
	end
	self:OnTextChanged(self.input:GetText())
	self:SetShown(conv ~= nil)
end

function C:OnTextChanged(value)
	value = value or ""
	local trimmed = Text.Trim(value)
	self.send:SetActive(trimmed ~= "" and self.conv ~= nil)
	if self.conv then
		ns.ConversationManager.SetDraft(self.conv.id, value)
	end

	local bytes = #value
	if bytes >= WARN_AT then
		local parts = #Text.SplitForSend(trimmed, ns.MAX_MESSAGE_BYTES)
		if parts > 1 then
			self.counter:SetText(L["Will be sent as %d messages"]:format(parts))
			W.SetTextRole(self.counter, "warning")
		else
			local left = ns.MAX_MESSAGE_BYTES - bytes
			self.counter:SetText(tostring(left))
			-- The countdown only earns colour once it is nearly out; before
			-- that it is information, not a problem.
			W.SetTextRole(self.counter, left <= CLOSE_TO_LIMIT and "warning" or "textMuted")
		end
		self.counter:Show()
	else
		self.counter:Hide()
	end
	-- The composer is a different height with the counter than without it.
	self:Relayout()
end

function C:Submit()
	if not self.conv then return end
	local value = Text.Trim(self.input:GetText())
	if value == "" then return end
	local sent = ns.ConversationManager.SendMessage(self.conv.id, value)
	if sent then
		self.input:SetText("")
		self:OnTextChanged("")
	end
	self.input:Focus()
end

function C:Focus()
	self.input:Focus()
end

function C:HasFocus()
	return self.input:HasFocus()
end

function C:Insert(value)
	self.input:Insert(value)
end

-- The player changed the language. Everything below was written once, when the
-- frame was built, which is exactly why none of it can notice on its own.
function C:Relocalize()
	W.SetTooltip(self.emoji, L["Emoji"])
	W.SetTooltip(self.send, L["Send"])
	-- SetConversation early-outs on the thread it is already showing, so the
	-- placeholder is re-derived here rather than by pretending the thread moved.
	local conv = self.conv
	if conv then
		self.input:SetPlaceholder(L["Message %s..."]:format(
			ns.ConversationManager.DisplayName(conv)))
	else
		self.input:SetPlaceholder(L["Type a message..."])
	end
	self:OnTextChanged(self.input:GetText())
end

function C:ApplyTheme()
	self.surface:ApplyTheme()
	self.divider:ApplyTheme()
	self.emoji:ApplyTheme()
	self.send:ApplyTheme()
	self.input:ApplyTheme()
	W.RefreshText(self.counter)
	self:Relayout()
end
