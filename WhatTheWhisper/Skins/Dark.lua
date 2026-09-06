-- WhatTheWhisper -- Dark: neutral greys, no chroma anywhere.
local _, ns = ...

ns.Skins.Register("dark", {
	name = "Dark",
	description = "Pure neutral greys for people who do not want a colour.",
	metrics = { sortIndex = 30 },
	colors = {
		bg0            = "#121212",
		bg1            = "#171717",
		bg2            = "#1B1B1B",
		bg3            = "#232323",
		headerBg       = "#171717",
		composerBg     = "#171717",
		inputBg        = "#232323",

		hover          = { "#FFFFFF", 0.06 },
		selected       = { "#FFFFFF", 0.12 },
		pressed        = { "#FFFFFF", 0.17 },

		borderSubtle   = { "#FFFFFF", 0.08 },
		borderStrong   = { "#FFFFFF", 0.16 },

		accent         = "#E4E4E4",
		accentHover    = "#FFFFFF",
		accentActive   = "#C9C9C9",
		onAccent       = "#171717",

		textPrimary    = "#EDEDED",
		textSecondary  = "#A8A8A8",
		textMuted      = "#767676",
		textDisabled   = "#4E4E4E",

		bubbleIn       = "#242424",
		bubbleInText   = "#EDEDED",
		bubbleOut      = "#3A3A3A",
		bubbleOutText  = "#F5F5F5",

		success        = "#7BC98E",
		danger         = "#D97070",
		warning        = "#D9BC70",

		online         = "#7BC98E",
		away           = "#D9BC70",
		busy           = "#D97070",

		link           = "#9CB8DE",
		scrim          = { "#000000", 0.66 },
		shadow         = { "#000000", 0.60 },
		scrollbar      = { "#FFFFFF", 0.20 },
		focusRing      = "#E4E4E4",
	},
})
