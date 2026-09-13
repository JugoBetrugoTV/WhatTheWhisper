-- WhatTheWhisper -- Strings, in every language the client ships in.
--
-- Not AceLocale, and that is a decision rather than an oversight. AceLocale
-- discards every locale that is not the client's at load time: NewLocale returns
-- nil and the file bails on its first line. That is the right trade when the
-- language is fixed for the session, and it makes a language *picker*
-- impossible -- the table you would switch to was never built.
--
-- So the tables live here instead, one per locale, and a lookup picks between
-- them at read time. Everything else about the shape is AceLocale's, because it
-- is a good shape: the source language writes `true` for "the key is the text",
-- a missing key falls back rather than rendering as nil, and the whole thing is
-- one table index at the call site.

local _, ns = ...

--------------------------------------------------------------------------------
-- The locales the client actually ships
--------------------------------------------------------------------------------

-- In the order the picker offers them.
--
-- `native` is what a speaker of that language calls it, because a menu of
-- language names written in a language you cannot read is not a menu you can
-- use. `english` is the fallback for when the native name is one this client
-- has no font for -- a German install has no Korean glyphs at all, and "한국어"
-- there is three empty boxes, which is worse than "Korean".
--
-- `script` is what the strings are written in, which decides both of the above
-- and which font the addon draws itself with while that language is chosen.
ns.LOCALES = {
	{ code = "enUS", native = "English",      english = "English",               script = "latin" },
	{ code = "deDE", native = "Deutsch",      english = "German",                script = "latin" },
	{ code = "frFR", native = "Français",     english = "French",                script = "latin" },
	{ code = "esES", native = "Español (EU)", english = "Spanish (EU)",          script = "latin" },
	{ code = "esMX", native = "Español (AL)", english = "Spanish (LA)",          script = "latin" },
	{ code = "itIT", native = "Italiano",     english = "Italian",               script = "latin" },
	{ code = "ptBR", native = "Português",    english = "Portuguese",            script = "latin" },
	{ code = "ruRU", native = "Русский",      english = "Russian",               script = "cyrillic" },
	{ code = "koKR", native = "한국어",          english = "Korean",                script = "korean" },
	{ code = "zhCN", native = "简体中文",        english = "Chinese (Simplified)",  script = "hans" },
	{ code = "zhTW", native = "繁體中文",        english = "Chinese (Traditional)", script = "hant" },
}

local BY_CODE = {}
for i = 1, #ns.LOCALES do BY_CODE[ns.LOCALES[i].code] = ns.LOCALES[i] end

function ns.LocaleEntry(code)
	return BY_CODE[code]
end

-- The writing system a locale is set in, which is what decides whether this
-- client can draw it at all.
function ns.ScriptOf(code)
	local entry = BY_CODE[code]
	return entry and entry.script or "latin"
end

local BASE = "enUS"

-- enGB clients report enGB and there is no enGB text anywhere in the game; the
-- client's own strings are enUS. Everything else maps to itself.
local ALIASES = { enGB = "enUS" }

local tables = {}
ns.LocaleData = tables

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- Called by each locale file with its own table. The source language passes
-- `true` for entries whose text is the key, so enUS.lua stays a list of keys
-- rather than a list of keys repeated twice. A translation may pass `true` too,
-- and there it means "the English is correct here as well" -- a product name, a
-- file format -- which is a decision, not a gap, and counts as covered below.
function ns.RegisterLocale(code, strings)
	if type(code) ~= "string" or type(strings) ~= "table" then return end
	if code == BASE then
		for key, value in pairs(strings) do
			if value == true then strings[key] = key end
		end
	end
	tables[code] = strings
end

--------------------------------------------------------------------------------
-- Which locale is in force
--------------------------------------------------------------------------------

local clientLocale = BASE
do
	local ok, locale = pcall(_G.GetLocale)
	if ok and type(locale) == "string" and locale ~= "" then
		clientLocale = ALIASES[locale] or locale
	end
end
ns.CLIENT_LOCALE = clientLocale

-- The player's choice, or the client's language when they have not made one.
-- Read through a function rather than cached, because the setting can change
-- while the addon is running and every string has to follow it.
-- A language is only usable if the client can actually draw it. Choosing one it
-- cannot would turn every label in the addon into a row of boxes -- including
-- the settings row you would need to read to change it back.
local function usable(code)
	if not code or not tables[code] then return false end
	local Compat = ns.Compat
	if not Compat or not Compat.CanDrawScript then return true end
	return Compat.CanDrawScript(ns.ScriptOf(code))
end
ns.LocaleIsUsable = usable

local function activeCode()
	local db = ns.db
	local chosen = db and db.profile and db.profile.appearance
		and db.profile.appearance.locale
	if chosen and chosen ~= "auto" and usable(chosen) then return chosen end
	if usable(clientLocale) then return clientLocale end
	return BASE
end
ns.ActiveLocale = activeCode

function ns.LocaleIsAvailable(code)
	return tables[code] ~= nil
end

--------------------------------------------------------------------------------
-- The lookup
--------------------------------------------------------------------------------

-- Three chances at every key: the chosen language, then the source language,
-- then the key itself. A partial translation therefore shows English for the
-- lines nobody has done yet rather than blanks or the word "nil", which is what
-- makes shipping an unfinished locale safe.
ns.L = setmetatable({}, {
	__index = function(_, key)
		if type(key) ~= "string" then return key end
		local active = tables[activeCode()]
		local value = active and active[key]
		if value ~= nil and value ~= true then return value end
		local base = tables[BASE]
		value = base and base[key]
		if value ~= nil and value ~= true then return value end
		return key
	end,
	-- Writing to it is always a mistake: the tables are the locale files.
	__newindex = function(_, key)
		ns.SoftError("Locale", "tried to assign to L[" .. tostring(key) .. "]")
	end,
})

--------------------------------------------------------------------------------
-- Coverage, for the settings screen
--------------------------------------------------------------------------------

-- How much of the source language a locale actually answers. Shown next to the
-- name in the picker: choosing a language that is a third done should be a
-- decision the player makes knowingly, not a surprise they discover later.
--
-- A key the locale answers with `true` counts: it says "English is right here",
-- which is an answer. A key it does not mention at all does not -- that is the
-- one that silently renders in the wrong language.
function ns.LocaleCoverage(code)
	local base, other = tables[BASE], tables[code]
	if not base or not other then return 0, 0 end
	local total, done = 0, 0
	for key in pairs(base) do
		total = total + 1
		if other[key] ~= nil then done = done + 1 end
	end
	if code == BASE then return total, total end
	return done, total
end
