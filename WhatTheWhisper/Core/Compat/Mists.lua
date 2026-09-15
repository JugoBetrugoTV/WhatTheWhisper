-- WhatTheWhisper -- Mists of Pandaria Classic (5.5.4) specifics.
local _, ns = ...
local Compat = ns.Compat
if not Compat.isMoP then return end

local _G = _G

Compat.flavorName = "MoP Classic"

-- MoP Classic runs on the modern client, so it has the Settings namespace, the
-- new SetGradient and C_BattleNet -- but only nine classes and no Evoker,
-- Demon Hunter or Dracthyr/Earthen races.
Compat.classCount = 11
Compat.hasScenarios = true

function Compat.RegisterOptionsPanel(panel, title, onOpen)
	panel.name = title
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

Compat.whoThrottle = 5
