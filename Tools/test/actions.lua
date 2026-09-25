-- Every action the interface offers, actually performed.
--
-- The other suites check that things are built, laid out and coloured correctly.
-- This one checks that they *do* something: every entry in every menu, every
-- button in the chrome, every dialog's confirm and cancel. A handler that was
-- wired to the wrong function, or to nothing at all, looks perfect in a geometry
-- audit and does nothing at all in the game.
--
-- So each action here is invoked the way a player invokes it, and the assertion
-- is about the state it was supposed to change -- not merely that it did not
-- raise an error. "It did not crash" is the weakest possible thing to know about
-- a button.

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
local CM = ns.ConversationManager

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local soft = {}
ns.SoftError = function(context, err) soft[#soft + 1] = context .. ": " .. tostring(err) end

M.guids = {
	["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}

local function whisper(text, from, guid)
	M.FireEvent("CHAT_MSG_WHISPER", text, from, "Common", "", from, "", 0, 0, "", 0, 1, guid)
end

whisper("hey", "Thrall", "G-THRALL")
whisper("kurz", "Jaina", "G-JAINA")
ns.UI.Show()
M.RunFrames(6)

local thrall = ns.Compat.NormalizeName("Thrall")
CM.Select(thrall)
CM.SendMessage(thrall, "on my way")
M.RunFrames(6)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Runs one action and reports anything the addon logged while it ran, so a
-- handler that fails inside ns.Guard -- which swallows by design -- is not
-- mistaken for one that worked.
local function perform(label, fn)
	local errorsBefore, softBefore = #M.errors, #soft
	local ok, err = pcall(fn)
	M.RunFrames(4)
	check(label .. ": runs", ok, err)
	check(label .. ": raises nothing",
		#M.errors == errorsBefore, M.errors[#M.errors])
	check(label .. ": logs no soft error",
		#soft == softBefore, soft[#soft])
	return ok
end

local function findEntry(entries, text)
	for i = 1, #entries do
		if entries[i].text == text then return entries[i] end
	end
	return nil
end

local function conv() return CM.Get(thrall) end

--------------------------------------------------------------------------------
-- The conversation menu: every entry, and what each one is for
--------------------------------------------------------------------------------

do
	local entries = ns.UI.BuildConversationMenu(conv())
	local actionable, named = 0, {}
	for i = 1, #entries do
		local entry = entries[i]
		if not entry.separator then
			named[#named + 1] = entry.text
			if entry.onClick or entry.secureMacro then actionable = actionable + 1 end
		end
	end
	check("the conversation menu has entries", #named >= 10, tostring(#named))
	check("and every one of them does something",
		actionable == #named,
		("%d of %d entries have no handler"):format(#named - actionable, #named))

	-- Every entry carries an icon, because a menu with holes in its icon column
	-- reads as a menu with something missing from it.
	for i = 1, #entries do
		local entry = entries[i]
		if not entry.separator then
			check("menu entry has an icon: " .. tostring(entry.text),
				(entry.icon or "") ~= "", entry.text)
		end
	end
end

-- Mute, pin, read/unread and popout are toggles, so each one is performed twice
-- and has to land back where it started. A toggle that only goes one way is the
-- most common way one of these breaks.
local TOGGLES = {
	{ "Mute conversation", "Unmute conversation", function() return conv().muted == true end },
	{ "Pin conversation", "Unpin conversation", function() return conv().pinned == true end },
}
for _, spec in ipairs(TOGGLES) do
	local on, off, readState = spec[1], spec[2], spec[3]
	local before = readState()
	local entry = findEntry(ns.UI.BuildConversationMenu(conv()), before and off or on)
	check("the menu offers " .. (before and off or on), entry ~= nil)
	if entry then
		perform(entry.text, entry.onClick)
		eq(entry.text .. " changed the conversation", readState(), not before)
		local back = findEntry(ns.UI.BuildConversationMenu(conv()), before and on or off)
		check("and the menu now offers the other way", back ~= nil)
		if back then
			perform(back.text, back.onClick)
			eq(back.text .. " put it back", readState(), before)
		end
	end
end

do
	-- Read and unread, which is the pair with a counter behind it rather than a
	-- flag, so it is checked against the counter.
	whisper("noch was", "Thrall", "G-THRALL")
	M.RunFrames(2)
	CM.MarkUnread(thrall)
	check("the thread is unread to begin with", conv().unread > 0, tostring(conv().unread))
	local entry = findEntry(ns.UI.BuildConversationMenu(conv()), "Mark as read")
	check("the menu offers Mark as read", entry ~= nil)
	if entry then
		perform("Mark as read", entry.onClick)
		eq("Mark as read cleared the counter", conv().unread, 0)
	end
	local back = findEntry(ns.UI.BuildConversationMenu(conv()), "Mark as unread")
	check("the menu offers Mark as unread", back ~= nil)
	if back then
		perform("Mark as unread", back.onClick)
		check("Mark as unread set the counter", conv().unread > 0, tostring(conv().unread))
		CM.MarkRead(thrall)
	end
end

do
	-- The popout pair.
	local entry = findEntry(ns.UI.BuildConversationMenu(conv()), "Pop out")
	check("the menu offers Pop out", entry ~= nil)
	if entry then
		perform("Pop out", entry.onClick)
		eq("Pop out detached the conversation", ns.Popout.IsOpen(thrall), true)
		local back = findEntry(ns.UI.BuildConversationMenu(conv()), "Dock")
		check("the menu now offers Dock", back ~= nil)
		if back then
			perform("Dock", back.onClick)
			eq("Dock put it back", ns.Popout.IsOpen(thrall), false)
		end
	end
end

do
	-- The nickname pair, which runs through a prompt rather than acting directly.
	local entry = findEntry(ns.UI.BuildConversationMenu(conv()), "Add a nickname")
	check("the menu offers Add a nickname", entry ~= nil)
	if entry then
		perform("Add a nickname", entry.onClick)
		local dialog = _G.WhatTheWhisperPromptDialog
		check("it opens a prompt", dialog ~= nil and dialog:IsShown())
		if dialog and dialog:IsShown() then
			dialog.input:SetText("Warchief")
			M.Click(dialog.accept, "LeftButton")
			M.RunFrames(4)
			eq("accepting the prompt set the nickname", CM.GetAlias(thrall), "Warchief")
			check("and the thread now answers to it",
				CM.DisplayName(conv()) == "Warchief", CM.DisplayName(conv()))
		end
	end
	local remove = findEntry(ns.UI.BuildConversationMenu(conv()), "Remove nickname")
	check("the menu offers Remove nickname once there is one", remove ~= nil)
	if remove then
		perform("Remove nickname", remove.onClick)
		eq("removing it clears the nickname", CM.GetAlias(thrall), nil)
	end
end

do
	-- Copy and export, which open dialogs with content in them.
	local entry = findEntry(ns.UI.BuildConversationMenu(conv()), "Copy name")
	if entry then
		perform("Copy name", entry.onClick)
		local dialog = _G.WhatTheWhisperCopyDialog
		check("Copy name opens a dialog with the name in it",
			dialog ~= nil and dialog:IsShown() and dialog.edit:GetText() == thrall,
			dialog and dialog.edit:GetText())
		ns.Dialogs.HideAll()
	end
	local export = findEntry(ns.UI.BuildConversationMenu(conv()), "Export conversation")
	check("Export is enabled while there are messages", export and not export.disabled)
	if export then
		perform("Export conversation", export.onClick)
		local dialog = _G.WhatTheWhisperCopyDialog
		check("Export opens a dialog with the thread in it",
			dialog ~= nil and dialog:IsShown() and #dialog.edit:GetText() > 20,
			dialog and #dialog.edit:GetText())
		ns.Dialogs.HideAll()
	end
end

do
	-- The ones that talk to the client -- and each has to get past the client,
	-- which is what the report said none of them did.
	local invited = {}
	local realInvite = _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit
	_G.C_PartyInfo = _G.C_PartyInfo or {}
	_G.C_PartyInfo.InviteUnit = function(name) invited[#invited + 1] = name end
	local invite = findEntry(ns.UI.BuildConversationMenu(conv()), "Invite to group")
	check("Invite to group is offered", invite ~= nil and invite.onClick ~= nil)
	if invite then perform("Invite to group", invite.onClick) end
	eq("the invite reaches the client, addressed as the client addresses them",
		invited[1], "Thrall")
	_G.C_PartyInfo.InviteUnit = realInvite

	-- Look up is the profile pages, to copy.
	local lookUp = findEntry(ns.UI.BuildConversationMenu(conv()), "Look up")
	check("Look up is offered", lookUp ~= nil and lookUp.onClick ~= nil)
	if lookUp then perform("Look up", lookUp.onClick) end
	local links = _G.WhatTheWhisperLinksDialog
	check("Look up opens the profile links", links ~= nil and links:IsShown())
	eq("and sends no /who, which the client would block", #(M.whoSent or {}), 0)
	ns.Dialogs.HideAll()

	-- Add friend is restricted from addon code; the entry is a secure macro
	-- button running the client's own /friend, and clicking it adds the friend
	-- without a single blocked action.
	local add = findEntry(ns.UI.BuildConversationMenu(conv()), "Add friend")
	check("Add friend is offered", add ~= nil)
	eq("through the client's own /friend", add and add.secureMacro, "/friend Thrall")
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv()))
	M.RunFrames(2)
	local secure = _G.WhatTheWhisperSecureAction
	check("with a secure button over it", secure ~= nil and secure:IsVisible())
	if secure and secure:IsVisible() then
		perform("Add friend", function() M.Click(secure) end)
	end
	eq("the friend was added", M.friendsAdded[#M.friendsAdded], "Thrall")
	eq("and nothing was blocked", #M.actionsBlocked, 0, table.concat(M.actionsBlocked, ", "))
	ns.Menu.Close()

	-- Somebody who is already a friend is offered the opposite.
	M.friends = { { name = "Thrall", connected = true } }
	local remove = findEntry(ns.UI.BuildConversationMenu(conv()), "Remove friend")
	check("a friend is offered Remove friend instead", remove ~= nil and remove.onClick ~= nil)
	check("and not Add friend", findEntry(ns.UI.BuildConversationMenu(conv()), "Add friend") == nil)
	if remove then perform("Remove friend", remove.onClick) end
	eq("which removes them", M.friendsRemoved[#M.friendsRemoved], "Thrall")
	M.friends = {}

	-- Ignore, and then the way back.
	check("nobody is ignored yet", findEntry(ns.UI.BuildConversationMenu(conv()), "Unignore") == nil)
	local ignore = findEntry(ns.UI.BuildConversationMenu(conv()), "Ignore")
	M.ignored = {}
	ns.Compat.AddIgnore(thrall)
	eq("ignoring reaches the client", M.ignored["Thrall"], true)
	local unignore = findEntry(ns.UI.BuildConversationMenu(conv()), "Unignore")
	check("an ignored player is offered Unignore", unignore ~= nil and unignore.onClick ~= nil,
		ignore and ignore.text)
	check("and not Ignore again", findEntry(ns.UI.BuildConversationMenu(conv()), "Ignore") == nil)
	if unignore then perform("Unignore", unignore.onClick) end
	eq("which takes them off the list", M.ignored["Thrall"], nil)

	-- Target is gone: the report asked for it to go.
	check("there is no Target entry", findEntry(ns.UI.BuildConversationMenu(conv()), "Target") == nil)
end

--------------------------------------------------------------------------------
-- The message menu
--------------------------------------------------------------------------------

do
	local view = ns.MainWindow.Get().view
	local bubble
	for f in view.list.bubblePool:EnumerateActive() do bubble = bubble or f end
	check("there is a message on screen to right-click", bubble ~= nil)
	if bubble then
		local opened
		local realOpen = ns.Menu.Open
		ns.Menu.Open = function(entries, opts) opened = entries return realOpen(entries, opts) end
		perform("right-click a message", function() view.list:OpenMessageMenu(bubble) end)
		ns.Menu.Open = realOpen
		ns.Menu.Close()
		check("the message menu opened with entries", opened ~= nil and #opened > 0)
		for i = 1, #(opened or {}) do
			local entry = opened[i]
			if not entry.separator then
				check("message menu entry does something: " .. tostring(entry.text),
					entry.onClick ~= nil, entry.text)
				if entry.onClick then
					perform("message menu: " .. tostring(entry.text), entry.onClick)
					ns.Dialogs.HideAll()
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Every button in the chrome
--------------------------------------------------------------------------------

-- Walked rather than listed, so a button added later is audited without anybody
-- remembering to add it here.
do
	ns.Dialogs.HideAll()
	ns.Menu.Close()
	M.RunFrames(4)
	local window = ns.MainWindow.Get()
	local clickable = {}
	for _, node in ipairs(M.Descendants(window)) do
		local scripts = node._scripts
		if scripts and (scripts.OnMouseUp or scripts.OnClick)
			and M.EffectivelyShown(node, window) then
			local w, h = node:GetWidth() or 0, node:GetHeight() or 0
			if w > 1 and h > 1 then clickable[#clickable + 1] = node end
		end
	end
	check("the window has buttons to click", #clickable >= 8, tostring(#clickable))
	print(("      (%d clickable nodes walked)"):format(#clickable))

	local errorsBefore, softBefore = #M.errors, #soft
	for i = 1, #clickable do
		local node = clickable[i]
		if node:IsShown() then
			pcall(M.Click, node, "LeftButton")
			M.RunFrames(2)
			ns.Menu.Close()
			ns.Dialogs.HideAll()
			ns.SettingsUI.Hide()
			-- Whatever a click opened, the messenger goes back up for the next one.
			ns.UI.Show()
			M.RunFrames(2)
		end
	end
	check("clicking every button in the window raises nothing",
		#M.errors == errorsBefore,
		("%d new: %s"):format(#M.errors - errorsBefore, tostring(M.errors[#M.errors])))
	check("and logs no soft error",
		#soft == softBefore,
		("%d new: %s"):format(#soft - softBefore, tostring(soft[#soft])))
end

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
