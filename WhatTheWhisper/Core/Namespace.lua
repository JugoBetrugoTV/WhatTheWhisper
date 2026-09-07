-- WhatTheWhisper -- Namespace and design tokens.
--
-- Every number that describes the look of the addon lives here. Nothing in UI/ or
-- Modules/ is allowed to invent a spacing, size, radius, font size or duration; see
-- DESIGN.md for the rationale behind each family of values.

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "1.0.0"

_G.WhatTheWhisper = ns

--------------------------------------------------------------------------------
-- Spacing scale (DESIGN.md §1)
--------------------------------------------------------------------------------

ns.S = {
	XS   = 4,
	SM   = 8,
	MD   = 12,
	LG   = 16,
	XL   = 20,
	XXL  = 24,
	HUGE = 32,
}

--------------------------------------------------------------------------------
-- Corner radii
--------------------------------------------------------------------------------

ns.R = {
	SM   = 4,
	MD   = 8,
	LG   = 12,
	XL   = 16,
	PILL = 999, -- clamped to half the shorter side by Draw.RoundedRect
}

--------------------------------------------------------------------------------
-- Component metrics
--------------------------------------------------------------------------------

ns.SZ = {
	WINDOW_W          = 940,
	WINDOW_H          = 580,
	WINDOW_MIN_W      = 660,
	WINDOW_MIN_H      = 420,
	WINDOW_MAX_W      = 1800,
	WINDOW_MAX_H      = 1200,

	TITLEBAR_H        = 36,

	SIDEBAR_W         = 288,
	SIDEBAR_MIN_W     = 220,
	SIDEBAR_MAX_W     = 420,
	SIDEBAR_COMPACT_AT= 232,
	SIDEBAR_RAIL_W    = 68,
	SIDEBAR_HEADER_H  = 52,

	ROW_H             = 64,
	ROW_H_COMPACT     = 52,

	HEADER_H          = 56,
	TAB_H             = 36,
	TAB_MIN_W         = 96,
	TAB_MAX_W         = 168,

	COMPOSER_MIN_H    = 60,
	COMPOSER_MAX_H    = 140,
	COMPOSER_FIELD_H  = 36,

	AVATAR_LG         = 40,
	AVATAR_MD         = 32,
	AVATAR_SM         = 24,
	AVATAR_XS         = 18,

	BADGE_H           = 18,
	STATUS_DOT        = 8,

	ICON_BTN          = 30,
	ICON_GLYPH        = 16,
	ICON_GLYPH_SM     = 14,
	SEND_BTN          = 32,

	SCROLLBAR_W       = 4,
	SCROLLBAR_HIT     = 10,

	LIST_PAD_X        = 20,
	LIST_PAD_Y        = 16,

	BUBBLE_MAX_PCT    = 0.66,
	BUBBLE_MAX_ABS    = 560,
	BUBBLE_PAD_X      = 11,
	BUBBLE_PAD_Y      = 7,
	BUBBLE_TAIL_R     = 4,

	MSG_GAP_TIGHT     = 2,
	MSG_GAP_GROUP     = 12,
	MSG_GAP_DATE      = 20,

	MENU_ITEM_H       = 28,
	MENU_MIN_W        = 168,
	MENU_ICON         = 14,

	TOAST_W           = 320,
	TOAST_H           = 62,

	SETTINGS_W        = 860,
	SETTINGS_H        = 600,
	SETTINGS_NAV_W    = 200,
	SETTINGS_ROW_H    = 32,
	SETTINGS_MAX_CONTENT = 560,

	TOGGLE_W          = 36,
	TOGGLE_H          = 20,
	TOGGLE_KNOB       = 16,

	SLIDER_TRACK      = 4,
	SLIDER_THUMB      = 14,

	POPOUT_W          = 380,
	POPOUT_H          = 460,
	POPOUT_MIN_W      = 280,
	POPOUT_MIN_H      = 240,
	POPOUT_HEADER_H   = 48,

	SNAP_DISTANCE     = 12,
}

--------------------------------------------------------------------------------
-- Type scale
--------------------------------------------------------------------------------

ns.T = {
	MICRO   = 11,
	SMALL   = 12,
	BODY    = 14,
	TITLE   = 16,
	DISPLAY = 18,
}

ns.LINE_SPACING = 3

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

ns.MOTION = {
	FAST   = 0.10,
	BASE   = 0.16,
	SLOW   = 0.24,
	WINDOW = 0.28,
}

-- Multiplier applied to every duration, indexed by the "animations" setting.
ns.MOTION_SCALE = {
	off     = 0,
	reduced = 0.6,
	normal  = 1,
	fancy   = 1,
}

--------------------------------------------------------------------------------
-- Domain constants
--------------------------------------------------------------------------------

-- Message direction
ns.DIR_IN  = 0
ns.DIR_OUT = 1

-- Message kind
ns.MSG_WHISPER = 1
ns.MSG_BNET    = 2
ns.MSG_SYSTEM  = 3
ns.MSG_AFK     = 4
ns.MSG_DND     = 5

-- Delivery state for outgoing messages
ns.SEND_PENDING = 0
ns.SEND_OK      = 1
ns.SEND_FAILED  = 2

-- Grouping window: consecutive messages from the same sender inside this many
-- seconds collapse into one visual group.
ns.GROUP_WINDOW = 300

-- Hard whisper payload limit in bytes, enforced by the server.
ns.MAX_MESSAGE_BYTES = 255

--------------------------------------------------------------------------------
-- Small shared helpers
--------------------------------------------------------------------------------

local CHAT_PREFIX = "|cff5A7CFAWhatTheWhisper|r: "

function ns.Print(...)
	local chat = _G.DEFAULT_CHAT_FRAME
	if not chat then return end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	chat:AddMessage(CHAT_PREFIX .. table.concat(parts, " "))
end

-- Non-fatal error reporting. Never let a UI glitch break the whole event
-- handler; Debug.NoteError also counts these, and past a threshold the addon
-- stops hiding whispers from the chat frame.
function ns.SoftError(context, err)
	if ns.Debug then
		ns.Debug.NoteError(context, err)
		return
	end
	if ns.db and ns.db.profile and ns.db.profile.advanced and ns.db.profile.advanced.debug then
		ns.Print("|cffE5484Derror|r in " .. tostring(context) .. ": " .. tostring(err))
	end
end

-- pcall wrapper used around every UI callback that is reachable from a game event.
function ns.Guard(context, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		ns.SoftError(context, err)
	end
	return ok
end
