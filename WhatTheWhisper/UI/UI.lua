-- WhatTheWhisper -- UI coordinator.
--
-- Everything that owns cross-component state lives here: which conversations
-- have tabs, which are popped out, what combat did to the windows, and how the
-- model's bus events reach the views.

local _, ns = ...
local Theme, Anim, Compat = ns.Theme, ns.Anim, ns.Compat
local CM = ns.ConversationManager
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local UI = {}
ns.UI = UI

local tabOrder = {}
local tabSweepScheduled = false
local combatState

--------------------------------------------------------------------------------
-- Window access
--------------------------------------------------------------------------------

local function main()
	return ns.MainWindow.Get()
end

function UI.Show()
	local window = main()
	if window:IsShown() then
		window:Raise()
		return
	end
	window:Show()
	Anim.PopIn(window, Theme.Duration("WINDOW"))
	window:RefreshUnreadBadge()
	local selected = CM.SelectedID()
	if not selected then
		local ordered = CM.Ordered()
		if ordered[1] then CM.Select(ordered[1].id) end
	end
	UI.RefreshAll()
end

function UI.Hide()
	local window = main()
	if not window:IsShown() then return end
	Anim.FadeOut(window, Theme.Duration("FAST"), function() window:Hide() end)
	ns.Menu.Close()
	ns.EmojiPicker.Close()
end

function UI.Toggle()
	if main():IsShown() then UI.Hide() else UI.Show() end
end

function UI.Minimize()
	UI.Hide()
end

function UI.IsAnyWindowShown()
	if main():IsShown() then return true end
	local any = false
	ns.Popout.Each(function() any = true end)
	return any
end

-- "Visible" means the message is genuinely on screen: the right conversation is
-- selected in a shown main window, or its popout is open and not minimised.
function UI.IsConversationVisible(id)
	local popout = ns.Popout.Get(id)
	if popout and popout:IsShown() and not popout.minimized then return true end
	local window = main()
	if window:IsShown() and CM.SelectedID() == id then return true end
	return false
end

function UI.OnComposerEscape()
	-- Escape in the composer gives the game back its keyboard, it does not close
	-- the window; that would be infuriating mid-sentence.
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

function UI.GetTabOrder()
	return tabOrder
end

local function tabIndex(id)
	for i = 1, #tabOrder do
		if tabOrder[i] == id then return i end
	end
	return nil
end

function UI.EnsureConversationOpen(id, focus)
	if not CM.Get(id) then return end
	if not tabIndex(id) then
		if ns.db.profile.layout.tabAutoOpen or focus then
			tabOrder[#tabOrder + 1] = id
			local limit = ns.db.profile.layout.maxTabs or 8
			-- Retire the least recently active tab rather than growing forever.
			while #tabOrder > limit do
				local victim, victimIndex
				for i = 1, #tabOrder do
					local conv = CM.Get(tabOrder[i])
					if conv and tabOrder[i] ~= CM.SelectedID() and not conv.poppedOut then
						if not victim or conv.lastActivity < victim.lastActivity then
							victim, victimIndex = conv, i
						end
					end
				end
				if not victimIndex then break end
				table.remove(tabOrder, victimIndex)
			end
			if main().tabs then main().tabs:Refresh() end
		end
	end
	if focus then
		UI.Show()
		CM.Select(id)
	end
end

function UI.MoveTab(id, target)
	local index = tabIndex(id)
	if not index or index == target then return end
	table.remove(tabOrder, index)
	table.insert(tabOrder, math.max(1, math.min(#tabOrder + 1, target)), id)
end

function UI.CloseConversation(id)
	local index = tabIndex(id)
	if index then table.remove(tabOrder, index) end
	if ns.Popout.IsOpen(id) then ns.Popout.Close(id) end
	ns.Sounds.Play("closeConv")
	if CM.SelectedID() == id then
		local ordered = CM.Ordered()
		local nextID
		for i = 1, #ordered do
			if ordered[i].id ~= id then nextID = ordered[i].id break end
		end
		CM.Select(nextID)
	end
	if main().tabs then main().tabs:Refresh() end
end

function UI.ScheduleTabSweep()
	local minutes = ns.db.profile.layout.tabAutoClose or 0
	if minutes <= 0 or tabSweepScheduled then return end
	tabSweepScheduled = true
	Anim.After(60, function()
		tabSweepScheduled = false
		local limit = (ns.db.profile.layout.tabAutoClose or 0) * 60
		if limit <= 0 then return end
		local now = Compat.GetServerTime()
		for i = #tabOrder, 1, -1 do
			local id = tabOrder[i]
			local conv = CM.Get(id)
			if conv and id ~= CM.SelectedID() and conv.unread == 0
				and not conv.poppedOut and not conv.pinned
				and (now - (conv.lastActivity or 0)) > limit then
				table.remove(tabOrder, i)
			end
		end
		if main().tabs then main().tabs:Refresh() end
		UI.ScheduleTabSweep()
	end)
end

--------------------------------------------------------------------------------
-- Popouts
--------------------------------------------------------------------------------

function UI.TogglePopout(id)
	if ns.Popout.IsOpen(id) then
		UI.DockConversation(id)
	else
		ns.Popout.Open(id)
		ns.Sounds.Play("openConv")
	end
end

function UI.DockConversation(id)
	ns.Popout.Close(id)
	UI.Show()
	CM.Select(id)
end

--------------------------------------------------------------------------------
-- Context menu
--------------------------------------------------------------------------------

function UI.BuildConversationMenu(conv)
	local entries = {}
	local isBN = conv.isBN
	local shortName = isBN and conv.name or Compat.ShortName(conv.id)

	entries[#entries + 1] = { text = L["Whisper"], icon = "message", onClick = function()
		UI.Show()
		CM.Select(conv.id)
		Anim.After(0.05, function() main().view:Focus() end)
	end }

	if not isBN and Compat.canInvite then
		entries[#entries + 1] = { text = L["Invite to group"], icon = "person_plus",
			onClick = function() Compat.InviteUnit(conv.id) end }
	end

	if not isBN then
		-- Targeting from insecure Lua is impossible, so this entry is backed by a
		-- real secure macro button; ContextMenu disables it during combat.
		entries[#entries + 1] = {
			text = L["Target"], icon = "person",
			secureMacro = "/target " .. conv.id,
			combatTooltip = L["Combat"],
		}
	end

	if not isBN and Compat.canAddFriend then
		entries[#entries + 1] = { text = L["Add friend"], icon = "star",
			onClick = function() Compat.AddFriend(conv.id) end }
	end

	if not isBN and Compat.canWho then
		entries[#entries + 1] = { text = L["Look up"], icon = "search",
			onClick = function() ns.PlayerInfo.RequestWho(conv.id) end }
	end

	entries[#entries + 1] = { separator = true }

	entries[#entries + 1] = { text = L["Copy name"], icon = "copy", onClick = function()
		ns.Dialogs.ShowCopy(conv.id, L["Copy name"])
	end }
	entries[#entries + 1] = { text = L["Export conversation"], icon = "export",
		disabled = #conv.messages == 0,
		onClick = function() ns.Dialogs.ShowExport(conv) end }

	entries[#entries + 1] = { separator = true }

	entries[#entries + 1] = {
		text = conv.muted and L["Unmute conversation"] or L["Mute conversation"],
		icon = conv.muted and "volume" or "volume_off",
		onClick = function() CM.SetMuted(conv.id, not conv.muted) end,
	}
	entries[#entries + 1] = {
		text = conv.pinned and L["Unpin conversation"] or L["Pin conversation"],
		icon = conv.pinned and "pin_filled" or "pin",
		onClick = function() CM.SetPinned(conv.id, not conv.pinned) end,
	}
	entries[#entries + 1] = {
		text = conv.unread > 0 and L["Mark as read"] or L["Mark as unread"],
		icon = "check",
		onClick = function()
			if conv.unread > 0 then CM.MarkRead(conv.id) else CM.MarkUnread(conv.id) end
		end,
	}
	entries[#entries + 1] = {
		text = ns.Popout.IsOpen(conv.id) and L["Dock"] or L["Pop out"],
		icon = ns.Popout.IsOpen(conv.id) and "dock" or "popout",
		onClick = function() UI.TogglePopout(conv.id) end,
	}

	entries[#entries + 1] = { separator = true }

	entries[#entries + 1] = { text = L["Close conversation"], icon = "close",
		onClick = function() UI.CloseConversation(conv.id) end }
	entries[#entries + 1] = {
		text = L["Clear history"], icon = "trash", danger = true,
		disabled = #conv.messages == 0,
		onClick = function() UI.ConfirmClear(conv) end,
	}
	if not isBN and Compat.canIgnore then
		entries[#entries + 1] = { text = L["Ignore"], icon = "block", danger = true,
			onClick = function()
				Compat.AddIgnore(conv.id)
				UI.CloseConversation(conv.id)
			end }
	end

	return entries
end

--------------------------------------------------------------------------------
-- Dialog helpers
--------------------------------------------------------------------------------

function UI.ConfirmClear(conv)
	ns.Dialogs.Confirm(
		L["Clear this conversation?"],
		L["This removes %d stored messages. It cannot be undone."]:format(#conv.messages),
		L["Delete"],
		function()
			ns.History.Clear(conv.id)
			UI.RefreshAll()
		end, true)
end

function UI.ConfirmClearAll()
	local conversations, messages = ns.History.Stats()
	ns.Dialogs.Confirm(
		L["Clear all history?"],
		L["This removes every stored message in %d conversations. It cannot be undone."]
			:format(conversations),
		L["Delete"],
		function()
			ns.History.ClearAll()
			UI.RefreshAll()
		end, true)
end

function UI.ConfirmResetSettings()
	ns.Dialogs.Confirm(
		L["Reset all settings?"],
		L["Every option goes back to its default. Message history is not touched."],
		L["Reset"],
		function()
			ns.db:ResetProfile()
			Theme.Refresh()
			UI.RefreshLayout()
			UI.RefreshAll()
			if ns.SettingsUI.IsShown() then ns.SettingsUI.Refresh() end
		end, true)
end

function UI.PromptNewConversation()
	ns.Dialogs.Prompt(L["New conversation"], L["Whisper a player"],
		L["Enter a character name"], L["Open"], function(value)
			local id = Compat.NormalizeName(ns.Text.UpperFirst(value))
			CM.GetOrCreate(id)
			UI.Show()
			CM.Select(id)
			UI.EnsureConversationOpen(id, true)
			Anim.After(0.05, function() main().view:Focus() end)
		end)
end

--------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------

function UI.ShowToast(conv, msg, isMention)
	ns.Toast.Show(conv, msg, isMention)
end

function UI.ShowStatusToast(text)
	ns.Print(text)
end

--------------------------------------------------------------------------------
-- Combat
--------------------------------------------------------------------------------

function UI.CaptureVisibility()
	local state = { main = main():IsShown(), popouts = {} }
	ns.Popout.Each(function(id, win) state.popouts[id] = not win.minimized end)
	return state
end

function UI.RestoreVisibility(state)
	if not state then return end
	if state.main and not main():IsShown() then UI.Show() end
	for id, wasOpen in pairs(state.popouts) do
		local win = ns.Popout.Get(id)
		if win then
			win:Show()
			if wasOpen and win.minimized then win:ToggleMinimized(false) end
		end
	end
end

function UI.SetCombatFade(opacity)
	local alpha = opacity or 1
	main():SetAlpha(alpha)
	ns.Popout.Each(function(_, win) win:SetAlpha(alpha) end)
end

function UI.MinimizeAll()
	main():Hide()
	ns.Popout.Each(function(_, win) win:ToggleMinimized(true) end)
end

function UI.HideAll()
	main():Hide()
	ns.Popout.Each(function(_, win) win:Hide() end)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function UI.RefreshLayout()
	local window = main()
	window:Relayout()
	window:SetSidebarWidth(ns.db.profile.layout.sidebarWidth or ns.SZ.SIDEBAR_W)
	window.tabs:Refresh()
	UI.ScheduleTabSweep()
end

function UI.RefreshAll()
	local window = main()
	window.sidebar:Refresh()
	window.tabs:Refresh()
	window.view:SetConversation(CM.Selected())
	window.view.list:Rebuild(true)
	window:RefreshUnreadBadge()
	ns.Popout.Each(function(id, win)
		win.view.list:Rebuild(true)
		win.view:RefreshHeader()
	end)
end

function UI.ApplyTheme()
	main():ApplyTheme()
	ns.Popout.ApplyTheme()
	ns.Toast.ApplyTheme()
	ns.Tooltip.ApplyTheme()
	ns.Menu.ApplyTheme()
	ns.EmojiPicker.ApplyTheme()
	ns.Dialogs.ApplyTheme()
	ns.SettingsUI.ApplyTheme()
	ns.Expose.ApplyTheme()
	ns.Minimap.ApplyTheme()
end

--------------------------------------------------------------------------------
-- Bus wiring
--------------------------------------------------------------------------------

function UI.Init()
	local Bus, EV = ns.Bus, ns.EV

	Bus.Register(EV.THEME_CHANGED, "UI", function()
		UI.ApplyTheme()
	end)

	Bus.Register(EV.CONVERSATION_ADDED, "UI", function(conv)
		main().sidebar:Refresh()
		if ns.db.profile.layout.tabAutoOpen then UI.EnsureConversationOpen(conv.id, false) end
	end)

	Bus.Register(EV.CONVERSATION_REMOVED, "UI", function(id)
		local index = nil
		for i = 1, #tabOrder do if tabOrder[i] == id then index = i break end end
		if index then table.remove(tabOrder, index) end
		ns.Popout.Close(id)
		main().sidebar:Refresh()
		main().tabs:Refresh()
	end)

	Bus.Register(EV.CONVERSATION_UPDATED, "UI", function(conv)
		main().sidebar:Refresh()
		main().tabs:Refresh()
		main().view:OnConversationUpdated(conv)
		ns.Popout.OnConversationUpdated(conv)
	end)

	Bus.Register(EV.CONVERSATION_SELECTED, "UI", function(id)
		local conv = id and CM.Get(id) or nil
		main().view:SetConversation(conv)
		main().sidebar:Refresh()
		main().sidebar:ScrollToConversation(id)
		main().tabs:Refresh()
		if conv then UI.EnsureConversationOpen(id, false) end
		ns.Toast.DismissFor(id)
	end)

	Bus.Register(EV.MESSAGE_ADDED, "UI", function(conv, msg, index)
		main().view:OnMessageAdded(conv, msg, index)
		ns.Popout.OnMessageAdded(conv, msg, index)
		main().sidebar:Refresh()
		main().tabs:Refresh()
	end)

	Bus.Register(EV.MESSAGE_UPDATED, "UI", function(conv, msg)
		main().view:OnMessageUpdated(conv, msg)
		ns.Popout.OnMessageUpdated(conv, msg)
	end)

	Bus.Register(EV.UNREAD_CHANGED, "UI", function()
		main():RefreshUnreadBadge()
		ns.Minimap.Update()
	end)

	Bus.Register(EV.PLAYER_INFO_UPDATED, "UI", function(fullName)
		if not main():IsShown() then return end
		main().sidebar:Refresh()
		local selected = CM.Selected()
		if selected and (not fullName or selected.id == fullName) then
			main().view:RefreshHeader()
		end
	end)

	Bus.Register(EV.HISTORY_CLEARED, "UI", function()
		UI.RefreshAll()
	end)

	UI.ScheduleTabSweep()
end
