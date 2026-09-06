-- WhatTheWhisper -- Colour helpers.
--
-- Colours travel through the addon as {r, g, b, a} tables with values in 0..1.
-- Skins define them once; nothing else is allowed to hardcode a value.

local _, ns = ...

local Color = {}
ns.Color = Color

local floor, min, max = math.floor, math.min, math.max
local format, tonumber, sub = string.format, tonumber, string.sub

function Color.New(r, g, b, a)
	return { r or 0, g or 0, b or 0, a == nil and 1 or a }
end

-- "#5A7CFA" / "5A7CFA" / "FF5A7CFA" -> colour table
function Color.FromHex(hex, alpha)
	if type(hex) ~= "string" then return Color.New(1, 1, 1, alpha) end
	if sub(hex, 1, 1) == "#" then hex = sub(hex, 2) end
	local a = alpha
	if #hex == 8 then
		a = (tonumber(sub(hex, 1, 2), 16) or 255) / 255
		hex = sub(hex, 3)
	end
	local r = (tonumber(sub(hex, 1, 2), 16) or 255) / 255
	local g = (tonumber(sub(hex, 3, 4), 16) or 255) / 255
	local b = (tonumber(sub(hex, 5, 6), 16) or 255) / 255
	return { r, g, b, a == nil and 1 or a }
end

-- Colour code usable inside a FontString: "|cffRRGGBB"
function Color.ToEscape(c)
	return format("|cff%02x%02x%02x",
		floor(min(max(c[1], 0), 1) * 255 + 0.5),
		floor(min(max(c[2], 0), 1) * 255 + 0.5),
		floor(min(max(c[3], 0), 1) * 255 + 0.5))
end

function Color.ToHex(c)
	return format("%02x%02x%02x",
		floor(min(max(c[1], 0), 1) * 255 + 0.5),
		floor(min(max(c[2], 0), 1) * 255 + 0.5),
		floor(min(max(c[3], 0), 1) * 255 + 0.5))
end

function Color.WithAlpha(c, a)
	return { c[1], c[2], c[3], a }
end

function Color.Mix(a, b, t)
	t = min(max(t or 0, 0), 1)
	return {
		a[1] + (b[1] - a[1]) * t,
		a[2] + (b[2] - a[2]) * t,
		a[3] + (b[3] - a[3]) * t,
		(a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t,
	}
end

local WHITE = { 1, 1, 1, 1 }
local BLACK = { 0, 0, 0, 1 }

function Color.Lighten(c, amount)
	local out = Color.Mix(c, WHITE, amount)
	out[4] = c[4] or 1
	return out
end

function Color.Darken(c, amount)
	local out = Color.Mix(c, BLACK, amount)
	out[4] = c[4] or 1
	return out
end

-- Perceived luminance, used to pick readable foregrounds over arbitrary skins.
function Color.Luminance(c)
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

function Color.IsLight(c)
	return Color.Luminance(c) > 0.55
end

-- Nudges a class colour until it is readable on the given background.
function Color.EnsureContrast(fg, bg, minDelta)
	minDelta = minDelta or 0.28
	local lf, lb = Color.Luminance(fg), Color.Luminance(bg)
	local delta = lf - lb
	if math.abs(delta) >= minDelta then return fg end
	local target = lb > 0.5 and BLACK or WHITE
	local out = fg
	for _ = 1, 8 do
		out = Color.Mix(out, target, 0.12)
		if math.abs(Color.Luminance(out) - lb) >= minDelta then break end
	end
	out[4] = fg[4] or 1
	return out
end

function Color.Equal(a, b)
	if a == b then return true end
	if not a or not b then return false end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and (a[4] or 1) == (b[4] or 1)
end

function Color.Copy(c)
	return { c[1], c[2], c[3], c[4] or 1 }
end

-- Class colour with a guaranteed fallback, cached per class file.
local classCache = {}
function Color.Class(classFile)
	if not classFile then return nil end
	local cached = classCache[classFile]
	if cached then return cached end
	local r, g, b = ns.Compat.GetClassColor(classFile)
	if not r then return nil end
	local c = { r, g, b, 1 }
	classCache[classFile] = c
	return c
end

function Color.ResetClassCache()
	wipe(classCache)
end
