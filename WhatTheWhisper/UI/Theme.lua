-- WhatTheWhisper -- Resolved theme.
--
-- Skins declare intent; this file turns the active skin plus the user's
-- appearance settings into the concrete colours, fonts, radii and durations the
-- widgets consume. Nothing else reads the skin tables directly.

local _, ns = ...
local Color, Compat, Skins = ns.Color, ns.Compat, ns.Skins

local Theme = {}
ns.Theme = Theme

Theme.c = {}          -- resolved colour roles
Theme.m = {}          -- resolved metrics
Theme.fonts = {}      -- FontObjects by type token

local min, max = math.min, math.max

-- Surfaces are affected by the opacity slider; content colours never are.
local SURFACE_ROLES = {
	bg0 = 1, bg1 = 1, bg2 = 1, headerBg = 1, composerBg = 1,
}
-- Raised surfaces stay more opaque than the window so menus stay readable.
local RAISED_ROLES = {
	bg3 = 1, inputBg = 1,
}

local RADIUS_SCALE = { [0] = 0, [1] = 1, [2] = 1.6 }
local SPACING_SCALE = { [0] = 0.7, [1] = 1, [2] = 1.4 }

local measureHost

--------------------------------------------------------------------------------
-- Settings access
--------------------------------------------------------------------------------

local function appearance()
	local db = ns.db
	if db and db.profile then return db.profile.appearance end
	return ns.defaults.profile.appearance
end

--------------------------------------------------------------------------------
-- Fonts
--------------------------------------------------------------------------------

local FONT_TOKENS = { "MICRO", "SMALL", "BODY", "TITLE", "DISPLAY" }

local function buildFonts()
	local ap = appearance()
	local path = ap.font
	if not path or path == "" or not Compat.ValidateFont(path) then
		path = Compat.GetDefaultFont()
	end
	Theme.fontPath = path

	local offset = tonumber(ap.fontScale) or 0
	local shadowAlpha = (Theme.m.surfaceAlpha or 1) < 1 and 0.45 or 0

	for i = 1, #FONT_TOKENS do
		local token = FONT_TOKENS[i]
		local size = min(28, max(8, (ns.T[token] or 12) + offset))
		local fo = Theme.fonts[token]
		if not fo then
			fo = CreateFont("WhatTheWhisperFont" .. token)
			Theme.fonts[token] = fo
		end
		fo:SetFont(path, size, "")
		fo:SetShadowOffset(shadowAlpha > 0 and 1 or 0, shadowAlpha > 0 and -1 or 0)
		fo:SetShadowColor(0, 0, 0, shadowAlpha)
		fo:SetJustifyH("LEFT")
		fo:SetJustifyV("MIDDLE")
		Theme.fontSizes = Theme.fontSizes or {}
		Theme.fontSizes[token] = size
	end
end

function Theme.Font(token)
	return Theme.fonts[token] or Theme.fonts.BODY
end

function Theme.FontSize(token)
	return (Theme.fontSizes and Theme.fontSizes[token]) or ns.T[token] or 12
end

-- A hidden FontString per type token, used for measuring without touching a
-- live widget.
function Theme.Measure(token)
	if not measureHost then
		measureHost = CreateFrame("Frame", nil, UIParent)
		measureHost:Hide()
		measureHost:SetSize(1, 1)
		measureHost.strings = {}
	end
	local fs = measureHost.strings[token]
	if not fs then
		fs = measureHost:CreateFontString(nil, "ARTWORK")
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		measureHost.strings[token] = fs
	end
	fs:SetFontObject(Theme.Font(token))
	fs:SetSpacing(ns.LINE_SPACING)
	return fs
end

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

local fallbackSkin

function Theme.Get(role)
	local c = Theme.c[role]
	if c then return c end
	if fallbackSkin and fallbackSkin.colors[role] then return fallbackSkin.colors[role] end
	return { 1, 0, 1, 1 }   -- magenta: an unresolved role must be obvious
end

-- Shorthand used everywhere: local c = Theme.c
function Theme.Unpack(role, alphaOverride)
	local c = Theme.Get(role)
	return c[1], c[2], c[3], alphaOverride or c[4] or 1
end

--------------------------------------------------------------------------------
-- Metrics
--------------------------------------------------------------------------------

function Theme.Radius(base)
	local scale = Theme.m.radiusScale or 1
	local r = (base or ns.R.MD) * scale
	if r < 0.5 then return 0 end
	return r
end

function Theme.BubbleRadius()
	return Theme.Radius(Theme.m.bubbleRadius or ns.R.LG)
end

function Theme.MessageSpacing(base)
	return base * (Theme.m.spacingScale or 1)
end

function Theme.Border(frame)
	return ns.Pixel.Hairline(frame, Theme.m.borderScale or 1)
end

function Theme.RowHeight()
	local ap = appearance()
	if ap.density == "compact" then return ns.SZ.ROW_H_COMPACT end
	return ns.SZ.ROW_H
end

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

function Theme.MotionScale()
	local db = ns.db
	local level = (db and db.profile and db.profile.animations.level) or "normal"
	return ns.MOTION_SCALE[level] or 1
end

function Theme.Duration(token)
	return (ns.MOTION[token] or ns.MOTION.BASE) * Theme.MotionScale()
end

function Theme.AnimationsEnabled()
	return Theme.MotionScale() > 0
end

function Theme.IsFancy()
	local db = ns.db
	return db and db.profile and db.profile.animations.level == "fancy"
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function Theme.Refresh()
	fallbackSkin = Skins.Get("midnight")
	local ap = appearance()
	local skin = Skins.Get(ap.skin)
	Theme.skin = skin
	Theme.skinID = skin.id

	-- metrics
	wipe(Theme.m)
	for k, v in pairs(Skins.DEFAULT_METRICS) do Theme.m[k] = v end
	for k, v in pairs(skin.metrics) do Theme.m[k] = v end
	Theme.m.radiusScale = (Theme.m.radiusScale or 1) * (RADIUS_SCALE[ap.radius] or 1)
	Theme.m.spacingScale = (Theme.m.spacingScale or 1) * (SPACING_SCALE[ap.spacing] or 1)
	if not ap.shadows then Theme.m.shadow = 0 end

	-- colours
	wipe(Theme.c)
	local opacity = min(1, max(0.35, tonumber(ap.opacity) or 1))
	local surfaceAlpha = opacity * (Theme.m.surfaceAlpha or 1)
	local raisedAlpha = (0.55 + 0.45 * opacity) * (Theme.m.surfaceAlpha or 1)

	for i = 1, #Skins.ROLES do
		local role = Skins.ROLES[i]
		local src = skin.colors[role] or fallbackSkin.colors[role]
		if src then
			local c = Color.Copy(src)
			if SURFACE_ROLES[role] then
				c[4] = (c[4] or 1) * surfaceAlpha
			elseif RAISED_ROLES[role] then
				c[4] = (c[4] or 1) * raisedAlpha
			end
			Theme.c[role] = c
		end
	end

	-- user link colour override
	local db = ns.db
	if db and db.profile and db.profile.links and db.profile.links.color then
		local lc = db.profile.links.color
		Theme.c.link = { lc[1] or 0, lc[2] or 0, lc[3] or 0, 1 }
	end

	-- bubble opacity slider
	local bubbleAlpha = min(1, max(0.15, tonumber(ap.bubbleOpacity) or 1))
	if Theme.c.bubbleIn then Theme.c.bubbleIn[4] = (Theme.c.bubbleIn[4] or 1) * bubbleAlpha end
	if Theme.c.bubbleOut then Theme.c.bubbleOut[4] = (Theme.c.bubbleOut[4] or 1) * bubbleAlpha end

	buildFonts()
	Color.ResetClassCache()
	if ns.Avatar then ns.Avatar.ResetFallbackCache() end

	ns.Bus.Fire(ns.EV.THEME_CHANGED)
end

-- Class colour, blended towards the skin's palette and then contrast-corrected
-- against the surface it will actually sit on.
function Theme.ClassColor(classFile, surfaceRole)
	local ap = appearance()
	if not ap.classColors or not classFile then return nil end
	local c = Color.Class(classFile)
	if not c then return nil end
	local blend = Theme.m.classColorBlend or 0
	if blend > 0 then
		c = Color.Mix(c, Theme.Get("textPrimary"), blend)
	end
	if surfaceRole then
		return Color.EnsureContrast(c, Theme.Get(surfaceRole), 0.22)
	end
	return c
end

-- Convenience: apply a font token and a colour role to a FontString in one call.
function Theme.Style(fontString, token, role, alpha)
	fontString:SetFontObject(Theme.Font(token))
	local c = Theme.Get(role or "textPrimary")
	fontString:SetTextColor(c[1], c[2], c[3], alpha or c[4] or 1)
end
