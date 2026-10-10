-- Every switch does the thing on its label.
--
-- A setting that is stored, rendered as a control and read by nobody is the
-- easiest kind of bug to ship and the hardest to notice: the checkbox moves, the
-- value is saved, and nothing happens. This addon has shipped one before --
-- "mark read when focused" cleared the mark either way for a long time.
--
-- settings.lua proves every control points at a real setting. This proves the
-- other direction: for each switch whose effect is behavioural rather than
-- visual, the behaviour is driven in both positions and the two outcomes have to
-- differ. Twenty-one of them had no such check anywhere.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
local CM, Options = ns.ConversationManager, ns.Options

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

M.guids = {
	["G-T"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-J"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}
local function whisper(text, who, guid)
	M.FireEvent("CHAT_MSG_WHISPER", text, who, "Common", "", who, "", 0, 0, "", 0, 1, guid)
	M.RunFrames(3)
end

local thrall = ns.Compat.NormalizeName("Thrall")

-- The filter the client actually runs, rather than a flag: this is the thing
-- that decides whether a whisper is taken out of the chat frame.
local function filterSuppresses(text, who, guid)
	local filters = M.chatFilters and M.chatFilters["CHAT_MSG_WHISPER"]
	check("a whisper filter is registered", filters ~= nil and #filters > 0)
	if not filters or #filters == 0 then return false end
	for i = 1, #filters do
		if filters[i](nil, "CHAT_MSG_WHISPER", text, who, "Common", "", who,
			"", 0, 0, "", 0, 1, guid) then
			return true
		end
	end
	return false
end

-- Sets a setting for the duration of one body and puts it back afterwards, so a
-- failure part way through cannot leave the next check standing on it.
local function with(path, value, body)
	local before = Options.Get(path)
	Options.Set(path, value)
	M.RunFrames(2)
	local ok, err = pcall(body)
	Options.Set(path, before)
	M.RunFrames(2)
	if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
-- The master switch
--------------------------------------------------------------------------------

do
	local id = "Schalter-Blackrock"
	CM.GetOrCreate(id, { name = "Schalter" })
	local before = #CM.Get(id).messages

	with("enabled", false, function()
		M.FireEvent("CHAT_MSG_WHISPER", "aus", "Schalter", "Common", "", "Schalter",
			"", 0, 0, "", 0, 1, "G-OFF")
		M.RunFrames(3)
		eq("switched off, a whisper is not taken in", #CM.Get(id).messages, before)
		eq("and it is left in the chat frame",
			filterSuppresses("aus", "Schalter", "G-OFF"), false)
	end)

	whisper("an", "Schalter", "G-OFF")
	check("switched on, the same whisper is taken in", #CM.Get(id).messages > before,
		("%d -> %d"):format(before, #CM.Get(id).messages))
end

--------------------------------------------------------------------------------
-- Where whispers are shown
--------------------------------------------------------------------------------

do
	with("messages.hideFromChatFrame", true, function()
		eq("a whisper is taken out of the chat frame when that is wanted",
			filterSuppresses("versteckt", "Thrall", "G-T"), true)
	end)
	with("messages.hideFromChatFrame", false, function()
		eq("and left in it when it is not",
			filterSuppresses("sichtbar", "Thrall", "G-T"), false)
	end)

	-- Chosen the way a player chooses it: the control in the settings window,
	-- which offers two places rather than a switch named for what it hides.
	ns.SettingsUI.Show()
	ns.SettingsUI.SelectCategory("general")
	M.RunFrames(2)
	local control
	for row in ns.SettingsUI.RowPool():EnumerateActive() do
		if row.control and row.control.spec and row.control.spec.path == "messages.hideFromChatFrame" then
			control = row.control
		end
	end
	check("the settings offer where whispers are shown", control ~= nil)
	if control then
		control:SetValue(false, true)
		M.RunFrames(2)
		eq("choosing the messenger and the chat window leaves them in the chat",
			filterSuppresses("beides", "Thrall", "G-T"), false)
		local inform = M.ChatFrameWouldShow("CHAT_MSG_WHISPER_INFORM", "auch raus", "Thrall",
			"", "", "Thrall", "", 0, 0, "", 0, 99, "G-T")
		eq("the ones you send as well", inform, true)
		control:SetValue(true, true)
		M.RunFrames(2)
		eq("and the messenger only takes them out again",
			filterSuppresses("nur hier", "Thrall", "G-T"), true)
	end
	ns.SettingsUI.Hide()
end

--------------------------------------------------------------------------------
-- What puts the window on screen
--------------------------------------------------------------------------------

local function windowShown()
	local w = ns.MainWindow.Get()
	return w and w:IsShown() or false
end

do
	with("messages.openOnWhisper", false, function()
		ns.UI.Hide()
		M.RunFrames(3)
		whisper("nicht aufmachen", "Jaina", "G-J")
		eq("a whisper leaves the window shut when that is wanted", windowShown(), false)
	end)
	with("messages.openOnWhisper", true, function()
		ns.UI.Hide()
		M.RunFrames(3)
		whisper("jetzt aufmachen", "Jaina", "G-J")
		eq("and opens it when that is wanted", windowShown(), true)
	end)

	-- Or the way WIM does it: every thread in a small window of its own.
	with("messages.openAs", "window", function()
		ns.UI.Hide()
		ns.Popout.CloseAll()
		M.RunFrames(3)
		local id = ns.Compat.NormalizeName("Anduin")
		whisper("eigenes fenster", "Anduin", "G-A")
		M.RunFrames(3)
		check("a whisper opens its own window when that is wanted", ns.Popout.IsOpen(id))
		eq("and leaves the messenger shut", windowShown(), false)
		whisper("noch was", "Anduin", "G-A")
		M.RunFrames(3)
		check("a second whisper does not close it again", ns.Popout.IsOpen(id))
		ns.Popout.CloseAll()
		M.RunFrames(3)
	end)
end

do
	with("messages.openOnCompose", false, function()
		ns.UI.Hide()
		M.RunFrames(3)
		ns.ChatEvents.OnComposeWhisper("Thrall")
		M.RunFrames(3)
		eq("starting a whisper leaves the window shut when that is wanted",
			windowShown(), false)
	end)
	with("messages.openOnCompose", true, function()
		ns.UI.Hide()
		M.RunFrames(3)
		ns.ChatEvents.OnComposeWhisper("Thrall")
		M.RunFrames(3)
		eq("and opens it when that is wanted", windowShown(), true)
	end)
end

do
	-- Auto-switch decides whether an arriving message takes the selection away
	-- from the thread being read.
	ns.UI.Show()
	M.RunFrames(3)
	with("messages.autoSwitch", false, function()
		CM.Select(thrall)
		M.RunFrames(2)
		whisper("woanders", "Jaina", "G-J")
		eq("a message elsewhere does not steal the selection", CM.SelectedID(), thrall)
	end)
	with("messages.autoSwitch", true, function()
		CM.Select(thrall)
		M.RunFrames(2)
		whisper("hierher", "Jaina", "G-J")
		check("and does when that is wanted",
			CM.SelectedID() == ns.Compat.NormalizeName("Jaina"), tostring(CM.SelectedID()))
	end)
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

local function openTabCount()
	return #(ns.UI.GetTabOrder() or {})
end
local function closeAllTabs()
	-- A copy: closing a tab removes it from the very list being walked, and a
	-- walk over a shrinking array skips every other entry.
	local ids = {}
	for i, id in ipairs(ns.UI.GetTabOrder() or {}) do ids[i] = id end
	for _, id in ipairs(ids) do ns.UI.CloseConversation(id) end
	M.RunFrames(3)
end

do
	ns.UI.Show()
	closeAllTabs()
	with("layout.tabAutoOpen", false, function()
		local before = openTabCount()
		whisper("kein Tab", "Jaina", "G-J")
		eq("a whisper opens no tab when that is switched off", openTabCount(), before)
	end)
	closeAllTabs()
	with("layout.tabAutoOpen", true, function()
		local before = openTabCount()
		whisper("doch ein Tab", "Jaina", "G-J")
		check("and opens one when it is switched on", openTabCount() > before,
			("%d -> %d"):format(before, openTabCount()))
	end)
end

--------------------------------------------------------------------------------
-- Window handling
--------------------------------------------------------------------------------

do
	-- Pressing the title bar is what starts a drag, so that is what is pressed.
	-- The window only begins moving if the handle let it, which is the whole of
	-- what "lock" means.
	local window = ns.MainWindow.Get()
	ns.UI.Show()
	M.RunFrames(3)
	local handle = window.titlebar or window.header or window
	local moving = 0
	local realStart = window.StartMoving
	window.StartMoving = function(self) moving = moving + 1 if realStart then realStart(self) end end

	with("layout.locked", true, function()
		moving = 0
		local down = handle._scripts and handle._scripts.OnMouseDown
		check("the title bar takes a press", down ~= nil)
		if down then down(handle, "LeftButton") end
		M.RunFrames(2)
		if handle._scripts.OnMouseUp then handle._scripts.OnMouseUp(handle, "LeftButton") end
		eq("a locked window refuses to be dragged", moving, 0)
	end)
	with("layout.locked", false, function()
		-- Far enough after the press above that the title bar does not read the
		-- two together as a double-click, which minimises instead of moving.
		M.RunFrames(12)
		moving = 0
		local down = handle._scripts and handle._scripts.OnMouseDown
		if down then down(handle, "LeftButton") end
		M.RunFrames(2)
		if handle._scripts.OnMouseUp then handle._scripts.OnMouseUp(handle, "LeftButton") end
		check("and an unlocked one moves", moving > 0, tostring(moving))
	end)
	window.StartMoving = realStart
end

do
	local window = ns.MainWindow.Get()
	ns.UI.Show()
	M.RunFrames(3)
	with("layout.remember", false, function()
		ns.db.profile.layout.point = nil
		window:SavePosition()
		eq("with remembering off, no position is stored",
			ns.db.profile.layout.point, nil)
	end)
	with("layout.remember", true, function()
		ns.db.profile.layout.point = nil
		window:SavePosition()
		check("and with it on, one is",
			type(ns.db.profile.layout.point) == "table",
			tostring(ns.db.profile.layout.point))
	end)
end

--------------------------------------------------------------------------------
-- Sound suppression
--------------------------------------------------------------------------------

do
	for _, spec in ipairs({
		{ "sounds.dnd", nil, "do not disturb" },
		{ "sounds.muteCombat", "combat", "in combat" },
		{ "sounds.muteDungeon", "party", "in a dungeon" },
		{ "sounds.muteRaid", "raid", "in a raid" },
		{ "sounds.muteArena", "arena", "in an arena" },
		{ "sounds.muteBattleground", "pvp", "in a battleground" },
	}) do
		local path, situation, label = spec[1], spec[2], spec[3]
		-- Put the player in the situation the switch is about.
		local restoreCombat = M.inCombat
		local realIsInInstance = _G.IsInInstance
		if situation == "combat" then
			M.inCombat = true
		elseif situation then
			_G.IsInInstance = function() return true, situation end
		end
		M.RunFrames(2)

		with(path, false, function()
			eq(("sound is not suppressed %s with the switch off"):format(label),
				(ns.Sounds.IsSuppressed()), false)
		end)
		with(path, true, function()
			eq(("sound is suppressed %s with the switch on"):format(label),
				(ns.Sounds.IsSuppressed()), true)
		end)

		M.inCombat = restoreCombat
		_G.IsInInstance = realIsInInstance
		M.RunFrames(2)
	end
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

do
	local function toastCount()
		return #ns.Toast.Active()
	end
	-- A toast is for a message you cannot already see, so the thread it is about
	-- has to be one that is not on screen. With "open on new whisper" left on,
	-- the window opens and shows that very thread before the notification is
	-- decided, and then no toast is offered whichever way the switch points --
	-- which is correct behaviour and a test that proves nothing.
	Options.Set("messages.openOnWhisper", false)
	ns.UI.Show()
	CM.Select(thrall)
	M.RunFrames(3)
	check("the thread the toast is about is not the one on screen",
		not ns.UI.IsConversationVisible(ns.Compat.NormalizeName("Jaina")))

	with("notifications.toasts", false, function()
		ns.Toast.DismissAll()
		M.RunFrames(6)
		whisper("kein Toast", "Jaina", "G-J")
		eq("no toast when they are switched off", toastCount(), 0)
	end)
	with("notifications.toasts", true, function()
		ns.Toast.DismissAll()
		M.RunFrames(6)
		whisper("doch ein Toast", "Jaina", "G-J")
		check("and one when they are switched on", toastCount() > 0, tostring(toastCount()))
		ns.Toast.DismissAll()
		M.RunFrames(6)
	end)
	Options.Set("messages.openOnWhisper", true)
end

do
	-- The taskbar flash goes through Compat, so it is counted there.
	local flashes = 0
	local real = _G.FlashClientIcon
	_G.FlashClientIcon = function() flashes = flashes + 1 end
	Options.Set("messages.openOnWhisper", false)
	ns.UI.Show()
	CM.Select(thrall)
	M.RunFrames(3)
	with("notifications.flashClient", false, function()
		flashes = 0
		whisper("kein Blinken", "Jaina", "G-J")
		eq("the taskbar is not flashed when that is switched off", flashes, 0)
	end)
	with("notifications.flashClient", true, function()
		flashes = 0
		whisper("blinken", "Jaina", "G-J")
		check("and is when it is switched on", flashes > 0, tostring(flashes))
	end)
	_G.FlashClientIcon = real
	Options.Set("messages.openOnWhisper", true)
end

do
	-- The unread badge on the minimap button.
	ns.Minimap.Update()
	M.RunFrames(3)
	local button = _G.WhatTheWhisperMinimapButton
	check("the minimap button exists to look at", button ~= nil)
	CM.MarkUnread(thrall)
	M.RunFrames(2)
	with("notifications.badge", false, function()
		ns.Minimap.Update()
		M.RunFrames(3)
		eq("no badge when it is switched off", button.badge:IsShown(), false)
	end)
	with("notifications.badge", true, function()
		ns.Minimap.Update()
		M.RunFrames(3)
		check("and a badge when it is switched on", button.badge:IsShown(),
			tostring(button.badge.count))
	end)
	CM.MarkRead(thrall)
end

do
	-- Repeated messages from one thread collapse into a count rather than a
	-- stack of toasts.
	-- The window must stay shut, or the thread is visible and a toast is
	-- correctly not offered for it -- which would make this test pass for the
	-- wrong reason.
	Options.Set("messages.openOnWhisper", false)
	ns.UI.Show()
	CM.Select(thrall)
	M.RunFrames(3)
	local function toastText()
		local t = ns.Toast.Active()[1]
		return t and t.body and t.body._text or ""
	end
	with("notifications.summarise", true, function()
		ns.Toast.DismissAll()
		M.RunFrames(6)
		whisper("eins", "Jaina", "G-J")
		whisper("zwei", "Jaina", "G-J")
		whisper("drei", "Jaina", "G-J")
		eq("repeats stay in one toast", #ns.Toast.Active(), 1)
		check("and it says how many there were",
			toastText():find("%d") ~= nil, toastText())
		ns.Toast.DismissAll()
		M.RunFrames(6)
	end)
	with("notifications.summarise", false, function()
		ns.Toast.DismissAll()
		M.RunFrames(6)
		whisper("eins", "Jaina", "G-J")
		whisper("zwei", "Jaina", "G-J")
		check("without summarising the toast shows the message itself",
			toastText():find("%d") == nil or toastText():find("zwei") ~= nil, toastText())
		ns.Toast.DismissAll()
		M.RunFrames(6)
	end)
	Options.Set("messages.openOnWhisper", true)
end

--------------------------------------------------------------------------------
-- The rest
--------------------------------------------------------------------------------

do
	-- The minimap button itself.
	local button = _G.WhatTheWhisperMinimapButton
	with("advanced.minimap.hide", true, function()
		ns.Minimap.Update()
		M.RunFrames(3)
		eq("the minimap button hides when asked", button:IsShown(), false)
	end)
	with("advanced.minimap.hide", false, function()
		ns.Minimap.Update()
		M.RunFrames(3)
		eq("and comes back", button:IsShown(), true)
	end)
end

do
	with("advanced.debug", true, function()
		eq("debug logging follows its switch on", ns.Debug.IsEnabled(), true)
	end)
	with("advanced.debug", false, function()
		eq("and off", ns.Debug.IsEnabled(), false)
	end)
end

do
	-- The hover timestamp only earns its keep when the markers are off, which is
	-- what its own description promises.
	ns.UI.Show()
	whisper("etwas zum Anschauen", "Thrall", "G-T")
	CM.Select(thrall)
	M.RunFrames(8)
	local view = ns.MainWindow.Get().view
	local function bubbles()
		local n = 0
		for _ in view.list.bubblePool:EnumerateActive() do n = n + 1 end
		return n
	end
	check("there are messages on screen to hover", bubbles() > 0, tostring(bubbles()))
	local function anyBubbleWantsStamp()
		for f in view.list.bubblePool:EnumerateActive() do
			if f.showStamp then return true end
		end
		return false
	end
	with("appearance.timestamps", false, function()
		with("appearance.hoverTimestamp", true, function()
			ns.UI.RefreshAll()
			M.RunFrames(6)
			eq("with the markers off, hovering offers a time", anyBubbleWantsStamp(), true)
		end)
		with("appearance.hoverTimestamp", false, function()
			ns.UI.RefreshAll()
			M.RunFrames(6)
			eq("and does not when that is switched off too", anyBubbleWantsStamp(), false)
		end)
	end)
	with("appearance.timestamps", true, function()
		ns.UI.RefreshAll()
		M.RunFrames(6)
		eq("with the markers on, the thread already says when", anyBubbleWantsStamp(), false)
	end)
end

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
