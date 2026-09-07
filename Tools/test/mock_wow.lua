-- Minimal but strict World of Warcraft API mock, used to actually load and run
-- WhatTheWhisper outside the game. Unknown methods are recorded rather than
-- silently accepted, so a typo in an API name shows up in the report.

local M = {}
_G.WOWMOCK = M

M.unknownMethods = {}
M.frames = {}
M.regions = {}
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

-- Which widget types own which methods.
--
-- A real Frame has no SetText; a real Texture has no SetFontObject; calling
-- either raises in the client. The mock has to raise too, or the harness
-- happily proves code that cannot run in the game. WIDGET_OWNER maps a method
-- to the types that actually have it, so a misuse names the right mistake
-- instead of just failing.
local WIDGET_OWNER = {}
local function own(kinds, names)
	for name in names:gmatch("%S+") do
		WIDGET_OWNER[name] = WIDGET_OWNER[name] or {}
		for kind in kinds:gmatch("%S+") do WIDGET_OWNER[name][kind] = true end
	end
end

-- Text-bearing widgets. A plain Frame has none of these.
own("Button EditBox FontString", "SetText GetText SetTextColor GetTextColor SetFontObject GetFontObject SetFont GetFont")
own("EditBox", [[
	SetMultiLine IsMultiLine SetAutoFocus SetFocus ClearFocus HasFocus
	SetMaxLetters GetNumLetters SetCursorPosition GetCursorPosition
	HighlightText Insert SetTextInsets SetCountInvisibleLetters
	SetNumeric IsNumeric SetPassword GetInputLanguage
	SetAltArrowKeyMode SetBlinkSpeed ToggleInputLanguage AddHistoryLine]])
-- Line spacing and justification belong to anything that lays out text, which
-- is both of them -- a FontString:SetSpacing is entirely real.
own("EditBox FontString", "SetSpacing SetJustifyH SetJustifyV")
own("FontString", [[
	SetWordWrap SetNonSpaceWrap SetMaxLines GetStringWidth GetStringHeight
	SetShadowOffset SetShadowColor CanWordWrap GetFieldSize SetIndentedWordWrap]])
own("Button CheckButton", [[
	SetNormalTexture SetPushedTexture SetHighlightTexture SetDisabledTexture
	GetNormalTexture GetPushedTexture GetHighlightTexture
	RegisterForClicks SetButtonState GetButtonState Click SetFormattedText]])
own("CheckButton", "SetChecked GetChecked SetCheckedTexture GetCheckedTexture")
own("ScrollFrame", [[
	SetScrollChild GetScrollChild SetVerticalScroll GetVerticalScroll
	GetVerticalScrollRange SetHorizontalScroll GetHorizontalScroll
	GetHorizontalScrollRange UpdateScrollChildRect]])
own("Slider", [[
	SetMinMaxValues GetMinMaxValues SetValue GetValue SetValueStep GetValueStep
	SetOrientation SetThumbTexture GetThumbTexture SetObeyStepOnDrag]])
own("StatusBar", [[
	SetStatusBarTexture GetStatusBarTexture SetStatusBarColor
	SetMinMaxValues GetMinMaxValues SetValue GetValue SetFillStyle SetRotatesTexture]])
own("Button CheckButton EditBox Slider StatusBar", "Enable Disable IsEnabled SetEnabled")

-- Frame-only, which is the distinction that matters most in practice: a texture
-- is scaled by an animation, not by SetScale, and code that resets a scale on
-- whatever it was handed has to check first.
local FRAME_KINDS = "Frame Button CheckButton EditBox ScrollFrame Slider StatusBar GameTooltip"
own(FRAME_KINDS, [[
	SetScale GetScale GetEffectiveScale SetFrameStrata GetFrameStrata
	SetFrameLevel GetFrameLevel SetClampedToScreen SetMovable SetResizable
	StartMoving StopMovingOrSizing StartSizing SetToplevel Raise Lower
	RegisterEvent UnregisterEvent UnregisterAllEvents IsEventRegistered
	EnableMouse IsMouseEnabled EnableMouseWheel EnableKeyboard
	SetHitRectInsets GetHitRectInsets SetID GetID SetAttribute GetAttribute
	CreateTexture CreateFontString SetClipsChildren SetHyperlinksEnabled
	SetPropagateKeyboardInput RegisterForDrag SetMinResize SetMaxResize
	SetResizeBounds IsMouseOver GetCursorPosition]])

-- Real widget API that this mock has simply not modelled. Reaching one of these
-- is fine -- it returns nil like an unmodelled getter -- but it is recorded, so
-- the list of what the harness pretends about stays visible instead of the mock
-- silently answering every call.
local UNMODELLED = {}
for name in ([[
	SetBackdrop SetBackdropColor SetBackdropBorderColor GetBackdrop
	SetUserPlaced IsUserPlaced SetDontSavePosition RegisterForMouseWheel
	SetFrameRef GetFrameRef Execute WrapScript UnwrapScript
	SetPassThroughButtons SetMouseClickEnabled SetMouseMotionEnabled
	SetFlattensRenderLayers SetIsFrameBuffer GetChildren GetRegions
	GetNumChildren GetNumRegions GetBoundsRect GetRect
	IsForbidden IsProtected CanChangeProtectedState
	SetResizeBounds GetResizeBounds SetFixedFrameStrata SetFixedFrameLevel
	RegisterUnitEvent RegisterAllEvents GetDebugName IsObjectType GetObjectType
	SetShown IsShown IsVisible SetAlpha GetAlpha SetParent GetParent
]]):gmatch("%S+") do UNMODELLED[name] = true end

local function makeObject(kind, methods)
	local proto = {}
	for name, fn in pairs(methods) do proto[name] = fn end
	local mt = {
		__index = function(t, key)
			if M.blocked and M.blocked[kind .. ":" .. key] then return nil end
			if type(key) ~= "string" or not key:match("^%u") then return nil end

			-- Checked before the method table, not after: the mock defines the
			-- EditBox and Button methods on one shared table for convenience, so
			-- looking them up first would hand a plain Frame a SetText that the
			-- client would have refused.
			--
			-- The answer is nil rather than an error, because that is what the
			-- client does: texture.SetScale simply is not there, so reading it
			-- yields nil and `type(x.SetScale) == "function"` is a legitimate
			-- capability check that addons really use. Calling it still fails,
			-- loudly and with the right message, the moment anyone tries.
			local owners = WIDGET_OWNER[key]
			local actual = t._kind or kind
			if owners and not owners[actual] then return nil end

			local value = rawget(proto, key)
			if value ~= nil then return value end

			if not UNMODELLED[key] then
				error(("%s: %s is not a widget method the client provides "
					.. "(frame type %s). If it is real, add it to the mock."):format(
					tostring(t._name or "<anonymous>"), key,
					tostring(t._kind or kind)), 3)
			end

			record(kind, key)
			local stub = function() return nil end
			rawset(t, key, stub)
			return stub
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

-- Forward declared: Region:CreateAnimationGroup is defined before the
-- AnimationGroup metatable exists, and closes over it.
local agMT

local regionMethods = {}

-- Anchor bookkeeping. Sizes are derived from opposing anchors the way the real
-- layout engine does, so measurement code runs against realistic numbers
-- instead of a constant.
local LEFT_EDGE = { LEFT = true, TOPLEFT = true, BOTTOMLEFT = true }
local RIGHT_EDGE = { RIGHT = true, TOPRIGHT = true, BOTTOMRIGHT = true }
local TOP_EDGE = { TOP = true, TOPLEFT = true, TOPRIGHT = true }
local BOTTOM_EDGE = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local ANCHOR_POINTS = {}
for name in ([[TOPLEFT TOP TOPRIGHT LEFT CENTER RIGHT
	BOTTOMLEFT BOTTOM BOTTOMRIGHT]]):gmatch("%S+") do ANCHOR_POINTS[name] = true end

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
	assert(ANCHOR_POINTS[point], "invalid anchor point: " .. tostring(point))
	assert(ANCHOR_POINTS[relPoint], "invalid relative anchor point: " .. tostring(relPoint))
	assert(relTo ~= self, "a region cannot be anchored to itself")
	assert(type(x) == "number" and type(y) == "number",
		"anchor offsets must be numbers, got " .. type(x) .. "/" .. type(y))
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

	-- A font string with no explicit size is as big as its text, the way the
	-- client sizes it. Without this every unsized label would measure 100x100 and
	-- an audit could not tell a label that fits from one that runs off the panel.
	local naturalW, naturalH
	if region._kind == "FontString" then
		naturalW = region.GetStringWidth and region:GetStringWidth() or nil
	end

	local left, w = axis(xConstraints, width or naturalW)
	if region._kind == "FontString" and not height then
		local size = select(2, region:GetFont()) or 12
		if region._wordWrap == false then
			naturalH = size + 2
		else
			local lines = math.max(1, math.ceil((naturalW or 0) / math.max(w, 1)))
			naturalH = lines * (size + (region._spacing or 0)) + 2
		end
	end
	local bottom, h = axis(yConstraints, height or naturalH)
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
-- Effective visibility: a frame is on screen only if it and every ancestor is
-- shown. The client fires OnShow and OnHide on that, not on the frame's own
-- flag, which is why hiding a window also fires OnHide on everything under it.
local function effectivelyVisible(region)
	local node, hops = region, 0
	while node and hops < 64 do
		if node._shown == false then return false end
		node = node._parent
		hops = hops + 1
	end
	return true
end
M.EffectivelyVisible = effectivelyVisible

-- Only the changed frame's own subtree can flip, so the walk is over children
-- rather than over every frame in the session. M.children is maintained by
-- CreateFrame and SetParent.
M.children = setmetatable({}, { __mode = "k" })

local function fireVisibility(frame, becameVisible)
	local script = frame._scripts and frame._scripts[becameVisible and "OnShow" or "OnHide"]
	if script then
		local ok, err = pcall(script, frame)
		if not ok then
			M.errors[#M.errors + 1] =
				(becameVisible and "OnShow: " or "OnHide: ") .. tostring(err)
		end
	end
	local kids = M.children[frame]
	if not kids then return end
	for i = 1, #kids do
		local kid = kids[i]
		-- A child that is hidden in its own right does not change state when an
		-- ancestor does; nothing below it does either.
		if kid._shown ~= false then fireVisibility(kid, becameVisible) end
	end
end

-- Without this the mock could not test anything that reacts to a window opening
-- or closing -- which is how a drop shadow anchored from outside its window
-- shipped without ever being hidden with it.
local function setShown(region, shown)
	shown = shown and true or false
	if region._shown == shown then return end
	local wasVisible = effectivelyVisible(region)
	region._shown = shown
	local isVisible = effectivelyVisible(region)
	if wasVisible ~= isVisible then fireVisibility(region, isVisible) end
	-- An edit box that goes off screen loses keyboard focus, the same way the
	-- client drops it when the frame holding it is hidden.
	if M.focus and not effectivelyVisible(M.focus) then
		M.focus._focus = false
		M.focus = nil
	end
end

function regionMethods:Show() setShown(self, true) end
function regionMethods:Hide() setShown(self, false) end
function regionMethods:IsShown() return self._shown ~= false end
function regionMethods:IsVisible() return self._shown ~= false end
function regionMethods:SetShown(v) setShown(self, v) end
function regionMethods:SetAlpha(a) self._alpha = a end
function regionMethods:GetAlpha() return self._alpha or 1 end
function regionMethods:SetParent(p)
	local old = self._parent
	if old and M.children[old] then
		local kids = M.children[old]
		for i = #kids, 1, -1 do
			if kids[i] == self then table.remove(kids, i) end
		end
	end
	self._parent = p
	if p then
		local kids = M.children[p]
		if not kids then kids = {} M.children[p] = kids end
		kids[#kids + 1] = self
	end
	invalidate()
end
function regionMethods:GetParent() return self._parent end
local DRAW_LAYERS = {}
for name in ("BACKGROUND BORDER ARTWORK OVERLAY HIGHLIGHT"):gmatch("%S+") do
	DRAW_LAYERS[name] = true
end
function regionMethods:SetDrawLayer(layer, sub)
	assert(DRAW_LAYERS[layer], "invalid draw layer: " .. tostring(layer))
	assert(sub == nil or (type(sub) == "number" and sub >= -8 and sub <= 7),
		"draw sub-level must be -8..7, got " .. tostring(sub))
	self._layer = layer
end
function regionMethods:GetObjectType() return self._kind end
function regionMethods:SetIgnoreParentAlpha() end
function regionMethods:SetIgnoreParentScale() end

--------------------------------------------------------------------------------
-- Texture
--------------------------------------------------------------------------------

local textureMethods = {}
-- Animation groups belong to Region, so a texture or a font string can have
-- one too; plenty of addons animate a texture directly.
function regionMethods:CreateAnimationGroup()
	return setmetatable({ _kind = "AnimationGroup", _parent = self }, agMT)
end

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
	M.regions[#M.regions + 1] = t
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
function fsMethods:SetJustifyH(v) self._justifyH = v end
function fsMethods:SetJustifyV(v) self._justifyV = v end
function fsMethods:SetWordWrap(v) self._wordWrap = (v ~= false) end
function fsMethods:SetNonSpaceWrap() end
function fsMethods:SetSpacing(v) self._spacing = v end
function fsMethods:SetTextColor() end
function fsMethods:GetTextColor() return 1, 1, 1, 1 end
function fsMethods:SetMaxLines() end
function fsMethods:SetShadowOffset() end
function fsMethods:SetShadowColor() end

local fsProto, fsMT = makeObject("FontString", fsMethods)

local function newFontString(parent, layer)
	local fs = setmetatable({ _kind = "FontString", _parent = parent, _layer = layer }, fsMT)
	M.regions[#M.regions + 1] = fs
	return fs
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
local ANIMATION_TYPES = {}
for name in ("Alpha Scale Translation Rotation Path LineScale LineTranslation FlipBook"):gmatch("%S+") do
	ANIMATION_TYPES[name] = true
end
function agMethods:CreateAnimation(kind)
	assert(ANIMATION_TYPES[kind], "invalid animation type: " .. tostring(kind))
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
local agProto
agProto, agMT = makeObject("AnimationGroup", agMethods)

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

function frameMethods:EnableMouse(v) self._mouseEnabled = (v ~= false) end
function frameMethods:IsMouseEnabled() return self._mouseEnabled or false end
function frameMethods:EnableMouseWheel() end
function frameMethods:EnableKeyboard() end
function frameMethods:IsMouseOver() return self._mouseOver or false end
function frameMethods:SetHitRectInsets(l, r, t, b)
	self._hitLeft, self._hitRight, self._hitTop, self._hitBottom = l, r, t, b
end
function frameMethods:GetHitRectInsets()
	return self._hitLeft or 0, self._hitRight or 0, self._hitTop or 0, self._hitBottom or 0
end
-- The client accepts these eight strata names and raises on anything else, so
-- a typo like "DIALOGUE" has to fail here rather than at a player's login.
local STRATA = {}
for name in ([[BACKGROUND LOW MEDIUM HIGH DIALOG FULLSCREEN FULLSCREEN_DIALOG
	TOOLTIP]]):gmatch("%S+") do STRATA[name] = true end

function frameMethods:SetFrameStrata(s)
	assert(STRATA[s], "invalid frame strata: " .. tostring(s))
	self._strata = s
end
function frameMethods:GetFrameStrata() return self._strata or "MEDIUM" end
function frameMethods:SetFrameLevel(level)
	assert(type(level) == "number" and level >= 0 and level % 1 == 0,
		"frame level must be a non-negative integer, got " .. tostring(level))
	self._level = level
end
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
function frameMethods:SetHyperlinksEnabled(enabled)
	self._hyperlinksEnabled = (enabled ~= false)
end
function frameMethods:GetHyperlinksEnabled() return self._hyperlinksEnabled or false end
function frameMethods:Raise() end
function frameMethods:Lower() end
function frameMethods:SetScale(s) self._scale = s end
function frameMethods:GetScale() return self._scale or 1 end
-- Effective scale is the product up the parent chain, the way the client
-- computes it; a mock that ignores UIParent's scale would make every pixel
-- snapping test pass at exactly the one scale nobody plays at.
function frameMethods:GetEffectiveScale()
	local scale, node, hops = 1, self, 0
	while node and hops < 64 do
		scale = scale * (node._scale or 1)
		node = node._parent
		hops = hops + 1
	end
	return scale
end
function frameMethods:GetName() return self._name end
function frameMethods:SetID(id) self._id = id end
function frameMethods:GetID() return self._id or 0 end
-- Frames built from a secure template are protected: the client blocks
-- show/hide/position/attribute changes on them while in combat. The mock raises
-- so a protected action shows up as a test failure rather than as
-- ADDON_ACTION_BLOCKED spam in someone's chat.
local PROTECTED_IN_COMBAT = {
	Show = true, Hide = true, SetShown = true, SetPoint = true, SetAllPoints = true,
	ClearAllPoints = true, SetParent = true, SetWidth = true, SetHeight = true,
	SetSize = true, SetScale = true, SetFrameLevel = true, SetFrameStrata = true,
	EnableMouse = true, SetAttribute = true,
}

local function guardProtected(frame, method)
	if M.inCombat and frame._protected and PROTECTED_IN_COMBAT[method] then
		error(("protected frame %s: %s is blocked in combat")
			:format(frame._name or "<anonymous>", method), 3)
	end
end
M.GuardProtected = guardProtected

function frameMethods:SetAttribute(k, v)
	guardProtected(self, "SetAttribute")
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
-- Selection, as an edit box records it: no arguments means everything.
function frameMethods:HighlightText(from, to)
	self._highlight = { from or 0, to or -1 }
end
function frameMethods:GetHighlight() return self._highlight end

-- Keyboard focus needs an edit box that is actually on screen. In the client,
-- SetFocus on a hidden edit box -- or one inside a window that has not been
-- shown yet -- does nothing, and hiding a focused edit box drops the focus.
--
-- Modelling that is the point: a copy dialog that fills its box and focuses it
-- before the window is up looks perfect in a mock that just sets a flag, and in
-- the game it hands the player an unfocused box where Ctrl+C copies nothing.
function frameMethods:SetFocus()
	if not effectivelyVisible(self) then return end
	if M.focus and M.focus ~= self then M.focus._focus = false end
	self._focus = true
	M.focus = self
end
function frameMethods:ClearFocus()
	self._focus = false
	if M.focus == self then M.focus = nil end
end
function frameMethods:HasFocus() return self._focus or false end
function frameMethods:Insert(v) self:SetText((self._text or "") .. (v or "")) end
function frameMethods:GetNumLetters() return #(self._text or "") end

-- Button
function frameMethods:Disable() end
function frameMethods:Enable() end
function frameMethods:SetNormalTexture() end
function frameMethods:SetHighlightTexture() end
function frameMethods:SetPushedTexture() end

for _, method in ipairs({
	"Show", "Hide", "SetShown", "SetPoint", "SetAllPoints", "ClearAllPoints",
	"SetParent", "SetWidth", "SetHeight", "SetSize", "SetScale",
	"SetFrameLevel", "SetFrameStrata", "EnableMouse",
}) do
	local original = frameMethods[method]
	frameMethods[method] = function(self, ...)
		guardProtected(self, method)
		if original then return original(self, ...) end
	end
end

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

-- Frame types and templates the client actually provides. An unknown template
-- name raises in the game; the mock has to do the same or a typo ships.
local FRAME_TYPES = {}
for name in ([[Frame Button CheckButton EditBox ScrollFrame Slider StatusBar
	GameTooltip MessageFrame ScrollingMessageFrame SimpleHTML Cooldown
	ColorSelect Model PlayerModel ModelScene Browser Minimap MovieFrame
	POIFrame QuestPOIFrame ArchaeologyDigSiteFrame ScenarioPOIFrame
	UnitButton ContainedAlertFrame OffScreenFrame FogOfWarFrame]]):gmatch("%S+") do
	FRAME_TYPES[name] = true
end

M.knownTemplates = {}
for name in ([[UIPanelButtonTemplate UIPanelCloseButton
	SecureActionButtonTemplate SecureHandlerClickTemplate
	BackdropTemplate TooltipBorderedFrameTemplate
	InputBoxTemplate UIDropDownMenuTemplate
	OptionsSliderTemplate UICheckButtonTemplate
	InsecureActionButtonTemplate]]):gmatch("%S+") do
	M.knownTemplates[name] = true
end

function _G.CreateFrame(kind, name, parent, template)
	assert(FRAME_TYPES[kind or "Frame"], "unknown frame type: " .. tostring(kind))
	if template then
		for one in tostring(template):gmatch("[^,%s]+") do
			assert(M.knownTemplates[one], "unknown frame template: " .. one)
		end
	end
	assert(name == nil or _G[name] == nil or _G[name]._kind ~= nil,
		"frame name collides with an existing global: " .. tostring(name))
	local f = setmetatable({
		_kind = kind or "Frame", _name = name, _parent = parent, _template = template,
		_shown = true,
		_protected = template ~= nil and tostring(template):find("Secure") ~= nil,
	}, frameMT)
	M.frames[#M.frames + 1] = f
	if parent then
		local kids = M.children[parent]
		if not kids then kids = {} M.children[parent] = kids end
		kids[#kids + 1] = f
	end
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

-- Advances time and ticks every shown frame's OnUpdate, so animation code is
-- exercised and tweens actually finish instead of sitting in the queue.
function M.RunFrames(count, dt)
	dt = dt or 0.05
	for _ = 1, count or 20 do
		M.now = M.now + dt
		local snapshot = {}
		for i = 1, #M.frames do snapshot[i] = M.frames[i] end
		for i = 1, #snapshot do
			local frame = snapshot[i]
			local script = frame._shown ~= false and frame._scripts and frame._scripts.OnUpdate
			if script then
				local ok, err = pcall(script, frame, dt)
				if not ok then M.errors[#M.errors + 1] = "OnUpdate: " .. tostring(err) end
			end
		end
		M.RunTimers(1)
	end
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
-- Real filter storage rather than a no-op: whether a whisper still reaches the
-- default chat frame is the single most important thing the addon must not get
-- wrong, so the harness has to be able to observe it.
M.chatFilters = {}
_G.ChatFrame_AddMessageEventFilter = function(event, filter)
	local list = M.chatFilters[event]
	if not list then list = {} M.chatFilters[event] = list end
	for i = 1, #list do
		assert(list[i] ~= filter, "filter registered twice for " .. tostring(event))
	end
	list[#list + 1] = filter
end
_G.ChatFrame_RemoveMessageEventFilter = function(event, filter)
	local list = M.chatFilters[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == filter then table.remove(list, i) end
	end
end

-- Runs the registered filters the way the client does: the first one to return
-- true suppresses the line. Returns whether the chat frame would show it.
-- Clicks a widget the way a player does: enter, press, release, leave. Buttons
-- in this addon check IsMouseOver inside OnMouseUp, so a bare script call would
-- silently do nothing and the test would pass for the wrong reason.
-- A click the way a player makes one: press, at least one frame passes, release.
--
-- The frame in the middle is not decoration. Anything that installs an OnUpdate
-- on press -- a drag handler, say -- gets to run before the release, which is
-- how a drag handler with no movement threshold ends up eating every click. A
-- press and release with nothing between them proves the button works in a
-- world where time does not pass.
function M.Click(frame, button, heldFrames)
	assert(frame, "M.Click on a nil frame")
	assert(frame:IsShown(), "M.Click on a hidden frame")
	button = button or "LeftButton"
	local previous = frame._mouseOver
	frame._mouseOver = true
	local scripts = frame._scripts or {}
	if scripts.OnEnter then scripts.OnEnter(frame) end
	if scripts.OnMouseDown then scripts.OnMouseDown(frame, button) end
	M.RunFrames(heldFrames or 1)
	scripts = frame._scripts or {}
	if scripts.OnMouseUp then scripts.OnMouseUp(frame, button) end
	if scripts.OnClick then scripts.OnClick(frame, button) end
	if scripts.OnLeave then scripts.OnLeave(frame) end
	frame._mouseOver = previous
end

-- Everything under a frame, frames and regions alike, so a UI audit can measure
-- what was actually built instead of what the code was supposed to build.
function M.Descendants(root, out)
	out = out or {}
	local function isUnder(node)
		local hops = 0
		while node do
			if node == root then return true end
			hops = hops + 1
			if hops > 64 then return false end   -- cycle guard
			node = node._parent
		end
		return false
	end
	for _, list in ipairs({ M.frames, M.regions }) do
		for i = 1, #list do
			local node = list[i]
			if node ~= root and isUnder(node) then out[#out + 1] = node end
		end
	end
	return out
end

-- A node is only really on screen if it and every ancestor up to the root are
-- shown; a hidden panel full of visible children must not be audited.
function M.EffectivelyShown(node, root)
	local hops = 0
	while node do
		if node._shown == false then return false end
		if node == root then return true end
		hops = hops + 1
		if hops > 64 then return false end
		node = node._parent
	end
	return root == nil
end

function M.ChatFrameWouldShow(event, ...)
	local list = M.chatFilters[event]
	if not list then return true end
	for i = 1, #list do
		local ok, suppress = pcall(list[i], _G.DEFAULT_CHAT_FRAME, event, ...)
		if not ok then
			M.errors[#M.errors + 1] = "chat filter: " .. tostring(suppress)
		elseif suppress then
			return false
		end
	end
	return true
end
_G.PlaySound = function() return true end
_G.PlaySoundFile = function() return true end
_G.FlashClientIcon = function() end
_G.SetItemRef = function() end
_G.geterrorhandler = function() return function(msg) M.errors[#M.errors + 1] = tostring(msg) end end
-- The real thing: appends to a global function without replacing it, and the
-- hook receives the same arguments. A no-op here made anything built on a
-- Blizzard hook impossible to test, which is worse than not having the mock.
_G.hooksecurefunc = function(a, b, c)
	local owner, name, hook
	if type(a) == "string" then owner, name, hook = _G, a, b
	else owner, name, hook = a, b, c end
	local original = owner[name]
	assert(type(original) == "function",
		"hooksecurefunc on something that is not a function: " .. tostring(name))
	assert(type(hook) == "function", "hooksecurefunc needs a function to add")
	owner[name] = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
end

-- Blizzard's default chat edit box, and the function it calls whenever the
-- player points it somewhere else. Enough of it to drive "/w Someone".
_G.DEFAULT_CHAT_FRAME_EDITBOX = CreateFrame("EditBox", "ChatFrame1EditBox", UIParent)
function _G.ChatEdit_UpdateHeader(editBox) return editBox end

-- Drives the chat box the way typing "/w Name " does: set the target, then let
-- Blizzard update the header, which is where addons hook in.
function M.ComposeWhisper(target)
	local editBox = _G.DEFAULT_CHAT_FRAME_EDITBOX
	editBox:SetAttribute("chatType", target and "WHISPER" or "SAY")
	editBox:SetAttribute("tellTarget", target)
	_G.ChatEdit_UpdateHeader(editBox)
end
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
