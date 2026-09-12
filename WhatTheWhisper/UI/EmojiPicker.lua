-- WhatTheWhisper -- Emoji picker.
--
-- Inserts the *text* form (":)", ":fire:", "{rt1}") because that is what travels
-- over the wire. Someone without this addon sees a normal emoticon; someone with
-- it sees the drawn glyph.

local _, ns = ...
local Theme, W, Anim, Draw, Pool = ns.Theme, ns.Widgets, ns.Anim, ns.Draw, ns.Pool
local Emoticons = ns.Emoticons
local L = ns.L

local Picker = {}
ns.EmojiPicker = Picker

local COLS = 8
local CELL = 30
local PAD = ns.S.MD
local TABS_H = 30

local frame, catcher, cellPool, tabButtons
local currentCategory = "smileys"
local currentComposer

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------

local function createCell()
	local cell = CreateFrame("Frame", nil, frame)
	cell:SetSize(CELL, CELL)
	cell.surface = W.Surface(cell, { radius = ns.R.SM })
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetSize(20, 20)
	cell.icon:SetPoint("CENTER")

	W.MakeInteractive(cell, function(state, instant)
		local role = (state == "pressed" and "pressed") or (state == "hover" and "hover") or nil
		W.FadeSurfaceTo(cell.surface, cell, role, instant and 0 or Theme.Duration("FAST"))
	end)

	cell:HookScript("OnMouseUp", function(self)
		if not self:IsMouseOver() or not self.emojiName then return end
		Picker.Insert(self.emojiName)
	end)
	return cell
end

local function resetCell(_, cell)
	cell:Hide()
	cell:ClearAllPoints()
	cell.emojiName = nil
	cell.__wtwTooltip = nil
	cell.surface:SetColorOverride(0, 0, 0, 0)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function build()
	if frame then return end

	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(20)
	catcher:EnableMouse(true)
	catcher:Hide()
	catcher:SetScript("OnMouseDown", function() Picker.Close() end)

	frame = CreateFrame("Frame", "WhatTheWhisperEmojiPicker", UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(30)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame.surface = W.Surface(frame, {
		color = "bg3", border = "borderStrong", radius = ns.R.LG, shadow = 16,
	})

	frame:SetWidth(COLS * CELL + PAD * 2)
	cellPool = Pool.New(createCell, resetCell, "emoji.cell")

	-- Category tabs
	tabButtons = {}
	local categories = { { id = "recent", label = L["Recent"] } }
	for i = 1, #Emoticons.CATEGORIES do
		local category = Emoticons.CATEGORIES[i]
		categories[#categories + 1] = { id = category.id, label = L[category.label] }
	end

	local tabWidth = (COLS * CELL) / #categories
	for i = 1, #categories do
		local category = categories[i]
		local button = ns.Button.Text(frame, {
			text = category.label, token = "MICRO", height = TABS_H - 6,
			radius = ns.R.SM, autoWidth = false,
			onClick = function() Picker.SetCategory(category.id) end,
		})
		button:SetWidth(tabWidth)
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * tabWidth, -PAD + 1)
		button.categoryID = category.id
		tabButtons[#tabButtons + 1] = button
	end

	if type(_G.UISpecialFrames) == "table" then
		local found
		for i = 1, #_G.UISpecialFrames do
			if _G.UISpecialFrames[i] == "WhatTheWhisperEmojiPicker" then found = true break end
		end
		if not found then table.insert(_G.UISpecialFrames, "WhatTheWhisperEmojiPicker") end
	end
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

local function itemsFor(categoryID)
	if categoryID == "recent" then
		local recent = ns.db.profile.emoticons.recent
		if #recent == 0 then
			-- An empty Recent tab is a dead end; show the smileys instead.
			return Emoticons.CATEGORIES[1].items
		end
		return recent
	end
	for i = 1, #Emoticons.CATEGORIES do
		if Emoticons.CATEGORIES[i].id == categoryID then
			return Emoticons.CATEGORIES[i].items
		end
	end
	return Emoticons.CATEGORIES[1].items
end

function Picker.SetCategory(categoryID)
	currentCategory = categoryID
	for i = 1, #tabButtons do
		tabButtons[i]:SetSelectedState(tabButtons[i].categoryID == categoryID)
	end
	Picker.Render()
end

function Picker.Render()
	cellPool:ReleaseAll()
	local items = itemsFor(currentCategory)
	local rows = math.ceil(#items / COLS)

	for i = 1, #items do
		local name = items[i]
		local cell = cellPool:Acquire()
		cell.emojiName = name
		local column = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", frame, "TOPLEFT",
			PAD + column * CELL, -(PAD + TABS_H + row * CELL))

		local markerIndex = name:match("^rt(%d)$")
		if markerIndex then
			cell.icon:SetTexture(Emoticons.MarkerTexture(tonumber(markerIndex)), "CLAMP", "CLAMP")
			cell.icon:SetTexCoord(0, 1, 0, 1)
		else
			Draw.SetEmoji(cell.icon, name)
		end
		W.SetTooltip(cell, Emoticons.InsertText(name))
		cell:Show()
	end

	frame:SetHeight(PAD * 2 + TABS_H + math.max(1, rows) * CELL)
	frame.surface:Layout()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function Picker.Insert(name)
	Emoticons.RememberRecent(name)
	if currentComposer then
		currentComposer:Insert(Emoticons.InsertText(name))
	end
	Picker.Close()
end

function Picker.Open(anchor, composer)
	build()
	currentComposer = composer
	Picker.SetCategory(currentCategory)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -PAD, ns.S.SM)
	catcher:Show()
	frame:Show()
	Anim.SlideIn(frame, 0, -6, Theme.Duration("FAST"))
end

function Picker.Close()
	if not frame then return end
	catcher:Hide()
	frame:Hide()
	ns.Tooltip.Hide()
end

function Picker.IsOpen()
	return frame and frame:IsShown()
end

function Picker.Toggle(anchor, composer)
	if Picker.IsOpen() then
		Picker.Close()
	else
		Picker.Open(anchor, composer)
	end
end

function Picker.ApplyTheme()
	if not frame then return end
	frame.surface:ApplyTheme()
	for i = 1, #tabButtons do tabButtons[i]:ApplyTheme() end
	local function refresh(cell) cell.surface:ApplyTheme() end
	for cell in cellPool:EnumerateActive() do refresh(cell) end
	for _, cell in ipairs(cellPool.free) do refresh(cell) end
	if frame:IsShown() then Picker.Render() end
end
