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
	-- No rule above the composer. The composer's own surface is a shade darker
	-- than the thread it sits under, which is separation enough -- a line as
	-- well is the belt-and-braces look that makes an interface feel heavy.
	c.emoji = ns.Button.Icon(c, {
		icon = "emoji", size = ns.SZ.ICON_BTN, radius = ns.R.PILL,
		tooltip = L["Emoji"],
		onClick = function(self) ns.EmojiPicker.Toggle(self, c) end,
	})
	-- The composer sits on the same column as the thread above it: its left
	-- margin is the message list's padding, and its right margin is that plus
	-- the scrollbar gutter, so the send button lines up with the right edge of
	-- the outgoing bubbles instead of hanging past them.
	local LEFT_MARGIN = ns.SZ.LIST_PAD_X
	local RIGHT_MARGIN = ns.SZ.LIST_PAD_X + ns.SZ.SCROLLBAR_HIT

	c.send = ns.Button.Send(c, {
		tooltip = L["Send"],
		onClick = function() c:Submit() end,
	})

	-- Both buttons are shorter than the field beside them and sit centred on it.
	-- The field's height is not a constant -- it is one line of whatever size
	-- the player set the font to, and it grows as a message wraps -- so the
	-- offset is recomputed rather than derived once from COMPOSER_FIELD_H. It
	-- used to be, and the result was a one pixel misalignment at the default
	-- font scale that got worse at every larger one.
	c.margins = { left = LEFT_MARGIN, right = RIGHT_MARGIN }

	c.input = ns.Input.New(c, {
		multiline = true,
		placeholder = L["Type a message..."],
		minHeight = ns.SZ.COMPOSER_FIELD_H,
		maxHeight = ns.SZ.COMPOSER_MAX_H - PAD * 2,
		-- A pill while it holds one line, which is what it holds almost always.
		-- Draw.RoundedRect clamps the radius to half the shorter side, so this
		-- relaxes into a rounded rectangle on its own as the field grows.
		radius = ns.R.PILL,
		-- The one field in the addon that is drawn with a line around it.
		-- Everywhere else a filled shape on a darker panel is unmistakably a
		-- field and an outline is the clearest tell that something was drawn
		-- with a game toolkit -- but the Messages composer is stroked, and it is
		-- the field the eye goes to first.
		border = "borderStrong",
		-- Room kept clear for the send arrow, which is drawn inside the field.
		insetRight = ns.SZ.SEND_BTN,
		onEnter = function() c:Submit() end,
		onChange = function(value) c:OnTextChanged(value) end,
		onResize = function() c:Relayout() end,
		onEscape = function()
			if ns.UI then ns.UI.OnComposerEscape() end
		end,
	})
	c.input:SetPoint("LEFT", c.emoji, "RIGHT", ns.S.SM, 0)
	c.input:SetPoint("RIGHT", c, "RIGHT", -RIGHT_MARGIN, 0)
	c.input:SetPoint("BOTTOM", c, "BOTTOM", 0, PAD)
	-- The send arrow is drawn over the field, so it has to be told to sit above
	-- it: siblings built in either order end up on the same frame level, and
	-- which of them wins is not something to leave to creation order.
	c.send:SetFrameLevel((c.input:GetFrameLevel() or 1) + 2)

	-- Above the field, right aligned with it, and the composer grows to make
	-- room for it rather than overlapping whatever is above. It used to be
	-- tucked into the gap over the field, where at the default font scale it
	-- stuck three pixels into the message list -- and further at every larger
	-- font scale, which is exactly when a player needs to read it.
	c.counter = W.Text(c, "MICRO", "textMuted")
	c.counter:SetPoint("BOTTOMRIGHT", c.input, "TOPRIGHT", 0, ns.S.XS)
	c.counter:SetJustifyH("RIGHT")
	c.counter:Hide()

	c:Relayout()
	return c
end

-- Both buttons sit on the last line of the field, not on the middle of it: once
-- a message wraps, the field grows upward and they stay with the line being
-- typed, which is where the hand already is.
--
-- The emoji button is outside the field on the left and the send arrow is inside
-- it on the right, which is how Messages arranges the two. The arrow being
-- inside is what makes the field read as the thing you are working in rather
-- than as one control in a row of three.
function C:PositionButtons(fieldHeight)
	local line = math.min(fieldHeight, self.input:SingleLineHeight())
	local function lift(size) return PAD + (line - size) / 2 end
	self.emoji:ClearAllPoints()
	self.emoji:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT",
		self.margins.left, lift(ns.SZ.ICON_BTN))
	-- The same gap under the arrow as beside it, so it sits in the field's
	-- corner rather than on its edge.
	local inset = math.max(2, (line - ns.SZ.SEND_BTN) / 2)
	self.send:ClearAllPoints()
	self.send:SetPoint("BOTTOMRIGHT", self.input, "BOTTOMRIGHT", -inset, inset)
end

function C:Relayout()
	local inputHeight = self.input:GetHeight() or ns.SZ.COMPOSER_FIELD_H
	self:PositionButtons(inputHeight)
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

-- The placeholder names the thread, and that name changes under it: a nickname
-- given or taken away, the realm setting, the language. It used to be written
-- only when the thread changed, so "Message <old nickname>..." stayed in the
-- field after the nickname was gone.
function C:RefreshPlaceholder()
	local conv = self.conv
	if conv then
		self.input:SetPlaceholder(L["Message %s..."]:format(
			ns.ConversationManager.DisplayName(conv)))
	else
		self.input:SetPlaceholder(L["Type a message..."])
	end
end

function C:SetConversation(conv)
	if self.conv == conv then
		self:RefreshPlaceholder()
		return
	end
	-- Keep the half-typed message with the thread it belongs to.
	if self.conv then
		ns.ConversationManager.SetDraft(self.conv.id, self.input:GetText())
	end
	self.conv = conv
	self:RefreshPlaceholder()
	self.input:SetText(conv and conv.draft or "")
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
	self:RefreshPlaceholder()
	self:OnTextChanged(self.input:GetText())
end

function C:ApplyTheme()
	self.surface:ApplyTheme()
	self.emoji:ApplyTheme()
	self.send:ApplyTheme()
	self.input:ApplyTheme()
	W.RefreshText(self.counter)
	self:Relayout()
end
