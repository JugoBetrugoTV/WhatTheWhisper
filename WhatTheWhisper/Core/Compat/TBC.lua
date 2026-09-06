-- WhatTheWhisper -- Burning Crusade Anniversary (2.5.6) specifics.
local _, ns = ...
local Compat = ns.Compat
if not Compat.isTBC then return end

local _G = _G

Compat.flavorName = "TBC Classic"

-- 2.5.x is the 9.x engine: SetGradientAlpha instead of SetGradient, the legacy
-- colour picker, and InterfaceOptions instead of the Settings namespace.
Compat.classCount = 9
Compat.hasScenarios = false

function Compat.RegisterOptionsPanel(panel, title, onOpen)
	panel.name = title
	Compat.optionsPanel = panel
	if _G.InterfaceOptions_AddCategory then
		_G.InterfaceOptions_AddCategory(panel)
		panel:SetScript("OnShow", onOpen)
		return true
	end
	return false
end

function Compat.OpenOptionsPanel()
	if _G.InterfaceOptionsFrame_OpenToCategory and Compat.optionsPanel then
		-- Calling twice is the long-standing workaround for the first call
		-- landing on the wrong category.
		_G.InterfaceOptionsFrame_OpenToCategory(Compat.optionsPanel)
		_G.InterfaceOptionsFrame_OpenToCategory(Compat.optionsPanel)
		return true
	end
	return false
end

Compat.whoThrottle = 5
