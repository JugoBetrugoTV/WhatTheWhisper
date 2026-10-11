-- Coexistence: WhatTheWhisper ships its own libraries, and so does everyone else.
--
-- The scenarios below are the ones that actually break addons in the wild:
-- another addon loads first with an older copy, or a newer copy, or the same
-- one; ours loads first and theirs arrives after; two addons hold references to
-- the same library across an upgrade. In every case there must be no error, no
-- second initialisation, no lost callbacks and no lost AceAddon modules.
--
-- Everything here loads out of WhatTheWhisper/Libs, never a sibling Ace3.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
local Harness = dofile(ROOT .. "Tools/test/harness.lua")

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

--------------------------------------------------------------------------------
-- The manifest is the only source of truth
--------------------------------------------------------------------------------

local libFiles = Harness.LibraryFiles()
check("the embedded manifest lists libraries", #libFiles > 0)
for i = 1, #libFiles do
	check("every embedded library lives under WhatTheWhisper/Libs",
		libFiles[i]:find(ROOT .. "WhatTheWhisper/Libs/", 1, true) == 1, libFiles[i])
end
check("LibStub is first", libFiles[1]:find("LibStub.lua", 1, true) ~= nil, libFiles[1])

--------------------------------------------------------------------------------
-- Another addon got here first with an OLDER LibStub
--------------------------------------------------------------------------------

-- A minimal older LibStub, exactly as an addon from years ago would have
-- shipped it. Ours must replace it and carry its registry across.
local function installOldLibStub(minor)
	local lib = { minor = minor, libs = {}, minors = {} }
	function lib:NewLibrary(major, newMinor)
		newMinor = tonumber(newMinor)
		local old = self.minors[major]
		if old and old >= newMinor then return nil end
		self.minors[major], self.libs[major] = newMinor, self.libs[major] or {}
		return self.libs[major], old
	end
	function lib:GetLibrary(major, silent)
		if not self.libs[major] and not silent then
			error("Cannot find a library instance of " .. tostring(major))
		end
		return self.libs[major], self.minors[major]
	end
	function lib:IterateLibraries() return pairs(self.libs) end
	setmetatable(lib, { __call = lib.GetLibrary })
	_G.LibStub = lib
	return lib
end

local older = installOldLibStub(1)
-- A library another addon registered before we load at all.
local foreign = older:NewLibrary("SomeOtherLib-1.0", 5)
foreign.marker = "belongs to the other addon"

Harness.LoadLibraries()

check("our newer LibStub replaced the older one", _G.LibStub.minor >= 2,
	tostring(_G.LibStub.minor))
local carried = _G.LibStub:GetLibrary("SomeOtherLib-1.0", true)
check("the other addon's library survived the LibStub upgrade", carried ~= nil)
eq("and it is the same table, not a fresh one", carried, foreign)
eq("with its state intact", carried and carried.marker, "belongs to the other addon")

for _, major in ipairs({ "CallbackHandler-1.0", "AceAddon-3.0", "AceConsole-3.0",
	"AceEvent-3.0", "AceDB-3.0" }) do
	local lib, minor = _G.LibStub:GetLibrary(major, true)
	check(major .. " registered with LibStub", lib ~= nil)
	check(major .. " registered a numeric revision", type(minor) == "number", tostring(minor))
end

--------------------------------------------------------------------------------
-- Loading the same libraries a second time is a no-op, not a reset
--------------------------------------------------------------------------------

-- This is what happens when a second addon embeds the same revision we do: its
-- copy runs, LibStub sees the revision is not newer, and the file bails out.
local AceAddonBefore = _G.LibStub("AceAddon-3.0")
local AceDBBefore = _G.LibStub("AceDB-3.0")
local AceEventBefore = _G.LibStub("AceEvent-3.0")

-- Register something through each library first, so a reset would be visible.
local probeAddon = AceAddonBefore:NewAddon("CoexistenceProbe", "AceEvent-3.0")
probeAddon:NewModule("ProbeModule")
local fired = 0
probeAddon.OnProbeEvent = function() fired = fired + 1 end

local minorsBefore = {}
for major in _G.LibStub:IterateLibraries() do
	minorsBefore[major] = select(2, _G.LibStub:GetLibrary(major))
end

Harness.LoadLibraries()      -- the second addon's identical copies

eq("AceAddon is still the same table", _G.LibStub("AceAddon-3.0"), AceAddonBefore)
eq("AceDB is still the same table", _G.LibStub("AceDB-3.0"), AceDBBefore)
eq("AceEvent is still the same table", _G.LibStub("AceEvent-3.0"), AceEventBefore)

for major, minor in pairs(minorsBefore) do
	eq("re-loading did not change " .. major .. "'s revision",
		select(2, _G.LibStub:GetLibrary(major)), minor)
end

check("the addon registered before the reload still exists",
	AceAddonBefore:GetAddon("CoexistenceProbe", true) ~= nil)
check("and it still has its module",
	AceAddonBefore:GetAddon("CoexistenceProbe", true):GetModule("ProbeModule", true) ~= nil)

--------------------------------------------------------------------------------
-- Callbacks survive a duplicate load
--------------------------------------------------------------------------------

probeAddon:RegisterEvent("PLAYER_LOGIN", "OnProbeEvent")
M.FireEvent("PLAYER_LOGIN")
eq("the event reached the handler", fired, 1)

Harness.LoadLibraries()      -- a third addon, same revisions again
M.FireEvent("PLAYER_LOGIN")
eq("the registration survived another duplicate load", fired, 2)

probeAddon:UnregisterEvent("PLAYER_LOGIN")
M.FireEvent("PLAYER_LOGIN")
eq("unregistering still works afterwards", fired, 2)

--------------------------------------------------------------------------------
-- A NEWER foreign copy of a library must win over ours
--------------------------------------------------------------------------------

-- Another addon ships a revision above ours. LibStub hands it the existing
-- table to upgrade in place, so our consumers keep their references and simply
-- get the newer behaviour.
local currentMinor = select(2, _G.LibStub:GetLibrary("AceEvent-3.0"))
local upgraded, oldMinor = _G.LibStub:NewLibrary("AceEvent-3.0", currentMinor + 1)
check("a newer foreign revision is accepted", upgraded ~= nil)
eq("and it is handed our existing table to upgrade", upgraded, AceEventBefore)
eq("with the previous revision reported", oldMinor, currentMinor)
eq("the registry now holds the newer revision",
	select(2, _G.LibStub:GetLibrary("AceEvent-3.0")), currentMinor + 1)

-- An older foreign copy must be refused outright.
local refused = _G.LibStub:NewLibrary("AceEvent-3.0", currentMinor)
eq("an older foreign revision is refused", refused, nil)
eq("and the registry is unchanged",
	select(2, _G.LibStub:GetLibrary("AceEvent-3.0")), currentMinor + 1)

--------------------------------------------------------------------------------
-- With all that churn, the addon itself still loads and works
--------------------------------------------------------------------------------

local ns = Harness.LoadAddon()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(4)

check("the addon initialised", ns.db ~= nil and ns.db.profile ~= nil)
check("its own AceAddon object exists", ns.addon ~= nil)
check("the other addon is still registered alongside it",
	AceAddonBefore:GetAddon("CoexistenceProbe", true) ~= nil)

local guid = "G-THRALL"
M.guids = { [guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" } }
M.FireEvent("CHAT_MSG_WHISPER", "hello", "Thrall", "Common", "", "Thrall",
	"", 0, 0, "", 0, 1, guid)
M.RunFrames(2)
local thrall = ns.Compat.NormalizeName("Thrall")
check("a whisper still arrives after all the library churn",
	ns.ConversationManager.Get(thrall) ~= nil)

--------------------------------------------------------------------------------
-- No global namespace pollution beyond LibStub itself
--------------------------------------------------------------------------------

-- LibStub is a global on purpose and must stay one. It is the registry the
-- whole library ecosystem looks for by that exact name, so hiding, renaming or
-- sandboxing it would cut this addon off from every other addon's copies --
-- the opposite of what embedding shared libraries is for. Asserted positively
-- so a later "no globals" cleanup cannot quietly break it.
check("LibStub is a global", _G.LibStub ~= nil)
eq("under exactly that name", type(_G.LibStub), "table")
check("with the standard registry interface",
	type(_G.LibStub.NewLibrary) == "function"
	and type(_G.LibStub.GetLibrary) == "function"
	and type(_G.LibStub.IterateLibraries) == "function")
check("and callable as LibStub(\"Major\"), which is how addons ask",
	type(getmetatable(_G.LibStub) or {}) == "table"
	and (getmetatable(_G.LibStub) or {}).__call ~= nil)

-- Everything else goes into that registry instead. A library leaking its own
-- global would be reachable by, and clobberable by, every other addon.
for _, major in ipairs({ "AceAddon-3.0", "AceDB-3.0", "AceEvent-3.0",
	"AceConsole-3.0", "CallbackHandler-1.0" }) do
	local bare = major:gsub("%-.*$", "")
	check(bare .. " did not leak a global", _G[bare] == nil, tostring(_G[bare]))
	check(major .. " did not leak a global under its full name",
		_G[major] == nil, tostring(_G[major]))
end

-- Nor may the addon invent private forks of shared libraries: another addon
-- asking LibStub for AceAddon-3.0 has to get the shared one.
for _, forbidden in ipairs({ "WhatTheWhisperAceAddon", "WTWAceDB", "WTWLibStub",
	"WhatTheWhisperLibStub", "WTWAceEvent" }) do
	check("no private fork named " .. forbidden, _G[forbidden] == nil)
end
for major in _G.LibStub:IterateLibraries() do
	check("no namespaced library major: " .. major,
		not major:find("WhatTheWhisper") and not major:find("^WTW"), major)
end

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 5)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
