-- WhatTheWhisper -- Combat behaviour.
--
-- None of this addon's frames are protected: no SecureActionButtonTemplate on
-- any window, no reparenting of Blizzard frames, no hooks into protected code
-- paths. That means showing, hiding, moving and fading our windows during combat
-- is safe and cannot taint the execution path.
--
-- The one place where combat genuinely restricts us is the secure "Target"
-- button in the context menu, which needs SetAttribute -- that is guarded
-- separately in UI/Widgets/ContextMenu.lua.

local _, ns = ...

local Combat = {}
ns.Combat = Combat

local frame = CreateFrame("Frame")
local inCombat = false
local savedState

local function settings()
	return (ns.db and ns.db.profile and ns.db.profile.combat) or ns.defaults.profile.combat
end

function Combat.InCombat()
	return inCombat
end

local function captureState()
	local UI = ns.UI
	if not UI then return nil end
	return UI.CaptureVisibility()
end

local function onEnterCombat()
	inCombat = true
	local mode = settings().onEnter
	local UI = ns.UI
	if UI and mode ~= "nothing" then
		savedState = captureState()
		if mode == "fade" then
			UI.SetCombatFade(settings().fadeOpacity)
		elseif mode == "minimize" then
			UI.MinimizeAll()
		elseif mode == "hide" then
			UI.HideAll()
		end
	end
	ns.Bus.Fire(ns.EV.COMBAT_STATE_CHANGED, true)
end

local function onLeaveCombat()
	inCombat = false
	local UI = ns.UI
	if UI then
		UI.SetCombatFade(nil)
		if settings().onLeave == "restore" and savedState then
			UI.RestoreVisibility(savedState)
		end
	end
	savedState = nil
	ns.Bus.Fire(ns.EV.COMBAT_STATE_CHANGED, false)
end

frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		ns.Guard("Combat.enter", onEnterCombat)
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Guard("Combat.leave", onLeaveCombat)
	end
end)

function Combat.Init()
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	inCombat = InCombatLockdown() and true or false
end
