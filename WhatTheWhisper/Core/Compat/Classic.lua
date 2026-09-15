-- WhatTheWhisper -- Classic Era (1.15.9) specifics.
local _, ns = ...
local Compat = ns.Compat
if not Compat.isClassicEra then return end

local _G = _G

Compat.flavorName = "Classic Era"

-- Classic Era runs on the current engine, so the rendering API is modern, but
-- the game data is Vanilla: nine classes, no Death Knight, no cross-faction
-- whispers, and guild ranks/levels cap at 60.
Compat.classCount = 9
Compat.hasScenarios = false

function Compat.RegisterOptionsPanel(panel, title, onOpen)
	panel.name = title
	Compat.optionsPanel = panel
	if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
		local category = _G.Settings.RegisterCanvasLayoutCategory(panel, title)
		category.ID = title
		_G.Settings.RegisterAddOnCategory(category)
		Compat.optionsCategory = category
		panel:SetScript("OnShow", onOpen)
		return true
	end
	if _G.InterfaceOptions_AddCategory then
		_G.InterfaceOptions_AddCategory(panel)
		panel:SetScript("OnShow", onOpen)
		return true
	end
	return false
end

function Compat.OpenOptionsPanel()
	if _G.Settings and _G.Settings.OpenToCategory and Compat.optionsCategory then
		_G.Settings.OpenToCategory(Compat.optionsCategory.ID or Compat.optionsCategory:GetID())
		return true
	end
	if _G.InterfaceOptionsFrame_OpenToCategory and Compat.optionsPanel then
		_G.InterfaceOptionsFrame_OpenToCategory(Compat.optionsPanel)
		_G.InterfaceOptionsFrame_OpenToCategory(Compat.optionsPanel)
		return true
	end
	return false
end

Compat.whoThrottle = 10
