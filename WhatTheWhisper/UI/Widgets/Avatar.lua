-- WhatTheWhisper -- Avatars.
--
-- Three sources, in order of how much they actually tell you:
--   1. the live unit portrait, when that player happens to be in range
--   2. the class icon, when the class is known from a GUID, roster or /who
--   3. a class-coloured disc with the first character of the name
-- Anything the client cannot tell us falls through to the next one, so there is
-- never an empty square.

local _, ns = ...
local Theme, W, Draw, Compat, Text = ns.Theme, ns.Widgets, ns.Draw, ns.Compat, ns.Text

local Avatar = {}
ns.Avatar = Avatar

local STATUS_RING = 2

function Avatar.New(parent, size)
	local a = CreateFrame("Frame", nil, parent)
	a:SetSize(size, size)
	a.size = size

	-- Background disc, always drawn: it is the fallback and the ring behind a
	-- class icon that does not fill its square.
	a.disc = a:CreateTexture(nil, "BACKGROUND")
	a.disc:SetTexture(Draw.TEX_ROUND, "CLAMP", "CLAMP")
	a.disc:SetAllPoints(a)

	a.image = a:CreateTexture(nil, "ARTWORK")
	a.image:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
	a.image:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
	a.image:Hide()

	local masked = Draw.MaskCircle(a, a.image)
	a.masked = masked
	if not masked then
		-- No mask support: the image is inset and the disc shows as a ring, so
		-- the footprint and palette stay identical to the masked version.
		a.image:SetPoint("TOPLEFT", a, "TOPLEFT", 2, -2)
		a.image:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -2, 2)
	end

	a.initials = W.Text(a, size >= 36 and "BODY" or "MICRO", "onAccent", "OVERLAY")
	a.initials:ClearAllPoints()
	a.initials:SetPoint("CENTER", a, "CENTER", 0, 0)
	a.initials:SetJustifyH("CENTER")

	-- Status dot with a cut-out ring so it reads on any background.
	a.statusRing = a:CreateTexture(nil, "OVERLAY", nil, 1)
	a.statusRing:SetTexture(Draw.TEX_ROUND, "CLAMP", "CLAMP")
	a.statusRing:SetSize(ns.SZ.STATUS_DOT + STATUS_RING * 2, ns.SZ.STATUS_DOT + STATUS_RING * 2)
	a.statusRing:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 1, -1)
	a.statusRing:Hide()

	a.status = a:CreateTexture(nil, "OVERLAY", nil, 2)
	a.status:SetTexture(Draw.TEX_ROUND, "CLAMP", "CLAMP")
	a.status:SetSize(ns.SZ.STATUS_DOT, ns.SZ.STATUS_DOT)
	a.status:SetPoint("CENTER", a.statusRing, "CENTER")
	a.status:Hide()

	a.SetConversation = Avatar.SetConversation
	a.SetStatus = Avatar.SetStatus
	a.SetAvatarSize = Avatar.SetAvatarSize
	a.SetSurfaceRole = Avatar.SetSurfaceRole
	a.ApplyTheme = Avatar.ApplyTheme
	return a
end

function Avatar:SetAvatarSize(size)
	self.size = size
	self:SetSize(size, size)
	self.initials:SetFontObject(Theme.Font(size >= 36 and "BODY" or "MICRO"))
	self.initials.__wtwToken = size >= 36 and "BODY" or "MICRO"
end

-- When the class is unknown, or class colours are switched off, the disc still
-- has to distinguish one person from another -- so it is derived from the name
-- the way every other messenger does it, then blended towards the skin so a
-- palette of six never looks bolted on.
local FALLBACK = {
	"#5A7CFA", "#3FBF7F", "#E8B84B", "#E5484D", "#9B6BE8", "#2FA8C7", "#E07A3F", "#4FB3A5",
}
local fallbackCache = {}

local function fallbackColor(key)
	local cached = fallbackCache[key]
	if cached then return cached end
	local sum = 0
	for i = 1, #key do sum = sum + key:byte(i) * i end
	local base = ns.Color.FromHex(FALLBACK[(sum % #FALLBACK) + 1])
	local blend = (Theme.m and Theme.m.classColorBlend) or 0
	if blend > 0 then base = ns.Color.Mix(base, Theme.Get("textPrimary"), blend) end
	fallbackCache[key] = base
	return base
end

function Avatar.ResetFallbackCache()
	wipe(fallbackCache)
end

local function discFill(conv)
	local c = Theme.ClassColor(conv.class)
	if c then return c end
	return fallbackColor(conv.id or conv.name or "?")
end

function Avatar:SetConversation(conv)
	self.conv = conv
	if not conv then
		self.image:Hide()
		self.initials:SetText("")
		return
	end

	local ap = ns.db.profile.appearance
	local style = ap.avatarStyle
	local classFile = conv.class

	local fill = discFill(conv)
	self.disc:SetVertexColor(fill[1], fill[2], fill[3], 1)

	local usedImage = false

	if style == "auto" and not conv.isBN then
		-- A live portrait only exists while the player is nearby; when they walk
		-- away we fall back rather than freezing a stale face.
		if Compat.ClassFromVisibleUnit(conv.id) then
			for _, unit in ipairs({ "target", "focus", "mouseover" }) do
				if UnitExists(unit) and UnitIsPlayer(unit) then
					local n, r = UnitName(unit)
					local full = (r and r ~= "") and (n .. "-" .. r:gsub("%s+", ""))
						or Compat.NormalizeName(n or "")
					if full == conv.id and Compat.SetPortraitTexture(self.image, unit) then
						self.image:SetTexCoord(0, 1, 0, 1)
						self.image:Show()
						usedImage = true
						break
					end
				end
			end
		end
	end

	if not usedImage and style ~= "initials" and classFile then
		local l, r, t, b = Compat.GetClassIconCoords(classFile)
		if l then
			self.image:SetTexture(Compat.CLASS_ICON_TEXTURE, "CLAMP", "CLAMP")
			self.image:SetTexCoord(l, r, t, b)
			self.image:SetVertexColor(1, 1, 1, 1)
			self.image:Show()
			usedImage = true
		end
	end

	if usedImage then
		self.initials:SetText("")
	else
		self.image:Hide()
		local label = Text.UpperFirst(Text.FirstChar(conv.name or conv.id or "?"))
		self.initials:SetText(label)
		-- Pick the readable foreground for whatever disc colour we ended up with.
		local fg = ns.Color.IsLight(fill) and { 0.08, 0.09, 0.11, 1 } or { 1, 1, 1, 0.95 }
		self.initials:SetTextColor(fg[1], fg[2], fg[3], fg[4])
	end

	self:SetStatus(conv.isBN and nil or ns.PlayerInfo.IsOnline(conv.id))
end

-- online: true / false / nil (unknown -> no dot, because a grey dot would be a
-- claim we cannot back up)
function Avatar:SetStatus(online, surfaceRole)
	if online == nil then
		self.status:Hide()
		self.statusRing:Hide()
		return
	end
	local c = Theme.Get(online and "online" or "textMuted")
	self.status:SetVertexColor(c[1], c[2], c[3], 1)
	local ring = Theme.Get(surfaceRole or self.surfaceRole or "bg1")
	self.statusRing:SetVertexColor(ring[1], ring[2], ring[3], 1)
	self.status:Show()
	self.statusRing:Show()
end

function Avatar:SetSurfaceRole(role)
	self.surfaceRole = role
end

function Avatar:ApplyTheme()
	W.RefreshText(self.initials)
	if self.conv then self:SetConversation(self.conv) end
end
