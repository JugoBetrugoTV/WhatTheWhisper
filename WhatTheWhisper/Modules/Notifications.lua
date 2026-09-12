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
	--
	-- Opening the messenger because of a message and then showing a different
	-- thread is worse than leaving it shut, so the window that pops up is
	-- always on the message that caused it. autoSwitch is a different question
	-- -- whether to interrupt a conversation already on screen -- and only
	-- applies once the window is up.
	local ms = messageSettings()
	if UI and not conv.muted and not visible then
		if ms.openOnWhisper and not UI.IsShown() then
			UI.Show()
			ns.ConversationManager.Select(conv.id)
		elseif ms.autoSwitch and UI.IsShown() then
			ns.ConversationManager.Select(conv.id)
		end
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
		local L = ns.L
		UI.ShowStatusToast(string.format(L["%s is offline. Message not delivered."], conv.name))
	end
end
