-- Dumps the addon's real design tokens as JSON so the design preview renderer
-- can never drift from the code.
local ROOT = "/home/user/WhatTheWhisper/WhatTheWhisper/"
local ns = {}
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local function load(path)
	local chunk = assert(loadfile(ROOT .. path))
	chunk("WhatTheWhisper", ns)
end

load("Core/Namespace.lua")
load("Core/Util/Color.lua")
load("Skins/Skins.lua")
for _, skin in ipairs({ "Midnight", "WhatsApp", "Dark", "Minimal", "Glass", "Classic" }) do
	load("Skins/" .. skin .. ".lua")
end

local out = {}
local function emit(s) out[#out + 1] = s end

local function jsonNumberTable(t)
	local parts = {}
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = string.format('"%s":%s', k, tostring(t[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

emit('{"S":' .. jsonNumberTable(ns.S))
emit(',"R":' .. jsonNumberTable(ns.R))
emit(',"SZ":' .. jsonNumberTable(ns.SZ))
emit(',"T":' .. jsonNumberTable(ns.T))
emit(',"LINE_SPACING":' .. ns.LINE_SPACING)
emit(',"MOTION":' .. jsonNumberTable(ns.MOTION))

emit(',"skins":{')
local first = true
for _, id in ipairs(ns.Skins.order) do
	local skin = ns.Skins.list[id]
	if not first then emit(",") end
	first = false
	emit(string.format('"%s":{"name":"%s","colors":{', id, skin.name))
	local roles = {}
	for role in pairs(skin.colors) do roles[#roles + 1] = role end
	table.sort(roles)
	for i, role in ipairs(roles) do
		local c = skin.colors[role]
		emit(string.format('%s"%s":[%.5f,%.5f,%.5f,%.5f]',
			i > 1 and "," or "", role, c[1], c[2], c[3], c[4] or 1))
	end
	emit('},"metrics":' .. jsonNumberTable((function()
		local m = {}
		for k, v in pairs(ns.Skins.DEFAULT_METRICS) do
			if type(v) == "number" then m[k] = v end
		end
		for k, v in pairs(skin.metrics) do
			if type(v) == "number" then m[k] = v end
		end
		return m
	end)()) .. "}")
end
emit("}}")
print(table.concat(out))
