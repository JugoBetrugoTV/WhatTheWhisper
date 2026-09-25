-- WhatTheWhisper -- SavedVariables defaults.
--
-- Settings live in WhatTheWhisperDB (AceDB, profile aware). Message history
-- lives in a *separate* SavedVariable so that copying or resetting a profile can
-- never destroy or duplicate thousands of messages.

local _, ns = ...

ns.defaults = {
	profile = {
		enabled = true,

		layout = {
			mode          = "sidebar",   -- sidebar | tabbed | hybrid
			sidebarWidth  = ns.SZ.SIDEBAR_W,
			width         = ns.SZ.WINDOW_W,
			height        = ns.SZ.WINDOW_H,
			point         = nil,         -- {point, x, y} relative to UIParent centre
			locked        = false,
			remember      = true,
			snap          = true,
			tabAutoClose  = 0,           -- minutes; 0 = never
			tabBlink      = true,
			tabAutoOpen   = true,
			maxTabs       = 8,
			-- The character details panel under the header. On by default: the
			-- most common complaint about a whisper window is not knowing who
			-- you are talking to.
			showProfile   = true,
		},

		appearance = {
			-- English out of the box, on every client. "auto" is offered in the
			-- picker and follows the game's language instead; it is not the
			-- default because the addon's own English is the text that has been
			-- read, and a player who wants their own language can say so in one
			-- click. Overriding the client at all is the whole reason the
			-- strings do not live in AceLocale, which keeps only the client's
			-- own language and discards the rest at load.
			locale         = "enUS",
			skin           = "midnight",
			font           = false,      -- false = the client's own chat font
			fontScale      = 0,          -- -2 .. +4, applied to the whole type scale
			opacity        = 0.97,
			bubbleOpacity  = 1,
			radius         = 1,          -- 0 square, 1 normal, 2 round
			density        = "comfortable", -- comfortable | compact
			classColors    = true,
			timestamps     = true,
			clock24        = true,
			dateFormat     = "auto",     -- auto | dmy | mdy | iso
			avatars        = true,
			avatarStyle    = "auto",     -- auto | class | initials
			bubbles        = true,
			grouping       = true,
			dateSeparators = true,
			spacing        = 1,          -- 0 tight, 1 normal, 2 airy
			shadows        = true,
			hoverTimestamp = true,
		},

		messages = {
			openOnSend         = true,
			autoSwitch         = false,
			-- A messenger that stays shut when somebody writes to you is a
			-- messenger you miss messages in, so both directions open it: a
			-- whisper arriving, and you starting to type one.
			openOnWhisper      = true,
			-- "messenger": the main window, on that thread. "window": the thread
			-- in a small window of its own, one per person, the way WIM does it.
			openAs             = "messenger",
			openOnCompose      = true,
			hideFromChatFrame  = true,
			markReadOnFocus    = true,
			deliveryStatus     = true,
			showRealm          = "cross", -- never | cross | always
		},

		history = {
			retention          = "30d",   -- off | session | 1d | 7d | 30d | forever
			maxPerConversation = 2000,
			maxConversations   = 200,
		},

		sounds = {
			newMessage     = "TELL_MESSAGE",
			hiddenMessage  = "TELL_MESSAGE",
			mention        = "RAID_WARNING",
			openConv       = "none",
			closeConv      = "none",
			cooldown       = 5,
			customFile     = "",
			dnd            = false,
			muteCombat     = true,
			muteDungeon    = false,
			muteRaid       = true,
			muteArena      = true,
			muteBattleground = true,
		},

		notifications = {
			toasts     = true,
			position   = "topright",     -- topright | topleft | bottomright | bottomleft
			duration   = 5,
			badge      = true,
			summarise  = true,
			flashClient = true,
			maxVisible = 3,
		},

		animations = {
			level        = "normal",     -- off | reduced | normal | fancy
			smoothScroll = true,
		},

		combat = {
			onEnter     = "nothing",     -- nothing | fade | minimize | hide
			onLeave     = "restore",     -- restore | stay
			fadeOpacity = 0.35,
		},

		links = {
			detect = true,
			color  = nil,                -- nil = the skin's link colour
		},

		emoticons = {
			style       = "images",      -- text | colored | images
			raidMarkers = true,
			recent      = {},
		},

		advanced = {
			debug   = false,
			minimap = { hide = false, angle = 205 },
		},

		-- Per-conversation popout geometry, keyed by conversation id.
		popouts = {},
		-- A local nickname per conversation, keyed by the conversation's own id.
		-- Display only: the id is still the id, and a message still goes to the
		-- character it was always going to.
		aliases = {},
	},

	-- Account wide, deliberately outside the profile: a first-run hint that
	-- reappeared every time somebody made a new profile would not be a hint.
	global = {
		seenWelcome = false,
	},
}

--------------------------------------------------------------------------------
-- History container
--------------------------------------------------------------------------------

-- Shape of WhatTheWhisperHistoryDB:
--
--   version = 1
--   chars = {
--     ["Player-Realm"] = {
--       conv = {
--         ["Thrall-Blackrock"] = {
--           n  = "Thrall",          display name
--           c  = "SHAMAN",          class file, when known
--           bt = "Tag#1234",        BattleTag, Battle.net conversations only
--           t  = 1725651660,        last activity
--           u  = 2,                 unread count
--           p  = true,              pinned
--           m  = false,             muted
--           lv = 70,                last known level
--           f  = "Horde",           faction, when derivable
--           msgs = {                array, oldest first
--             { ts, dir, text, kind, status },
--           },
--         },
--       },
--     },
--   }
--
-- Message tuples are plain arrays on purpose: the SavedVariables writer emits
-- them as {1725651660,0,"hi",1} instead of a keyed table, which roughly halves
-- the file size for a large history.

ns.MSG_TS, ns.MSG_DIR, ns.MSG_TEXT, ns.MSG_KIND, ns.MSG_STATUS = 1, 2, 3, 4, 5
-- Two separate facts about a message the game's own chat filter has hidden, and
-- they have to be separate because one outlives the session and the other does
-- not.
--
--   MSG_CENSORED  durable. "This is hidden." Written to saved variables, read
--                 back after a reload, and the only thing display depends on --
--                 so a hidden message can never quietly turn back into the raw
--                 placeholder because an id went stale.
--   MSG_LINE      ephemeral. "This session still has a line we could ask about."
--                 A chat line id means nothing after a reload, so it is dropped
--                 when history is loaded and the reveal is simply not offered.
ns.MSG_CENSORED, ns.MSG_LINE = 6, 7

ns.RETENTION_SECONDS = {
	["off"]      = 0,
	["session"]  = -1,      -- kept in memory only
	["1d"]       = 86400,
	["7d"]       = 604800,
	["30d"]      = 2592000,
	["forever"]  = -2,
}
