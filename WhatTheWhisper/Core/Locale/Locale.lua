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

-- In the order the picker offers them. `native` is what a speaker of that
-- language calls it, because a menu of language names written in a language you
-- cannot read is not a menu you can use.
ns.LOCALES = {
	{ code = "enUS", native = "English" },
	{ code = "deDE", native = "Deutsch" },
	{ code = "frFR", native = "Français" },
	{ code = "esES", native = "Español (EU)" },
	{ code = "esMX", native = "Español (AL)" },
	{ code = "itIT", native = "Italiano" },
	{ code = "ptBR", native = "Português" },
	{ code = "ruRU", native = "Русский" },
	{ code = "koKR", native = "한국어" },
	{ code = "zhCN", native = "简体中文" },
	{ code = "zhTW", native = "繁體中文" },
}

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
-- rather than a list of keys repeated twice.
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
local function activeCode()
	local db = ns.db
	local chosen = db and db.profile and db.profile.appearance
		and db.profile.appearance.locale
	if chosen and chosen ~= "auto" and tables[chosen] then return chosen end
	if tables[clientLocale] then return clientLocale end
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
function ns.LocaleCoverage(code)
	local base, other = tables[BASE], tables[code]
	if not base or not other then return 0, 0 end
	local total, done = 0, 0
	for key in pairs(base) do
		total = total + 1
		local value = other[key]
		if value ~= nil and value ~= true then done = done + 1 end
	end
	if code == BASE then return total, total end
	return done, total
end
