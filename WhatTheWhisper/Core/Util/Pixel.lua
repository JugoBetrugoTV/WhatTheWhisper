-- WhatTheWhisper -- Pixel-perfect geometry.
--
-- A "1 px" hairline that is actually 1.37 physical pixels is the single most
-- common reason an addon looks blurry next to a real desktop app. Everything
-- that draws a border or a divider goes through here.

local _, ns = ...
local Compat = ns.Compat

local Pixel = {}
ns.Pixel = Pixel

local floor, abs = math.floor, math.abs

-- Size of one physical pixel expressed in the coordinate space of `frame`.
function Pixel.Size(frame)
	local scale = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale())
		or (UIParent and UIParent:GetEffectiveScale())
		or 1
	if scale <= 0 then scale = 1 end
	return 768 / Compat.GetPhysicalHeight() / scale
end

-- Round a length to a whole number of physical pixels (never below one).
function Pixel.Snap(value, frame)
	local px = Pixel.Size(frame)
	if px <= 0 then return value end
	local snapped = floor(value / px + 0.5) * px
	if snapped < px then snapped = px end
	return snapped
end

-- Round a coordinate to the pixel grid. Unlike Snap this may return 0.
function Pixel.SnapCoord(value, frame)
	local px = Pixel.Size(frame)
	if px <= 0 then return value end
	return floor(value / px + 0.5) * px
end

-- Hairline thickness: exactly one physical pixel, or a user-configured multiple.
function Pixel.Hairline(frame, multiplier)
	return Pixel.Size(frame) * (multiplier or 1)
end

-- Positions a frame at whole physical pixels so its textures cannot smear.
function Pixel.AlignFrame(frame)
	if not frame or not frame.GetLeft then return end
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left or not bottom then return end
	local px = Pixel.Size(frame)
	local dx = left - floor(left / px + 0.5) * px
	local dy = bottom - floor(bottom / px + 0.5) * px
	if abs(dx) < 1e-4 and abs(dy) < 1e-4 then return end
	local point, relTo, relPoint, x, y = frame:GetPoint(1)
	if not point then return end
	frame:SetPoint(point, relTo, relPoint, x - dx, y - dy)
end
