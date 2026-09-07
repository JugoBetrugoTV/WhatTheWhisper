-- Minimal but strict World of Warcraft API mock, used to actually load and run
-- WhatTheWhisper outside the game. Unknown methods are recorded rather than
-- silently accepted, so a typo in an API name shows up in the report.

local M = {}
_G.WOWMOCK = M

M.unknownMethods = {}
M.frames = {}
M.eventFrames = {}
M.timers = {}
M.now = 1000
M.errors = {}

local function record(kind, name)
	local key = kind .. ":" .. name
	M.unknownMethods[key] = (M.unknownMethods[key] or 0) + 1
end

--------------------------------------------------------------------------------
-- Base object
--------------------------------------------------------------------------------

local function makeObject(kind, methods)
	local proto = {}
	for name, fn in pairs(methods) do proto[name] = fn end
	local mt = {
		__index = function(t, key)
			local value = rawget(proto, key)
			if value ~= nil then return value end
			if M.blocked and M.blocked[kind .. ":" .. key] then return nil end
			if type(key) == "string" and key:match("^%u") then
				record(kind, key)
				local stub = function() return nil end
				rawset(t, key, stub)
				return stub
			end
			return nil
		end,
	}
	return proto, mt
end

--------------------------------------------------------------------------------
-- Regions (shared by frames, textures, font strings)
--------------------------------------------------------------------------------

-- Bumped whenever the anchor graph changes; the solver memoises per generation.
local generation = 1
local function invalidate() generation = generation + 1 end
M.InvalidateLayout = invalidate

local regionMethods = {}

-- Anchor bookkeeping. Sizes are derived from opposing anchors the way the real
-- layout engine does, so measurement code runs against realistic numbers
-- instead of a constant.
local LEFT_EDGE = { LEFT = true, TOPLEFT = true, BOTTOMLEFT = true }
local RIGHT_EDGE = { RIGHT = true, TOPRIGHT = true, BOTTOMRIGHT = true }
local TOP_EDGE = { TOP = true, TOPLEFT = true, TOPRIGHT = true }
local BOTTOM_EDGE = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

function regionMethods:SetPoint(a, b, c, d, e)
	local point, relTo, relPoint, x, y
	point = a
	if b == nil then
		relTo, relPoint, x, y = nil, point, 0, 0
	elseif type(b) == "number" then
		relTo, relPoint, x, y = nil, point, b, c or 0
	elseif type(c) == "number" then
		relTo, relPoint, x, y = b, point, c, d or 0
	else
		relTo, relPoint, x, y = b, c or point, d or 0, e or 0
	end
	self._points = self._points or {}
	self._points[#self._points + 1] = { point, relTo, relPoint, x, y }
	invalidate()
end

function regionMethods:SetAllPoints(other)
	other = other or self._parent
	self._points = { { "TOPLEFT", other, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", other, "BOTTOMRIGHT", 0, 0 } }
	invalidate()
end

--------------------------------------------------------------------------------
-- Layout solver
--
-- Resolves absolute geometry from the anchor graph, memoised per generation so
-- a deep frame tree does not blow up. Good enough that measurement, wrapping,
-- truncation and list virtualisation all run against realistic numbers.
--------------------------------------------------------------------------------

local X_OF = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = 0.5, TOP = 0.5,
	BOTTOM = 0.5, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
local Y_OF = { BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, CENTER = 0.5, LEFT = 0.5,
	RIGHT = 0.5, TOP = 1, TOPLEFT = 1, TOPRIGHT = 1 }

local solving = {}

local function geometry(region)
	if not region then return 0, 0, 100, 30 end
	if region._geomGen == generation then
		return region._gl, region._gb, region._gw, region._gh
	end
	if solving[region] then
		return 0, 0, region._w or 100, region._h or 30
	end
	solving[region] = true

	local width, height = region._w, region._h
	local xConstraints, yConstraints = {}, {}
	local points = region._points or {}
	for i = 1, #points do
		local p = points[i]
		local ref = p[2] or region._parent
		if ref and ref ~= region then
			local rl, rb, rw, rh = geometry(ref)
			local fx, fy = X_OF[p[3]], Y_OF[p[3]]
			if fx then xConstraints[#xConstraints + 1] = { X_OF[p[1]], rl + rw * fx + p[4] } end
			if fy then yConstraints[#yConstraints + 1] = { Y_OF[p[1]], rb + rh * fy + p[5] } end
		end
	end

	local function axis(constraints, known)
		local lo, mid, hi
		for i = 1, #constraints do
			local c = constraints[i]
			if c[1] == 0 then lo = lo or c[2]
			elseif c[1] == 1 then hi = hi or c[2]
			else mid = mid or c[2] end
		end
		if lo and hi then return lo, hi - lo end
		local size = known or 100
		if lo then return lo, size end
		if hi then return hi - size, size end
		if mid then return mid - size / 2, size end
		return 0, size
	end

	local left, w = axis(xConstraints, width)
	local bottom, h = axis(yConstraints, height)
	if width then w = width end
	if height then h = height end
	if w <= 0 then w = 1 end
	if h <= 0 then h = 1 end

	solving[region] = nil
	region._geomGen, region._gl, region._gb, region._gw, region._gh =
		generation, left, bottom, w, h
	return left, bottom, w, h
end
M.Geometry = geometry

function regionMethods:ClearAllPoints() self._points = {} invalidate() end
function regionMethods:GetPoint(index)
	local p = self._points and self._points[index or 1]
	if not p then return nil end
	return p[1], p[2], p[3], p[4], p[5]
end
function regionMethods:GetNumPoints() return self._points and #self._points or 0 end

function regionMethods:SetSize(w, h) self._w, self._h = w, h invalidate() end
function regionMethods:SetWidth(w) self._w = w invalidate() end
function regionMethods:SetHeight(h) self._h = h invalidate() end
function regionMethods:GetWidth()
	return (select(3, geometry(self)))
end
function regionMethods:GetHeight()
	return (select(4, geometry(self)))
end
function regionMethods:GetSize() return self:GetWidth(), self:GetHeight() end
function regionMethods:GetLeft() return (geometry(self)) end
function regionMethods:GetRight()
	local l, _, w = geometry(self)
	return l + w
end
function regionMethods:GetTop()
	local _, b, _, h = geometry(self)
	return b + h
end
function regionMethods:GetBottom() return (select(2, geometry(self))) end
function regionMethods:GetCenter()
	local l, b, w, h = geometry(self)
	return l + w / 2, b + h / 2
end
function regionMethods:Show() self._shown = true end
function regionMethods:Hide() self._shown = false end
function regionMethods:IsShown() return self._shown ~= false end
function regionMethods:IsVisible() return self._shown ~= false end
function regionMethods:SetShown(v) self._shown = v and true or false end
function regionMethods:SetAlpha(a) self._alpha = a end
function regionMethods:GetAlpha() return self._alpha or 1 end
function regionMethods:SetParent(p) self._parent = p invalidate() end
function regionMethods:GetParent() return self._parent end
function regionMethods:SetDrawLayer() end
function regionMethods:GetObjectType() return self._kind end
function regionMethods:SetIgnoreParentAlpha() end
function regionMethods:SetIgnoreParentScale() end

--------------------------------------------------------------------------------
-- Texture
--------------------------------------------------------------------------------

local textureMethods = {}
for k, v in pairs(regionMethods) do textureMethods[k] = v end
function textureMethods:SetTexture(path) self._texture = path end
function textureMethods:GetTexture() return self._texture end
function textureMethods:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function textureMethods:SetTexCoord() end
function textureMethods:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function textureMethods:GetVertexColor()
	local v = self._vertex or { 1, 1, 1, 1 }
	return v[1], v[2], v[3], v[4]
end
function textureMethods:SetRotation() end
function textureMethods:SetDesaturated() end
function textureMethods:SetBlendMode() end
function textureMethods:SetVertexOffset() end
function textureMethods:SetMask() end
function textureMethods:AddMaskTexture() end
function textureMethods:RemoveMaskTexture() end
function textureMethods:SetGradient(orientation, a, b)
	assert(type(orientation) == "string", "SetGradient orientation must be a string")
	assert(type(a) == "table" and type(b) == "table", "SetGradient needs colour objects")
end
function textureMethods:SetHorizTile() end
function textureMethods:SetVertTile() end

function textureMethods:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	assert(type(orientation) == "string", "SetGradientAlpha orientation must be a string")
	assert(type(a2) == "number", "SetGradientAlpha needs eight colour components")
end

local texProto, texMT = makeObject("Texture", textureMethods)

local function newTexture(parent, layer)
	local t = setmetatable({ _kind = "Texture", _parent = parent, _layer = layer }, texMT)
	return t
end

--------------------------------------------------------------------------------
-- FontString
--------------------------------------------------------------------------------

local fsMethods = {}
for k, v in pairs(textureMethods) do fsMethods[k] = v end

local function visibleLength(text)
	if not text then return 0 end
	-- strip escape sequences so measurement roughly matches what is drawn
	local stripped = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "XX"):gsub("|A.-|a", "XX")
	return #stripped
end

function fsMethods:SetText(text) self._text = text and tostring(text) or "" end
function fsMethods:GetText() return self._text or "" end
function fsMethods:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function fsMethods:SetFontObject(fo) self._font = fo end
function fsMethods:SetFont(path, size, flags)
	self._fontPath, self._fontSize = path, size
	return true
end
function fsMethods:GetFont()
	if self._fontPath then return self._fontPath, self._fontSize or 12, "" end
	if self._font and self._font.GetFont then return self._font:GetFont() end
	return "Fonts\\FRIZQT__.TTF", 12, ""
end
function fsMethods:GetStringWidth()
	local size = select(2, self:GetFont()) or 12
	return visibleLength(self._text) * size * 0.52
end
function fsMethods:GetStringHeight()
	local size = select(2, self:GetFont()) or 12
	local width = self._w
	if not width or width <= 0 then return size + 2 end
	local natural = self:GetStringWidth()
	local lines = math.max(1, math.ceil(natural / width))
	return lines * (size + (self._spacing or 0)) + 2
end
function fsMethods:SetJustifyH() end
function fsMethods:SetJustifyV() end
function fsMethods:SetWordWrap() end
function fsMethods:SetNonSpaceWrap() end
function fsMethods:SetSpacing(v) self._spacing = v end
function fsMethods:SetTextColor() end
function fsMethods:GetTextColor() return 1, 1, 1, 1 end
function fsMethods:SetMaxLines() end
function fsMethods:SetShadowOffset() end
function fsMethods:SetShadowColor() end

local fsProto, fsMT = makeObject("FontString", fsMethods)

local function newFontString(parent, layer)
	return setmetatable({ _kind = "FontString", _parent = parent, _layer = layer }, fsMT)
end

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

local animMethods = {}
function animMethods:SetOrder() end
function animMethods:SetDuration(d) self._duration = d end
function animMethods:SetSmoothing() end
function animMethods:SetStartDelay() end
function animMethods:SetFromAlpha() end
function animMethods:SetToAlpha() end
function animMethods:SetChange() end
function animMethods:SetScaleFrom() end
function animMethods:SetScaleTo() end
function animMethods:SetScale() end
function animMethods:SetOffset() end
function animMethods:SetTarget() end
local animProto, animMT = makeObject("Animation", animMethods)

local agMethods = {}
function agMethods:CreateAnimation(kind)
	local a = setmetatable({ _kind = "Animation", _type = kind }, animMT)
	self._animations = self._animations or {}
	self._animations[#self._animations + 1] = a
	return a
end
function agMethods:Play()
	self._playing = true
	-- Fire OnFinished immediately so callbacks that depend on it are exercised.
	local script = self._scripts and self._scripts.OnFinished
	self._playing = false
	if script then script(self) end
end
function agMethods:Stop() self._playing = false end
function agMethods:Finish() self._playing = false end
function agMethods:IsPlaying() return self._playing or false end
function agMethods:SetLooping() end
function agMethods:SetScript(name, fn)
	self._scripts = self._scripts or {}
	self._scripts[name] = fn
end
function agMethods:GetScript(name) return self._scripts and self._scripts[name] end
function agMethods:HookScript(name, fn)
	local existing = self._scripts and self._scripts[name]
	self:SetScript(name, function(...)
		if existing then existing(...) end
		fn(...)
	end)
end
local agProto, agMT = makeObject("AnimationGroup", agMethods)

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local frameMethods = {}
for k, v in pairs(regionMethods) do frameMethods[k] = v end

function frameMethods:CreateTexture(name, layer) return newTexture(self, layer) end
function frameMethods:CreateFontString(name, layer) return newFontString(self, layer) end
function frameMethods:CreateMaskTexture(name, layer) return newTexture(self, layer) end
function frameMethods:CreateAnimationGroup()
	return setmetatable({ _kind = "AnimationGroup", _parent = self }, agMT)
end

-- Script handlers are frame-type specific. Setting OnDoubleClick on a plain
-- Frame, for instance, silently does nothing in the real client, so the mock
-- refuses it instead of letting a dead feature pass the suite.
local FRAME_SCRIPTS = {}
for _, name in ipairs({
	"OnLoad", "OnUpdate", "OnEvent", "OnShow", "OnHide", "OnEnter", "OnLeave",
	"OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnDragStart", "OnDragStop",
	"OnSizeChanged", "OnAttributeChanged", "OnKeyDown", "OnKeyUp", "OnChar",
	"OnHyperlinkClick", "OnHyperlinkEnter", "OnHyperlinkLeave", "OnReceiveDrag",
}) do FRAME_SCRIPTS[name] = true end

local TYPE_SCRIPTS = {
	Button = { OnClick = true, OnDoubleClick = true },
	CheckButton = { OnClick = true, OnDoubleClick = true },
	EditBox = {
		OnEnterPressed = true, OnEscapePressed = true, OnTextChanged = true,
		OnTextSet = true, OnCursorChanged = true, OnEditFocusGained = true,
		OnEditFocusLost = true, OnSpacePressed = true, OnTabPressed = true,
		OnInputLanguageChanged = true,
	},
	ScrollFrame = {
		OnScrollRangeChanged = true, OnHorizontalScroll = true, OnVerticalScroll = true,
	},
	Slider = { OnValueChanged = true, OnMinMaxChanged = true },
	StatusBar = { OnValueChanged = true, OnMinMaxChanged = true },
}

local function assertScript(frame, name)
	if FRAME_SCRIPTS[name] then return end
	local extra = TYPE_SCRIPTS[frame._kind]
	if extra and extra[name] then return end
	error(("%s has no %s script (frame type %s)")
		:format(frame._name or "<anonymous>", name, tostring(frame._kind)), 3)
end

function frameMethods:SetScript(name, fn)
	assertScript(self, name)
	self._scripts = self._scripts or {}
	self._scripts[name] = fn
end
function frameMethods:GetScript(name) return self._scripts and self._scripts[name] end
function frameMethods:HookScript(name, fn)
	assertScript(self, name)
	local existing = self._scripts and self._scripts[name]
	self:SetScript(name, function(...)
		if existing then existing(...) end
		return fn(...)
	end)
end
function frameMethods:Fire(name, ...)
	local script = self._scripts and self._scripts[name]
	if script then return script(self, ...) end
end

function frameMethods:RegisterEvent(event)
	assert(type(event) == "string" and event:match("^[%u_%d]+$"), "bad event: " .. tostring(event))
	assert(M.knownEvents[event], "unknown event: " .. event)
	M.eventFrames[event] = M.eventFrames[event] or {}
	M.eventFrames[event][self] = true
	self._events = self._events or {}
	self._events[event] = true
end
function frameMethods:UnregisterEvent(event)
	if M.eventFrames[event] then M.eventFrames[event][self] = nil end
	if self._events then self._events[event] = nil end
end
function frameMethods:UnregisterAllEvents()
	if not self._events then return end
	for event in pairs(self._events) do
		if M.eventFrames[event] then M.eventFrames[event][self] = nil end
	end
	self._events = {}
end
function frameMethods:IsEventRegistered(event)
	return self._events and self._events[event] or false
end

function frameMethods:EnableMouse() end
function frameMethods:EnableMouseWheel() end
function frameMethods:EnableKeyboard() end
function frameMethods:IsMouseOver() return self._mouseOver or false end
function frameMethods:SetHitRectInsets() end
function frameMethods:SetFrameStrata(s) self._strata = s end
function frameMethods:GetFrameStrata() return self._strata or "MEDIUM" end
function frameMethods:SetFrameLevel(l) self._level = l end
function frameMethods:GetFrameLevel() return self._level or 1 end
function frameMethods:SetToplevel() end
function frameMethods:SetMovable() end
function frameMethods:SetResizable() end
function frameMethods:SetClampedToScreen() end
function frameMethods:StartMoving() end
function frameMethods:StopMovingOrSizing() end
function frameMethods:StartSizing() end
function frameMethods:SetResizeBounds(minW, minH)
	assert(type(minW) == "number" and type(minH) == "number", "SetResizeBounds needs numbers")
end
function frameMethods:SetMinResize() end
function frameMethods:SetMaxResize() end
function frameMethods:SetClipsChildren() end
function frameMethods:SetHyperlinksEnabled() end
function frameMethods:Raise() end
function frameMethods:Lower() end
function frameMethods:SetScale(s) self._scale = s end
function frameMethods:GetScale() return self._scale or 1 end
function frameMethods:GetEffectiveScale() return (self._scale or 1) * 1 end
function frameMethods:GetName() return self._name end
function frameMethods:SetID(id) self._id = id end
function frameMethods:GetID() return self._id or 0 end
function frameMethods:SetAttribute(k, v)
	assert(not M.inCombat, "SetAttribute called in combat")
	self._attributes = self._attributes or {}
	self._attributes[k] = v
end
function frameMethods:GetAttribute(k) return self._attributes and self._attributes[k] end
function frameMethods:RegisterForClicks() end
function frameMethods:RegisterForDrag() end
function frameMethods:SetPropagateKeyboardInput() end

-- ScrollFrame
function frameMethods:SetScrollChild(child) self._scrollChild = child end
function frameMethods:GetScrollChild() return self._scrollChild end
function frameMethods:SetVerticalScroll(v) self._vscroll = v end
function frameMethods:GetVerticalScroll() return self._vscroll or 0 end
function frameMethods:GetVerticalScrollRange() return 0 end
function frameMethods:UpdateScrollChildRect() end

-- EditBox
function frameMethods:SetMultiLine(v) self._multiline = v end
function frameMethods:IsMultiLine() return self._multiline or false end
function frameMethods:SetAutoFocus() end
function frameMethods:SetFontObject(fo) self._font = fo end
function frameMethods:SetTextInsets() end
function frameMethods:SetMaxLetters() end
function frameMethods:SetCountInvisibleLetters() end
function frameMethods:SetTextColor() end
function frameMethods:SetSpacing() end
function frameMethods:SetText(v)
	self._text = v or ""
	local script = self._scripts and self._scripts.OnTextChanged
	if script then script(self, false) end
end
function frameMethods:GetText() return self._text or "" end
function frameMethods:SetCursorPosition(p) self._cursor = p end
function frameMethods:GetCursorPosition() return self._cursor or 0 end
function frameMethods:HighlightText() end
function frameMethods:SetFocus() self._focus = true end
function frameMethods:ClearFocus() self._focus = false end
function frameMethods:HasFocus() return self._focus or false end
function frameMethods:Insert(v) self:SetText((self._text or "") .. (v or "")) end
function frameMethods:GetNumLetters() return #(self._text or "") end

-- Button
function frameMethods:Disable() end
function frameMethods:Enable() end
function frameMethods:SetNormalTexture() end
function frameMethods:SetHighlightTexture() end
function frameMethods:SetPushedTexture() end

local frameProto, frameMT = makeObject("Frame", frameMethods)

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

M.knownEvents = {}
for _, e in ipairs({
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_AFK", "CHAT_MSG_DND", "CHAT_MSG_SYSTEM",
	"GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "WHO_LIST_UPDATE",
	"BN_FRIEND_INFO_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
}) do M.knownEvents[e] = true end

M.protos = { Frame = frameProto, Texture = texProto, FontString = fsProto }
M.blocked = {}

-- Removes an API from the mock so capability probes see a client that does not
-- have it. Used to simulate Classic Era / TBC.
function M.Disable(kind, name)
	local proto = M.protos[kind]
	if proto then rawset(proto, name, nil) end
	M.blocked[kind .. ":" .. name] = true
end

function _G.CreateFrame(kind, name, parent, template)
	local f = setmetatable({
		_kind = kind or "Frame", _name = name, _parent = parent, _template = template,
		_shown = true,
	}, frameMT)
	M.frames[#M.frames + 1] = f
	if name then _G[name] = f end
	return f
end

function M.FireEvent(event, ...)
	local list = M.eventFrames[event]
	if not list then return 0 end
	local count = 0
	for frame in pairs(list) do
		local script = frame._scripts and frame._scripts.OnEvent
		if script then
			count = count + 1
			local ok, err = pcall(script, frame, event, ...)
			if not ok then
				M.errors[#M.errors + 1] = event .. ": " .. tostring(err)
			end
		end
	end
	return count
end

function M.RunTimers(rounds)
	for _ = 1, rounds or 4 do
		local queue = M.timers
		M.timers = {}
		for i = 1, #queue do
			local ok, err = pcall(queue[i])
			if not ok then M.errors[#M.errors + 1] = "timer: " .. tostring(err) end
		end
	end
end

_G.UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
UIParent._left, UIParent._bottom = 0, 0
UIParent._points = {}
_G.Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
_G.DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1", UIParent)
DEFAULT_CHAT_FRAME.AddMessage = function(_, text) M.chat = M.chat or {} M.chat[#M.chat + 1] = text end
_G.GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
GameTooltip.SetOwner = function() end
GameTooltip.SetHyperlink = function() return true end
_G.ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
ColorPickerFrame.GetColorRGB = function() return 1, 1, 1 end
ColorPickerFrame.SetColorRGB = function() end
_G.UISpecialFrames = {}

local function makeFontObject(name, size)
	local fo = {
		_size = size,
		SetFont = function(self, path, s) self._path, self._size = path, s return true end,
		GetFont = function(self) return self._path or "Fonts\\FRIZQT__.TTF", self._size or 12, "" end,
		SetShadowOffset = function() end,
		SetShadowColor = function() end,
		SetJustifyH = function() end,
		SetJustifyV = function() end,
		SetTextColor = function() end,
	}
	_G[name] = fo
	return fo
end
makeFontObject("ChatFontNormal", 14)
makeFontObject("GameFontNormal", 12)
makeFontObject("GameFontNormalLarge", 16)
makeFontObject("GameFontHighlightSmall", 11)
makeFontObject("SystemFont_Shadow_Med1", 12)
makeFontObject("NumberFontNormal", 12)

_G.CreateFont = function(name)
	if _G[name] then return _G[name] end
	return makeFontObject(name, 12)
end

_G.WOW_PROJECT_ID = 1
_G.WOW_PROJECT_MAINLINE = 1
_G.WOW_PROJECT_CLASSIC = 2
_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
_G.WOW_PROJECT_MISTS_CLASSIC = 19

M.build = { "12.1.0", "60000", "Sep 06 2026", 120100 }
_G.GetBuildInfo = function() return unpack(M.build) end
_G.GetLocale = function() return M.locale or "enUS" end
_G.GetRealmName = function() return "Blackrock" end
_G.GetNormalizedRealmName = function() return "Blackrock" end
_G.GetTime = function() return M.now end
_G.GetServerTime = function() return 1788000000 end
_G.GetScreenHeight = function() return 1080 end
_G.GetScreenWidth = function() return 1920 end
_G.GetPhysicalScreenSize = function() return 1920, 1080 end
_G.GetCursorPosition = function() return 500, 500 end
_G.IsShiftKeyDown = function() return M.shift or false end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.InCombatLockdown = function() return M.inCombat or false end
_G.IsInInstance = function() return false, "none" end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return false end
_G.GetNumGroupMembers = function() return 0 end
_G.UnitExists = function(unit) return M.units and M.units[unit] ~= nil end
_G.UnitIsPlayer = function() return true end
_G.UnitName = function(unit)
	local u = M.units and M.units[unit]
	if unit == "player" then return "Testchar", "" end
	if not u then return nil end
	return u.name, u.realm or ""
end
_G.UnitClass = function(unit)
	local u = M.units and M.units[unit]
	if unit == "player" then return "Mage", "MAGE" end
	if not u then return nil end
	return u.class, u.class
end
_G.UnitLevel = function(unit)
	local u = M.units and M.units[unit]
	return u and u.level or 70
end
_G.GetPlayerInfoByGUID = function(guid)
	local info = M.guids and M.guids[guid]
	if not info then return nil end
	return info.class, info.class, info.race, info.race, 2, info.name, info.realm
end
_G.Ambiguate = function(name) return name end
_G.SendChatMessage = function(text, kind, lang, target)
	M.sent = M.sent or {}
	M.sent[#M.sent + 1] = { text = text, kind = kind, target = target }
	assert(#text <= 255, "whisper longer than 255 bytes: " .. #text)
end
_G.ChatFrame_AddMessageEventFilter = function() end
_G.ChatFrame_RemoveMessageEventFilter = function() end
_G.PlaySound = function() return true end
_G.PlaySoundFile = function() return true end
_G.FlashClientIcon = function() end
_G.SetItemRef = function() end
_G.geterrorhandler = function() return function(msg) M.errors[#M.errors + 1] = tostring(msg) end end
_G.hooksecurefunc = function() end
_G.SetPortraitTexture = function() end
_G.InterfaceOptions_AddCategory = function() end
_G.InterfaceOptionsFrame_OpenToCategory = function() end

_G.C_Timer = {
	After = function(delay, fn) M.timers[#M.timers + 1] = fn end,
	NewTimer = function(delay, fn) M.timers[#M.timers + 1] = fn return { Cancel = function() end } end,
	NewTicker = function() return { Cancel = function() end } end,
}
_G.C_FriendList = {
	GetNumFriends = function() return 0 end,
	GetFriendInfoByIndex = function() return nil end,
	AddFriend = function() end,
	AddOrDelIgnore = function() end,
	IsIgnored = function() return false end,
	SendWho = function() end,
	GetNumWhoResults = function() return 0 end,
	GetWhoInfo = function() return nil end,
}
_G.C_PartyInfo = { InviteUnit = function() end }
_G.C_BattleNet = {
	GetFriendAccountInfo = function() return nil end,
	GetAccountInfoByID = function(id)
		local info = M.bnet and M.bnet[id]
		if not info then return nil end
		return { battleTag = info.tag, accountName = info.name,
			gameAccountInfo = { isOnline = true, characterName = info.character } }
	end,
}
_G.BNGetNumFriends = function() return 0 end
_G.BNSendWhisper = function(id, text)
	M.sentBN = M.sentBN or {}
	M.sentBN[#M.sentBN + 1] = { id = id, text = text }
end
_G.C_GuildInfo = { GuildRoster = function() end }
_G.GetNumGuildMembers = function() return 0 end
_G.GetGuildRosterInfo = function() return nil end
_G.C_ClassColor = nil
_G.C_CreatureInfo = nil

_G.RAID_CLASS_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.41, g = 0.80, b = 0.94 },
	ROGUE = { r = 1.00, g = 0.96, b = 0.41 }, DRUID = { r = 1.00, g = 0.49, b = 0.04 },
	HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
	PRIEST = { r = 1.00, g = 1.00, b = 1.00 }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
	MONK = { r = 0.00, g = 1.00, b = 0.59 }, DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
	EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
}
_G.CLASS_ICON_TCOORDS = {}
for cls in pairs(RAID_CLASS_COLORS) do CLASS_ICON_TCOORDS[cls] = { 0, 0.25, 0, 0.25 } end
_G.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", SHAMAN = "Shaman", ROGUE = "Rogue" }
_G.SOUNDKIT = { TELL_MESSAGE = 3081, RAID_WARNING = 8959, READY_CHECK = 8960 }
_G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
_G.LEVEL = "Level"
_G.WEEKDAY_SUNDAY, _G.WEEKDAY_MONDAY, _G.WEEKDAY_TUESDAY = "Sunday", "Monday", "Tuesday"
_G.WEEKDAY_WEDNESDAY, _G.WEEKDAY_THURSDAY = "Wednesday", "Thursday"
_G.WEEKDAY_FRIDAY, _G.WEEKDAY_SATURDAY = "Friday", "Saturday"
_G.ICON_LIST = {}
_G.MAX_CHAT_MSG_LENGTH = 255

-- WoW's Lua allows xpcall(f, handler, ...); stock 5.1 does not. Ace3 relies on it.
local rawxpcall = xpcall
_G.xpcall = function(f, handler, ...)
	local n = select("#", ...)
	if n == 0 then return rawxpcall(f, handler) end
	local args = { ... }
	return rawxpcall(function() return f(unpack(args, 1, n)) end, handler)
end
_G.IsLoggedIn = function() return M.loggedIn or false end
-- WoW exposes these as globals, not through the os table.
_G.time = os.time
_G.date = os.date

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert, _G.tremove = table.insert, table.remove
_G.strsplit = function(sep, str)
	local out = {}
	for part in string.gmatch(str, "([^" .. sep .. "]+)") do out[#out + 1] = part end
	return unpack(out)
end
_G.strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
_G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
_G.format = string.format
_G.strmatch, _G.strfind, _G.strsub = string.match, string.find, string.sub
_G.gsub, _G.strlower, _G.strupper = string.gsub, string.lower, string.upper
_G.max, _G.min, _G.abs, _G.floor, _G.ceil = math.max, math.min, math.abs, math.floor, math.ceil
_G.debugstack = function() return "" end
_G.debugprofilestop = function() return 0 end
_G.securecall = function(fn, ...) return fn(...) end
_G.securecallfunction = function(fn, ...) return fn(...) end
_G.issecurevariable = function() return true end
_G.forceinsecure = function() end
_G.GetFramerate = function() return 60 end
_G.GetAddOnMetadata = function() return nil end
_G.C_AddOns = { GetAddOnMetadata = function() return nil end }

return M
