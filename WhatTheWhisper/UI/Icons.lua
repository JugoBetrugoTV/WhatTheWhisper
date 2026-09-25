-- WhatTheWhisper -- Semantic icons, and where their art comes from.
--
-- Every glyph in the addon is named for what it *means* -- "send", "search",
-- "mute" -- and never for where its pixels live. That indirection is the whole
-- point of this file: it lets somebody drop a better-looking send.tga into
-- Media/Icons/ and have the send button pick it up on the next reload, without
-- editing a line of Lua, rebuilding a sprite sheet, or touching a UV coordinate.
--
-- Two sources, in order:
--
--   1. Media\Icons\<name>.tga   -- a drop-in file, if one is there
--   2. Art\Icons.tga            -- the built-in sheet, always there
--
-- The second is a real fallback, not a formality: a missing drop-in file has to
-- leave a working button behind rather than an invisible one, because that is
-- what makes replacing the set one file at a time possible.

local _, ns = ...

local Icons = {}
ns.Icons = Icons

-- Where a replacement goes. Named Media rather than Art so it is obvious which
-- of the two folders is the one to put things in, and so an update that ships
-- new built-in art can never overwrite somebody's own.
local CUSTOM_DIR = "Interface\\AddOns\\" .. ns.ADDON_NAME .. "\\Media\\Icons\\"
Icons.CUSTOM_DIR = CUSTOM_DIR

--------------------------------------------------------------------------------
-- Which names are replaceable
--------------------------------------------------------------------------------

-- Only glyphs the UI actually draws. A folder listing a file for every atlas
-- entry would be a folder of homework, most of it for buttons that do not
-- exist, and docs/ICON-REPLACEMENT.md is generated from exactly this table.
--
-- `size` is what the glyph is drawn at, and it is here rather than at the call
-- site so the manifest can state a real number instead of "about 17". Where one
-- drawing is used at two sizes, the larger one is recorded: an asset that
-- survives being shrunk is the one worth asking for.
Icons.REPLACEABLE = {
	-- The composer, which is the most-looked-at control in the addon.
	send = {
		size = "ICON_GLYPH_LG",
		note = "paper plane, pointing up-right",
		use = "The send button in the composer",
	},
	emoji = {
		size = "ICON_GLYPH",
		note = "simple round smile",
		use = "Opens the emoji picker, left of the composer field",
	},

	-- Navigation and window chrome.
	search = {
		size = "ICON_GLYPH",
		note = "magnifier, handle to lower right",
		use = "Search fields, and the header's search-in-thread button",
	},
	close = {
		size = "ICON_GLYPH",
		note = "a thin X, equal-armed",
		use = "Close buttons: window, popout, dialogs, clearing a search",
	},
	minimize = {
		size = "ICON_GLYPH",
		note = "single horizontal bar, low",
		use = "Minimise the window and collapse a popout to its header",
	},
	up = {
		size = "ICON_GLYPH_SM",
		note = "chevron pointing up",
		use = "Previous search match",
	},
	down = {
		size = "ICON_GLYPH_SM",
		note = "chevron pointing down",
		use = "Next search match, jump-to-latest, and dropdown chevrons",
	},
	more = {
		size = "ICON_GLYPH",
		note = "three horizontal dots",
		use = "The overflow menu in the conversation header and tab strip",
	},
	settings = {
		size = "ICON_GLYPH",
		note = "two horizontal sliders",
		use = "Opens the settings window; the Appearance-level settings category",
	},
	popout = {
		size = "ICON_GLYPH",
		note = "square with an arrow leaving it",
		use = "Detach this conversation into its own window",
	},
	grid = {
		size = "ICON_GLYPH",
		note = "four rounded squares",
		use = "Show every open conversation window at once",
	},
	logo = {
		size = "ICON_LOGO",
		note = "the addon's own mark; a speech bubble",
		use = "The addon's mark: title bar and minimap button",
	},

	-- Conversation actions, in the header and the context menus.
	newchat = {
		size = "ICON_GLYPH",
		note = "speech bubble with a plus",
		use = "Start a new conversation, top right of the sidebar",
	},
	chat = {
		size = "ICON_GLYPH",
		note = "plain speech bubble",
		use = "Whisper someone; empty-state illustration",
	},
	info = {
		size = "ICON_GLYPH",
		note = "circled lower-case i",
		use = "Show character details under the conversation header",
	},
	pin = {
		size = "ICON_MARK",
		note = "push-pin, filled",
		use = "Pinned conversation marker, and the pin action",
	},
	unpin = {
		size = "MENU_ICON",
		note = "push-pin, outline only",
		use = "Unpin, in the conversation menu",
	},
	mute = {
		size = "ICON_MARK",
		note = "bell with a slash",
		use = "Muted conversation marker, and the mute action",
	},
	dock = {
		size = "ICON_GLYPH",
		note = "arrow entering a square",
		use = "Put a detached conversation back in the main window",
	},
	bell = {
		size = "ICON_GLYPH",
		note = "plain bell",
		use = "Unmute, in the conversation menu",
	},
	copy = {
		size = "MENU_ICON",
		note = "two overlapping rounded squares",
		use = "Copy name, copy message, copy URL",
	},
	export = {
		size = "MENU_ICON",
		note = "tray with an arrow leaving upward",
		use = "Export or copy a whole conversation",
	},
	trash = {
		size = "MENU_ICON",
		note = "waste bin with a lid",
		use = "Clear or delete a conversation",
	},
	block = {
		size = "MENU_ICON",
		note = "circle with a diagonal bar",
		use = "Ignore this player",
	},
	person = {
		size = "MENU_ICON",
		note = "head and shoulders",
		use = "Nickname actions",
	},
	invite = {
		size = "MENU_ICON",
		note = "head and shoulders with a plus",
		use = "Invite this player to your group",
	},

	-- Delivery state. The smallest things drawn: the first two share a line with
	-- an 11px word under the newest message you sent, and the third stands alone
	-- beside a message that did not go.
	sent = {
		size = "STATUS_ICON",
		note = "single check",
		use = "Delivery line: sent, waiting for the server's echo",
	},
	delivered = {
		size = "STATUS_ICON",
		note = "two overlapping checks",
		use = "Delivery line: the server echoed it back",
	},
	failed = {
		size = "STATUS_ICON",
		note = "circled exclamation or X",
		use = "Delivery: it did not go -- in the line, and beside the message",
	},

	-- The settings sidebar. One per category, and they are read as a column of
	-- small marks rather than individually, so they matter less than the rest --
	-- but they are the first thing a half-replaced set makes look inconsistent.
	history = {
		size = "ICON_GLYPH",
		note = "clock face",
		use = "Settings category: History",
	},
	sounds = {
		size = "ICON_GLYPH",
		note = "speaker with one wave",
		use = "Settings category: Sounds",
	},
	animations = {
		size = "ICON_GLYPH",
		note = "circular arrow",
		use = "Settings category: Animations",
	},
	combat = {
		size = "ICON_GLYPH",
		note = "shield outline",
		use = "Settings category: Combat",
	},
	advanced = {
		size = "ICON_GLYPH",
		note = "keyboard, or a wrench",
		use = "Settings category: Advanced",
	},
	appearance = {
		size = "ICON_GLYPH",
		note = "eye, or a paint drop",
		use = "Settings category: Appearance",
	},
	link = {
		size = "MENU_ICON",
		note = "globe with two meridians",
		use = "Open a link in the browser",
	},
	star = {
		size = "MENU_ICON",
		note = "five-pointed star, outline",
		use = "Add friend",
	},
	reveal = {
		size = "MENU_ICON",
		note = "an open eye",
		use = "Show a message the game has hidden",
	},
	bullet = {
		size = "MENU_ICON",
		note = "a small filled dot",
		use = "The default menu and settings-category mark, when nothing better fits",
	},
	grip = {
		size = "ICON_MARK",
		note = "three short diagonal strokes",
		use = "The window's resize corner",
	},
}

--------------------------------------------------------------------------------
-- Semantic name -> atlas key
--------------------------------------------------------------------------------

-- The built-in sheet was drawn before these names existed, so this is where the
-- two vocabularies meet. Anything not listed falls through to a key of the same
-- name, which is how the rest of the sheet stays reachable.
local ATLAS_ALIAS = {
	emoji = "smiley",
	more = "dots",
	settings = "sliders",
	up = "chevron_up",
	down = "chevron_down",
	newchat = "message_plus",
	chat = "message",
	pin = "pin_filled",
	mute = "bell_off",
	invite = "person_plus",
	sent = "check",
	delivered = "check_double",
	failed = "x_circle",
	unpin = "pin",
	history = "clock",
	sounds = "volume",
	animations = "refresh",
	combat = "shield",
	advanced = "keyboard",
	appearance = "eye",
	link = "globe",
	reveal = "eye",
	bullet = "dot",
	grip = "sort",
}
Icons.ATLAS_ALIAS = ATLAS_ALIAS

function Icons.AtlasKey(name)
	return ATLAS_ALIAS[name] or name
end

--------------------------------------------------------------------------------
-- Is there a drop-in file for this one?
--------------------------------------------------------------------------------

-- The client is the only thing that knows what is on disk, and it will not be
-- asked directly: there is no "does this file exist" call. What there is, is a
-- texture that either takes a path or does not, so that is what gets asked.
--
-- It cannot simply be asked, though, because clients disagree about what they
-- answer for a path that resolves to nothing -- some clear the texture, some
-- keep the string they were handed. Guessing wrong in one direction hands the
-- player an invisible button; guessing wrong in the other means their new icons
-- silently never appear. So the probe is calibrated before it is trusted: a path
-- that certainly exists and one that certainly does not are pushed through it
-- first, and it is only believed if it tells them apart.
local probeTexture, probeWorks

local function calibrate()
	if probeWorks ~= nil then return probeWorks end
	probeWorks = false
	if not _G.UIParent or not _G.CreateFrame then return false end

	local host = CreateFrame("Frame", nil, UIParent)
	host:Hide()
	probeTexture = host:CreateTexture(nil, "BACKGROUND")

	local function answer(path)
		probeTexture:SetTexture(nil)
		local ok = pcall(probeTexture.SetTexture, probeTexture, path)
		if not ok then return nil end
		local got = probeTexture:GetTexture()
		return got
	end

	-- Our own sheet: if this is not there, nothing in the addon is.
	local present = answer(ns.ART .. "Icons")
	-- A name nobody will ever ship. The suffix is not a real file extension,
	-- so it cannot collide with a drop-in either.
	local absent = answer(CUSTOM_DIR .. "__wtw_probe_absent__")

	probeWorks = (present ~= nil) and (absent == nil)
	ns.Debug.Log("icons", "drop-in probe %s (present=%s absent=%s)",
		probeWorks and "usable" or "unusable", tostring(present ~= nil),
		tostring(absent ~= nil))
	return probeWorks
end

-- nil once asked and not found, the path once asked and found.
local resolved = {}

-- Returns the drop-in path for a semantic name, or nil to use the sheet.
function Icons.CustomPath(name)
	if not name or Icons.REPLACEABLE[name] == nil then return nil end
	local cached = resolved[name]
	if cached ~= nil then
		if cached == false then return nil end
		return cached
	end
	if not calibrate() then
		resolved[name] = false
		return nil
	end
	local path = CUSTOM_DIR .. name
	probeTexture:SetTexture(nil)
	local ok = pcall(probeTexture.SetTexture, probeTexture, path)
	local found = ok and probeTexture:GetTexture() ~= nil
	resolved[name] = found and path or false
	if found then
		ns.Debug.Log("icons", "using drop-in art for %s", name)
	end
	return found and path or nil
end

-- Forgets every answer, so a file dropped in during a session is picked up by a
-- /wtw reload rather than needing the client restarted. The probe's calibration
-- is kept: what the client answers for a missing file does not change.
function Icons.Rescan()
	wipe(resolved)
end

-- How many of the replaceable set are being served by drop-in files. Printed by
-- the diagnostics command, so "my icons are not showing up" has an answer that
-- is a number rather than a shrug.
function Icons.CustomCount()
	local custom, total = 0, 0
	for name in pairs(Icons.REPLACEABLE) do
		total = total + 1
		if Icons.CustomPath(name) then custom = custom + 1 end
	end
	return custom, total, probeWorks ~= false
end
