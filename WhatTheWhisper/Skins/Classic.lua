-- WhatTheWhisper -- Classic: WoW flavoured, not Blizzard framed.
local _, ns = ...

ns.Skins.Register("classic", {
	name = "Classic",
	description = "Warm dark parchment with gold, in a modern layout.",
	metrics = { sortIndex = 60, bubbleRadius = 8, borderScale = 1.4,
		classColorBlend = 0.32 },
	colors = {
		bg0            = "#17120C",
		bg1            = "#1D160E",
		bg2            = "#211A11",
		bg3            = "#2A2116",
		headerBg       = "#1D160E",
		composerBg     = "#1D160E",
		inputBg        = "#2A2116",

		hover          = { "#E0B24C", 0.08 },
		selected       = { "#E0B24C", 0.16 },
		pressed        = { "#E0B24C", 0.24 },

		borderSubtle   = { "#C8A76A", 0.18 },
		borderStrong   = { "#C8A76A", 0.34 },

		accent         = "#E0B24C",
		accentHover    = "#F0C767",
		accentActive   = "#C79A3A",
		onAccent       = "#241A08",

		textPrimary    = "#F2E6CE",
		textSecondary  = "#C3B190",
		textMuted      = "#8C7C5F",
		textDisabled   = "#5F5340",

		bubbleIn       = "#3D3428",
		bubbleInText   = "#F2E6CE",
		bubbleOut      = "#4A3818",
		bubbleOutText  = "#FBF1DC",

		success        = "#69B36B",
		danger         = "#C4494A",
		warning        = "#D9A441",

		online         = "#69B36B",
		away           = "#D9A441",
		busy           = "#C4494A",

		link           = "#6EC7E8",
		scrim          = { "#000000", 0.64 },
		shadow         = { "#000000", 0.62 },
		scrollbar      = { "#C8A76A", 0.30 },
		focusRing      = "#E0B24C",
	},
})
