-- WhatTheWhisper -- Aurora: ink-violet, with a gradient where there is something
-- to say.
--
-- The messenger's own look rather than a phone's. Midnight is Apple's system
-- greys and is the safe skin; this is the one with a point of view: a deep violet
-- ink for the surfaces, a vivid violet-to-blue for what is yours -- your bubbles,
-- the send button, the unread count -- and cool lavender-white for text, so the
-- palette is one family from the background to the type instead of grey with an
-- accent on it.
--
-- Every pair is chosen against the ones it sits on, not by eye: white on the top
-- of the outgoing bubble is 5.1:1, and the quieter text steps keep the contrast
-- the audit asks of them on the thread and on the sidebar.
local _, ns = ...

ns.Skins.Register("aurora", {
	name = "Aurora",
	description = "Ink violet with a violet-to-blue gradient for your own messages.",
	metrics = { sortIndex = 5, bubbleRadius = 18, classColorBlend = 0.08, headerWash = 0.26 },
	colors = {
		bg0            = "#0A0916",   -- the window plate
		bg1            = "#100E20",   -- the sidebar
		bg2            = "#0B0A18",   -- the thread, at its top...
		bg2To          = "#15112E",   -- ...and at its bottom, where it meets the composer
		bg3            = "#1A1736",   -- raised: menus, cards
		headerBg       = "#100E20",
		composerBg     = "#15112E",   -- the thread's bottom, so the two are one surface
		inputBg        = "#211D40",

		hover          = { "#B8ADFF", 0.07 },
		selected       = { "#9C8BFF", 0.24 },
		pressed        = { "#9C8BFF", 0.32 },

		borderSubtle   = { "#B8ADFF", 0.10 },
		borderStrong   = { "#B8ADFF", 0.22 },

		accent         = "#8E70FF",
		accentHover    = "#A78EFF",
		accentActive   = "#7552EE",
		accentTo       = "#4F8DFF",   -- what the accent fades to: the send button, the count
		onAccent       = "#FFFFFF",

		textPrimary    = "#F5F3FF",
		textSecondary  = { "#D2CCF7", 0.74 },
		textMuted      = { "#D2CCF7", 0.50 },
		textDisabled   = { "#D2CCF7", 0.30 },

		bubbleIn       = "#2B2652",
		bubbleInText   = "#F5F3FF",
		bubbleOut      = "#6F4DFF",
		bubbleOutTo    = "#5651F2",
		bubbleOutText  = "#FFFFFF",

		success        = "#3DDC97",
		danger         = "#FF5C7A",
		warning        = "#FFB347",

		online         = "#3DDC97",
		away           = "#FFB347",
		busy           = "#FF5C7A",

		link           = "#93B7FF",
		scrim          = { "#05040C", 0.66 },
		shadow         = { "#000000", 0.60 },
		scrollbar      = { "#D2CCF7", 0.20 },
		focusRing      = "#8E70FF",
	},
})
