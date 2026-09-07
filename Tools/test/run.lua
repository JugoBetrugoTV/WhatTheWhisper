-- Loads WhatTheWhisper into the mock client and exercises it.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

--------------------------------------------------------------------------------
-- Client profile
--------------------------------------------------------------------------------

local FLAVOR = (arg and arg[1]) or "retail"

local PROFILES = {
	retail = { build = { "12.1.0", "60000", "Sep 06 2026", 120100 }, project = 1 },
	mop    = { build = { "5.5.4", "60000", "Sep 06 2026", 50504 }, project = 19 },
	tbc    = { build = { "2.5.6", "60000", "Sep 06 2026", 20506 }, project = 5,
		legacy = true, noMasks = true, noClip = true },
	classic = { build = { "1.15.9", "60000", "Sep 06 2026", 11509 }, project = 2,
		legacy = true, noMasks = true, noClip = true, noBNet = true, noModernSocial = true },
}

local profile = PROFILES[FLAVOR] or PROFILES.retail
M.build = profile.build
_G.WOW_PROJECT_ID = profile.project
_G.locale = nil
M.locale = (arg and arg[2]) or "enUS"

if profile.legacy then
	-- 9.x era rendering API: no new SetGradient, no SetResizeBounds.
	M.Disable("Texture", "SetGradient")
	M.Disable("Frame", "SetResizeBounds")
	_G.GetPhysicalScreenSize = nil
end
if profile.noMasks then
	M.Disable("Frame", "CreateMaskTexture")
	M.Disable("Texture", "AddMaskTexture")
end
if profile.noClip then
	M.Disable("Frame", "SetClipsChildren")
end
if profile.noBNet then
	_G.C_BattleNet = nil
	_G.BNGetNumFriends = nil
	_G.BNSendWhisper = nil
end
if profile.noModernSocial then
	_G.C_PartyInfo = nil
	_G.C_FriendList = nil
	_G.GetNumFriends = function() return 0 end
	_G.GetFriendInfo = function() return nil end
	_G.AddFriend = function() end
	_G.AddOrDelIgnore = function() end
	_G.InviteUnit = function() end
	_G.SendWho = function() end
end

print(("=== profile: %s (toc %d, locale %s) ==="):format(FLAVOR, profile.build[4], M.locale))

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local failures = {}
local function report(context, err)
	failures[#failures + 1] = context .. ": " .. tostring(err)
	print("!! " .. context .. ": " .. tostring(err))
end

--------------------------------------------------------------------------------
-- Library loading
--------------------------------------------------------------------------------

local libs = {
	"Ace3/LibStub/LibStub.lua",
	"Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua",
	"Ace3/AceAddon-3.0/AceAddon-3.0.lua",
	"Ace3/AceEvent-3.0/AceEvent-3.0.lua",
	"Ace3/AceTimer-3.0/AceTimer-3.0.lua",
	"Ace3/AceHook-3.0/AceHook-3.0.lua",
	"Ace3/AceDB-3.0/AceDB-3.0.lua",
	"Ace3/AceLocale-3.0/AceLocale-3.0.lua",
	"Ace3/AceConsole-3.0/AceConsole-3.0.lua",
}
for _, path in ipairs(libs) do
	local chunk, err = loadfile(ROOT .. path)
	if not chunk then
		report("load " .. path, err)
	else
		local ok, loadErr = pcall(chunk, path:match("([^/]+)%.lua$"), {})
		if not ok then report("run " .. path, loadErr) end
	end
end

--------------------------------------------------------------------------------
-- Addon loading, in the order the XML declares
--------------------------------------------------------------------------------

local xml = io.open(ROOT .. "WhatTheWhisper/WhatTheWhisper.xml"):read("*a")
local files = {}
for file in xml:gmatch('<Script file="([^"]+)"/>') do
	files[#files + 1] = (file:gsub("\\", "/"))
end
print(("loading %d addon files"):format(#files))

local ns = {}
for _, file in ipairs(files) do
	local chunk, err = loadfile(ROOT .. "WhatTheWhisper/" .. file)
	if not chunk then
		report("compile " .. file, err)
	else
		local ok, runErr = pcall(chunk, "WhatTheWhisper", ns)
		if not ok then report("load " .. file, runErr) end
	end
end

if #failures > 0 then
	print("\nLOAD FAILED")
	os.exit(1)
end
print("all files loaded")

-- The addon deliberately swallows errors inside event handlers so one bad
-- message cannot break chat. In the harness we want every one of them.
ns.SoftError = function(context, err)
	report("soft:" .. tostring(context), err)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function step(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then report(name, err) end
	-- Drive real frames, not just timers, so animation code runs and tweens
	-- reach their completion callbacks.
	M.RunFrames(4)
	for i = 1, #M.errors do report(name .. " (deferred)", M.errors[i]) end
	M.errors = {}
	return ok
end

step("ADDON_LOADED", function() M.FireEvent("ADDON_LOADED", "WhatTheWhisper") end)
M.loggedIn = true
step("PLAYER_LOGIN", function() M.FireEvent("PLAYER_LOGIN") end)
print(("bus listeners on CONVERSATION_SELECTED: %d")
	:format(ns.Bus.CountListeners("CONVERSATION_SELECTED")))

assert(ns.db, "database was not created")
print("profile skin: " .. tostring(ns.db.profile.appearance.skin))

step("PLAYER_ENTERING_WORLD", function() M.FireEvent("PLAYER_ENTERING_WORLD") end)

--------------------------------------------------------------------------------
-- Traffic
--------------------------------------------------------------------------------

M.guids = {
	["Player-1-AAAA"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["Player-1-BBBB"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}

local function whisper(text, sender, guid)
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "", 0, 1, guid)
end
local function inform(text, target, guid)
	M.FireEvent("CHAT_MSG_WHISPER_INFORM", text, target, "Common", "", target, "", 0, 0, "", 0, 2, guid)
end

step("incoming whisper", whisper, "Yo kommst du Raid? :)", "Thrall", "Player-1-AAAA")
step("incoming whisper 2", whisper, "check https://wowhead.com/spell=133 pls", "Thrall", "Player-1-AAAA")
step("incoming whisper 3", whisper, "und {rt1} setzen", "Thrall", "Player-1-AAAA")
step("second player", whisper, "Portal in 5", "Jaina", "Player-1-BBBB")

-- Traffic must not build the window: a player who never opens the messenger
-- should not pay for its frames.
step("lazy window", function()
	assert(ns.MainWindow.Existing() == nil,
		"main window was built before it was ever shown")
	print(("  frames after four whispers, window unopened: %d"):format(#M.frames))
end)

step("show window", function() ns.UI.Show() end)
step("select conversation", function() ns.ConversationManager.Select("Thrall-Blackrock") end)

step("send message", function()
	local ok = ns.ConversationManager.SendMessage("Thrall-Blackrock", "Ja bin gleich da")
	assert(ok, "send returned false")
	assert(M.sent and #M.sent >= 1, "nothing reached SendChatMessage")
end)
step("server echo", inform, "Ja bin gleich da", "Thrall", "Player-1-AAAA")

step("long message split", function()
	local long = string.rep("Sehr langer Text der gesplittet werden muss. ", 20)
	ns.ConversationManager.SendMessage("Thrall-Blackrock", long)
end)

step("failed delivery", function()
	ns.ConversationManager.SendMessage("Jaina-Blackrock", "bist du da?")
	M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Jaina' is currently playing.")
end)

step("afk reply", function()
	M.FireEvent("CHAT_MSG_AFK", "Away from keyboard", "Thrall")
end)

if not profile.noBNet then
	step("battle.net whisper", function()
		M.bnet = { [42] = { tag = "Sylvanas#2311", name = "Sylvanas", character = "Sylvanas" } }
		M.FireEvent("CHAT_MSG_BN_WHISPER", "hey there", "Sylvanas",
			"", "", "", "", 0, 0, "", 0, 3, 42)
	end)
end

--------------------------------------------------------------------------------
-- UI interaction
--------------------------------------------------------------------------------

step("sidebar filter", function()
	local window = ns.MainWindow.Get()
	window.sidebar:SetFilter("thr")
	assert(#window.sidebar.filtered == 1, "expected one filtered row, got "
		.. #window.sidebar.filtered)
	window.sidebar:SetFilter("")
end)

step("conversation search", function()
	local view = ns.MainWindow.Get().view
	view:ToggleSearch(true)
	view:RunSearch("raid")
	view:StepSearch(1)
	view:ToggleSearch(false)
end)

step("tab strip", function()
	local window = ns.MainWindow.Get()
	ns.db.profile.layout.mode = "hybrid"
	ns.UI.RefreshLayout()
	window.tabs:Refresh()
	ns.db.profile.layout.mode = "sidebar"
	ns.UI.RefreshLayout()
end)

step("popout", function()
	ns.UI.TogglePopout("Thrall-Blackrock")
	whisper("noch was", "Thrall", "Player-1-AAAA")
	ns.UI.DockConversation("Thrall-Blackrock")
end)

step("context menu", function()
	local conv = ns.ConversationManager.Get("Thrall-Blackrock")
	local entries = ns.UI.BuildConversationMenu(conv)
	assert(#entries > 8, "menu too small")
	ns.Menu.Open(entries)
	ns.Menu.Close()
end)

step("emoji picker", function()
	local composer = ns.MainWindow.Get().view.composer
	ns.EmojiPicker.Open(composer.emoji, composer)
	ns.EmojiPicker.Insert("fire")
	composer.input:SetText("")
end)

step("export dialog", function()
	local conv = ns.ConversationManager.Get("Thrall-Blackrock")
	for _, format in ipairs({ "text", "markdown", "bbcode", "csv" }) do
		local out = ns.Export.Conversation(conv, format)
		assert(type(out) == "string" and #out > 0, "empty export for " .. format)
	end
	ns.Dialogs.ShowExport(conv)
	ns.Dialogs.ShowCopy("https://example.com", "Copy URL")
end)

step("settings window", function()
	ns.SettingsUI.Show()
	local schema = ns.Options.BuildSchema()
	for i = 1, #schema do
		ns.SettingsUI.SelectCategory(schema[i].id)
	end
	ns.SettingsUI.SetFilter("sound")
	ns.SettingsUI.SetFilter("")
end)

step("every skin", function()
	for _, id in ipairs(ns.Skins.order) do
		ns.Options.Set("appearance.skin", id)
		ns.UI.RefreshAll()
	end
	ns.Options.Set("appearance.skin", "midnight")
end)

step("option permutations", function()
	local toggles = {
		"appearance.bubbles", "appearance.grouping", "appearance.avatars",
		"appearance.timestamps", "appearance.dateSeparators", "appearance.classColors",
		"messages.deliveryStatus", "links.detect", "emoticons.raidMarkers",
	}
	for _, path in ipairs(toggles) do
		ns.Options.Set(path, false)
		ns.UI.RefreshAll()
		ns.Options.Set(path, true)
		ns.UI.RefreshAll()
	end
	for _, level in ipairs({ "off", "reduced", "normal", "fancy" }) do
		ns.Options.Set("animations.level", level)
		ns.UI.RefreshAll()
	end
	ns.Options.Set("animations.level", "normal")
	for _, style in ipairs({ "text", "colored", "images" }) do
		ns.Options.Set("emoticons.style", style)
		ns.UI.RefreshAll()
	end
	ns.Options.Set("emoticons.style", "images")
	for _, density in ipairs({ "compact", "comfortable" }) do
		ns.Options.Set("appearance.density", density)
		ns.UI.RefreshAll()
	end
end)

step("expose", function()
	ns.UI.TogglePopout("Jaina-Blackrock")
	ns.Expose.Open()
	ns.Expose.Close()
	ns.Popout.CloseAll()
end)

step("combat", function()
	ns.Options.Set("combat.onEnter", "fade")
	M.inCombat = true
	M.FireEvent("PLAYER_REGEN_DISABLED")
	whisper("im kampf", "Thrall", "Player-1-AAAA")
	M.inCombat = false
	M.FireEvent("PLAYER_REGEN_ENABLED")
	ns.Options.Set("combat.onEnter", "nothing")
end)

step("scale change", function() M.FireEvent("UI_SCALE_CHANGED") end)

step("slash commands", function()
	local addon = ns.addon
	addon:HandleCommand("")
	addon:HandleCommand("diag")
	addon:HandleCommand("help")
	addon:HandleCommand("Sylvanas")
	addon:HandleCommand("expose")
	ns.Expose.Close()
	addon:HandleCommand("")
end)

step("retention change", function()
	for _, value in ipairs({ "off", "session", "1d", "7d", "30d", "forever" }) do
		ns.Options.Set("history.retention", value)
	end
end)

step("bulk history", function()
	local id = "Bulk-Blackrock"
	for i = 1, 3000 do
		ns.ConversationManager.AddMessage(id, i % 2, "Nachricht Nummer " .. i .. " mit etwas Text",
			ns.MSG_WHISPER, 1788000000 + i * 30)
	end
	local conv = ns.ConversationManager.Get(id)
	assert(#conv.messages <= ns.db.profile.history.maxPerConversation + 300,
		"trim did not run: " .. #conv.messages)
	ns.ConversationManager.Select(id)
	local list = ns.MainWindow.Get().view.list
	list:Rebuild(false)
	assert(#list.layout > 0, "layout empty for bulk conversation")
	local rendered = 0
	for _ in list.bubblePool:EnumerateActive() do rendered = rendered + 1 end
	print(("bulk: %d messages, %d layout entries, %d bubble frames live")
		:format(#conv.messages, #list.layout, rendered))
	assert(rendered < 60, "virtualisation is not working: " .. rendered .. " frames")

	-- A scroll that stays inside the same set of elements must reuse them rather
	-- than releasing and re-rendering the whole visible window.
	local before = {}
	for f in list.bubblePool:EnumerateActive() do before[f] = true end
	local created = select(1, list.bubblePool:Stats())
	list:SetOffset(list:GetOffset() - 3, false)
	local same, total = 0, 0
	for f in list.bubblePool:EnumerateActive() do
		total = total + 1
		if before[f] then same = same + 1 end
	end
	assert(total > 0 and same == total,
		("scroll fast path did not reuse elements: %d/%d"):format(same, total))
	assert(select(1, list.bubblePool:Stats()) == created, "scroll created new frames")
	print(("scroll fast path: %d/%d elements reused, 0 new frames"):format(same, total))
end)

step("logout", function() M.FireEvent("PLAYER_LOGOUT") end)

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

print("\n--- unknown API methods touched ---")
local unknown = {}
for key, count in pairs(M.unknownMethods) do unknown[#unknown + 1] = key .. " x" .. count end
table.sort(unknown)
if #unknown == 0 then
	print("(none)")
else
	for _, line in ipairs(unknown) do print("  " .. line) end
end

print(("compat: masks=%s clip=%s gradient=%s bnet=%s flavor=%s")
	:format(tostring(ns.Compat.hasMasks), tostring(ns.Compat.hasClipsChildren),
		tostring(ns.Compat.hasGradient), tostring(ns.Compat.hasBattleNet),
		tostring(ns.Compat.flavorName)))
print(("\nframes created: %d"):format(#M.frames))
print(("messages sent: %d"):format(M.sent and #M.sent or 0))

if #failures > 0 then
	print(("\n%d FAILURES"):format(#failures))
	os.exit(1)
end
print("\nALL CHECKS PASSED")
