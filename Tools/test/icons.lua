-- The drop-in icon system: can somebody replace the artwork without editing Lua,
-- and does a half-replaced set still leave every button visible?
--
-- That second question is the whole reason this file exists. A missing icon must
-- degrade to the built-in sheet, never to an empty square, because replacing the
-- set one file at a time is the workflow this was built for -- and during it,
-- most of the files are missing.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
local Client = dofile(ROOT .. "Tools/test/client.lua")
Client.Setup("retail")

-- Two runs, because the thing being tested is decided once at load and kept.
-- "blind" is the client that will not say whether a file is on disk.
local MODE = (arg and arg[1]) or "normal"
local BLIND = MODE == "blind"
M.textureProbeAnswers = not BLIND

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local Icons, Draw = ns.Icons, ns.Draw

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local DIR = "Interface\\AddOns\\WhatTheWhisper\\Media\\Icons\\"

-- A texture to read answers off, made the way the addon makes its own.
local host = CreateFrame("Frame", nil, UIParent)
local function probe(name)
	local tex = host:CreateTexture(nil, "ARTWORK")
	tex:SetTexCoord(0.5, 0.6, 0.5, 0.6)   -- dirty, so a reset is observable
	local ok = Draw.SetIcon(tex, name)
	return ok, tex
end

--------------------------------------------------------------------------------
-- Nothing dropped in: the built-in sheet carries everything
--------------------------------------------------------------------------------

-- True on both clients. Whatever the probe can or cannot tell, a window with no
-- drop-in files in it is the shipped product and every button in it is visible.
do
	Icons.Rescan()
	local missing = {}
	for name in pairs(Icons.REPLACEABLE) do
		local ok, tex = probe(name)
		if not ok or tex:GetTexture() == nil then
			missing[#missing + 1] = name
		end
	end
	check("every replaceable icon renders with no drop-in files at all",
		#missing == 0, table.concat(missing, ", "))

	local _, tex = probe("send")
	eq("and it comes from the built-in sheet", tex:GetTexture(),
		"Interface\\AddOns\\WhatTheWhisper\\Art\\Icons")

	local custom, total, usable = Icons.CustomCount()
	eq("none of them are drop-ins", custom, 0)
	check("the set is not empty", total > 20, total)
	eq("and the client answers the file question as expected", usable, not BLIND)
end

--------------------------------------------------------------------------------
-- One file dropped in
--------------------------------------------------------------------------------

-- The workflow this exists for: generate one icon, drop it in the folder,
-- reload. No Lua edited, nothing rebuilt, and the other thirty keep working.
if not BLIND then
	M.textureFiles[DIR .. "send"] = true
	Icons.Rescan()

	local ok, tex = probe("send")
	check("a dropped-in file is used", ok)
	eq("from the drop-in folder", tex:GetTexture(), DIR .. "send")
	local l, r, t, b = tex:GetTexCoord()
	check("and the sheet's cell coordinates are cleared off it",
		l == 0 and r == 1 and t == 0 and b == 1,
		("%s %s %s %s"):format(tostring(l), tostring(r), tostring(t), tostring(b)))

	local _, other = probe("search")
	eq("its neighbours still come from the sheet", other:GetTexture(),
		"Interface\\AddOns\\WhatTheWhisper\\Art\\Icons")

	local custom = Icons.CustomCount()
	eq("and exactly one is a drop-in", custom, 1)
end

--------------------------------------------------------------------------------
-- A client that will not say whether a file is there
--------------------------------------------------------------------------------

-- Some clients hand a path straight back whatever is on disk, so "does this
-- exist" has no answer. Asking anyway would put a blank texture on every button
-- whose file has not been dropped in yet -- which, for somebody who has replaced
-- three of thirty, is twenty-seven invisible buttons. So the addon has to work
-- out that it cannot tell, and stay on the art it knows is there.
if BLIND then
	local _, _, usable = Icons.CustomCount()
	eq("the addon works out that it cannot tell", usable, false)

	M.textureFiles[DIR .. "send"] = true
	Icons.Rescan()
	local ok, tex = probe("send")
	check("so it stays on the built-in sheet", ok)
	eq("even though the file is really there", tex:GetTexture(),
		"Interface\\AddOns\\WhatTheWhisper\\Art\\Icons")

	local blanks = 0
	for name in pairs(Icons.REPLACEABLE) do
		local _, t = probe(name)
		if t:GetTexture() == nil then blanks = blanks + 1 end
	end
	eq("and not one button is left empty", blanks, 0)
	M.textureFiles[DIR .. "send"] = nil
end

--------------------------------------------------------------------------------
-- ...and taken away again
--------------------------------------------------------------------------------

if not BLIND then
	M.textureFiles[DIR .. "send"] = nil
	Icons.Rescan()
	local ok, tex = probe("send")
	check("removing the file falls back rather than blanking the button", ok)
	eq("to the sheet", tex:GetTexture(),
		"Interface\\AddOns\\WhatTheWhisper\\Art\\Icons")
end

--------------------------------------------------------------------------------
-- Every name the UI asks for resolves to something
--------------------------------------------------------------------------------

-- The alias table is the join between "what this glyph means" and "which cell of
-- the sheet draws it". An entry pointing at a cell that is not there is an
-- invisible button, and it would look exactly like a working one in the source.
do
	local broken = {}
	for name, key in pairs(Icons.ATLAS_ALIAS) do
		if not ns.ICON_ATLAS[key] then
			broken[#broken + 1] = name .. " -> " .. key
		end
	end
	check("every alias points at a cell that exists in the sheet",
		#broken == 0, table.concat(broken, ", "))

	local unbacked = {}
	for name in pairs(Icons.REPLACEABLE) do
		if not ns.ICON_ATLAS[Icons.AtlasKey(name)] then
			unbacked[#unbacked + 1] = name
		end
	end
	check("and every replaceable icon has a built-in fallback",
		#unbacked == 0, table.concat(unbacked, ", "))
end

--------------------------------------------------------------------------------
-- The display sizes are named, not typed
--------------------------------------------------------------------------------

-- The manifest tells somebody what resolution to generate at, and it can only do
-- that if the addon knows what size it draws each glyph at. A `size` naming a
-- token that does not exist would put a blank in that column.
do
	local unknown = {}
	for name, spec in pairs(Icons.REPLACEABLE) do
		if type(ns.SZ[spec.size]) ~= "number" then
			unknown[#unknown + 1] = name .. " (" .. tostring(spec.size) .. ")"
		end
	end
	check("every icon's render size is a real design token",
		#unknown == 0, table.concat(unknown, ", "))

	local undescribed = {}
	for name, spec in pairs(Icons.REPLACEABLE) do
		if type(spec.note) ~= "string" or #spec.note < 8 then
			undescribed[#undescribed + 1] = name
		end
	end
	check("and every one says what it should look like",
		#undescribed == 0, table.concat(undescribed, ", "))
end

--------------------------------------------------------------------------------

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("\n[%s] %d passed, %d failed"):format(MODE, pass, fail))
os.exit(fail == 0 and 0 or 1)
