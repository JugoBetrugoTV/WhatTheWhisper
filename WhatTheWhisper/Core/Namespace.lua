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

-- The iOS corner ladder. Apple uses a small set of radii and uses them
-- consistently, which is most of why its interfaces look like one thing: 8 for a
-- small control, 12 for a grouped list or a row, 16 for a panel, 22 for a sheet.
--
-- Nothing here is decorative. The radius is most of what separates "an
-- application" from "a frame with a border", and the specific values are most of
-- what separates iOS from every other rounded interface.
ns.R = {
	SM   = 8,    -- badges, inline chips, small controls
	MD   = 12,   -- grouped list groups, rows, menu items
	LG   = 16,   -- panels, windows, popouts
	XL   = 22,   -- sheets and dialogs
	PILL = 999,  -- clamped to half the shorter side by Draw.RoundedRect
}

--------------------------------------------------------------------------------
-- Component metrics
--------------------------------------------------------------------------------

-- The smallest thing a mouse should have to hit. Roughly 5mm on a 1080p 24"
-- display at scale 1.0. Controls drawn smaller than this keep their look and
-- grow their hit rect to match.
ns.MIN_HIT = 20

ns.SZ = {
	-- Wider and calmer. A desktop messenger is a two-column application, and at
	-- 940 the thread column was narrow enough that most messages wrapped -- which
	-- is the single thing that made this read as a game panel rather than as one.
	WINDOW_W          = 1040,
	WINDOW_H          = 640,
	WINDOW_MIN_W      = 700,
	WINDOW_MIN_H      = 440,
	WINDOW_MAX_W      = 1800,
	WINDOW_MAX_H      = 1200,

	TITLEBAR_H        = 34,

	-- Roughly 30% of the default width, which is where every desktop messenger
	-- lands: enough for a name, a preview and a time without any of them
	-- truncating on an ordinary conversation.
	SIDEBAR_W         = 320,
	SIDEBAR_MIN_W     = 240,
	SIDEBAR_MAX_W     = 440,
	SIDEBAR_COMPACT_AT= 248,
	SIDEBAR_RAIL_W    = 76,
	SIDEBAR_HEADER_H  = 60,
	-- The iOS search field, at the height iOS draws one.
	SEARCH_H          = 36,

	-- A 48px avatar with 14px above and below it. The row height is that sum
	-- rather than a number chosen first and filled afterwards, and it lands
	-- where a two-line iOS list row lands.
	ROW_H             = 76,
	ROW_H_COMPACT     = 60,

	HEADER_H          = 64,
	TAB_H             = 36,
	TAB_MIN_W         = 96,
	TAB_MAX_W         = 168,

	COMPOSER_MIN_H    = 66,
	COMPOSER_MAX_H    = 160,
	-- The rounded field itself, at a comfortable single line of 17px body.
	COMPOSER_FIELD_H  = 42,

	AVATAR_LG         = 48,
	AVATAR_MD         = 40,
	AVATAR_SM         = 28,
	AVATAR_XS         = 20,

	BADGE_H           = 20,
	-- The delivery mark: in the receipt line under the newest message you sent,
	-- and beside a message that did not go. Still the smallest glyph the UI
	-- draws -- it shares a line with an 11px word and must not out-shout it --
	-- but a tick nobody can resolve is a tick that may as well not be drawn.
	STATUS_ICON       = 16,
	STATUS_DOT        = 7,

	-- An icon button is a hit target with a mark inside it. The two sizes are
	-- independent on purpose: the target is what the mouse needs and the glyph is
	-- what the eye needs, and they are not the same number.
	--
	-- The glyph fills about seven tenths of its button. That is the proportion
	-- the messengers use, and it is deliberately fuller than a system toolbar's:
	-- a toolbar icon is drawn at a weight the operating system controls, and
	-- these are drawn by whoever made the file. At 56% the marks were technically
	-- present and practically unreadable -- a row of small grey suggestions. The
	-- button's footprint did not change, so nothing around them moved.
	ICON_BTN          = 32,
	-- The tighter button used in title bars and search bars, where a full size
	-- one would crowd the row it sits in.
	ICON_BTN_SM       = 28,
	-- The mark inside the composer's send button, which is the one glyph in the
	-- addon that is meant to be noticed.
	ICON_GLYPH_LG     = 24,
	ICON_GLYPH        = 22,
	ICON_GLYPH_SM     = 19,
	-- Only for glyphs inside something already small, like a tab's close mark.
	ICON_GLYPH_XS     = 15,
	-- The pin and mute marks beside a name in the sidebar, and the resize grip.
	-- These annotate a row rather than being read on their own, so they stay
	-- below the button glyphs -- but they are marks with a meaning, not texture,
	-- and at 15 the shape was dissolving.
	ICON_MARK         = 18,
	-- The logo, wherever it is drawn as a mark rather than as art.
	ICON_LOGO         = 22,
	SEND_BTN          = 36,

	SCROLLBAR_W       = 4,
	SCROLLBAR_HIT     = 10,
	-- However long the list, the thing you grab stays a comfortable grab. 28 was
	-- proportional and awkward in a thread of a few hundred messages.
	SCROLLBAR_MIN_THUMB = 32,

	LIST_PAD_X        = 24,
	LIST_PAD_Y        = 20,

	BUBBLE_MAX_PCT    = 0.68,
	BUBBLE_MAX_ABS    = 620,
	BUBBLE_PAD_X      = 12,
	BUBBLE_PAD_Y      = 8,
	BUBBLE_TAIL_R     = 5,

	-- The delivery line under the newest message you sent. It belongs to the
	-- bubble above it rather than to the thread, so it sits closer than any two
	-- messages ever do -- MSG_GAP_TIGHT is already the tightest gap between two
	-- separate things, and this is one thing.
	RECEIPT_GAP       = 3,
	RECEIPT_ICON_GAP  = 4,

	MSG_GAP_TIGHT     = 3,
	MSG_GAP_GROUP     = 14,
	-- The air around a centred time marker. It is the thread's paragraph break:
	-- everything below it was said after a pause long enough to be worth naming.
	MSG_GAP_DATE      = 24,
	-- A word and a time set side by side read as one label at a word's space
	-- apart, and as two labels at anything more.
	SEP_WORD_GAP      = 4,

	-- An iOS context menu row.
	MENU_ITEM_H       = 44,
	MENU_MIN_W        = 184,
	-- A menu entry's mark is read as part of the line it labels, so it is set
	-- against the entry's text rather than against a button.
	MENU_ICON         = 20,

	-- A notification, not a dialog. Wide enough for a name and one line of
	-- message, and no taller than that needs.
	TOAST_W           = 332,
	TOAST_H           = 68,

	SETTINGS_W        = 900,
	SETTINGS_H        = 640,
	SETTINGS_NAV_W    = 216,
	-- A settings row is a label, an optional description under it, and a control
	-- on the right. 44 is the iOS row height, and it is the right one here for
	-- the same reason: it is what a comfortable tap or click target looks like
	-- when the thing being clicked is the whole row.
	SETTINGS_ROW_H    = 44,   -- the iOS table row, unchanged: it was already this
	-- The category list on the left is a list of destinations, not of controls,
	-- so its rows are tighter than the settings rows they lead to.
	SETTINGS_NAV_ROW_H = 36,
	SETTINGS_GROUP_GAP = 28,
	SETTINGS_MAX_CONTENT = 600,

	-- Empty states: a large, faded glyph over two centred lines. Shared so that
	-- "no conversation selected" and "no settings match" are the same thing
	-- twice rather than two designs that happen to look similar.
	EMPTY_ICON        = 44,
	-- The same idea at panel scale, for an empty sidebar or an empty thread,
	-- where the full-size mark would be the loudest thing on screen.
	EMPTY_ICON_SM     = 36,
	EMPTY_TEXT_W      = 340,

	-- The iOS switch, at the size iOS draws it: 51 x 31 with a 27 knob. Not
	-- proportions near those -- these exact ones. It is the single most
	-- recognisable control Apple ships, and at 44 x 26 it read as something
	-- imitating a switch rather than as one.
	TOGGLE_W          = 51,
	TOGGLE_H          = 31,
	TOGGLE_KNOB       = 27,

	-- A segmented control: a track with one raised thumb sliding between equal
	-- segments. SEGMENT_RIM is the gap between the thumb and the track's edge,
	-- and it is what makes the thumb read as sitting *in* the track.
	SEGMENT_H         = 32,
	SEGMENT_RIM       = 2,
	SEGMENT_MIN_W     = 56,

	SLIDER_TRACK      = 4,
	SLIDER_THUMB      = 14,
	-- The value readout to the right of the track, and the gap before it.
	SLIDER_VALUE_W    = 42,
	SLIDER_VALUE_GAP  = 4,

	-- A detached thread is a small messenger window, so it is shaped like one:
	-- taller than it is wide, with room for a dozen messages above the composer.
	POPOUT_W          = 400,
	POPOUT_H          = 520,
	POPOUT_MIN_W      = 300,
	POPOUT_MIN_H      = 260,
	POPOUT_HEADER_H   = 52,

	-- The sidebar splitter is a grab handle, not a gutter: it is centred on the
	-- boundary and only the hairline is drawn, so the panels stay flush.
	SPLITTER_HIT      = 12,

	-- The corner resize handle. 16 was too small to hit reliably, and 20 left the
	-- mark inside it one pixel from the edge once the glyphs were enlarged --
	-- which reads as a rendering fault rather than as a handle. 24 is a better
	-- grab target and gives the mark room to be a mark.
	RESIZE_GRIP       = 24,

	-- The bar along the top edge of the active tab. The only place left that
	-- marks a selection with a drawn bar rather than with the surface under it:
	-- tabs sit edge to edge on a strip their own colour, so there is no surface
	-- change available to carry it.
	TAB_MARKER_H      = 3,

	-- The toast's remaining-time hairline, riding inside the bottom radius.
	TOAST_PROGRESS_H  = 2,
	TOAST_PROGRESS_INSET = 3,

	SNAP_DISTANCE     = 12,
}

--------------------------------------------------------------------------------
-- Type scale
--------------------------------------------------------------------------------

-- Apple's text ramp, by the names Apple gives the steps. Using the real numbers
-- rather than numbers near them is the difference between "iOS-ish" and iOS:
-- every size below is a text style the system actually ships, and the gaps
-- between them are the ones the eye has been trained on for a decade.
--
-- The one liberty taken is that iOS separates a title from a body with *weight*
-- as often as with size, and the game ships no semibold face for most of the
-- fonts a player can pick. So where Apple would set a header at 17 semibold over
-- 17 regular, this steps up a size instead.
--
-- Nothing is smaller than 11. A timestamp that has to be squinted at is not
-- quiet, it is unreadable, and those are different things.
ns.T = {
	MICRO   = 11,   -- caption 2: timestamps, delivery state, counters
	SMALL   = 13,   -- footnote: descriptions, section headers
	SUBHEAD = 15,   -- subheadline: previews, control values, secondary rows
	BODY    = 17,   -- body: message text, list titles, settings labels
	TITLE   = 20,   -- title 3: the name in a conversation header
	DISPLAY = 24,   -- title 2: empty states
}

-- Message text is read in paragraphs, so it is set looser than a label. iOS body
-- is 17 over a 22 line box; 5px of leading on a 17px face lands there.
ns.LINE_SPACING = 5

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

-- How long the thread has to have been quiet before the time is worth writing
-- down again. Messages carry no time of their own any more -- a centred marker
-- above a group carries it for everything under it, which is what Messages does
-- and is most of why a thread there reads as a conversation rather than a log.
--
-- An hour, not the five minutes that decide grouping. Grouping asks "is this the
-- same breath"; this asks "is this the same sitting", and a marker at every
-- five minute gap would put a clock between almost every pair of messages --
-- which is the log this exists to stop being.
ns.STAMP_WINDOW = 3600

-- Hard whisper payload limit in bytes, enforced by the server.
ns.MAX_MESSAGE_BYTES = 255

-- Written beside every file export so that somebody opening the saved variables
-- file months later knows what they are looking at.
ns.EXPORT_README =
	"Conversations exported from WhatTheWhisper. Each entry under 'exports' "
	.. "holds one conversation as plain text. Delete this whole variable, or "
	.. "use the Clear button in the export window, when you no longer need it."

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
