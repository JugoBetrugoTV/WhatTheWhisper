-- WhatTheWhisper -- Midnight: the default skin.
-- Very dark blue-grey layers, indigo accent, high-contrast text.
local _, ns = ...

ns.Skins.Register("midnight", {
	name = "Midnight",
	description = "Deep blue-grey with an indigo accent.",
	metrics = { sortIndex = 10 },
	colors = {
		bg0            = "#0E1116",
		bg1            = "#12161C",
		bg2            = "#161B22",
		bg3            = "#1C222B",
		headerBg       = "#12161C",
		composerBg     = "#12161C",
		inputBg        = "#1C222B",

		hover          = { "#FFFFFF", 0.06 },
		selected       = { "#FFFFFF", 0.11 },
		pressed        = { "#FFFFFF", 0.16 },

		borderSubtle   = { "#FFFFFF", 0.07 },
		borderStrong   = { "#FFFFFF", 0.14 },

		accent         = "#5A7CFA",
		accentHover    = "#7190FF",
		accentActive   = "#4A6AE0",
		onAccent       = "#FFFFFF",

		textPrimary    = "#E8ECF2",
		textSecondary  = "#A7B0BE",
		textMuted      = "#79828F",
		textDisabled   = "#4A515C",

		bubbleIn       = "#1E2530",
		bubbleInText   = "#E4E9F0",
		bubbleOut      = "#2C3F6B",
		bubbleOutText  = "#EAF0FF",

		success        = "#3FBF7F",
		danger         = "#E5484D",
		warning        = "#E8B84B",

		online         = "#3FBF7F",
		away           = "#E8B84B",
		busy           = "#E5484D",

		link           = "#7AA2FF",
		scrim          = { "#000000", 0.62 },
		shadow         = { "#000000", 0.55 },
		scrollbar      = { "#FFFFFF", 0.18 },
		focusRing      = "#5A7CFA",
	},
})
