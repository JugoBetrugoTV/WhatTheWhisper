-- WhatTheWhisper -- Minimap button.
--
-- Deliberately not LibDBIcon: that library is not in the library folder this
-- addon was pointed at, and a single draggable button is not worth a hard
-- dependency. It shows the unread count, which the LDB version could not.

local _, ns = ...
local Theme, W, Draw, Anim = ns.Theme, ns.Widgets, ns.Draw, ns.Anim
local CM = ns.ConversationManager
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local MinimapButton = {}
ns.Minimap = MinimapButton

local button
local RADIUS = 80
local SIZE = 26

local function positionAt(angle)
	local minimap = _G.Minimap
	if not minimap or not button then return end
	local radians = math.rad(angle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", minimap, "CENTER",
		math.cos(radians) * RADIUS, math.sin(radians) * RADIUS)
end

local function build()
	if button then return button end
	local minimap = _G.Minimap
	if not minimap then return nil end

	button = CreateFrame("Frame", "WhatTheWhisperMinimapButton", minimap)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata(minimap:GetFrameStrata())
	button:SetFrameLevel((minimap:GetFrameLevel() or 1) + 8)
	button:EnableMouse(true)
	button:SetMovable(true)

	button.surface = W.Surface(button, {
		color = "bg0", border = "borderStrong", radius = SIZE / 2, shadow = 6,
	})
	button.icon = W.Icon(button, "logo", 14, "accent")
	button.icon:SetPoint("CENTER")

	button.badge = ns.Controls.Badge(button, { height = 14 })
	button.badge:SetPoint("CENTER", button, "TOPRIGHT", -2, -2)

	W.MakeInteractive(button, function(state, instant)
		local duration = instant and 0 or Theme.Duration("FAST")
		local role = (state == "pressed" and "selected")
			or (state == "hover" and "hover") or "bg0"
		W.FadeSurfaceTo(button.surface, button, role, duration)
	end)
	W.SetTooltip(button, L["WhatTheWhisper"], L["/wtw - toggle the messenger"])

	button:HookScript("OnMouseUp", function(self, mouseButton)
		if self.dragging or not self:IsMouseOver() then return end
		if mouseButton == "RightButton" then
			ns.SettingsUI.Toggle()
		else
			ns.UI.Toggle()
		end
	end)

	-- Drag around the minimap edge.
	button:SetScript("OnMouseDown", function(self, mouseButton)
		if mouseButton ~= "LeftButton" then return end
		self.dragging = false
		self:SetScript("OnUpdate", function()
			local minimapFrame = _G.Minimap
			local scale = minimapFrame:GetEffectiveScale() or 1
			local cx, cy = GetCursorPosition()
			cx, cy = cx / scale, cy / scale
			local mx, my = minimapFrame:GetCenter()
			if not mx then return end
			self.dragging = true
			local angle = math.deg(math.atan2(cy - my, cx - mx))
			ns.db.profile.advanced.minimap.angle = angle
			positionAt(angle)
		end)
	end)
	local function endDrag(self)
		self:SetScript("OnUpdate", nil)
		if self.dragging then
			-- Swallow the click that ended a drag.
			Anim.After(0, function() self.dragging = false end)
		end
	end
	button:HookScript("OnMouseUp", endDrag)
	button:HookScript("OnHide", endDrag)

	return button
end

function MinimapButton.Update()
	if not ns.db then return end
	local hide = ns.db.profile.advanced.minimap.hide
	if hide then
		if button then button:Hide() end
		return
	end
	if not build() then return end
	positionAt(ns.db.profile.advanced.minimap.angle or 205)
	button.badge:SetCount(ns.db.profile.notifications.badge and CM.TotalUnread() or 0)
	button:Show()
end

function MinimapButton.ApplyTheme()
	if not button then return end
	button.surface:SetRadius(SIZE / 2)
	button.surface:ApplyTheme()
	W.RefreshIcon(button.icon)
	button.badge:ApplyTheme()
	button.UpdateVisualState(true)
end
