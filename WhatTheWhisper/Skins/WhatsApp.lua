-- WhatTheWhisper -- Messenger: warm charcoal with a green accent.
-- Inspired by, not a copy of, the messenger everyone already knows.
local _, ns = ...

ns.Skins.Register("messenger", {
	name = "Messenger",
	description = "Warm charcoal canvas, green accent, deep teal outgoing bubbles.",
	metrics = { sortIndex = 20, bubbleRadius = 14 },
	colors = {
		bg0            = "#0B141A",
		bg1            = "#111B21",
		bg2            = "#0D171E",
		bg3            = "#202C33",
		headerBg       = "#202C33",
		composerBg     = "#111B21",
		inputBg        = "#2A3942",

		hover          = { "#FFFFFF", 0.05 },
		selected       = { "#FFFFFF", 0.09 },
		pressed        = { "#FFFFFF", 0.14 },

		borderSubtle   = { "#FFFFFF", 0.06 },
		borderStrong   = { "#FFFFFF", 0.13 },

		accent         = "#25D366",
		accentHover    = "#3DDB7A",
		accentActive   = "#1FB955",
		onAccent       = "#06251A",

		textPrimary    = "#E9EDEF",
		textSecondary  = "#8696A0",
		textMuted      = "#75858F",
		textDisabled   = "#46545C",

		bubbleIn       = "#202C33",
		bubbleInText   = "#E9EDEF",
		bubbleOut      = "#005C4B",
		bubbleOutText  = "#E9EDEF",

		success        = "#25D366",
		danger         = "#F15C6D",
		warning        = "#FFB02E",

		online         = "#25D366",
		away           = "#FFB02E",
		busy           = "#F15C6D",

		link           = "#53BDEB",
		scrim          = { "#000000", 0.60 },
		shadow         = { "#000000", 0.55 },
		scrollbar      = { "#FFFFFF", 0.16 },
		focusRing      = "#25D366",
	},
})
