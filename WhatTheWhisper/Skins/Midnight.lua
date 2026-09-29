-- WhatTheWhisper -- Midnight: iOS Dark, and the skin the design is drawn for.
--
-- Apple's own system colours, by their own names and their own values. Using the
-- real numbers rather than numbers near them is most of the difference between
-- "iOS-ish" and iOS: these are the greys and blues a player has been looking at
-- on a phone every day for years, and the eye notices when they are almost right.
--
--   systemBackground            #000000
--   secondarySystemBackground   #1C1C1E     (systemGray6)
--   tertiarySystemBackground    #2C2C2E     (systemGray5)
--   systemGray4 / 3 / 2         #3A3A3C  #48484A  #636366
--   label                       #FFFFFF
--   secondary / tertiary label  #EBEBF5 at 60% / 30%
--   opaqueSeparator             #38383A
--   systemBlue / Green / Red    #0A84FF  #30D158  #FF453A
--
-- The thread is pure black and the sidebar is one step off it, which is how
-- Messages is built on an iPad: the conversation is the deepest surface and
-- everything else sits above it.
local _, ns = ...

ns.Skins.Register("midnight", {
	name = "Midnight",
	description = "iOS Dark: Apple's system greys with systemBlue.",
	metrics = { sortIndex = 10 },
	colors = {
		bg0            = "#000000",   -- the window plate
		bg1            = "#1C1C1E",   -- the sidebar
		bg2            = "#000000",   -- the thread, the way Messages does it
		bg3            = "#1C1C1E",   -- raised: menus, grouped lists, cards

		-- The navigation bar and the composer's strip. The composer shares the
		-- thread's black on purpose: in Messages the field floats on the
		-- conversation rather than sitting in a bar of its own.
		headerBg       = "#1C1C1E",
		composerBg     = "#000000",
		inputBg        = "#2C2C2E",

		-- Interaction is a change of surface, never an outline. The values are
		-- picked so the *selected* row clears the perceptibility floor against
		-- both the sidebar and a raised panel: it is the only thing saying which
		-- conversation you are in.
		hover          = { "#FFFFFF", 0.06 },
		selected       = { "#FFFFFF", 0.13 },
		pressed        = { "#FFFFFF", 0.18 },

		-- iOS separators, which are lighter than most people expect and still
		-- almost invisible until you look for one.
		borderSubtle   = { "#FFFFFF", 0.09 },
		borderStrong   = { "#FFFFFF", 0.16 },

		accent         = "#0A84FF",   -- systemBlue, dark
		accentHover    = "#3D9BFF",
		accentActive   = "#0768CC",
		onAccent       = "#FFFFFF",

		-- Apple's label ramp. Not four greys: one colour at four opacities,
		-- which is why secondary text sits in the same family as primary instead
		-- of looking like a different decision.
		textPrimary    = "#FFFFFF",
		textSecondary  = { "#EBEBF5", 0.60 },
		textMuted      = { "#EBEBF5", 0.40 },
		textDisabled   = { "#EBEBF5", 0.25 },

		-- iMessage. The incoming bubble is systemGray5, a step off the black
		-- thread and nothing more. The outgoing one is blue -- but a little
		-- deeper than systemBlue, because white on #0A84FF measures 3.65:1 and
		-- message text is the thing in this addon most likely to be read at two
		-- in the morning. #0A6FD8 is the same blue with the readability, at
		-- 4.91:1, and beside the send button nobody can tell them apart.
		bubbleIn       = "#2C2C2E",
		bubbleInText   = "#FFFFFF",
		bubbleOut      = "#0A6FD8",
		bubbleOutText  = "#FFFFFF",

		success        = "#30D158",   -- systemGreen
		danger         = "#FF453A",   -- systemRed
		warning        = "#FF9F0A",   -- systemOrange

		online         = "#30D158",
		away           = "#FF9F0A",
		busy           = "#FF453A",

		link           = "#0A84FF",
		scrim          = { "#000000", 0.60 },
		shadow         = { "#000000", 0.55 },
		scrollbar      = { "#EBEBF5", 0.18 },
		focusRing      = "#0A84FF",
	},
})
