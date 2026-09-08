-- WhatTheWhisper -- Who you are talking to, spelled out.
--
-- The header line can only carry a few words before it starts truncating, and
-- what it carries is whatever happened to be known. This panel is the long form:
-- one labelled row per fact, every row the client can answer, and -- this is the
-- part that matters -- a row for the ones it has *not* answered, so a missing
-- guild reads as "not looked up yet" rather than as a hole in the window.
--
-- Nothing here is invented. A row whose value the client has never given says so
-- in as many words, and offers the one thing that would fill it in.

local _, ns = ...
local W, Compat = ns.Widgets, ns.Compat
local PI = ns.PlayerInfo
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local ProfilePanel = {}
ns.ProfilePanel = ProfilePanel

local P = {}

local ROW_H = 18
local LABEL_W = 62
local PAD_X, PAD_Y = ns.S.LG, ns.S.SM
-- Two columns. Six facts stacked in one column is a tall panel using a quarter
-- of a wide window, and the window is wide.
local COLUMNS = 2
local COLUMN_GAP = ns.S.XL
-- Below this the columns would squeeze the values into ellipses, so the panel
-- falls back to one.
local MIN_COLUMN_W = 190
local LOOKUP_H = 22

--------------------------------------------------------------------------------
-- What we know
--------------------------------------------------------------------------------

local function localizedClass(classFile)
	if not classFile then return nil end
	local names = _G.LOCALIZED_CLASS_NAMES_MALE
	return (names and names[classFile]) or classFile
end

-- Every row the panel can show, in the order it shows them. `value` returns the
-- text or nil; nil means the client has not told us, and the row then renders as
-- unknown rather than disappearing.
local FIELDS = {
	{ key = "class",  label = "Class",
	  value = function(e) return localizedClass(e and e.class) end },
	{ key = "level",  label = "Level",
	  value = function(e)
			if not e or not e.level or e.level <= 0 then return nil end
			return tostring(e.level)
		end },
	{ key = "race",   label = "Race",
	  value = function(e) return e and e.race end },
	{ key = "guild",  label = "Guild",
	  value = function(e)
			if not e or not e.guild or e.guild == "" then return nil end
			return "<" .. e.guild .. ">"
		end },
	{ key = "zone",   label = "Zone",
	  value = function(e)
			if not e or not e.zone or e.zone == "" then return nil end
			return e.zone
		end },
	{ key = "realm",  label = "Realm",
	  value = function(_, conv)
			if not conv or conv.isBN then return nil end
			return Compat.RealmOf(conv.id) or Compat.GetRealmName()
		end },
}

-- Battle.net threads are a different person altogether: there is no character
-- behind the name until they are playing one, so the panel says what the client
-- actually knows about the account instead of six empty character rows.
local BN_FIELDS = {
	{ key = "battletag", label = "BattleTag",
	  value = function(_, conv) return conv and conv.battleTag end },
	{ key = "character", label = "Character",
	  value = function(_, conv)
			if not conv or not conv.bnetAccountID then return nil end
			local _, _, _, character = Compat.GetBNAccountInfoByID(conv.bnetAccountID)
			return character
		end },
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function createRow(panel)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row.label = W.Text(row, "MICRO", "textMuted")
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetWidth(LABEL_W)
	row.label:SetJustifyH("LEFT")
	row.value = W.Text(row, "MICRO", "textSecondary")
	row.value:ClearAllPoints()
	row.value:SetPoint("LEFT", row, "LEFT", LABEL_W + ns.S.SM, 0)
	row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.value:SetJustifyH("LEFT")
	row.value:SetJustifyH("LEFT")
	row.value:SetWordWrap(false)
	return row
end

function ProfilePanel.New(parent)
	local panel = CreateFrame("Frame", nil, parent)
	for k, v in pairs(P) do panel[k] = v end
	panel.surface = W.Surface(panel, { color = "bg3" })
	panel.divider = W.Hairline(panel, "horizontal",
		{ anchor = "BOTTOM", color = "borderSubtle" })
	panel.rows = {}
	panel:Hide()

	-- The one action that can fill in a blank row, put where the blank rows are.
	panel.lookup = ns.Button.Text(panel, {
		text = L["Look up"], variant = "subtle", minWidth = 84, height = LOOKUP_H,
		token = "MICRO", icon = "search", glyph = ns.SZ.ICON_GLYPH_XS,
		onClick = function() panel:Lookup() end,
	})
	panel.lookup:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD_X, PAD_Y)
	panel.lookup:Hide()

	return panel
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

function P:Row(index)
	local row = self.rows[index]
	if not row then
		row = createRow(self)
		self.rows[index] = row
	end
	return row
end

function P:SetConversation(conv)
	self.conv = conv
	self:Refresh()
end

function P:Refresh()
	local conv = self.conv
	if not conv or not self:IsShown() then return end

	local entry = not conv.isBN and PI.Get(conv.id) or nil
	local fields = conv.isBN and BN_FIELDS or FIELDS

	local inner = (self:GetWidth() or 0) - PAD_X * 2
	local columns = COLUMNS
	if inner < MIN_COLUMN_W * COLUMNS + COLUMN_GAP then columns = 1 end
	local columnW = columns > 1
		and ((inner - COLUMN_GAP * (columns - 1)) / columns) or inner
	local perColumn = math.ceil(#fields / columns)

	local unknown = 0
	for i = 1, #fields do
		local field = fields[i]
		local row = self:Row(i)
		-- pcall rather than ns.Guard: Guard reports and returns whether it went
		-- well, and what this needs is the answer. A field accessor that throws
		-- must not blank the other five rows, but it must still be reported.
		local ok, value = pcall(field.value, entry, conv)
		if not ok then
			ns.SoftError("ProfilePanel." .. tostring(field.key), value)
			value = nil
		end
		row.label:SetText(L[field.label])
		if value and value ~= "" then
			row.value:SetText(value)
			W.SetTextRole(row.value, "textSecondary")
		else
			-- Said out loud rather than left blank: an empty row looks like a
			-- bug, and "not known" is a fact about the client, not about them.
			row.value:SetText(L["not known"])
			W.SetTextRole(row.value, "textDisabled")
			unknown = unknown + 1
		end

		local column = math.floor((i - 1) / perColumn)
		local indexInColumn = (i - 1) % perColumn
		local x = PAD_X + column * (columnW + COLUMN_GAP)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(PAD_Y + indexInColumn * ROW_H))
		row:SetWidth(columnW)
		row:Show()
	end
	for i = #fields + 1, #self.rows do self.rows[i]:Hide() end
	local y = PAD_Y + perColumn * ROW_H

	-- The lookup is only offered where it can actually answer: on this realm,
	-- for a character, on a client that has the API.
	local canLookUp = not conv.isBN and Compat.canWho
		and not Compat.IsCrossRealm(conv.id) and unknown > 0
	self.lookup:SetShown(canLookUp)

	-- The button gets a row of its own. Tucking it into whatever space the last
	-- column happens to leave means it lands on a value as soon as the column
	-- count or the field list changes.
	local height = y + PAD_Y + (canLookUp and (LOOKUP_H + ns.S.SM) or 0)
	if math.abs(height - (self:GetHeight() or 0)) > 0.5 then
		self:SetHeight(height)
		if self.onResize then ns.Guard("ProfilePanel.onResize", self.onResize) end
	end
end

function P:Lookup()
	local conv = self.conv
	if not conv then return end
	-- The player asked, so this bypasses the per-player cooldown that keeps the
	-- automatic lookup quiet -- but not the client's own throttle.
	if PI.RequestWho(conv.id) then
		self.lookup:SetText(L["Looking up..."])
		ns.Anim.After(2, function()
			self.lookup:SetText(L["Look up"])
			self:Refresh()
		end)
	else
		self.lookup:SetText(L["Try again in a moment"])
		ns.Anim.After(3, function() self.lookup:SetText(L["Look up"]) end)
	end
end

function P:ApplyTheme()
	self.surface:ApplyTheme()
	self.divider:ApplyTheme()
	self.lookup:ApplyTheme()
	for i = 1, #self.rows do
		W.RefreshText(self.rows[i].label)
		W.RefreshText(self.rows[i].value)
	end
	self:Refresh()
end

ProfilePanel.HEIGHT_HINT = PAD_Y * 2 + ROW_H * math.ceil(#FIELDS / COLUMNS)
