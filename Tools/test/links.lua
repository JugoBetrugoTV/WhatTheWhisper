-- "Look up": a character's public profile pages, to copy.
--
-- The addresses are only worth anything if they lead to the character, so the
-- realm has to be spelled the way the sites spell it. The client drops the
-- spaces ("ArgentDawn"); the sites want "argent-dawn". The expected slugs below
-- are the ones Raider.IO's own realm table uses, including the realms whose
-- names no rule recovers.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

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
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)
local problems = {}
ns.SoftError = function(context, err) problems[#problems + 1] = context .. ": " .. tostring(err) end

local Links = ns.ProfileLinks

--------------------------------------------------------------------------------
-- Realm slugs
--------------------------------------------------------------------------------

local SLUGS = {
	-- one word, and words recovered from the capitals
	Blackrock = "blackrock", Antonidas = "antonidas", ArgentDawn = "argent-dawn",
	TwistingNether = "twisting-nether", KulTiras = "kul-tiras", BurningBlade = "burning-blade",
	DasSyndikat = "das-syndikat",
	-- apostrophes go, and do not start a word
	["Aman'Thul"] = "amanthul", ["Kel'Thuzad"] = "kelthuzad", ["Drak'thul"] = "drakthul",
	["Blade'sEdge"] = "blades-edge",
	-- small words that lost their capital along with the space
	AltarofStorms = "altar-of-storms", ShrineoftheDormantFlame = "shrine-of-the-dormant-flame",
	["ConfrérieduThorium"] = "confrérie-du-thorium", KultderVerdammten = "kult-der-verdammten",
	DerRatvonDalaran = "der-rat-von-dalaran",
	-- digits, acronyms and brackets
	Area52 = "area-52", EUMythicDungeons = "eu-mythic-dungeons", ["Aggra(Português)"] = "aggra-português",
	-- the ones spelled out
	AzjolNerub = "azjolnerub", ThunderBluff = "thunder-bluff", Templenoir = "temple-noir",
	VanCleef = "vancleef", CultedelaRivenoire = "culte-de-la-rive-noire",
}
for realm, slug in pairs(SLUGS) do
	eq("realm " .. realm, Links.RealmSlug(realm), slug)
end
eq("a Cyrillic realm has no slug rather than a wrong one", Links.RealmSlug("Гордунни"), nil)
eq("nor has a Korean one", Links.RealmSlug("하이잘"), nil)

--------------------------------------------------------------------------------
-- Addresses
--------------------------------------------------------------------------------

local function byLabel(list)
	local out = {}
	for _, link in ipairs(list) do out[link.label] = link.url end
	return out
end

local links, note = Links.For("Thrall-ArgentDawn")
local urls = byLabel(links)
eq("no note when every site is there", note, nil)
eq("the first line is the name the sites search for", links[1].url, "Thrall-ArgentDawn")
eq("Armory", urls["Armory"], "https://worldofwarcraft.blizzard.com/en-gb/character/eu/argent-dawn/thrall")
eq("Raider.IO", urls["Raider.IO"], "https://raider.io/characters/eu/argent-dawn/Thrall")
eq("Warcraft Logs", urls["Warcraft Logs"], "https://www.warcraftlogs.com/character/eu/argent-dawn/thrall")
eq("WoWProgress", urls["WoWProgress"], "https://www.wowprogress.com/character/eu/argent-dawn/Thrall")
eq("Check-PvP, which wants the realm as it is written", urls["Check-PvP"],
	"https://check-pvp.fr/eu/Argent%20Dawn/Thrall")
eq("Wowhead", urls["Wowhead"], "https://www.wowhead.com/profile=eu.argent-dawn.thrall")
eq("Simple Armory, for achievements and collections", urls["Simple Armory"],
	"https://simplearmory.com/#/eu/argent-dawn/thrall")

-- Your own realm, named only by the client.
local own = byLabel((Links.For(ns.Compat.NormalizeName("Jaina"))))
eq("someone on your own realm gets your realm", own["Raider.IO"],
	"https://raider.io/characters/eu/blackrock/Jaina")
eq("and the name line is how the client would address them", (Links.For(ns.Compat.NormalizeName("Jaina")))[1].url, "Jaina")

-- Americas: another locale for the armory.
_G.GetCurrentRegion = function() return 1 end
eq("the US armory", byLabel((Links.For("Thrall-Blackrock")))["Armory"],
	"https://worldofwarcraft.blizzard.com/en-us/character/us/blackrock/thrall")
-- China: none of the sites cover it, and the dialog says so.
_G.GetCurrentRegion = function() return 5 end
local cn, cnNote = Links.For("Thrall-Blackrock")
eq("a region the sites do not cover offers only the name", #cn, 1)
check("and says why", cnNote ~= nil)
_G.GetCurrentRegion = function() return 3 end

eq("a Battle.net account has no character pages", #(Links.For("BN:Freund#1234")), 0)

--------------------------------------------------------------------------------
-- The dialog
--------------------------------------------------------------------------------

ns.Dialogs.ShowLinks("Look up", links, nil)
M.RunFrames(2)
local d = _G.WhatTheWhisperLinksDialog
check("the dialog is up", d ~= nil and d:IsShown())
local shownRows = 0
for _, row in ipairs(d.rows) do if row:IsShown() then shownRows = shownRows + 1 end end
eq("one row per address", shownRows, #links)
eq("each field holds its address", d.rows[3].edit:GetText(), links[3].url)
check("the first address is ready to copy", M.focus == d.rows[2].edit,
	"focus is on " .. tostring(M.focus))

-- Typing into a field puts the address back: it is there to be copied.
local field = d.rows[4].edit
field:SetText("kaputt")
local changed = field._scripts and field._scripts.OnTextChanged
if changed then changed(field, true) end
eq("an address cannot be typed over", field:GetText(), links[4].url)

-- A click on any field selects it for Ctrl+C.
local up = field._scripts and field._scripts.OnMouseUp
if up then up(field, "LeftButton") end
eq("clicking a field gives it the keyboard", M.focus, field)

-- Fewer links next time: the rows left over are hidden, not left showing.
ns.Dialogs.ShowLinks("Look up", { links[1] }, "A note.")
M.RunFrames(2)
shownRows = 0
for _, row in ipairs(d.rows) do if row:IsShown() then shownRows = shownRows + 1 end end
eq("a shorter list hides the rows it does not need", shownRows, 1)
check("and shows its note", d.note:IsShown() and d.note:GetText() == "A note.")
ns.Dialogs.HideAll()
check("Escape and HideAll close it", not d:IsShown())
check("and give the keyboard back", M.focus == nil, tostring(M.focus))

--------------------------------------------------------------------------------

check("no soft errors", #problems == 0, table.concat(problems, "\n      "))
check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
