-- WhatTheWhisper -- World of Warcraft: Forever (1.60.1) specifics.
--
-- Blizzard calls this client line "Camelot" in its own interface source, which
-- is where the TOC suffix comes from, and "Forever" everywhere a player can see
-- it. Everything below was read out of that source at the 1.60.1 tag, the same
-- way the other flavours were -- see PROVENANCE in Tools/test/client.lua.
local _, ns = ...
local Compat = ns.Compat
if not Compat.isForever then return end

local _G = _G

Compat.flavorName = "Forever"

-- Vanilla's nine classes, verbatim: Blizzard_FrameXMLBase/Camelot/Constants.lua
-- sets CLASS_SORT_ORDER to the same nine Classic Era has, with no Death Knight.
-- So this is Classic's world drawn by Retail's engine, and the addon wants the
-- modern API surface with the Vanilla class table.
Compat.classCount = 9
Compat.hasScenarios = false

-- The Settings namespace is there -- Forever loads the mainline family of
-- Blizzard_Settings_Shared -- but the legacy path is kept for the same reason
-- every other flavour keeps it: this is a beta, and what it ships with on the
-- fourth of November is not something to find out the hard way.
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

-- Vanilla's /who throttle, because it is Vanilla's server.
Compat.whoThrottle = 10
