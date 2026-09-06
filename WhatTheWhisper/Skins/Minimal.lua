-- WhatTheWhisper -- Minimal: almost no borders, a lot of air.
local _, ns = ...

ns.Skins.Register("minimal", {
	name = "Minimal",
	description = "One flat surface, hairlines barely there, generous spacing.",
	metrics = {
		sortIndex = 40,
		bubbleRadius = 8,
		spacingScale = 1.35,
		borderScale = 0.6,
		shadow = 0.4,
		accentBar = false,
	},
	colors = {
		bg0            = "#101215",
		bg1            = "#101215",
		bg2            = "#101215",
		bg3            = "#171A1F",
		headerBg       = "#101215",
		composerBg     = "#101215",
		inputBg        = "#191D23",

		hover          = { "#FFFFFF", 0.04 },
		selected       = { "#FFFFFF", 0.08 },
		pressed        = { "#FFFFFF", 0.12 },

		borderSubtle   = { "#FFFFFF", 0.04 },
		borderStrong   = { "#FFFFFF", 0.09 },

		accent         = "#7C8CF8",
		accentHover    = "#95A2FF",
		accentActive   = "#6675E0",
		onAccent       = "#FFFFFF",

		textPrimary    = "#E6E9EF",
		textSecondary  = "#9AA1AC",
		textMuted      = "#666D78",
		textDisabled   = "#454A52",

		bubbleIn       = { "#FFFFFF", 0.05 },
		bubbleInText   = "#E6E9EF",
		bubbleOut      = { "#7C8CF8", 0.20 },
		bubbleOutText  = "#EDF0FF",

		success        = "#5FC48F",
		danger         = "#E06B70",
		warning        = "#DDB55E",

		online         = "#5FC48F",
		away           = "#DDB55E",
		busy           = "#E06B70",

		link           = "#8FA6FF",
		scrim          = { "#000000", 0.55 },
		shadow         = { "#000000", 0.40 },
		scrollbar      = { "#FFFFFF", 0.14 },
		focusRing      = "#7C8CF8",
	},
})
