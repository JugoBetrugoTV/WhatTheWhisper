-- WhatTheWhisper -- Drawing primitives.
--
-- WoW draws axis-aligned quads and nothing else, so a rounded rectangle has to
-- be assembled by hand. Every rounded surface in the addon is built from the
-- generated Round.tga: four corner quads sampling one quadrant of a disc, plus
-- three solid bands. That is seven textures for any radius, at any size, on
-- every client -- no BackdropTemplate, no 8 px Blizzard tiles, no per-client
-- differences.

local _, ns = ...
local Compat, Pixel = ns.Compat, ns.Pixel

local Draw = {}
ns.Draw = Draw

local ART = ns.ART
local TEX_ROUND  = ART .. "Round"
local TEX_SHADOW = ART .. "Shadow"
local TEX_ICONS  = ART .. "Icons"
local TEX_EMOJI  = ART .. "Emoji"

Draw.TEX_ROUND, Draw.TEX_SHADOW, Draw.TEX_ICONS, Draw.TEX_EMOJI =
	TEX_ROUND, TEX_SHADOW, TEX_ICONS, TEX_EMOJI

local min, max = math.min, math.max

-- Sampling the exact centre of the disc gives a fully opaque texel, which is how
-- a "square" corner is produced without a second texture.
local SOLID = { 0.45, 0.55, 0.45, 0.55 }
local QUADRANT = {
	TL = { 0.0, 0.5, 0.0, 0.5 },
	TR = { 0.5, 1.0, 0.0, 0.5 },
	BL = { 0.0, 0.5, 0.5, 1.0 },
	BR = { 0.5, 1.0, 0.5, 1.0 },
}

--------------------------------------------------------------------------------
-- Plain textures
--------------------------------------------------------------------------------

function Draw.Texture(parent, layer, subLevel)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel)
	return tex
end

function Draw.Solid(parent, layer, subLevel, r, g, b, a)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel)
	tex:SetColorTexture(r or 0, g or 0, b or 0, a == nil and 1 or a)
	return tex
end

function Draw.Fill(parent, layer, subLevel, r, g, b, a)
	local tex = Draw.Solid(parent, layer, subLevel, r, g, b, a)
	tex:SetAllPoints(parent)
	return tex
end

-- One physical pixel high/wide, so dividers stay crisp at any UI scale.
function Draw.Hairline(parent, layer, subLevel)
	local tex = parent:CreateTexture(nil, layer or "BORDER", nil, subLevel)
	tex:SetColorTexture(1, 1, 1, 1)
	-- Marked so a divider can be told apart from any other one-pixel strip; the
	-- audit uses it to prove no boundary ends up with two borders drawn on it.
	tex.__wtwHairline = true
	return tex
end

function Draw.SetHairlineH(tex, parent, yOffset, insetLeft, insetRight, thickness)
	local t = thickness or Pixel.Size(parent)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", parent, "TOPLEFT", insetLeft or 0, yOffset or 0)
	tex:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(insetRight or 0), yOffset or 0)
	tex:SetHeight(t)
end

function Draw.SetHairlineV(tex, parent, xOffset, insetTop, insetBottom, thickness)
	local t = thickness or Pixel.Size(parent)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset or 0, -(insetTop or 0))
	tex:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", xOffset or 0, insetBottom or 0)
	tex:SetWidth(t)
end

function Draw.Gradient(tex, orientation, c1, c2)
	Compat.SetGradient(tex, orientation,
		c1[1], c1[2], c1[3], c1[4] or 1,
		c2[1], c2[2], c2[3], c2[4] or 1)
end

--------------------------------------------------------------------------------
-- Rounded rectangle
--------------------------------------------------------------------------------

local RoundedMT = {}
RoundedMT.__index = RoundedMT

local function newPiece(parent, layer, subLevel)
	local tex = parent:CreateTexture(nil, layer, nil, subLevel)
	tex:SetTexture(TEX_ROUND, "CLAMP", "CLAMP")
	return tex
end

-- parent   frame the rectangle is drawn inside
-- layer    draw layer for all seven pieces
-- subLevel sub-level within that layer
function Draw.NewRounded(parent, layer, subLevel)
	layer = layer or "BACKGROUND"
	subLevel = subLevel or 0
	local o = setmetatable({
		parent = parent,
		radius = ns.R.MD,
		insets = { 0, 0, 0, 0 },
		corners = { TL = true, TR = true, BL = true, BR = true },
		color = { 1, 1, 1, 1 },
		shown = true,
	}, RoundedMT)

	o.tl = newPiece(parent, layer, subLevel)
	o.tr = newPiece(parent, layer, subLevel)
	o.bl = newPiece(parent, layer, subLevel)
	o.br = newPiece(parent, layer, subLevel)
	o.top = newPiece(parent, layer, subLevel)
	o.mid = newPiece(parent, layer, subLevel)
	o.bottom = newPiece(parent, layer, subLevel)
	o.pieces = { o.tl, o.tr, o.bl, o.br, o.top, o.mid, o.bottom }

	o.tl:SetTexCoord(unpack(QUADRANT.TL))
	o.tr:SetTexCoord(unpack(QUADRANT.TR))
	o.bl:SetTexCoord(unpack(QUADRANT.BL))
	o.br:SetTexCoord(unpack(QUADRANT.BR))
	o.top:SetTexCoord(unpack(SOLID))
	o.mid:SetTexCoord(unpack(SOLID))
	o.bottom:SetTexCoord(unpack(SOLID))

	o:Layout()
	return o
end

function RoundedMT:SetInsets(l, r, t, b)
	self.insets[1] = l or 0
	self.insets[2] = r or 0
	self.insets[3] = t or 0
	self.insets[4] = b or 0
	self:Layout()
	return self
end

function RoundedMT:SetRadius(radius)
	self.radius = max(0, radius or 0)
	self:Layout()
	return self
end

-- Which corners are rounded. Used for bubble tails and for tabs, where only the
-- top two corners are round.
function RoundedMT:SetCorners(tl, tr, bl, br)
	self.corners.TL = tl and true or false
	self.corners.TR = tr and true or false
	self.corners.BL = bl and true or false
	self.corners.BR = br and true or false
	self:Layout()
	return self
end

function RoundedMT:SetColor(r, g, b, a)
	if type(r) == "table" then
		r, g, b, a = r[1], r[2], r[3], r[4]
	end
	self.color[1], self.color[2], self.color[3], self.color[4] = r, g, b, a == nil and 1 or a
	for i = 1, 7 do
		self.pieces[i]:SetVertexColor(r, g, b, self.color[4])
	end
	return self
end

function RoundedMT:GetColor()
	local c = self.color
	return c[1], c[2], c[3], c[4]
end

function RoundedMT:SetAlpha(a)
	for i = 1, 7 do self.pieces[i]:SetAlpha(a) end
	return self
end

function RoundedMT:SetDrawLayer(layer, subLevel)
	for i = 1, 7 do self.pieces[i]:SetDrawLayer(layer, subLevel) end
	return self
end

function RoundedMT:Show()
	self.shown = true
	self:Layout()
	return self
end

function RoundedMT:Hide()
	self.shown = false
	for i = 1, 7 do self.pieces[i]:Hide() end
	return self
end

function RoundedMT:SetShown(shown)
	if shown then return self:Show() end
	return self:Hide()
end

function RoundedMT:IsShown()
	return self.shown
end

-- Recomputes all seven anchors. Called on every geometry change; cheap enough to
-- run from OnSizeChanged because it only touches anchors, never creates.
function RoundedMT:Layout()
	if not self.shown then return end
	local p = self.parent
	local il, ir, it, ib = self.insets[1], self.insets[2], self.insets[3], self.insets[4]

	local w = (p:GetWidth() or 0) - il - ir
	local h = (p:GetHeight() or 0) - it - ib
	if w <= 0 or h <= 0 then
		for i = 1, 7 do self.pieces[i]:Hide() end
		return
	end

	local r = min(self.radius, w / 2, h / 2)
	if r < 0.5 then r = 0 end

	local function corner(tex, key, point, ox, oy)
		tex:ClearAllPoints()
		if r <= 0 then
			tex:Hide()
			return
		end
		tex:SetTexCoord(unpack(self.corners[key] and QUADRANT[key] or SOLID))
		tex:SetSize(r, r)
		tex:SetPoint(point, p, point, ox, oy)
		tex:Show()
	end

	corner(self.tl, "TL", "TOPLEFT", il, -it)
	corner(self.tr, "TR", "TOPRIGHT", -ir, -it)
	corner(self.bl, "BL", "BOTTOMLEFT", il, ib)
	corner(self.br, "BR", "BOTTOMRIGHT", -ir, ib)

	-- centre band spans the full width between the corner rows
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", p, "TOPLEFT", il, -(it + r))
	self.mid:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -ir, ib + r)
	self.mid:Show()

	if r > 0 then
		self.top:ClearAllPoints()
		self.top:SetPoint("TOPLEFT", p, "TOPLEFT", il + r, -it)
		self.top:SetPoint("TOPRIGHT", p, "TOPRIGHT", -(ir + r), -it)
		self.top:SetHeight(r)
		self.top:Show()

		self.bottom:ClearAllPoints()
		self.bottom:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", il + r, ib)
		self.bottom:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(ir + r), ib)
		self.bottom:SetHeight(r)
		self.bottom:Show()
	else
		self.top:Hide()
		self.bottom:Hide()
	end
end

--------------------------------------------------------------------------------
-- Rounded rectangle with a hairline outline
--------------------------------------------------------------------------------

local OutlinedMT = {}
OutlinedMT.__index = OutlinedMT

-- The outline is the *outer* rounded rect and the fill is inset inside it by the
-- border thickness. Drawing it this way keeps the whole surface inside the
-- frame's bounds (so a row highlight never bleeds into its neighbour) and gives
-- an evenly thick stroke at any radius, which stroking four sides cannot.
function Draw.NewOutlined(parent, layer, subLevel)
	local o = setmetatable({
		parent = parent,
		radius = 0,
		thickness = 0,
		insets = { 0, 0, 0, 0 },
	}, OutlinedMT)
	o.border = Draw.NewRounded(parent, layer or "BACKGROUND", (subLevel or 0))
	o.fill = Draw.NewRounded(parent, layer or "BACKGROUND", (subLevel or 0) + 1)
	o.border:Hide()
	return o
end

function OutlinedMT:Apply()
	local i, t = self.insets, self.thickness or 0
	self.border:SetInsets(i[1], i[2], i[3], i[4])
	self.border:SetRadius(self.radius)
	self.fill:SetInsets(i[1] + t, i[2] + t, i[3] + t, i[4] + t)
	self.fill:SetRadius(math.max(0, self.radius - t))
	self.border:SetShown(t > 0)
	return self
end

function OutlinedMT:SetRadius(radius)
	self.radius = radius or 0
	return self:Apply()
end

function OutlinedMT:SetInsets(l, r, t, b)
	self.insets[1], self.insets[2] = l or 0, r or 0
	self.insets[3], self.insets[4] = t or 0, b or 0
	return self:Apply()
end

function OutlinedMT:SetBorder(thickness, r, g, b, a)
	self.thickness = thickness or 0
	if r then self.border:SetColor(r, g, b, a) end
	return self:Apply()
end

function OutlinedMT:SetColor(...)
	self.fill:SetColor(...)
	return self
end

function OutlinedMT:GetColor()
	return self.fill:GetColor()
end

function OutlinedMT:SetCorners(...)
	self.fill:SetCorners(...)
	self.border:SetCorners(...)
	return self
end

function OutlinedMT:Layout()
	self.border:Layout()
	self.fill:Layout()
end

function OutlinedMT:SetShown(shown)
	self.fill:SetShown(shown)
	self.border:SetShown(shown and (self.thickness or 0) > 0)
	return self
end

function OutlinedMT:SetAlpha(a)
	self.fill:SetAlpha(a)
	self.border:SetAlpha(a)
	return self
end

function OutlinedMT:SetDrawLayer(layer, sub)
	self.border:SetDrawLayer(layer, sub or 0)
	self.fill:SetDrawLayer(layer, (sub or 0) + 1)
	return self
end

--------------------------------------------------------------------------------
-- Drop shadow (nine-slice)
--------------------------------------------------------------------------------

local SHADOW_SLICE = 44 / 128

local ShadowMT = {}
ShadowMT.__index = ShadowMT

-- The shadow lives in its own frame one level below the target so it cannot be
-- clipped by SetClipsChildren and cannot cover the target's own content.
function Draw.NewShadow(target, spread)
	spread = spread or 14
	local parent = target:GetParent() or UIParent
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetFrameStrata(target:GetFrameStrata())
	frame:SetFrameLevel(max(0, (target:GetFrameLevel() or 1) - 1))
	frame:SetPoint("TOPLEFT", target, "TOPLEFT", -spread, spread)
	frame:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", spread, -spread)

	local o = setmetatable({ frame = frame, target = target, spread = spread, pieces = {} }, ShadowMT)

	-- The shadow has to be a sibling of the window rather than a child, because
	-- a child cannot draw behind its parent's own background. The cost of that
	-- is that hiding the window does not hide the shadow: it is not in the
	-- window's parent chain, so nothing tells it to go away, and a closed window
	-- leaves a dark rectangle sitting on the world.
	--
	-- So visibility is mirrored explicitly, and it is watched from a private
	-- one pixel child of the window rather than by hooking the window itself.
	--
	-- Hooking the target directly is fragile in a way that already shipped once:
	-- any later SetScript("OnHide", ...) on that frame replaces every handler on
	-- it, hooks included, and the shadow is orphaned with no sign that anything
	-- broke. Nobody else ever touches this child, and a child's OnHide fires
	-- whenever it stops being visible, an ancestor hiding included, so it covers
	-- closing the window, docking a popout and hiding the whole interface.
	--
	-- Re-evaluates, never records: passing a value here would write "hidden" as
	-- the caller's intent the first time the window closed, and the shadow would
	-- never come back.
	local function follow()
		o:SetShown()
	end
	local watcher = CreateFrame("Frame", nil, target)
	watcher:SetSize(1, 1)
	watcher:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
	watcher:SetScript("OnShow", follow)
	watcher:SetScript("OnHide", follow)
	o.watcher = watcher
	frame:SetShown(target:IsShown())

	local function piece(u1, u2, v1, v2)
		local tex = frame:CreateTexture(nil, "BACKGROUND")
		tex:SetTexture(TEX_SHADOW, "CLAMP", "CLAMP")
		tex:SetTexCoord(u1, u2, v1, v2)
		o.pieces[#o.pieces + 1] = tex
		return tex
	end

	local s = SHADOW_SLICE
	local sz = spread * 2
	local tl = piece(0, s, 0, s)          tl:SetSize(sz, sz) tl:SetPoint("TOPLEFT")
	local tr = piece(1 - s, 1, 0, s)      tr:SetSize(sz, sz) tr:SetPoint("TOPRIGHT")
	local bl = piece(0, s, 1 - s, 1)      bl:SetSize(sz, sz) bl:SetPoint("BOTTOMLEFT")
	local br = piece(1 - s, 1, 1 - s, 1)  br:SetSize(sz, sz) br:SetPoint("BOTTOMRIGHT")

	local t = piece(s, 1 - s, 0, s)
	t:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	local b = piece(s, 1 - s, 1 - s, 1)
	b:SetPoint("TOPLEFT", bl, "TOPRIGHT")
	b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	local l = piece(0, s, s, 1 - s)
	l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	local r = piece(1 - s, 1, s, 1 - s)
	r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
	r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	local c = piece(s, 1 - s, s, 1 - s)
	c:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
	c:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")

	return o
end

-- Remembers what the caller asked for. The shadow is only actually shown when
-- both that and the window's own visibility agree, so mirroring the window can
-- never resurrect a shadow that the theme or a setting switched off.
function ShadowMT:SetShown(shown)
	if shown ~= nil then self.wanted = shown and true or false end
	self.frame:SetShown((self.wanted ~= false) and self.target:IsShown())
	return self
end

function ShadowMT:IsShown()
	return self.frame:IsShown()
end

function ShadowMT:SetColor(r, g, b, a)
	if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
	for i = 1, #self.pieces do
		self.pieces[i]:SetVertexColor(r, g, b, a == nil and 1 or a)
	end
	return self
end

function ShadowMT:SetSpread(spread)
	self.spread = spread
	self.frame:SetPoint("TOPLEFT", self.target, "TOPLEFT", -spread, spread)
	self.frame:SetPoint("BOTTOMRIGHT", self.target, "BOTTOMRIGHT", spread, -spread)
	local sz = spread * 2
	for i = 1, 4 do self.pieces[i]:SetSize(sz, sz) end
	return self
end

function ShadowMT:SetFrameLevel(level)
	self.frame:SetFrameLevel(max(0, level))
	return self
end

--------------------------------------------------------------------------------
-- Circular masking
--------------------------------------------------------------------------------

-- Returns true when the texture was actually masked. Callers fall back to a
-- rounded square (same footprint, same palette) when masks are unavailable.
function Draw.MaskCircle(frame, texture)
	if not Compat.hasMasks then return false end
	local ok, mask = pcall(frame.CreateMaskTexture, frame)
	if not ok or not mask then return false end
	mask:SetTexture(TEX_ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	local applied = pcall(texture.AddMaskTexture, texture, mask)
	if not applied then return false end
	return true, mask
end

--------------------------------------------------------------------------------
-- Atlas helpers
--------------------------------------------------------------------------------

function Draw.SetIcon(texture, name)
	local coords = ns.ICON_ATLAS and ns.ICON_ATLAS[name]
	if not coords then
		texture:SetTexture(nil)
		return false
	end
	texture:SetTexture(TEX_ICONS, "CLAMP", "CLAMP")
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	return true
end

function Draw.SetEmoji(texture, name)
	local coords = ns.EMOJI_ATLAS and ns.EMOJI_ATLAS[name]
	if not coords then return false end
	texture:SetTexture(TEX_EMOJI, "CLAMP", "CLAMP")
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	return true
end

-- Inline emoji markup for use inside a FontString.
function Draw.EmojiMarkup(name, size)
	local coords = ns.EMOJI_ATLAS and ns.EMOJI_ATLAS[name]
	if not coords then return nil end
	-- |Tpath:h:w:x:y:sheetW:sheetH:left:right:top:bottom|t
	return string.format("|T%s:%d:%d:0:0:512:512:%d:%d:%d:%d|t",
		TEX_EMOJI, size, size,
		coords[1] * 512, coords[2] * 512, coords[3] * 512, coords[4] * 512)
end
