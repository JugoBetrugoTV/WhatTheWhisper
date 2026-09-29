-- Builds one scene of the real addon in the mock client and writes every
-- visible drawable -- textures, font strings, edit box text -- as JSON for
-- Tools/render/render.py to paint.
--
--   lua5.1 Tools/render/snapshot.lua <scene> <skin> <out.json> [metrics.lua]
--
-- Nothing here is drawn by hand: every rectangle, colour and string is what the
-- addon built. The only stand-in is text measurement, which comes from the real
-- font files through metrics.lua when render.py passes one, so bubbles are the
-- width the game would make them.

local ROOT = "/home/user/WhatTheWhisper/"
local scene, skin, outPath, metricsPath = arg[1] or "main", arg[2] or "midnight", arg[3], arg[4]

dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end
-- A Western client's chat font, which is what the addon uses unless told
-- otherwise.
_G.ChatFontNormal:SetFont("Fonts\\ARIALN.TTF", 14)
M.fontFiles = nil

--------------------------------------------------------------------------------
-- Real text measurement
--------------------------------------------------------------------------------

local metrics = metricsPath and dofile(metricsPath) or nil

local function codepoints(s)
	local out = {}
	for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local b1 = ch:byte(1)
		local cp
		if b1 < 0x80 then cp = b1
		elseif b1 < 0xE0 then cp = (b1 - 0xC0) * 64 + (ch:byte(2) - 0x80)
		elseif b1 < 0xF0 then
			cp = ((b1 - 0xE0) * 64 + (ch:byte(2) - 0x80)) * 64 + (ch:byte(3) - 0x80)
		else
			cp = (((b1 - 0xF0) * 64 + (ch:byte(2) - 0x80)) * 64 + (ch:byte(3) - 0x80)) * 64
				+ (ch:byte(4) - 0x80)
		end
		out[#out + 1] = cp
	end
	return out
end

-- Visible pieces of a string: plain runs and inline textures, escapes dropped.
local function visible(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|n", "\n")
	return text
end

local function advanceOf(fontPath, cp)
	local m = metrics and metrics.fonts[(fontPath or ""):lower()]
	if not m then
		io.stderr:write("no metrics for font " .. tostring(fontPath) .. "\n")
		metrics.fonts[(fontPath or ""):lower()] = { avg = 0.52 }
		return 0.52
	end
	return m[cp] or m.avg
end

local function measure(text, fontPath, size)
	local w = 0
	text = visible(text)
	-- An inline texture is as wide as it says, or a line high when it says 0.
	text = text:gsub("|T([^|]-)|t", function(spec)
		local h = tonumber(spec:match("^[^:]*:(%d+)")) or 0
		w = w + (h > 0 and h or size)
		return ""
	end):gsub("|A.-|a", function() w = w + size return "" end)
	for _, cp in ipairs(codepoints(text)) do w = w + advanceOf(fontPath, cp) * size end
	return w
end

local function fontOf(fs)
	local path, size = fs:GetFont()
	return path or "Fonts\\ARIALN.TTF", size or 12
end

-- Greedy word wrap, the way the client wraps a font string with word wrap on.
local function wrapLines(fs, width)
	local path, size = fontOf(fs)
	local text = fs._text or ""
	if text == "" then return 1 end
	local lines = 0
	for para in (visible(text) .. "\n"):gmatch("(.-)\n") do
		lines = lines + 1
		local lineW = 0
		for word, space in para:gmatch("(%S+)(%s*)") do
			local ww = measure(word, path, size)
			local sw = measure(space, path, size)
			if lineW > 0 and lineW + ww > width then
				lines = lines + 1
				lineW = 0
			end
			while ww > width and width > 0 do
				lines = lines + 1
				ww = ww - width
			end
			lineW = lineW + ww + sw
		end
	end
	return lines
end

if metrics then
	M.MeasureText = function(self)
		local path, size = fontOf(self)
		local widest = 0
		for para in ((self._text or "") .. "\n"):gmatch("(.-)\n") do
			widest = math.max(widest, measure(para, path, size))
		end
		return widest
	end
	M.WrapLines = wrapLines
end

--------------------------------------------------------------------------------
-- The addon
--------------------------------------------------------------------------------

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)

ns.Options.Set("appearance.skin", skin)
ns.Options.Set("messages.openOnWhisper", false)
ns.Options.Set("sounds.enabled", false)
if os.getenv("WTW_FONT") then ns.Options.Set("appearance.font", os.getenv("WTW_FONT")) end
M.RunFrames(2)

local CM, UI = ns.ConversationManager, ns.UI
M.guids = {
	["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
	["G-SYLV"] = { class = "HUNTER", race = "Scourge", name = "Sylvanas", realm = "Blackrock" },
	["G-ANDUIN"] = { class = "PRIEST", race = "Human", name = "Anduin", realm = "Blackrock" },
	["G-VALEERA"] = { class = "ROGUE", race = "BloodElf", name = "Valeera", realm = "Blackrock" },
}
M.friends = { { name = "Jaina", connected = true } }

local line = 1000
local function whisper(text, from, guid)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, from, "Common", "", from, "", 0, 0, "", 0, line, guid)
	M.RunTimers(1)
end
local function advance(seconds) M.now = (M.now or 0) + seconds end

local function populate()
	whisper("hast du kurz zeit?", "Valeera", "G-VALEERA")
	advance(600)
	whisper("gz zum mount!! :D", "Anduin", "G-ANDUIN")
	advance(900)
	whisper("kommst du heute mit in den raid?", "Sylvanas", "G-SYLV")
	advance(1200)
	whisper("Hey! Bist du noch on?", "Jaina", "G-JAINA")
	advance(40)
	whisper("Wir brauchen noch einen Heiler für Mythic heute Abend, 20 Uhr. Hättest du Lust? :)",
		"Jaina", "G-JAINA")
	advance(90)
	local jaina = ns.Compat.NormalizeName("Jaina")
	CM.Select(jaina)
	CM.SendMessage(jaina, "Klar, bin dabei!")
	M.RunTimers(1)
	advance(30)
	CM.SendMessage(jaina, "Brauchst du noch Flasks? Ich hab genug für alle mit.")
	M.RunTimers(1)
	advance(60)
	whisper("Perfekt, danke dir <3", "Jaina", "G-JAINA")
	advance(20)
	whisper("Treffpunkt ist Valdrakken, bei der Bank.", "Jaina", "G-JAINA")
	return jaina
end

--------------------------------------------------------------------------------
-- Scenes
--------------------------------------------------------------------------------

local focus   -- the frame the picture is cropped to
local jaina = populate()

if scene == "main" or scene == "menu" or scene == "emoji" then
	UI.Show()
	CM.Select(jaina)
	M.RunFrames(30)
	focus = ns.MainWindow.Get()
	if scene == "menu" then
		ns.Menu.Open(UI.BuildConversationMenu(CM.Get(jaina)), { anchor = focus })
		M.RunFrames(4)
	elseif scene == "emoji" then
		local composer = focus.view and focus.view.composer
		if composer then ns.EmojiPicker.Open(composer.emoji, composer) end
		M.RunFrames(4)
	end
elseif scene == "empty" then
	local ids = {}
	for id in pairs(CM.All()) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do CM.Remove(id) end
	UI.Show()
	M.RunFrames(30)
	focus = ns.MainWindow.Get()
elseif scene == "settings" then
	ns.SettingsUI.Show()
	M.RunFrames(30)
	focus = ns.SettingsUI.Frame()
elseif scene == "toast" then
	whisper("Bist du schon im Dungeon? Wir warten am Eingang.", "Thrall", "G-THRALL")
	ns.Toast.Show(CM.Get(ns.Compat.NormalizeName("Thrall")),
		CM.Get(ns.Compat.NormalizeName("Thrall")).messages[1])
	M.RunFrames(10)
elseif scene == "popout" then
	ns.Popout.Open(jaina)
	M.RunFrames(30)
	focus = ns.Popout.Get and ns.Popout.Get(jaina)
end

--------------------------------------------------------------------------------
-- Dump
--------------------------------------------------------------------------------

local LAYER = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }
local STRATA = { BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4, FULLSCREEN = 5,
	FULLSCREEN_DIALOG = 6, TOOLTIP = 7 }

local frameIndex = {}
for i, f in ipairs(M.frames) do frameIndex[f] = i end

local function effectiveAlpha(node)
	local a, hops = 1, 0
	while node and hops < 64 do
		a = a * (node._alpha or 1)
		node, hops = node._parent, hops + 1
	end
	return a
end

local function clipOf(region)
	local l, b, r, t = -1e9, -1e9, 1e9, 1e9
	local node, hops = region._parent, 0
	while node and hops < 64 do
		if node._clipsChildren then
			local nl, nb, nw, nh = M.Geometry(node)
			l, b = math.max(l, nl), math.max(b, nb)
			r, t = math.min(r, nl + nw), math.min(t, nb + nh)
		end
		node, hops = node._parent, hops + 1
	end
	if l == -1e9 and r == 1e9 then return nil end
	return { l, b, r, t }
end

local function rectOf(region)
	local l, b, w, h = M.Geometry(region)
	return { l, b, w, h }
end

local out = {}
local function emit(item, region, frame)
	item.rect = rectOf(region)
	item.alpha = effectiveAlpha(region)
	item.clip = clipOf(region)
	item.strata = STRATA[frame:GetFrameStrata()] or 2
	item.level = frame:GetFrameLevel()
	item.frame = frameIndex[frame] or 0
	item.layer = LAYER[region._layer or "ARTWORK"] or 2
	item.sub = region._sub or 0
	item.order = #out + 1
	out[#out + 1] = item
end

for _, region in ipairs(M.regions) do
	local frame = region._parent
	if frame and not region._isMask and region._layer ~= "HIGHLIGHT"
		and M.EffectivelyVisible(region) and effectiveAlpha(region) > 0.001
		and (M.Geometry(region) and not region._gEmpty) then
		if region._kind == "Texture" and (region._texture or region._color) then
			local masks = {}
			for _, mask in ipairs(region._masks or {}) do
				masks[#masks + 1] = { tex = mask._texture, rect = rectOf(mask),
					coord = mask._coord or { 0, 1, 0, 1 } }
			end
			emit({
				kind = "tex",
				tex = region._texture,
				color = region._color,
				coord = region._coord or { 0, 1, 0, 1 },
				vertex = region._vertex,
				gradient = region._gradient,
				blend = region._blend,
				masks = masks,
			}, region, frame)
		elseif region._kind == "FontString" and region._text and region._text ~= "" then
			local path, size = fontOf(region)
			local fo = region._font
			emit({
				kind = "text",
				text = region._text,
				font = path,
				size = size,
				color = region._textColor or (fo and fo._textColor) or { 1, 1, 1, 1 },
				justifyH = region._justifyH or (fo and fo._justifyH) or "CENTER",
				justifyV = region._justifyV or (fo and fo._justifyV) or "MIDDLE",
				wrap = region._wordWrap ~= false,
				spacing = region._spacing or 0,
			}, region, frame)
		end
	end
end

for _, frame in ipairs(M.frames) do
	if frame._kind == "EditBox" and frame._text and frame._text ~= ""
		and M.EffectivelyVisible(frame) then
		local path, size = frame:GetFont()
		emit({
			kind = "text",
			text = frame._text,
			font = path or "Fonts\\ARIALN.TTF",
			size = size or 12,
			color = frame._textColor or { 1, 1, 1, 1 },
			justifyH = "LEFT",
			justifyV = frame._multiline and "TOP" or "MIDDLE",
			wrap = frame._multiline and true or false,
			spacing = 0,
			insets = frame._textInsets,
		}, frame, frame)
	end
end

-- Minimal JSON.
local function encode(v)
	local t = type(v)
	if t == "nil" then return "null"
	elseif t == "boolean" then return v and "true" or "false"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		return string.format("%.4f", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
			elseif c == "\n" then return "\\n" end
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i = 1, #v do parts[i] = encode(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, val in pairs(v) do
			parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(val)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local focusRect = focus and rectOf(focus) or nil
local fh = assert(io.open(outPath, "w"))
fh:write(encode({ items = out, focus = focusRect, screen = { 1920, 1080 },
	errors = M.errors }))
fh:close()
if #M.errors > 0 then
	io.stderr:write("mock errors:\n  " .. table.concat(M.errors, "\n  ") .. "\n")
end
