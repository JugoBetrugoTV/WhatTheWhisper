-- WhatTheWhisper -- Time, date and size formatting.

local _, ns = ...
local L = ns.L

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

-- A timestamp date() can actually work with.
--
-- date() answers nil rather than raising for a value no calendar can hold, so
-- without this every function below either hands a nil to something expecting a
-- string or indexes one as a table -- which is what dayStart did, and it took
-- the whole thread's render with it.
--
-- The way that happens is a damaged saved-variables file: an infinity is still a
-- number, so it passed the type check in Migrations.Repair. That check is
-- stricter now, and this is the floor under it, because timestamps also arrive
-- from the client and from history written by other versions.
-- nil stays nil: "there is no timestamp" is a different answer from "there is
-- one and it is nonsense", and the callers below already say something sensible
-- about the first.
local function usable(ts)
	if ts == nil then return nil end
	ts = tonumber(ts)
	if not ts or date("*t", ts) == nil then return 0 end
	return ts
end
Format.UsableTime = usable

function Format.Clock(ts)
	ts = usable(ts)
	if not ts then return "" end
	if opt("appearance.clock24", true) then
		return date("%H:%M", ts)
	end
	-- %I gives a leading zero; messengers show "9:41 PM", not "09:41 PM".
	local h = tonumber(date("%I", ts)) or 12
	return format("%d:%s %s", h, date("%M", ts), date("%p", ts))
end

--------------------------------------------------------------------------------
-- Dates
--------------------------------------------------------------------------------

-- Midnight of the day containing `ts`, in local time.
local function dayStart(ts)
	local t = date("*t", usable(ts))
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
	local wday = tonumber(date("%w", usable(ts))) or 0
	local name = WEEKDAY_GLOBALS[wday + 1]
	if name and name ~= "" then return name end
	return date("%A", ts)
end
Format.WeekdayName = weekdayName

function Format.ShortDate(ts)
	ts = usable(ts)
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
	ts = usable(ts)
	local today = dayStart(time())
	local that = dayStart(ts)
	if that == today then return L["Today"] end
	if that == today - DAY then return L["Yesterday"] end
	if that > today - 6 * DAY then return weekdayName(ts) end
	return Format.ShortDate(ts)
end

-- Compact stamp for sidebar rows and tabs.
--
-- A full "05.09.2026" needs about 70px at the micro size, which does not fit
-- beside a name and a badge, so anything older than a week collapses to day and
-- month, and only a different year carries a (two digit) year.
function Format.CompactDate(ts)
	ts = usable(ts)
	local style = opt("appearance.dateFormat", "auto")
	local sameYear = date("%Y", ts) == date("%Y")
	if style == "iso" then
		return sameYear and date("%m-%d", ts) or date("%y-%m-%d", ts)
	end
	local locale = GetLocale and GetLocale() or "enUS"
	if style == "mdy" or (style == "auto" and (locale == "enUS" or locale == "enGB")) then
		return sameYear and date("%m/%d", ts) or date("%m/%d/%y", ts)
	end
	return sameYear and date("%d.%m.", ts) or date("%d.%m.%y", ts)
end

function Format.ListStamp(ts)
	ts = usable(ts)
	if not ts or ts == 0 then return "" end
	local today = dayStart(time())
	local that = dayStart(ts)
	if that == today then return Format.Clock(ts) end
	if that == today - DAY then return L["Yesterday"] end
	if that > today - 6 * DAY then
		local name = weekdayName(ts)
		return ns.Text.Sub(name, 1, 3)
	end
	return Format.CompactDate(ts)
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

function Format.Bytes(n)
	if n < 1024 then return format("%d B", n) end
	if n < 1024 * 1024 then return format("%.1f KB", n / 1024) end
	return format("%.1f MB", n / (1024 * 1024))
end

function Format.Duration(seconds)
	seconds = floor(seconds or 0)
	if seconds < 60 then return format("%ds", seconds) end
	if seconds < 3600 then return format("%dm", floor(seconds / 60)) end
	if seconds < DAY then return format("%dh", floor(seconds / 3600)) end
	return format("%dd", floor(seconds / DAY))
end

function Format.ExportStamp(ts)
	ts = usable(ts)
	return date("%Y-%m-%d %H:%M:%S", ts or time())
end
