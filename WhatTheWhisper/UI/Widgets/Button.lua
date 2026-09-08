-- WhatTheWhisper -- Buttons.
--
-- Four variants, one state machine, identical geometry. See DESIGN.md §4.7 for
-- the state table these implement.

local _, ns = ...
local Theme, W, Draw, Anim = ns.Theme, ns.Widgets, ns.Draw, ns.Anim

local Button = {}
ns.Button = Button

local VARIANTS = {
	ghost = {
		rest = { fill = nil,        fg = "textSecondary" },
		hover = { fill = "hover",    fg = "textPrimary" },
		pressed = { fill = "pressed", fg = "textPrimary" },
		selected = { fill = "selected", fg = "textPrimary" },
		disabled = { fill = nil,     fg = "textDisabled" },
	},
	primary = {
		rest = { fill = "accent",      fg = "onAccent" },
		hover = { fill = "accentHover", fg = "onAccent" },
		pressed = { fill = "accentActive", fg = "onAccent" },
		selected = { fill = "accentActive", fg = "onAccent" },
		disabled = { fill = "accent",  fg = "onAccent", alpha = 0.4 },
	},
	danger = {
		rest = { fill = nil,       fg = "danger" },
		hover = { fill = "danger",  fillAlpha = 0.16, fg = "danger" },
		pressed = { fill = "danger", fillAlpha = 0.26, fg = "danger" },
		selected = { fill = "danger", fillAlpha = 0.26, fg = "danger" },
		disabled = { fill = nil,   fg = "textDisabled" },
	},
	subtle = {
		rest = { fill = "bg3",     fg = "textSecondary" },
		hover = { fill = "hover",   fg = "textPrimary" },
		pressed = { fill = "pressed", fg = "textPrimary" },
		selected = { fill = "selected", fg = "textPrimary" },
		disabled = { fill = "bg3", fg = "textDisabled", alpha = 0.5 },
	},
	-- For a button sitting on a raised surface, where a filled one would be the
	-- same colour as the panel under it and simply disappear. The outline is
	-- what makes it a button; the fill only arrives on hover.
	-- The edge uses trackBg rather than a border role: those are tuned to sit
	-- quietly on the window, and in Minimal borderStrong against bg3 comes out
	-- at 1.29 to 1 -- under the point where an edge is visible at all, which is
	-- the exact bug this variant exists to fix. trackBg is derived to clear that
	-- floor in every palette.
	outline = {
		rest = { fill = nil,       fg = "textSecondary", border = "trackBg" },
		hover = { fill = "hover",   fg = "textPrimary", border = "trackBg" },
		pressed = { fill = "pressed", fg = "textPrimary", border = "trackBg" },
		selected = { fill = "selected", fg = "textPrimary", border = "accent" },
		disabled = { fill = nil,   fg = "textDisabled", border = "borderSubtle" },
	},
}
Button.VARIANTS = VARIANTS

local function applyState(btn, state, instant)
	local spec = VARIANTS[btn.variant][state] or VARIANTS[btn.variant].rest
	local duration = instant and 0 or Theme.Duration("FAST")

	if spec.fill then
		local c = Theme.Get(spec.fill)
		local a = (spec.fillAlpha or c[4] or 1) * (spec.alpha or 1)
		if duration <= 0 then
			btn.surface:SetColorOverride(c[1], c[2], c[3], a)
		else
			local r, g, b, ca = btn.surface.rect:GetColor()
			Anim.Color(btn, duration, { r or 0, g or 0, b or 0, ca or 0 },
				{ c[1], c[2], c[3], a }, function(nr, ng, nb, na)
					btn.surface:SetColorOverride(nr, ng, nb, na)
				end)
		end
	else
		local r, g, b, ca = btn.surface.rect:GetColor()
		if duration <= 0 or (ca or 0) == 0 then
			Anim.Stop(btn)
			btn.surface:SetColorOverride(0, 0, 0, 0)
		else
			Anim.Color(btn, duration, { r, g, b, ca }, { r, g, b, 0 },
				function(nr, ng, nb, na) btn.surface:SetColorOverride(nr, ng, nb, na) end)
		end
	end

	-- Only the outline variant asks for one, and it has to follow the state so
	-- the edge brightens with the fill rather than staying flat under it.
	if btn.surface.SetBorderRole then
		btn.surface:SetBorderRole(spec.border)
	end

	local fg = Theme.Get(spec.fg)
	local fgAlpha = (fg[4] or 1) * (spec.alpha or 1)
	if btn.icon then btn.icon:SetVertexColor(fg[1], fg[2], fg[3], fgAlpha) end
	if btn.label then btn.label:SetTextColor(fg[1], fg[2], fg[3], fgAlpha) end
	btn.__wtwFG = spec.fg
end

local function finish(btn, opts)
	btn.variant = opts.variant or "ghost"
	btn.surface = W.Surface(btn, {
		radius = opts.radius or ns.R.MD,
		layer = "BACKGROUND",
	})
	W.MakeInteractive(btn, function(state, instant) applyState(btn, state, instant) end)
	if opts.tooltip then W.SetTooltip(btn, opts.tooltip, opts.tooltipSub) end
	if opts.onClick then
		-- HookScript, not SetScript: MakeInteractive already installed the
		-- pressed-state reset on this handler and SetScript would drop it.
		btn:HookScript("OnMouseUp", function(self, mouseButton)
			if not self.__wtwEnabled then return end
			if not self:IsMouseOver() then return end
			ns.Guard("Button.onClick", opts.onClick, self, mouseButton)
		end)
	end

	function btn:SetVariant(variant)
		btn.variant = variant
		applyState(btn, btn.__wtwState or "rest", true)
	end

	function btn:ApplyTheme()
		btn.surface:ApplyTheme()
		if btn.icon then W.RefreshIcon(btn.icon) end
		if btn.label then W.RefreshText(btn.label) end
		applyState(btn, btn.__wtwState or "rest", true)
	end

	applyState(btn, "rest", true)
	return btn
end

--------------------------------------------------------------------------------
-- Icon button
--------------------------------------------------------------------------------

-- opts: icon, size, glyph, variant, radius, tooltip, onClick
function Button.Icon(parent, opts)
	opts = opts or {}
	local size = opts.size or ns.SZ.ICON_BTN
	local btn = CreateFrame("Frame", nil, parent)
	btn:SetSize(size, size)

	btn.icon = W.Icon(btn, opts.icon, opts.glyph or ns.SZ.ICON_GLYPH, "textSecondary")
	btn.icon:SetPoint("CENTER")

	function btn:SetIcon(name)
		Draw.SetIcon(btn.icon, name)
		btn.icon.__wtwIcon = name
	end

	return finish(btn, opts)
end

--------------------------------------------------------------------------------
-- Text button
--------------------------------------------------------------------------------

-- opts: text, variant, radius, minWidth, height, icon, tooltip, onClick
function Button.Text(parent, opts)
	opts = opts or {}
	local btn = CreateFrame("Frame", nil, parent)
	local height = opts.height or 32
	btn:SetHeight(height)

	btn.label = W.Text(btn, opts.token or "BODY", "textSecondary")
	btn.label:SetJustifyH("CENTER")

	if opts.icon then
		btn.icon = W.Icon(btn, opts.icon, opts.glyph or ns.SZ.ICON_GLYPH_SM, "textSecondary")
		btn.icon:SetPoint("LEFT", btn, "LEFT", ns.S.MD, 0)
		btn.label:SetPoint("LEFT", btn.icon, "RIGHT", ns.S.SM, 0)
		btn.label:SetPoint("RIGHT", btn, "RIGHT", -ns.S.MD, 0)
	else
		btn.label:SetPoint("LEFT", btn, "LEFT", ns.S.MD, 0)
		btn.label:SetPoint("RIGHT", btn, "RIGHT", -ns.S.MD, 0)
	end

	function btn:SetText(text)
		btn.label:SetText(text)
		if opts.autoWidth ~= false then
			local extra = opts.icon and (ns.SZ.ICON_GLYPH_SM + ns.S.SM) or 0
			btn:SetWidth(math.max(opts.minWidth or 72,
				btn.label:GetStringWidth() + ns.S.MD * 2 + extra))
		end
	end
	btn:SetText(opts.text or "")

	return finish(btn, opts)
end

--------------------------------------------------------------------------------
-- Circular send button
--------------------------------------------------------------------------------

-- The composer's send button. It is not a normal button: it lives in an
-- "inactive" muted state until there is something to send, then lights up.
function Button.Send(parent, opts)
	opts = opts or {}
	local size = opts.size or ns.SZ.SEND_BTN
	local btn = CreateFrame("Frame", nil, parent)
	btn:SetSize(size, size)
	btn.variant = "primary"
	btn.active = false

	btn.surface = W.Surface(btn, { radius = size / 2, layer = "BACKGROUND" })
	btn.icon = W.Icon(btn, "arrow_up", math.floor(size * 0.56), "onAccent")
	btn.icon:SetPoint("CENTER")

	local function paint(state, instant)
		local fill, fg
		if not btn.active then
			fill = Theme.Get("hover")
			fg = Theme.Get("textDisabled")
		elseif state == "pressed" then
			fill, fg = Theme.Get("accentActive"), Theme.Get("onAccent")
		elseif state == "hover" then
			fill, fg = Theme.Get("accentHover"), Theme.Get("onAccent")
		else
			fill, fg = Theme.Get("accent"), Theme.Get("onAccent")
		end
		local duration = instant and 0 or Theme.Duration("FAST")
		if duration <= 0 then
			btn.surface:SetColorOverride(fill[1], fill[2], fill[3], fill[4] or 1)
		else
			local r, g, b, a = btn.surface.rect:GetColor()
			Anim.Color(btn, duration, { r or 0, g or 0, b or 0, a or 0 }, fill,
				function(nr, ng, nb, na) btn.surface:SetColorOverride(nr, ng, nb, na) end)
		end
		btn.icon:SetVertexColor(fg[1], fg[2], fg[3], fg[4] or 1)
	end

	W.MakeInteractive(btn, paint)

	function btn:SetActive(active)
		if btn.active == (active and true or false) then return end
		btn.active = active and true or false
		paint(btn.__wtwState or "rest", false)
	end

	function btn:ApplyTheme()
		btn.surface:SetRadius(size / 2)
		btn.surface:ApplyTheme()
		W.RefreshIcon(btn.icon)
		paint(btn.__wtwState or "rest", true)
	end

	if opts.onClick then
		btn:HookScript("OnMouseUp", function(self, mouseButton)
			if not self:IsMouseOver() then return end
			ns.Guard("Button.Send", opts.onClick, self, mouseButton)
		end)
	end
	if opts.tooltip then W.SetTooltip(btn, opts.tooltip) end

	paint("rest", true)
	return btn
end
