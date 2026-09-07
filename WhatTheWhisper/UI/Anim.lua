-- WhatTheWhisper -- Motion.
--
-- Two mechanisms, chosen deliberately:
--   * AnimationGroups for alpha, scale and translation. These run inside the
--     engine, cost nothing in Lua, and keep running smoothly under load.
--   * One shared tween driver for everything AnimationGroups cannot express:
--     colours, widths, scroll offsets. The driver's OnUpdate is attached to a
--     frame that is only shown while at least one tween is alive, so the addon
--     has *no* permanently running OnUpdate.

local _, ns = ...
local Theme = ns.Theme

local Anim = {}
ns.Anim = Anim

local min = math.min

--------------------------------------------------------------------------------
-- Easing
--------------------------------------------------------------------------------

local Ease = {}
Anim.Ease = Ease

function Ease.linear(t) return t end
function Ease.outQuad(t) return 1 - (1 - t) * (1 - t) end
function Ease.outCubic(t) local u = 1 - t return 1 - u * u * u end
function Ease.inOutCubic(t)
	if t < 0.5 then return 4 * t * t * t end
	local u = -2 * t + 2
	return 1 - (u * u * u) / 2
end
function Ease.outBack(t)
	local c1, c3 = 1.10158, 2.10158
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

--------------------------------------------------------------------------------
-- Tween driver
--------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:Hide()

local tweens = {}       -- key -> tween table
local tweenCount = 0

local function stop(key, finish)
	local t = tweens[key]
	if not t then return end
	tweens[key] = nil
	tweenCount = tweenCount - 1
	if tweenCount <= 0 then
		tweenCount = 0
		driver:Hide()
	end
	if finish and t.onDone then
		ns.Guard("Anim.onDone", t.onDone)
	end
end

driver:SetScript("OnUpdate", function(_, elapsed)
	for key, t in pairs(tweens) do
		t.elapsed = t.elapsed + elapsed
		local progress = t.duration > 0 and min(1, t.elapsed / t.duration) or 1
		local eased = t.ease(progress)
		local ok, err = pcall(t.apply, t.from + (t.to - t.from) * eased, progress)
		if not ok then
			ns.SoftError("Anim", err)
			stop(key, false)
		elseif progress >= 1 then
			stop(key, true)
		end
	end
end)

-- key      identity of the tween; starting a new one with the same key replaces it
-- duration seconds (already scaled by the caller, or use Anim.Duration)
-- from,to  numbers
-- apply    function(value, progress)
-- opts     { ease = fn, onDone = fn }
function Anim.To(key, duration, from, to, apply, opts)
	opts = opts or {}
	if duration <= 0 or not Theme.AnimationsEnabled() then
		stop(key, false)
		apply(to, 1)
		if opts.onDone then ns.Guard("Anim.onDone", opts.onDone) end
		return
	end
	if not tweens[key] then
		tweenCount = tweenCount + 1
	end
	tweens[key] = {
		duration = duration,
		elapsed = 0,
		from = from,
		to = to,
		apply = apply,
		ease = opts.ease or Ease.outCubic,
		onDone = opts.onDone,
	}
	driver:Show()
end

function Anim.Stop(key)
	stop(key, false)
end

function Anim.IsRunning(key)
	return tweens[key] ~= nil
end

function Anim.ActiveCount()
	return tweenCount
end

-- Interpolates a colour role change. `apply` receives r, g, b, a.
function Anim.Color(key, duration, from, to, apply, opts)
	local r1, g1, b1, a1 = from[1], from[2], from[3], from[4] or 1
	local r2, g2, b2, a2 = to[1], to[2], to[3], to[4] or 1
	Anim.To(key, duration, 0, 1, function(v)
		apply(r1 + (r2 - r1) * v, g1 + (g2 - g1) * v, b1 + (b2 - b1) * v, a1 + (a2 - a1) * v)
	end, opts)
end

--------------------------------------------------------------------------------
-- AnimationGroup helpers
--------------------------------------------------------------------------------

local probe = driver:CreateAnimationGroup()
local probeAlpha = probe:CreateAnimation("Alpha")
local probeScale = probe:CreateAnimation("Scale")
local HAS_FROM_ALPHA = type(probeAlpha.SetFromAlpha) == "function"
local HAS_SCALE_TO = type(probeScale.SetScaleTo) == "function"

local function ensureFade(frame)
	local ag = frame.__wtwFade
	if ag then return ag, frame.__wtwFadeAnim end
	ag = frame:CreateAnimationGroup()
	local a = ag:CreateAnimation("Alpha")
	a:SetOrder(1)
	frame.__wtwFade = ag
	frame.__wtwFadeAnim = a
	ag:SetScript("OnFinished", function()
		frame:SetAlpha(frame.__wtwFadeTarget or 1)
		if frame.__wtwFadeHide then
			frame:Hide()
			frame.__wtwFadeHide = nil
		end
		local cb = frame.__wtwFadeDone
		frame.__wtwFadeDone = nil
		if cb then ns.Guard("Anim.Fade", cb) end
	end)
	return ag, a
end

function Anim.FadeTo(frame, targetAlpha, duration, onDone, hideAfter)
	if not frame then return end
	local ag, a = ensureFade(frame)
	ag:Stop()
	local current = frame:GetAlpha() or 1
	frame.__wtwFadeTarget = targetAlpha
	frame.__wtwFadeHide = hideAfter or nil
	frame.__wtwFadeDone = onDone

	if duration <= 0 or not Theme.AnimationsEnabled() then
		frame:SetAlpha(targetAlpha)
		if hideAfter then frame:Hide() end
		frame.__wtwFadeHide = nil
		frame.__wtwFadeDone = nil
		if onDone then ns.Guard("Anim.Fade", onDone) end
		return
	end

	if HAS_FROM_ALPHA then
		a:SetFromAlpha(current)
		a:SetToAlpha(targetAlpha)
	else
		a:SetChange(targetAlpha - current)
	end
	a:SetDuration(duration)
	a:SetSmoothing("OUT")
	ag:Play()
end

function Anim.FadeIn(frame, duration, onDone)
	if not frame then return end
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
	end
	Anim.FadeTo(frame, 1, duration or Theme.Duration("BASE"), onDone)
end

function Anim.FadeOut(frame, duration, onDone)
	if not frame or not frame:IsShown() then
		if onDone then ns.Guard("Anim.Fade", onDone) end
		return
	end
	Anim.FadeTo(frame, 0, duration or Theme.Duration("BASE"), onDone, true)
end

-- Scale + fade entrance used by windows and popups.
function Anim.PopIn(frame, duration, fromScale)
	if not frame then return end
	duration = duration or Theme.Duration("WINDOW")
	frame:Show()
	if duration <= 0 or not Theme.AnimationsEnabled() then
		frame:SetAlpha(1)
		frame:SetScale(frame.__wtwBaseScale or 1)
		return
	end
	frame.__wtwBaseScale = frame.__wtwBaseScale or frame:GetScale() or 1
	local base = frame.__wtwBaseScale
	local ag = frame.__wtwPop
	if not ag then
		ag = frame:CreateAnimationGroup()
		local s = ag:CreateAnimation("Scale")
		s:SetOrder(1)
		local a = ag:CreateAnimation("Alpha")
		a:SetOrder(1)
		frame.__wtwPop = ag
		frame.__wtwPopScale = s
		frame.__wtwPopAlpha = a
		ag:SetScript("OnFinished", function()
			frame:SetScale(frame.__wtwBaseScale or 1)
			frame:SetAlpha(1)
		end)
	end
	local s, a = frame.__wtwPopScale, frame.__wtwPopAlpha
	ag:Stop()
	local from = fromScale or 0.97
	if HAS_SCALE_TO then
		s:SetScaleFrom(from, from)
		s:SetScaleTo(1, 1)
	else
		s:SetScale(1 / from, 1 / from)
	end
	s:SetDuration(duration)
	s:SetSmoothing("OUT")
	if HAS_FROM_ALPHA then
		a:SetFromAlpha(0)
		a:SetToAlpha(1)
	else
		a:SetChange(1)
	end
	a:SetDuration(duration * 0.8)
	a:SetSmoothing("OUT")
	frame:SetScale(base * from)
	frame:SetAlpha(0)
	ag:Play()
end

-- One-shot attention pulse for unread badges. Fancy level only.
function Anim.Pulse(frame, strength)
	if not frame or not Theme.IsFancy() then return end
	local ag = frame.__wtwPulse
	if not ag then
		ag = frame:CreateAnimationGroup()
		local up = ag:CreateAnimation("Scale")
		up:SetOrder(1)
		up:SetDuration(0.11)
		up:SetSmoothing("OUT")
		local down = ag:CreateAnimation("Scale")
		down:SetOrder(2)
		down:SetDuration(0.13)
		down:SetSmoothing("IN")
		frame.__wtwPulse = ag
		frame.__wtwPulseUp = up
		frame.__wtwPulseDown = down
		ag:SetScript("OnFinished", function() frame:SetScale(1) end)
	end
	local s = 1 + (strength or 0.18)
	if HAS_SCALE_TO then
		frame.__wtwPulseUp:SetScaleFrom(1, 1)
		frame.__wtwPulseUp:SetScaleTo(s, s)
		frame.__wtwPulseDown:SetScaleFrom(s, s)
		frame.__wtwPulseDown:SetScaleTo(1, 1)
	else
		frame.__wtwPulseUp:SetScale(s, s)
		frame.__wtwPulseDown:SetScale(1 / s, 1 / s)
	end
	ag:Stop()
	ag:Play()
end

-- Slide-and-fade entrance for toasts and menus.
function Anim.SlideIn(frame, dx, dy, duration)
	if not frame then return end
	duration = duration or Theme.Duration("SLOW")
	frame:Show()
	if duration <= 0 or not Theme.AnimationsEnabled() then
		frame:SetAlpha(1)
		return
	end
	local ag = frame.__wtwSlide
	if not ag then
		ag = frame:CreateAnimationGroup()
		local t = ag:CreateAnimation("Translation")
		t:SetOrder(1)
		local a = ag:CreateAnimation("Alpha")
		a:SetOrder(1)
		frame.__wtwSlide = ag
		frame.__wtwSlideT = t
		frame.__wtwSlideA = a
		ag:SetScript("OnFinished", function() frame:SetAlpha(1) end)
	end
	ag:Stop()
	frame.__wtwSlideT:SetOffset(-dx, -dy)
	frame.__wtwSlideT:SetDuration(duration)
	frame.__wtwSlideT:SetSmoothing("OUT")
	if HAS_FROM_ALPHA then
		frame.__wtwSlideA:SetFromAlpha(0)
		frame.__wtwSlideA:SetToAlpha(1)
	else
		frame.__wtwSlideA:SetChange(1)
	end
	frame.__wtwSlideA:SetDuration(duration * 0.7)
	frame.__wtwSlideA:SetSmoothing("OUT")
	frame:SetAlpha(0)
	ag:Play()
end

function Anim.StopAll(frame)
	if not frame then return end
	if frame.__wtwFade then frame.__wtwFade:Stop() end
	if frame.__wtwPop then frame.__wtwPop:Stop() end
	if frame.__wtwSlide then frame.__wtwSlide:Stop() end
	if frame.__wtwPulse then frame.__wtwPulse:Stop() end
end

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------

function Anim.After(delay, fn)
	if ns.Compat.After(delay, function() ns.Guard("Anim.After", fn) end) then return end
	-- Should not happen on any supported client, but never leave a caller hanging.
	ns.Guard("Anim.After", fn)
end
