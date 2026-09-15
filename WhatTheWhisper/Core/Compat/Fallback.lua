-- WhatTheWhisper -- Anything the four supported flavours did not claim.
--
-- Wrath and Cataclysm Classic are not target platforms, but the addon must not
-- explode if someone drops it into one: this file supplies the handful of
-- entry points the flavour files own.
local _, ns = ...
local Compat = ns.Compat
if Compat.RegisterOptionsPanel then return end

local _G = _G

Compat.flavorName = Compat.flavorName or ("Unknown (" .. tostring(Compat.tocVersion) .. ")")
Compat.classCount = Compat.classCount or 10
Compat.whoThrottle = Compat.whoThrottle or 5

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
	return false
end
