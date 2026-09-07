-- WhatTheWhisper -- Deciding what a new message is allowed to interrupt.
--
-- The rules the UI is judged by:
--   * a thread you are already looking at never notifies and never counts unread
--   * a thread you are not looking at gets a badge, and at most one sound and
--     one toast per cooldown window no matter how fast the messages arrive
--   * nothing steals focus unless you asked it to

local _, ns = ...
local Sounds = ns.Sounds

local Notifications = {}
ns.Notifications = Notifications

local function settings()
	return (ns.db and ns.db.profile and ns.db.profile.notifications)
		or ns.defaults.profile.notifications
end

local function messageSettings()
	return (ns.db and ns.db.profile and ns.db.profile.messages)
		or ns.defaults.profile.messages
end

--------------------------------------------------------------------------------
-- Incoming
--------------------------------------------------------------------------------

function Notifications.OnIncoming(conv, msg, isMention)
	if not conv or not msg then return end
	local UI = ns.UI
	local visible = UI and UI.IsConversationVisible(conv.id) or false
	local windowShown = UI and UI.IsAnyWindowShown() or false

	-- Sound
	if isMention then
		Sounds.Play("mention", conv)
	elseif not windowShown then
		Sounds.Play("hiddenMessage", conv)
	elseif not visible then
		Sounds.Play("newMessage", conv)
	end

	-- Toast: only when you cannot already see the message.
	if settings().toasts and not visible and not conv.muted then
		if UI and UI.ShowToast then
			UI.ShowToast(conv, msg, isMention)
		end
	end

	-- Taskbar flash when the game does not have focus. FlashClientIcon is a
	-- no-op in-game, so this costs nothing when the player is at the keyboard.
	if settings().flashClient and not conv.muted and type(_G.FlashClientIcon) == "function" then
		pcall(_G.FlashClientIcon)
	end

	-- Window behaviour.
	--
	-- Muting a thread means "do not interrupt me about this one". The toast and
	-- the taskbar flash already respected that; opening the window did not, so a
	-- muted conversation still shoved the messenger in front of the player --
	-- which is the loudest interruption of the three.
	local ms = messageSettings()
	if ms.openOnWhisper and UI and not conv.muted then
		UI.Show()
		if ms.autoSwitch then
			ns.ConversationManager.Select(conv.id)
		end
	elseif ms.autoSwitch and windowShown and not conv.muted then
		ns.ConversationManager.Select(conv.id)
	end

	if UI and UI.EnsureConversationOpen then
		UI.EnsureConversationOpen(conv.id, false)
	end
end

--------------------------------------------------------------------------------
-- Outgoing / status
--------------------------------------------------------------------------------

function Notifications.OnSendFailed(conv)
	if not conv then return end
	local UI = ns.UI
	if UI and UI.ShowStatusToast then
		local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")
		UI.ShowStatusToast(string.format(L["%s is offline. Message not delivered."], conv.name))
	end
end
