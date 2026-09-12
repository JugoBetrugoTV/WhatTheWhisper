-- WhatTheWhisper -- Settings schema.
--
-- Declarative on purpose: the settings window renders whatever is described
-- here, so adding an option is one table entry rather than another hand-built
-- row, and every control ends up looking and behaving the same.

local _, ns = ...
local Compat = ns.Compat
local L = ns.L

local Options = {}
ns.Options = Options

--------------------------------------------------------------------------------
-- Path access
--------------------------------------------------------------------------------

local function resolve(path)
	local node = ns.db.profile
	local last
	for key in string.gmatch(path, "[^%.]+") do
		if last then
			node = node[last]
			if type(node) ~= "table" then return nil end
		end
		last = key
	end
	return node, last
end

function Options.Get(path)
	local node, key = resolve(path)
	if not node then return nil end
	return node[key]
end

function Options.Set(path, value)
	local node, key = resolve(path)
	if not node then return end
	if node[key] == value then return end
	node[key] = value
	Options.Apply(path, value)
	ns.Bus.Fire(ns.EV.SETTINGS_CHANGED, path, value)
end

-- Side effects of a setting change, in one place so nothing is forgotten.
local APPLY = {
	["appearance"] = function() ns.Theme.Refresh() end,
	["links.color"] = function() ns.Theme.Refresh() end,
	["emoticons.style"] = function()
		ns.MessageList.InvalidateMetrics()
		ns.UI.RefreshAll()
	end,
	["emoticons.raidMarkers"] = function()
		ns.MessageList.InvalidateMetrics()
		ns.UI.RefreshAll()
	end,
	["links.detect"] = function()
		ns.MessageList.InvalidateMetrics()
		ns.UI.RefreshAll()
	end,
	-- Every label was resolved from the string table when its frame was built,
	-- so refreshing the windows redraws the old language. The language is the
	-- one setting that has to reach back into them and rewrite the text.
	["appearance.locale"] = function()
		ns.UI.RefreshLayout()
		ns.UI.RefreshAll()
		ns.UI.Relocalize()
	end,
	["layout"] = function() ns.UI.RefreshLayout() end,
	["history.retention"] = function()
		ns.History.ApplyRetention()
		ns.UI.RefreshAll()
	end,
	["history"] = function() ns.History.Prune() end,
	["messages"] = function() ns.UI.RefreshAll() end,
	["notifications.position"] = function() ns.Toast.Relayout() end,
	["advanced.minimap.hide"] = function() ns.Minimap.Update() end,
}

function Options.Apply(path)
	local exact = APPLY[path]
	if exact then
		ns.Guard("Options.Apply", exact)
		return
	end
	local root = path:match("^([^%.]+)")
	local group = APPLY[root]
	if group then ns.Guard("Options.Apply", group) end
end

--------------------------------------------------------------------------------
-- Option lists
--------------------------------------------------------------------------------

-- Every language the client ships in, named in itself -- a menu of language
-- names written in a language you cannot read is not a menu you can use -- and
-- carrying how much of it is actually translated, because picking one that is
-- a third done should be a decision rather than a discovery.
function Options.LocaleOptions()
	local out = {
		{ value = "auto", label = L["Automatic"] },
	}
	for i = 1, #ns.LOCALES do
		local entry = ns.LOCALES[i]
		local done, total = ns.LocaleCoverage(entry.code)
		local label = entry.native
		if total > 0 and done < total then
			label = ("%s  (%d%%)"):format(label, math.floor(done / total * 100))
		end
		out[#out + 1] = { value = entry.code, label = label }
	end
	return out
end

function Options.SkinOptions()
	local out = {}
	for i = 1, #ns.Skins.order do
		local skin = ns.Skins.list[ns.Skins.order[i]]
		out[#out + 1] = { value = skin.id, label = skin.name }
	end
	return out
end

-- Only fonts the client can actually load are offered; each one is validated by
-- setting it and reading it back.
function Options.FontOptions()
	local out = { { value = false, label = L["Automatic"] } }
	local candidates = {
		{ "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
		{ "Fonts\\ARIALN.TTF", "Arial Narrow" },
		{ "Fonts\\MORPHEUS.TTF", "Morpheus" },
		{ "Fonts\\SKURRI.TTF", "Skurri" },
		{ "Fonts\\2002.TTF", "2002" },
		{ "Fonts\\NIM_____.ttf", "Nimrod" },
	}
	for i = 1, #candidates do
		if Compat.ValidateFont(candidates[i][1]) then
			out[#out + 1] = { value = candidates[i][1], label = candidates[i][2] }
		end
	end
	local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
	if LSM then
		local list = LSM:List("font")
		for i = 1, #list do
			local path = LSM:Fetch("font", list[i], true)
			if path and Compat.ValidateFont(path) then
				out[#out + 1] = { value = path, label = list[i] }
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Schema
--------------------------------------------------------------------------------

local function toggle(path, label, caption, invert)
	return { type = "toggle", path = path, label = label, caption = caption, invert = invert }
end

local function dropdown(path, label, options, caption)
	return { type = "dropdown", path = path, label = label, options = options, caption = caption }
end

local function slider(path, label, minValue, maxValue, step, format, caption)
	return {
		type = "slider", path = path, label = label, caption = caption,
		minValue = minValue, maxValue = maxValue, step = step, format = format,
	}
end

local function percent(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end
local function plain(value) return tostring(math.floor(value + 0.5)) end
local function seconds(value) return L["%d seconds"]:format(math.floor(value + 0.5)) end

function Options.BuildSchema()
	local soundOptions = ns.Sounds.Options()

	return {
		{
			id = "general", label = L["General"], icon = "sliders",
			cards = {
				{
					title = L["General"],
					rows = {
						toggle("enabled", L["Enable WhatTheWhisper"],
							L["Route whispers into the messenger instead of the default chat frame."]),
						toggle("messages.hideFromChatFrame", L["Hide whispers from chat frames"],
							L["Whispers still arrive normally, they are just not printed in the chat window."]),
						-- Stored inverted (hide), shown as "show".
						toggle("advanced.minimap.hide", L["Minimap button"],
							L["Show a button on the minimap to toggle the messenger."], true),
					},
				},
				{
					title = L["Conversations"],
					rows = {
						toggle("messages.openOnWhisper", L["Open on new whisper"],
							L["Show the messenger automatically when someone whispers you."]),
						toggle("messages.openOnCompose", L["Open when you start a whisper"],
							L["Typing /w in the default chat box opens that conversation here."]),
						toggle("messages.autoSwitch", L["Auto-switch to new conversations"],
							L["Switching away from what you are reading is off by default."]),
						toggle("messages.openOnSend", L["Open a tab for every conversation"]),
						dropdown("messages.showRealm", L["Realm"], {
							{ value = "never", label = L["Never"] },
							{ value = "cross", label = L["Automatic"] },
							{ value = "always", label = L["Always"] },
						}),
					},
				},
			},
		},
		{
			id = "appearance", label = L["Appearance"], icon = "eye",
			cards = {
				{
					title = L["Language"],
					rows = {
						dropdown("appearance.locale", L["Language"],
							Options.LocaleOptions(),
							L["Independent of the game's own language."]),
					},
				},
				{
					title = L["Theme"],
					rows = {
						dropdown("appearance.skin", L["Skin"], Options.SkinOptions()),
						slider("appearance.opacity", L["Background opacity"], 0.35, 1, 0.01, percent),
						dropdown("appearance.radius", L["Corner radius"], {
							{ value = 0, label = L["Square"] },
							{ value = 1, label = L["Normal"] },
							{ value = 2, label = L["Round"] },
						}),
						toggle("appearance.shadows", L["Drop shadows"]),
					},
				},
				{
					title = L["Typography"],
					rows = {
						dropdown("appearance.font", L["Font"], Options.FontOptions()),
						slider("appearance.fontScale", L["Font size"], -2, 4, 1, function(v)
							return v >= 0 and ("+" .. plain(v)) or plain(v)
						end),
					},
				},
				{
					title = L["Conversations"],
					rows = {
						dropdown("appearance.density", L["Density"], {
							{ value = "comfortable", label = L["Comfortable"] },
							{ value = "compact", label = L["Compact"] },
						}),
						toggle("appearance.classColors", L["Use class colours"]),
						toggle("appearance.avatars", L["Show avatars"]),
						dropdown("appearance.avatarStyle", L["Avatar style"], {
							{ value = "auto", label = L["Automatic"] },
							{ value = "class", label = L["Class icon"] },
							{ value = "initials", label = L["Initials"] },
						}),
					},
				},
			},
		},
		{
			id = "messages", label = L["Messages"], icon = "message",
			cards = {
				{
					title = L["Chat bubbles"],
					rows = {
						toggle("appearance.bubbles", L["Show chat bubbles"]),
						slider("appearance.bubbleOpacity", L["Bubble opacity"], 0.15, 1, 0.01, percent),
						toggle("appearance.grouping", L["Group messages"],
							L["Collapse consecutive messages from the same player."]),
						dropdown("appearance.spacing", L["Message spacing"], {
							{ value = 0, label = L["Compact"] },
							{ value = 1, label = L["Normal"] },
							{ value = 2, label = L["Comfortable"] },
						}),
					},
				},
				{
					title = L["Timestamps"],
					rows = {
						toggle("appearance.timestamps", L["Show timestamps"]),
						toggle("appearance.hoverTimestamp", L["Timestamp on hover"]),
						toggle("appearance.dateSeparators", L["Show date separators"]),
						dropdown("appearance.clock24", L["Timestamp format"], {
							{ value = true, label = L["24 hour"] },
							{ value = false, label = L["12 hour"] },
						}),
						dropdown("appearance.dateFormat", L["Format"], {
							{ value = "auto", label = L["Automatic"] },
							{ value = "dmy", label = "31.12.2026" },
							{ value = "mdy", label = "12/31/2026" },
							{ value = "iso", label = "2026-12-31" },
						}),
					},
				},
				{
					title = L["Delivery"],
					rows = {
						toggle("messages.deliveryStatus", L["Show delivery state"],
							L["Show whether the server accepted each message you send."]),
						toggle("messages.markReadOnFocus", L["Mark read when focused"]),
					},
				},
			},
		},
		{
			id = "layout", label = L["Layout"], icon = "grid",
			cards = {
				{
					title = L["Layout"],
					rows = {
						dropdown("layout.mode", L["Mode"], {
							{ value = "sidebar", label = L["Sidebar"] },
							{ value = "tabbed", label = L["Tabbed"] },
							{ value = "hybrid", label = L["Hybrid"] },
						}),
						slider("layout.sidebarWidth", L["Sidebar width"],
							ns.SZ.SIDEBAR_RAIL_W, ns.SZ.SIDEBAR_MAX_W, 4, plain),
						toggle("layout.showProfile", L["Character details"],
							L["Class, level, guild, zone and realm under the header."]),
					},
				},
				{
					title = L["Tabs"],
					rows = {
						toggle("layout.tabAutoOpen", L["Open a tab for every conversation"]),
						toggle("layout.tabBlink", L["Blink unread tabs"]),
						dropdown("layout.tabAutoClose", L["Close tabs after"], {
							{ value = 0, label = L["Never"] },
							{ value = 5, label = L["%d minutes"]:format(5) },
							{ value = 15, label = L["%d minutes"]:format(15) },
							{ value = 60, label = L["%d minutes"]:format(60) },
						}),
					},
				},
				{
					title = L["Windows"],
					rows = {
						toggle("layout.snap", L["Snap windows together"]),
						toggle("layout.locked", L["Lock window position"]),
						toggle("layout.remember", L["Remember window positions"]),
						{
							type = "button", label = L["Reset window positions"],
							buttonText = L["Reset window positions"],
							onClick = function()
								ns.MainWindow.Get():ResetGeometry()
								wipe(ns.db.profile.popouts)
								ns.Popout.CloseAll()
							end,
						},
					},
				},
			},
		},
		{
			id = "history", label = L["History"], icon = "clock",
			cards = {
				{
					title = L["History"],
					rows = {
						dropdown("history.retention", L["Keep history"], {
							{ value = "off", label = L["Disabled"] },
							{ value = "session", label = L["This session"] },
							{ value = "1d", label = L["1 day"] },
							{ value = "7d", label = L["7 days"] },
							{ value = "30d", label = L["30 days"] },
							{ value = "forever", label = L["Unlimited"] },
						}),
						slider("history.maxPerConversation", L["Max messages per conversation"],
							100, 10000, 100, plain),
						slider("history.maxConversations", L["Max conversations"], 20, 500, 10, plain),
					},
				},
				{
					title = L["Diagnostics"],
					rows = {
						{ type = "info", label = L["Stored messages: %d in %d conversations"],
							value = function()
								local conversations, messages = ns.History.Stats()
								return L["Stored messages: %d in %d conversations"]
									:format(messages, conversations)
							end },
						{ type = "info", label = L["Estimated size: %s"], value = function()
							local _, _, bytes = ns.History.Stats()
							return L["Estimated size: %s"]:format(ns.Format.Bytes(bytes))
						end },
						{
							type = "button", label = L["Clear all history"],
							buttonText = L["Clear all history"], danger = true,
							onClick = function() ns.UI.ConfirmClearAll() end,
						},
					},
				},
			},
		},
		{
			id = "sounds", label = L["Sounds"], icon = "volume",
			cards = {
				{
					title = L["Sounds"],
					rows = {
						dropdown("sounds.newMessage", L["Sound on new message"], soundOptions),
						dropdown("sounds.hiddenMessage", L["Sound when window is hidden"], soundOptions),
						dropdown("sounds.mention", L["Sound on mention"], soundOptions),
						dropdown("sounds.openConv", L["Sound when opening a conversation"], soundOptions),
						slider("sounds.cooldown", L["Repeat sound cooldown"], 0, 30, 1, seconds),
						{ type = "input", path = "sounds.customFile", label = L["Sound file path"],
							caption = "Interface\\AddOns\\YourAddon\\sound.ogg" },
					},
				},
				{
					title = L["Do not disturb"],
					rows = {
						toggle("sounds.dnd", L["Do not disturb"],
							L["Silence everything until you turn this off."]),
						toggle("sounds.muteCombat", L["Mute in combat"]),
						toggle("sounds.muteDungeon", L["Mute in dungeons"]),
						toggle("sounds.muteRaid", L["Mute in raids"]),
						toggle("sounds.muteArena", L["Mute in arenas"]),
						toggle("sounds.muteBattleground", L["Mute in battlegrounds"]),
					},
				},
			},
		},
		{
			id = "notifications", label = L["Notifications"], icon = "bell",
			cards = {
				{
					title = L["Notifications"],
					rows = {
						toggle("notifications.toasts", L["Show toast notifications"]),
						dropdown("notifications.position", L["Toast position"], {
							{ value = "topright", label = L["Top right"] },
							{ value = "topleft", label = L["Top left"] },
							{ value = "bottomright", label = L["Bottom right"] },
							{ value = "bottomleft", label = L["Bottom left"] },
						}),
						slider("notifications.duration", L["Toast duration"], 2, 15, 1, seconds),
						slider("notifications.maxVisible", L["Maximum toasts"], 1, 6, 1, plain),
						toggle("notifications.summarise", L["Summarise repeated messages"]),
						toggle("notifications.badge", L["Show unread badge"]),
						toggle("notifications.flashClient", L["Flash taskbar icon"]),
					},
				},
			},
		},
		{
			id = "animations", label = L["Animations"], icon = "refresh",
			cards = {
				{
					title = L["Animations"],
					rows = {
						dropdown("animations.level", L["Animation level"], {
							{ value = "off", label = L["Off"] },
							{ value = "reduced", label = L["Reduced"] },
							{ value = "normal", label = L["Normal"] },
							{ value = "fancy", label = L["Fancy"] },
						}),
						toggle("animations.smoothScroll", L["Smooth scrolling"]),
					},
				},
			},
		},
		{
			id = "combat", label = L["Combat"], icon = "shield",
			cards = {
				{
					title = L["Combat"],
					rows = {
						dropdown("combat.onEnter", L["Entering combat"], {
							{ value = "nothing", label = L["Do nothing"] },
							{ value = "fade", label = L["Fade conversations"] },
							{ value = "minimize", label = L["Minimize conversations"] },
							{ value = "hide", label = L["Hide conversations"] },
						}),
						dropdown("combat.onLeave", L["Leaving combat"], {
							{ value = "restore", label = L["Restore previous state"] },
							{ value = "stay", label = L["Stay hidden"] },
						}),
						slider("combat.fadeOpacity", L["Combat fade opacity"], 0.1, 1, 0.05, percent),
					},
				},
			},
		},
		{
			id = "links", label = L["Links"], icon = "globe",
			cards = {
				{
					title = L["Links"],
					rows = {
						toggle("links.detect", L["Detect links"],
							L["Highlight links in messages and make them clickable."]),
						{ type = "color", path = "links.color", label = L["Link colour"],
							defaultRole = "link" },
					},
				},
				{
					title = L["Emoticons"],
					rows = {
						dropdown("emoticons.style", L["Emoticon style"], {
							{ value = "text", label = L["Text"] },
							{ value = "colored", label = L["Coloured text"] },
							{ value = "images", label = L["Images"] },
						}),
						toggle("emoticons.raidMarkers", L["Convert raid target markers"]),
					},
				},
			},
		},
		{
			id = "advanced", label = L["Advanced"], icon = "keyboard",
			cards = {
				{
					title = L["Diagnostics"],
					rows = {
						{ type = "info", label = L["Client"], value = function()
							return ("%s  %s (%d)"):format(
								Compat.flavorName or Compat.flavor,
								Compat.buildVersion or "?", Compat.tocVersion)
						end },
						{ type = "info", label = L["Profile"], value = function()
							return ns.db:GetCurrentProfile()
						end },
						toggle("advanced.debug", L["Debug messages"]),
					},
				},
				{
					title = L["Reset"],
					rows = {
						{
							type = "button", label = L["Reset everything"],
							buttonText = L["Reset everything"], danger = true,
							onClick = function() ns.UI.ConfirmResetSettings() end,
						},
					},
				},
			},
		},
	}
end
