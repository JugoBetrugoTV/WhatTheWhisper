-- WhatTheWhisper -- Widget foundation.
--
-- Every control in the addon is assembled from the pieces here, which is what
-- keeps hover, press, focus and disabled states identical across the whole UI.
-- If a control does not have all five states it is not finished.

local _, ns = ...
local Draw, Theme, Pixel, Anim = ns.Draw, ns.Theme, ns.Pixel, ns.Anim

local W = {}
ns.Widgets = W

local max = math.max

--------------------------------------------------------------------------------
-- Surfaces
--------------------------------------------------------------------------------

local SurfaceMT = {}
SurfaceMT.__index = SurfaceMT

-- opts:
--   color        colour role for the fill
--   border       colour role for the hairline outline (optional)
--   borderWidth  multiplier on the hairline (default 1)
--   radius       base radius, before the skin's radius scale
--   shadow       drop shadow spread in px (optional)
--   insets       {l, r, t, b}
--   layer        draw layer (default BACKGROUND)
function W.Surface(frame, opts)
	opts = opts or {}
	local s = setmetatable({
		frame = frame,
		colorRole = opts.color,
		borderRole = opts.border,
		borderWidth = opts.borderWidth or 1,
		baseRadius = opts.radius or 0,
		insets = opts.insets or { 0, 0, 0, 0 },
		alphaScale = 1,
	}, SurfaceMT)

	s.rect = Draw.NewOutlined(frame, opts.layer or "BACKGROUND", opts.subLevel or 0)
	if opts.shadow and opts.shadow > 0 then
		s.shadowSpread = opts.shadow
		s.shadow = Draw.NewShadow(frame, opts.shadow)
	end

	frame:HookScript("OnSizeChanged", function() s:Layout() end)
	s:ApplyTheme()
	return s
end

function SurfaceMT:SetColorRole(role)
	self.colorRole = role
	self:ApplyTheme()
	return self
end

function SurfaceMT:SetBorderRole(role)
	self.borderRole = role
	self:ApplyTheme()
	return self
end

function SurfaceMT:SetRadius(radius)
	self.baseRadius = radius
	self:ApplyTheme()
	return self
end

function SurfaceMT:SetCorners(...)
	self.rect:SetCorners(...)
	return self
end

-- Overrides the theme colour, e.g. for a hover state or a class-coloured fill.
function SurfaceMT:SetColorOverride(r, g, b, a)
	self.override = r and { r, g, b, a } or nil
	self:ApplyColor()
	return self
end

function SurfaceMT:ApplyColor()
	local c = self.override
	if not c then
		if not self.colorRole then
			self.rect:SetColor(0, 0, 0, 0)
			return
		end
		c = Theme.Get(self.colorRole)
	end
	self.rect:SetColor(c[1], c[2], c[3], (c[4] or 1) * self.alphaScale)
end

function SurfaceMT:ApplyTheme()
	local i = self.insets
	self.rect:SetInsets(i[1], i[2], i[3], i[4])
	self.rect:SetRadius(Theme.Radius(self.baseRadius))
	if self.borderRole then
		local b = Theme.Get(self.borderRole)
		self.rect:SetBorder(Theme.Border(self.frame) * self.borderWidth, b[1], b[2], b[3], b[4])
	else
		self.rect:SetBorder(0)
	end
	self:ApplyColor()
	if self.shadow then
		local sc = Theme.Get("shadow")
		local strength = Theme.m.shadow or 1
		self.shadow:SetColor(sc[1], sc[2], sc[3], (sc[4] or 0.5) * strength)
		self.shadow:SetShown(strength > 0)
	end
	return self
end

function SurfaceMT:Layout()
	self.rect:Layout()
end

-- Call after changing the owning frame's strata or level; the shadow sits in a
-- sibling frame and does not follow on its own.
function SurfaceMT:SyncShadow()
	if not self.shadow then return end
	self.shadow.frame:SetFrameStrata(self.frame:GetFrameStrata())
	self.shadow:SetFrameLevel(max(0, (self.frame:GetFrameLevel() or 1) - 1))
end

function SurfaceMT:SetShown(shown)
	self.rect:SetShown(shown)
	if self.shadow then self.shadow:SetShown(shown and (Theme.m.shadow or 1) > 0) end
	return self
end

function SurfaceMT:SetAlphaScale(scale)
	self.alphaScale = scale or 1
	self:ApplyColor()
	return self
end

--------------------------------------------------------------------------------
-- Hairlines
--------------------------------------------------------------------------------

local LineMT = {}
LineMT.__index = LineMT

function W.Hairline(frame, orientation, opts)
	opts = opts or {}
	local o = setmetatable({
		frame = frame,
		orientation = orientation,
		role = opts.color or "borderSubtle",
		insetStart = opts.insetStart or 0,
		insetEnd = opts.insetEnd or 0,
		offset = opts.offset or 0,
		anchor = opts.anchor,
		width = opts.width or 1,
	}, LineMT)
	o.tex = Draw.Hairline(frame, opts.layer or "BORDER", opts.subLevel)
	frame:HookScript("OnSizeChanged", function() o:Layout() end)
	o:ApplyTheme()
	return o
end

function LineMT:ApplyTheme()
	local c = Theme.Get(self.role)
	self.tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	self:Layout()
	return self
end

function LineMT:SetColorRole(role)
	self.role = role
	return self:ApplyTheme()
end

function LineMT:Layout()
	local t = Pixel.Size(self.frame) * self.width
	local f = self.frame
	self.tex:ClearAllPoints()
	if self.orientation == "horizontal" then
		local anchor = self.anchor or "TOP"
		if anchor == "TOP" then
			self.tex:SetPoint("TOPLEFT", f, "TOPLEFT", self.insetStart, -self.offset)
			self.tex:SetPoint("TOPRIGHT", f, "TOPRIGHT", -self.insetEnd, -self.offset)
		else
			self.tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", self.insetStart, self.offset)
			self.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -self.insetEnd, self.offset)
		end
		self.tex:SetHeight(t)
	else
		local anchor = self.anchor or "LEFT"
		if anchor == "LEFT" then
			self.tex:SetPoint("TOPLEFT", f, "TOPLEFT", self.offset, -self.insetStart)
			self.tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", self.offset, self.insetEnd)
		else
			self.tex:SetPoint("TOPRIGHT", f, "TOPRIGHT", -self.offset, -self.insetStart)
			self.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -self.offset, self.insetEnd)
		end
		self.tex:SetWidth(t)
	end
	return self
end

function LineMT:SetShown(shown)
	self.tex:SetShown(shown and true or false)
	return self
end

--------------------------------------------------------------------------------
-- Icons
--------------------------------------------------------------------------------

function W.Icon(parent, name, size, role, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetSize(size, size)
	Draw.SetIcon(tex, name)
	local c = Theme.Get(role or "textSecondary")
	tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	tex.__wtwIcon = name
	tex.__wtwRole = role or "textSecondary"
	return tex
end

function W.SetIconRole(tex, role, alpha)
	tex.__wtwRole = role
	local c = Theme.Get(role)
	tex:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

function W.RefreshIcon(tex)
	if not tex or not tex.__wtwIcon then return end
	Draw.SetIcon(tex, tex.__wtwIcon)
	W.SetIconRole(tex, tex.__wtwRole or "textSecondary")
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

function W.Text(parent, token, role, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(Theme.Font(token))
	local c = Theme.Get(role or "textPrimary")
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("MIDDLE")
	fs.__wtwToken = token
	fs.__wtwRole = role or "textPrimary"
	return fs
end

function W.SetTextRole(fs, role, alpha)
	fs.__wtwRole = role
	local c = Theme.Get(role)
	fs:SetTextColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

function W.RefreshText(fs)
	if not fs or not fs.__wtwToken then return end
	fs:SetFontObject(Theme.Font(fs.__wtwToken))
	W.SetTextRole(fs, fs.__wtwRole or "textPrimary")
end

--------------------------------------------------------------------------------
-- Interaction state machine
--------------------------------------------------------------------------------

-- Attaches rest/hover/pressed/disabled handling to a frame. `onState` receives
-- the resolved state name so the caller decides what it means visually.
function W.MakeInteractive(frame, onState, opts)
	opts = opts or {}
	frame.__wtwState = "rest"
	frame.__wtwEnabled = true

	local function resolve()
		if not frame.__wtwEnabled then return "disabled" end
		if frame.__wtwSelected then return "selected" end
		if frame.__wtwPressed then return "pressed" end
		if frame.__wtwHover then return "hover" end
		return "rest"
	end

	local function update(instant)
		local state = resolve()
		if state == frame.__wtwState and not instant then return end
		frame.__wtwState = state
		onState(state, instant)
	end
	frame.UpdateVisualState = update

	frame:EnableMouse(true)
	frame:HookScript("OnEnter", function()
		frame.__wtwHover = true
		update()
		if frame.__wtwTooltip then ns.Tooltip.Schedule(frame, frame.__wtwTooltip) end
	end)
	frame:HookScript("OnLeave", function()
		frame.__wtwHover = false
		frame.__wtwPressed = false
		update()
		ns.Tooltip.Cancel(frame)
	end)
	frame:HookScript("OnMouseDown", function()
		if not frame.__wtwEnabled then return end
		frame.__wtwPressed = true
		update(true)
	end)
	frame:HookScript("OnMouseUp", function()
		frame.__wtwPressed = false
		update()
	end)
	if opts.hideOnHide ~= false then
		frame:HookScript("OnHide", function()
			frame.__wtwHover = false
			frame.__wtwPressed = false
			update(true)
			ns.Tooltip.Cancel(frame)
		end)
	end

	function frame:SetEnabled(enabled)
		frame.__wtwEnabled = enabled and true or false
		frame:EnableMouse(frame.__wtwEnabled)
		update(true)
	end
	function frame:IsEnabledState()
		return frame.__wtwEnabled
	end
	function frame:SetSelectedState(selected)
		frame.__wtwSelected = selected and true or false
		update()
	end
	function frame:IsSelectedState()
		return frame.__wtwSelected and true or false
	end

	update(true)
	return frame
end

function W.SetTooltip(frame, text, subtext)
	if text then
		frame.__wtwTooltip = { text = text, subtext = subtext }
	else
		frame.__wtwTooltip = nil
	end
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- Fades a surface between two colour roles instead of snapping, which is what
-- makes hover feel like a desktop app rather than a game menu.
function W.FadeSurfaceTo(surface, key, role, duration)
	local target = role and Theme.Get(role) or { 0, 0, 0, 0 }
	local currentR, currentG, currentB, currentA = surface.rect:GetColor()
	local from = { currentR or 0, currentG or 0, currentB or 0, currentA or 0 }
	if duration <= 0 or not Theme.AnimationsEnabled() then
		Anim.Stop(key)
		surface:SetColorOverride(target[1], target[2], target[3], target[4] or 1)
		return
	end
	Anim.Color(key, duration, from, target, function(r, g, b, a)
		surface:SetColorOverride(r, g, b, a)
	end)
end

--------------------------------------------------------------------------------
-- Window handles
--------------------------------------------------------------------------------

-- OnDoubleClick is a Button script: a plain Frame never receives it, so a title
-- bar that wants double-click-to-minimise has to time the presses itself.
local DOUBLE_CLICK = 0.30

-- opts: canMove() -> bool, onStartMove(), onStopMove(), onDoubleClick()
function W.MakeWindowHandle(handle, opts)
	local lastDown = 0
	handle:EnableMouse(true)

	handle:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local now = GetTime()
		if opts.onDoubleClick and (now - lastDown) <= DOUBLE_CLICK then
			lastDown = 0
			if opts.onStopMove then ns.Guard("Window.stopMove", opts.onStopMove) end
			ns.Guard("Window.doubleClick", opts.onDoubleClick)
			return
		end
		lastDown = now
		if opts.canMove and not opts.canMove() then return end
		if opts.onStartMove then ns.Guard("Window.startMove", opts.onStartMove) end
	end)

	local function stop()
		if opts.onStopMove then ns.Guard("Window.stopMove", opts.onStopMove) end
	end
	handle:SetScript("OnMouseUp", stop)
	handle:HookScript("OnHide", stop)
end

function W.ClampSize(frame, minW, minH, maxW, maxH)
	ns.Compat.SetResizeBounds(frame, minW, minH, maxW, maxH)
end
