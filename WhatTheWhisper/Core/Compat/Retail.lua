-- WhatTheWhisper -- Retail / Midnight (12.1.0) specifics.
local _, ns = ...
local Compat = ns.Compat
if not Compat.isRetail then return end

local _G = _G

Compat.flavorName = "Retail"

-- Retail is the only flavour that reports the "scenario" instance type, and the
-- only one where Delves/Follower dungeons also report "party".
Compat.hasScenarios = true

-- Evoker/Monk/Demon Hunter only exist here; the shared CLASS_ICON_TCOORDS table
-- already carries them, so nothing to patch -- but record it for /wtw diag.
Compat.classCount = 13

-- Options: 10.0 replaced InterfaceOptions_AddCategory with the Settings namespace.
function Compat.RegisterOptionsPanel(panel, title, onOpen)
	panel.name = title
	panel.OnCommit = function() end
	panel.OnDefault = function() end
	panel.OnRefresh = function() end
	if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
		local category = _G.Settings.RegisterCanvasLayoutCategory(panel, title)
		category.ID = title
		_G.Settings.RegisterAddOnCategory(category)
		Compat.optionsCategory = category
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

-- /who results are a table on every client that has C_FriendList, but Retail is
-- also the one that throttles them hardest; the Search module honours that.
Compat.whoThrottle = 5
