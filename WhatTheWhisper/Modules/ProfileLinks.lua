-- WhatTheWhisper -- Addresses of a character's public profile pages.
--
-- "Look up" used to ask the server with /who, and the client no longer lets an
-- addon do that: C_FriendList.SendWho is restricted on every supported client
-- and blocked outright from addon code, with an ADDON_ACTION_BLOCKED naming this
-- addon. What a player usually wants from looking someone up is their gear, logs,
-- rating and achievements anyway -- and those live on the sites below. An addon
-- cannot open a browser, so the addresses are offered for copying.
--
-- Only sites whose address shape was checked are listed, each for the client it
-- covers. WoW Forever has none yet; the dialog says so rather than offering
-- retail addresses that would lead to somebody else.

local _, ns = ...
local Compat = ns.Compat

local ProfileLinks = {}
ns.ProfileLinks = ProfileLinks

local lower, gsub, gmatch, format = string.lower, string.gsub, string.gmatch, string.format
local concat = table.concat

--------------------------------------------------------------------------------
-- Realm slugs
--------------------------------------------------------------------------------

-- The client names realms without their spaces ("ArgentDawn", "Blade'sEdge"),
-- and the sites want them lowercased with a hyphen per word ("argent-dawn",
-- "blades-edge"). The words are recovered from the capitals; small words that
-- lose their capital along with the space ("AltarofStorms") are split off when
-- another word follows them. Measured against Raider.IO's own table of every
-- EU and US realm, that gets all but the realms below, which are spelled out.
local SLUG_EXCEPTIONS = {
	["AzjolNerub"] = "azjolnerub",
	["Chantséternels"] = "chants-éternels",
	["CultedelaRivenoire"] = "culte-de-la-rive-noire",
	["DieewigeWacht"] = "die-ewige-wacht",
	["LaCroisadeécarlate"] = "la-croisade-écarlate",
	["Pozzodell'Eternità"] = "pozzo-delleternità",
	["StromgardeKeep"] = "stromgarde-keep",
	["Templenoir"] = "temple-noir",
	["ThunderAxeFortress"] = "thunder-axe-fortress",
	["ThunderBluff"] = "thunder-bluff",
	["VanCleef"] = "vancleef",
}

-- Longest first, so "ofthe" is taken before "of".
local PARTICLES = { "ofthe", "dela", "des", "der", "von", "of", "de", "du", "la" }
local SPLIT = { ofthe = { "of", "the" }, dela = { "de", "la" } }

-- Cyrillic, CJK and Hangul realms have transliterated slugs no rule can derive.
local function isLatin(text)
	return not text:find("[\208\209\227-\237]")
end

function ProfileLinks.RealmSlug(realm)
	if type(realm) ~= "string" or realm == "" then return nil end
	if SLUG_EXCEPTIONS[realm] then return SLUG_EXCEPTIONS[realm] end
	if not isLatin(realm) then return nil end
	local s = gsub(gsub(realm, "%s*%(", " "), "%)", "")
	s = gsub(s, "(%l)(%u)", "%1 %2")
	-- A lowercase accented letter is a UTF-8 continuation byte here.
	s = gsub(s, "([\128-\191])(%u)", "%1 %2")
	s = gsub(s, "(%a)(%d)", "%1 %2")
	s = gsub(s, "(%u)(%u%l)", "%1 %2")
	local words = {}
	for word in gmatch(s, "%S+") do words[#words + 1] = word end
	local out = {}
	for i, word in ipairs(words) do
		local tail
		if i < #words then
			for _, particle in ipairs(PARTICLES) do
				local base = word:match("^(.+%l)" .. particle .. "$")
				if base and #base >= 3 then
					word, tail = base, particle
					break
				end
			end
		end
		out[#out + 1] = word
		if tail then
			for _, part in ipairs(SPLIT[tail] or { tail }) do out[#out + 1] = part end
		end
	end
	return lower((gsub(concat(out, "-"), "'", "")))
end

-- "argent-dawn" -> "Argent%20Dawn", the form Check-PvP takes.
local function titleWords(slug)
	local words = {}
	for word in gmatch(slug, "[^%-]+") do
		words[#words + 1] = gsub(word, "^%l", string.upper)
	end
	return concat(words, "%20")
end

-- ASCII is lowered; anything else is left alone, since lowering it needs a
-- table of every script and the sites accept either case for those.
local function lowerName(name)
	return (gsub(name, "%u", lower))
end

--------------------------------------------------------------------------------
-- Sites
--------------------------------------------------------------------------------

local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw" }
local ARMORY_LOCALE = { us = "en-us", eu = "en-gb", kr = "ko-kr", tw = "zh-tw" }

-- Each site: a label and a function of (region, slug, name) -> address.
local RETAIL = {
	{ "Armory", function(r, s, n)
		return format("https://worldofwarcraft.blizzard.com/%s/character/%s/%s/%s",
			ARMORY_LOCALE[r], r, s, lowerName(n)) end },
	{ "Raider.IO", function(r, s, n)
		return format("https://raider.io/characters/%s/%s/%s", r, s, n) end },
	{ "Warcraft Logs", function(r, s, n)
		return format("https://www.warcraftlogs.com/character/%s/%s/%s", r, s, lowerName(n)) end },
	{ "WoWProgress", function(r, s, n)
		return format("https://www.wowprogress.com/character/%s/%s/%s", r, s, n) end },
	{ "Check-PvP", function(r, s, n)
		return format("https://check-pvp.fr/%s/%s/%s", r, titleWords(s), n) end },
	{ "Wowhead", function(r, s, n)
		return format("https://www.wowhead.com/profile=%s.%s.%s", r, s, lowerName(n)) end },
	{ "Simple Armory", function(r, s, n)
		return format("https://simplearmory.com/#/%s/%s/%s", r, s, lowerName(n)) end },
}

local MISTS = {
	{ "Raider.IO", function(r, s, n)
		return format("https://classic.raider.io/characters/%s/%s/%s", r, s, n) end },
	{ "Warcraft Logs", function(r, s, n)
		return format("https://classic.warcraftlogs.com/character/%s/%s/%s", r, s, lowerName(n)) end },
	{ "Check-PvP", function(r, s, n)
		return format("https://check-pvp-classic.fr/%s/%s/%s", r, titleWords(s), n) end },
}

local ANNIVERSARY = {
	{ "Raider.IO", function(r, s, n)
		return format("https://classic.raider.io/characters/%s/%s/%s", r, s, n) end },
	{ "Warcraft Logs", function(r, s, n)
		return format("https://fresh.warcraftlogs.com/character/%s/%s/%s", r, s, lowerName(n)) end },
}

local ERA = {
	{ "Raider.IO", function(r, s, n)
		return format("https://era.raider.io/characters/%s/%s/%s", r, s, n) end },
	{ "Warcraft Logs", function(r, s, n)
		return format("https://vanilla.warcraftlogs.com/character/%s/%s/%s", r, s, lowerName(n)) end },
}

local function sitesForThisClient()
	if Compat.isRetail then return RETAIL end
	if Compat.isMoP then return MISTS end
	if Compat.isTBC then return ANNIVERSARY end
	if Compat.isClassicEra then return ERA end
	return nil
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

-- Returns links, note. `links` is an array of { label, url }; the first entry is
-- always the name itself, which is what every site's own search box takes. `note`
-- is a sentence explaining why the list is short, or nil.
function ProfileLinks.For(id)
	if type(id) ~= "string" or Compat.IsBattleNet(id) then return {}, nil end
	local name = Compat.ShortName(id)
	local links = { { label = ns.L["Name"], url = Compat.WireName(id) } }

	local sites = sitesForThisClient()
	if not sites then
		return links, ns.L["There are no public profile sites for this version of the game yet."]
	end
	local region = REGIONS[Compat.GetRegion() or 0]
	if not region then
		return links, ns.L["The profile sites do not cover this region."]
	end
	local slug = ProfileLinks.RealmSlug(Compat.RealmOf(id) or Compat.GetRealmName())
	if not slug then
		return links, ns.L["This realm's name cannot be turned into a web address here."]
	end
	for i = 1, #sites do
		links[#links + 1] = { label = sites[i][1], url = sites[i][2](region, slug, name) }
	end
	return links, nil
end
