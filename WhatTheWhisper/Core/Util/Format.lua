-- WhatTheWhisper -- Time, date and size formatting.

local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local Format = {}
ns.Format = Format

local date, time, floor, format = date, time, math.floor, string.format

local DAY = 86400

--------------------------------------------------------------------------------
-- Settings access that works before the database exists
--------------------------------------------------------------------------------

local function opt(path, fallback)
	local db = ns.db
	if not db or not db.profile then return fallback end
	local node = db.profile
	for key in string.gmatch(path, "[^%.]+") do
		node = node[key]
		if node == nil then return fallback end
	end
	return node
end

--------------------------------------------------------------------------------
-- Clock
--------------------------------------------------------------------------------

function Format.Clock(ts)
	if not ts then return "" end
	if opt("appearance.clock24", true) then
		return date("%H:%M", ts)
	end
	-- %I gives a leading zero; messengers show "9:41 PM", not "09:41 PM".
	local h = tonumber(date("%I", ts)) or 12
	return format("%d:%s %s", h, date("%M", ts), date("%p", ts))
end

function Format.ClockSeconds(ts)
	if not ts then return "" end
	if opt("appearance.clock24", true) then
		return date("%H:%M:%S", ts)
	end
	local h = tonumber(date("%I", ts)) or 12
	return format("%d:%s:%s %s", h, date("%M", ts), date("%S", ts), date("%p", ts))
end

--------------------------------------------------------------------------------
-- Dates
--------------------------------------------------------------------------------

-- Midnight of the day containing `ts`, in local time.
local function dayStart(ts)
	local t = date("*t", ts)
	t.hour, t.min, t.sec = 0, 0, 0
	return time(t)
end
Format.DayStart = dayStart

function Format.IsSameDay(a, b)
	return dayStart(a) == dayStart(b)
end

local WEEKDAY_GLOBALS = {
	_G.WEEKDAY_SUNDAY, _G.WEEKDAY_MONDAY, _G.WEEKDAY_TUESDAY, _G.WEEKDAY_WEDNESDAY,
	_G.WEEKDAY_THURSDAY, _G.WEEKDAY_FRIDAY, _G.WEEKDAY_SATURDAY,
}

local function weekdayName(ts)
	local wday = tonumber(date("%w", ts)) or 0
	local name = WEEKDAY_GLOBALS[wday + 1]
	if name and name ~= "" then return name end
	return date("%A", ts)
end
Format.WeekdayName = weekdayName

function Format.ShortDate(ts)
	local style = opt("appearance.dateFormat", "auto")
	if style == "dmy" then return date("%d.%m.%Y", ts) end
	if style == "mdy" then return date("%m/%d/%Y", ts) end
	if style == "iso" then return date("%Y-%m-%d", ts) end
	local locale = GetLocale and GetLocale() or "enUS"
	if locale == "enUS" or locale == "enGB" then
		return date("%m/%d/%Y", ts)
	elseif locale == "koKR" or locale == "zhCN" or locale == "zhTW" then
		return date("%Y-%m-%d", ts)
	end
	return date("%d.%m.%Y", ts)
end

-- Header used by the date separators in a conversation.
function Format.DayLabel(ts)
	local today = dayStart(time())
	local that = dayStart(ts)
	if that == today then return L["Today"] end
	if that == today - DAY then return L["Yesterday"] end
	if that > today - 6 * DAY then return weekdayName(ts) end
	return Format.ShortDate(ts)
end

-- Compact stamp used in the sidebar rows and tabs.
function Format.ListStamp(ts)
	if not ts or ts == 0 then return "" end
	local today = dayStart(time())
	local that = dayStart(ts)
	if that == today then return Format.Clock(ts) end
	if that == today - DAY then return L["Yesterday"] end
	if that > today - 6 * DAY then
		local name = weekdayName(ts)
		return ns.Text.Sub(name, 1, 3)
	end
	return Format.ShortDate(ts)
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

function Format.Bytes(n)
	if n < 1024 then return format("%d B", n) end
	if n < 1024 * 1024 then return format("%.1f KB", n / 1024) end
	return format("%.1f MB", n / (1024 * 1024))
end

function Format.Count(n)
	if n < 1000 then return tostring(n) end
	if n < 10000 then return format("%.1fk", n / 1000) end
	return format("%dk", floor(n / 1000))
end

function Format.Duration(seconds)
	seconds = floor(seconds or 0)
	if seconds < 60 then return format("%ds", seconds) end
	if seconds < 3600 then return format("%dm", floor(seconds / 60)) end
	if seconds < DAY then return format("%dh", floor(seconds / 3600)) end
	return format("%dd", floor(seconds / DAY))
end

function Format.ExportStamp(ts)
	return date("%Y-%m-%d %H:%M:%S", ts or time())
end
