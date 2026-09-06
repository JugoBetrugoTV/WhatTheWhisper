-- WhatTheWhisper -- Skin registry.
--
-- A skin is a complete token set. Anything a skin leaves out falls back to
-- Midnight, so a partial or third-party skin can never render a broken window.

local _, ns = ...
local Color = ns.Color

local Skins = { list = {}, order = {} }
ns.Skins = Skins

-- Every colour role the UI is allowed to reference. Adding one here and
-- nowhere else makes it inherit from Midnight in all other skins.
Skins.ROLES = {
	"bg0", "bg1", "bg2", "bg3",
	"hover", "selected", "pressed",
	"borderSubtle", "borderStrong",
	"accent", "accentHover", "accentActive", "onAccent",
	"textPrimary", "textSecondary", "textMuted", "textDisabled",
	"bubbleIn", "bubbleInText", "bubbleOut", "bubbleOutText",
	"success", "danger", "warning",
	"online", "away", "busy",
	"link", "scrim", "shadow", "scrollbar", "focusRing",
	"headerBg", "composerBg", "inputBg",
}

local function parse(value)
	if type(value) == "table" then
		if type(value[1]) == "string" then
			return Color.FromHex(value[1], value[2])
		end
		return { value[1], value[2], value[3], value[4] or 1 }
	end
	return Color.FromHex(value)
end

function Skins.Register(id, def)
	local skin = {
		id = id,
		name = def.name or id,
		description = def.description,
		colors = {},
		metrics = def.metrics or {},
	}
	for role, value in pairs(def.colors) do
		skin.colors[role] = parse(value)
	end
	Skins.list[id] = skin
	Skins.order[#Skins.order + 1] = id
	table.sort(Skins.order, function(a, b)
		local sa = Skins.list[a].metrics.sortIndex or 50
		local sb = Skins.list[b].metrics.sortIndex or 50
		if sa ~= sb then return sa < sb end
		return a < b
	end)
	return skin
end

function Skins.Get(id)
	return Skins.list[id] or Skins.list["midnight"]
end

function Skins.Exists(id)
	return Skins.list[id] ~= nil
end

-- Default metric set; skins override individual entries.
Skins.DEFAULT_METRICS = {
	radiusScale   = 1,     -- multiplies every corner radius
	bubbleRadius  = 12,
	spacingScale  = 1,     -- multiplies the gaps between message groups
	borderScale   = 1,     -- multiplies hairline thickness
	shadow        = 1,     -- drop shadow strength (0 disables)
	surfaceAlpha  = 1,     -- extra multiplier on top of the user opacity slider
	accentBar     = true,  -- draw the accent bar on the selected sidebar row
	sortIndex     = 50,
}
