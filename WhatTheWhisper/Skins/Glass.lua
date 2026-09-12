-- WhatTheWhisper -- Glass: translucent layers floating over the game.
local _, ns = ...

ns.Skins.Register("glass", {
	name = "Glass",
	description = "Translucent surfaces, stronger hairlines, soft depth.",
	metrics = {
		sortIndex = 50,
		bubbleRadius = 14,
		shadow = 1.4,
		surfaceAlpha = 0.78,
	},
	colors = {
		bg0            = { "#0E1116", 0.72 },
		bg1            = { "#141922", 0.62 },
		bg2            = { "#101620", 0.55 },
		bg3            = { "#1E2531", 0.86 },
		headerBg       = { "#141922", 0.70 },
		composerBg     = { "#141922", 0.70 },
		inputBg        = { "#232B39", 0.90 },

		hover          = { "#FFFFFF", 0.09 },
		selected       = { "#FFFFFF", 0.15 },
		pressed        = { "#FFFFFF", 0.20 },

		borderSubtle   = { "#FFFFFF", 0.12 },
		borderStrong   = { "#FFFFFF", 0.22 },

		accent         = "#8AA6FF",
		accentHover    = "#A3B9FF",
		accentActive   = "#7591F0",
		onAccent       = "#0C1220",

		textPrimary    = "#F0F3F8",
		textSecondary  = "#B6BECC",
		textMuted      = "#818A99",
		textDisabled   = "#565E6B",

		bubbleIn       = { "#2A3341", 0.86 },
		bubbleInText   = "#EDF1F7",
		bubbleOut      = { "#3E5490", 0.88 },
		bubbleOutText  = "#F2F6FF",

		success        = "#5CD69B",
		danger         = "#F26B70",
		warning        = "#F0C463",

		online         = "#5CD69B",
		away           = "#F0C463",
		busy           = "#F26B70",

		link           = "#9DB6FF",
		scrim          = { "#000000", 0.50 },
		shadow         = { "#000000", 0.70 },
		scrollbar      = { "#FFFFFF", 0.26 },
		focusRing      = "#8AA6FF",
	},
})
