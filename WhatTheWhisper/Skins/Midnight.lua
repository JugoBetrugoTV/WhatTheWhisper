-- WhatTheWhisper -- Midnight: the default skin, and the one the design is for.
--
-- Dark, but not black, and nowhere near neon. The whole palette is built from
-- one family of desaturated blue-greys with a deliberately small step between
-- each layer: window, sidebar, thread, raised. You should be able to see that
-- the sidebar is a different surface from the thread beside it, and you should
-- have to look to see it. That restraint is most of what separates a calm
-- application from a game panel.
--
-- The accent is used sparingly and never at full saturation. It marks the
-- outgoing bubble, the send button and the unread badge, and nothing else --
-- a dark interface with bright blue sprinkled through it reads as a gamer UI no
-- matter how good the spacing is.
local _, ns = ...

ns.Skins.Register("midnight", {
	name = "Midnight",
	description = "Layered blue-grey with a muted indigo accent.",
	metrics = { sortIndex = 10 },
	colors = {
		-- The four surfaces, darkest to lightest. Each step is about 3% of
		-- lightness: enough to separate, not enough to draw a line.
		bg0            = "#0F1216",   -- the window plate, behind everything
		bg1            = "#14181D",   -- the sidebar
		bg2            = "#181D23",   -- the thread, which is the largest area
		bg3            = "#212831",   -- raised: menus, cards, the search field

		-- The header and the composer sit a half-step below the thread so the
		-- thread is the brightest thing on screen without a border saying so.
		headerBg       = "#14181D",
		composerBg     = "#14181D",
		inputBg        = "#232A34",

		-- Interaction is a change in the surface, never an outline.
		--
		-- Hover can be faint: the cursor is already there and the eye is already
		-- looking. Selected cannot -- it is how you know which conversation you
		-- are in, read from across the window, and with no marker bar beside the
		-- row any more it is the only thing saying so. 0.12 clears the
		-- perceptibility floor on every surface with room to spare.
		hover          = { "#FFFFFF", 0.055 },
		selected       = { "#FFFFFF", 0.12 },
		pressed        = { "#FFFFFF", 0.17 },

		-- Separators exist to be found, not seen. borderStrong is only for the
		-- few places that genuinely need an edge, like a focused field.
		borderSubtle   = { "#FFFFFF", 0.055 },
		borderStrong   = { "#FFFFFF", 0.12 },

		-- Desaturated indigo. The old accent was a 96% saturated blue that
		-- announced itself from across the screen; this one is the same hue with
		-- the volume down, and it still carries the send button perfectly well.
		accent         = "#5C7AE6",
		accentHover    = "#6D89F0",
		accentActive   = "#4C68CC",
		onAccent       = "#FFFFFF",

		-- Four levels, and the gaps between them are what the hierarchy is made
		-- of: a name, a message, a preview and a timestamp should be
		-- distinguishable with the text blurred out.
		textPrimary    = "#E9EDF3",
		textSecondary  = "#9AA4B2",
		textMuted      = "#6E7887",
		textDisabled   = "#464E59",

		-- The incoming bubble is a surface, a step above the thread it sits on
		-- and nothing more. The outgoing one carries the accent, but muted far
		-- past the button version: it is a large area of colour that a long
		-- conversation is read through, and at full strength it is exhausting.
		bubbleIn       = "#303845",
		bubbleInText   = "#E6EAF1",
		bubbleOut      = "#33487E",
		bubbleOutText  = "#EAEFFA",

		success        = "#43B581",
		danger         = "#E05A5F",
		warning        = "#D9A441",

		online         = "#43B581",
		away           = "#D9A441",
		busy           = "#E05A5F",

		link           = "#7D9BF5",
		scrim          = { "#000000", 0.58 },
		shadow         = { "#000000", 0.50 },
		scrollbar      = { "#FFFFFF", 0.15 },
		focusRing      = "#5C7AE6",
	},
})
