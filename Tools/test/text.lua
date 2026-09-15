-- Text processing: link detection that must not damage chat, UTF-8 safety, and
-- truncation that must not cut a character or an escape sequence in half.

local ROOT = "/home/user/WhatTheWhisper/"
local ns = { MAX_MESSAGE_BYTES = 255, T = { BODY = 14 }, R = {}, S = {}, SZ = {} }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.GetTime = function() return 100 end
ns.SoftError = function() end
ns.Guard = function(_, f, ...) return pcall(f, ...) end

local function load(path) assert(loadfile(ROOT .. "WhatTheWhisper/" .. path))("WhatTheWhisper", ns) end
load("Core/Util/Text.lua")
load("Core/Util/Color.lua")

ns.Theme = { Get = function() return { 0.35, 0.49, 0.98, 1 } end, FontSize = function() return 14 end }
ns.Draw = { EmojiMarkup = function(name) return "<" .. name .. ">" end }
ns.EMOJI_ATLAS = {}
for _, n in ipairs({ "smile", "grin", "laugh", "joy", "wink", "tongue", "cool", "love",
	"blush", "neutral", "sad", "cry", "angry", "surprised", "confused", "sleep",
	"heart", "heart_broken", "star", "sparkles", "fire", "skull", "crown", "sword",
	"shield", "potion", "gem", "coin", "ok", "no", "warn", "question" }) do
	ns.EMOJI_ATLAS[n] = true
end
ns.db = { profile = { links = { detect = true },
	emoticons = { style = "images", raidMarkers = true } } }

load("Modules/URLs.lua")
load("Modules/Emoticons.lua")

local pass, fail = 0, 0
local function eq(label, got, want)
	if got == want then pass = pass + 1 else
		fail = fail + 1
		print(("FAIL %s\n  got:  %s\n  want: %s"):format(label, tostring(got), tostring(want)))
	end
end
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n  " .. tostring(detail)) or ""))
	end
end

local C = "|cff5a7cfa"
local function url(s) return ns.URLs.Process(s, C) end
local function link(u, display) return C .. "|Hwtwurl:" .. u .. "|h" .. (display or u) .. "|h|r" end

--------------------------------------------------------------------------------
-- Links that must be found
--------------------------------------------------------------------------------

eq("https", url("https://example.com"), link("https://example.com"))
eq("http", url("http://example.com"), link("http://example.com"))
eq("www", url("www.example.com"), link("www.example.com"))
eq("wowhead with query", url("wowhead.com/item=123"), link("wowhead.com/item=123"))
eq("discord invite", url("discord.gg/test"), link("discord.gg/test"))
eq("query string", url("example.com/test?x=1&y=2"), link("example.com/test?x=1&y=2"))
eq("path with dashes", url("example.com/a-b_c/d"), link("example.com/a-b_c/d"))
eq("subdomain", url("de.wowhead.com/spell=133"), link("de.wowhead.com/spell=133"))
eq("port", url("https://example.com:8080/x"), link("https://example.com:8080/x"))
eq("anchor", url("https://example.com/a#b"), link("https://example.com/a#b"))

-- Trailing and wrapping punctuation stays outside the link.
eq("trailing period", url("siehe https://example.com."), "siehe " .. link("https://example.com") .. ".")
eq("trailing comma", url("https://example.com, ok"), link("https://example.com") .. ", ok")
eq("parenthesised", url("(https://example.com)"), "(" .. link("https://example.com") .. ")")
eq("bracketed", url("[www.example.com]"), "[" .. link("www.example.com") .. "]")
eq("question mark after", url("kennst du example.com?"), "kennst du " .. link("example.com") .. "?")
eq("exclamation after", url("example.com!"), link("example.com") .. "!")

-- Two links in one message, with text before, between and after.
eq("two links",
	url("erst a.com dann www.b.de fertig"),
	"erst " .. link("a.com") .. " dann " .. link("www.b.de") .. " fertig")

--------------------------------------------------------------------------------
-- Text that must NOT become a link
--------------------------------------------------------------------------------

for _, plain in ipairs({
	"das sind 3.5 dps", "e.g. so", "i.e. anders", "z.B. hier", "U.S. army",
	"Version 1.2.3 ist raus", "10.0.5 patch", "kostet 12.99 gold",
	"Mr.Smith war da", "ping 25.4 ms", "nein.das ist kein link",
}) do
	eq("plain text untouched: " .. plain, url(plain), plain)
end

--------------------------------------------------------------------------------
-- WoW escape sequences must survive
--------------------------------------------------------------------------------

local item = "|cffa335ee|Hitem:6948::::::::70:::::|h[Hearthstone]|h|r"
local spell = "|cff71d5ff|Hspell:133|h[Fireball]|h|r"
local achievement = "|cffffff00|Hachievement:1234:Player-1-AAAA:1|h[Achievement]|h|r"
local player = "|Hplayer:Thrall-Blackrock|h[Thrall]|h"
local texture = "|TInterface\\Icons\\INV_Misc_QuestionMark:14:14|t"

eq("item link untouched", url("schau " .. item), "schau " .. item)
eq("spell link untouched", url(spell), spell)
eq("achievement link untouched", url(achievement), achievement)
eq("player link untouched", url(player), player)
eq("texture untouched", url("a " .. texture .. " b"), "a " .. texture .. " b")
eq("colour codes untouched", url("|cffff0000rot|r"), "|cffff0000rot|r")
eq("link text is not scanned", url("|Hitem:1|h[wowhead.com]|h"), "|Hitem:1|h[wowhead.com]|h")
eq("url next to an item link",
	url(item .. " bei wowhead.com"), item .. " bei " .. link("wowhead.com"))
eq("url before an item link",
	url("wowhead.com " .. item), link("wowhead.com") .. " " .. item)

local extracted = ns.URLs.Extract("a https://x.com und www.y.de/p " .. item)
eq("extract count", extracted and #extracted or 0, 2)
eq("extract first", extracted and extracted[1], "https://x.com")
eq("extract ignores links", ns.URLs.Extract(item), nil)

--------------------------------------------------------------------------------
-- UTF-8
--------------------------------------------------------------------------------

local samples = {
	german = "Grüße aus München, Straße",
	french = "Voilà, c'est déjà prêt",
	spanish = "El niño está aquí",
	polish = "Zażółć gęślą jaźń",
	cyrillic = "Привет, как дела",
	chinese = "你好世界这是测试",
	korean = "안녕하세요 반갑습니다",
	mixed = "Grüße 你好 Привет ok",
}

local function isValidUTF8(s)
	local i, l = 1, #s
	while i <= l do
		local b = s:byte(i)
		local n
		if b < 0x80 then n = 1
		elseif b >= 0xC0 and b < 0xE0 then n = 2
		elseif b >= 0xE0 and b < 0xF0 then n = 3
		elseif b >= 0xF0 and b < 0xF8 then n = 4
		else return false end
		for k = 1, n - 1 do
			local c = s:byte(i + k)
			if not c or c < 0x80 or c >= 0xC0 then return false end
		end
		i = i + n
	end
	return true
end

for name, text in pairs(samples) do
	check("sample is valid utf8: " .. name, isValidUTF8(text))
	eq("links leave " .. name .. " alone", url(text), text)
	-- Truncation at every length must stay valid.
	local allValid = true
	for n = 0, ns.Text.Len(text) do
		local cut = ns.Text.TruncateVisible(text, n)
		if not isValidUTF8(cut) then allValid = false end
		if ns.Text.Len(cut) > n then allValid = false end
	end
	check("every truncation of " .. name .. " is valid utf8", allValid)
	-- Splitting for the wire must stay valid too.
	local parts = ns.Text.SplitForSend(text:rep(20), 255)
	local partsValid = true
	for i = 1, #parts do
		if not isValidUTF8(parts[i]) or #parts[i] > 255 then partsValid = false end
	end
	check("every send chunk of " .. name .. " is valid utf8", partsValid)
end

eq("first char of a multibyte name", ns.Text.FirstChar("Übermensch"), "Ü")
eq("first char cyrillic", ns.Text.FirstChar("Привет"), "П")
eq("first char chinese", ns.Text.FirstChar("你好"), "你")
eq("length counts characters", ns.Text.Len("Grüße"), 5)
eq("length cyrillic", ns.Text.Len("Привет"), 6)
eq("byte floor snaps down", ns.Text.SafeByteSub("Grüße", 1, 4), "Grü")
eq("byte ceil completes the char", ns.Text.SafeByteSub("你好世界", 2, 5), "你好")

--------------------------------------------------------------------------------
-- Truncation must not break markup
--------------------------------------------------------------------------------

eq("colour is closed when cut inside",
	ns.Text.TruncateVisible("|cffff0000rotertext|r danach", 5), "|cffff0000roter|r")
eq("colour that fits is kept whole",
	ns.Text.TruncateVisible("|cffff0000rot|r x", 5), "|cffff0000rot|r x")
eq("a link that does not fit is dropped, not halved",
	ns.Text.TruncateVisible("ab " .. item, 5), "ab ")
eq("a link that fits is kept whole",
	ns.Text.TruncateVisible("ab " .. item, 40), "ab " .. item)
check("truncation never emits a half escape",
	not ns.Text.TruncateVisible("|cffff0000abcdef|r", 3):find("|cf?f?f?$"))

--------------------------------------------------------------------------------
-- Stripping
--------------------------------------------------------------------------------

eq("strip item link keeps the visible text", ns.Text.Strip("hol " .. item), "hol [Hearthstone]")
eq("strip colour", ns.Text.Strip("|cffff0000rot|r"), "rot")
eq("strip texture", ns.Text.Strip("a " .. texture .. " b"), "a  b")
eq("strip player link", ns.Text.Strip(player), "[Thrall]")
eq("strip keeps utf8 intact", ns.Text.Strip("|cffff0000Grüße|r"), "Grüße")
eq("escaped pipe survives", ns.Text.Strip("a||b"), "a|b")

--------------------------------------------------------------------------------
-- Emoticons
--------------------------------------------------------------------------------

local function emo(s) return ns.Emoticons.Process(s, 14) end
eq("smile", emo("hey :)"), "hey <smile>")
eq("no match inside a number", emo("18) und 8)"), "18) und <cool>")
eq("colon name", emo("das ist :fire:"), "das ist <fire>")
eq("raid marker", emo("{skull} bitte"),
	"|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14:14|t bitte")
eq("emoticons skip links", emo("|Hitem:1|h[:)]|h"), "|Hitem:1|h[:)]|h")
eq("emoticons keep utf8", emo("Grüße :)"), "Grüße <smile>")
eq("emoticon next to an item link", emo(item .. " :)"), item .. " <smile>")

-- A byte string is valid UTF-8 only if every lead byte is followed by exactly
-- the continuation bytes its width promises.
local function validUTF8(str)
	local i, n = 1, #str
	while i <= n do
		local c = str:byte(i)
		local width = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3
			or c < 0xF8 and 4 or 0
		if width == 0 then return false end
		for k = 1, width - 1 do
			local cc = str:byte(i + k)
			if not cc or cc < 0x80 or cc >= 0xC0 then return false end
		end
		i = i + width
	end
	return true
end

--------------------------------------------------------------------------------
-- Native WoW markup must survive URL detection byte for byte
--------------------------------------------------------------------------------

-- The rule: never rewrite a Blizzard-formatted string blindly. A link, a
-- texture escape or a colour belongs to the client, and corrupting one turns a
-- working item link into visible garbage -- or worse, into a link that points
-- somewhere else.
local MIXED = {
	"Check https://wowhead.com/item=19019",
	"|cffff8000Thunderfury|r",
	"|Hitem:19019::::::::::::|h[Thunderfury, Blessed Blade of the Windseeker]|h",
	"|cffa335ee|Hitem:19019::::::::::::|h[Thunderfury]|h|r and https://wowhead.com/item=19019",
	"|Hplayer:Thrall-Blackrock:1|h[Thrall]|h says hi at example.com",
	"|cff71d5ff|Hspell:133|h[Fireball]|h|r beats http://fire.gg",
	"|cffffff00|Hachievement:1234:Player:0:0:0:0:0:0:0:0|h[Achievement]|h|r",
	"|TInterface\\Icons\\INV_Misc_QuestionMark:16|t icon then wowhead.com",
	"escaped pipe || and www.example.com",
	"Übergröße |cffa335ee|Hitem:19019::::::::::::|h[Straße]|h|r nötig auf example.de",
	"|Hitem:19019|h[a]|h|Hitem:19020|h[b]|h back to back plus test.com",
	"|cffff0000broken colour with no reset and https://x.com",
	"|Hitem:19019 unterminated link with example.com after",
	"just text, no links, nothing at all",
	"|Hquest:1234:70|h[A Quest]|h at questsite.com",
	"|cff00ff00|Hunit:Player-1234-ABCD:Thrall|h[Thrall]|h|r",
}

for _, raw in ipairs(MIXED) do
	local out = ns.URLs.Process(raw)
	local label = ("%q"):format(#raw > 46 and (raw:sub(1, 43) .. "...") or raw)

	-- Every |H...|h body must come back byte-identical.
	local intact = true
	for body in raw:gmatch("|H(.-)|h") do
		if not out:find("|H" .. body:gsub("(%W)", "%%%1") .. "|h") then intact = false end
	end
	check("native links survive URL detection in " .. label, intact, out)

	-- A URL link must never be created inside a native link's display text:
	-- that would nest hyperlinks, which the client cannot render.
	local nested = false
	for display in out:gmatch("|H[^|]*|h(.-)|h") do
		if display:find(ns.URLs.LINK_TYPE, 1, true) then nested = true end
	end
	check("no URL link is nested inside a native link in " .. label, not nested, out)

	-- Texture and atlas escapes are opaque.
	local textures = true
	for tex in raw:gmatch("|T.-|t") do
		if not out:find(tex, 1, true) then textures = false end
	end
	check("texture escapes survive in " .. label, textures, out)

	-- An escaped pipe is a literal pipe, not the start of anything.
	local _, rawPipes = raw:gsub("||", "")
	local _, outPipes = out:gsub("||", "")
	eq("escaped pipes are untouched in " .. label, outPipes, rawPipes)
end

-- The URL inside a mixed message is still found; surviving markup is not enough
-- if the feature stopped working.
local mixed = ns.URLs.Process(
	"|cffa335ee|Hitem:19019::::::::::::|h[Thunderfury]|h|r and https://wowhead.com/item=19019")
check("the URL beside a native link is still linked",
	mixed:find(ns.URLs.LINK_TYPE, 1, true) ~= nil, mixed)
local extracted = ns.URLs.Extract(
	"|Hitem:19019|h[Thunderfury]|h see https://example.com/a and www.b.org")
check("both URLs beside a link are extracted", extracted and #extracted == 2,
	extracted and table.concat(extracted, ", "))
check("an item id is not mistaken for a URL",
	not (ns.URLs.Extract("|Hitem:19019::::::::::::|h[Thunderfury]|h") or {})[1])

--------------------------------------------------------------------------------
-- Truncating by bytes, safely
--------------------------------------------------------------------------------

-- Every cut position, over text where almost every character is multi-byte.
local umlauts = string.rep("Übergrößenträger Straße ", 40)
local brokeUTF8, overLimit = 0, 0
for limit = 1, 200 do
	local out = ns.Text.SafeByteLimit(umlauts, limit)
	if not validUTF8(out) then brokeUTF8 = brokeUTF8 + 1 end
	if #out > limit then overLimit = overLimit + 1 end
end
eq("no cut position splits a character", brokeUTF8, 0)
eq("no cut position exceeds its limit", overLimit, 0)

-- Every cut position through a message carrying a link and a colour.
local linked = "hi |cffa335ee|Hitem:19019::::::::::::|h[Thunderfury]|h|r there"
local severed, unclosed = 0, 0
for limit = 1, #linked + 5 do
	local out = ns.Text.SafeByteLimit(linked, limit)
	local _, opens = out:gsub("|H", "")
	local _, closes = out:gsub("|h", "")
	if opens > 0 and opens * 2 ~= closes then severed = severed + 1 end
	local _, coloured = out:gsub("|c%x%x%x%x%x%x%x%x", "")
	local _, resets = out:gsub("|r", "")
	if coloured > resets then unclosed = unclosed + 1 end
end
eq("no cut position severs a link", severed, 0)
eq("no cut position leaves a colour open", unclosed, 0)

local short, cutShort = ns.Text.SafeByteLimit("short", 100)
eq("text under the limit is returned whole", short, "short")
eq("and reports that nothing was cut", cutShort, false)
local _, cutLong = ns.Text.SafeByteLimit(umlauts, 20)
eq("text over the limit reports that it was cut", cutLong, true)
eq("an empty string is handled", ns.Text.SafeByteLimit("", 10), "")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
