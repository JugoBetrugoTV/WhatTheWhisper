-- WhatTheWhisper -- Internal publish/subscribe.
--
-- Deliberately separate from AceEvent: this carries *addon* events (a
-- conversation changed, the theme was reskinned, unread counts moved) between
-- modules, and it never touches the game's event system. Handlers are keyed so
-- a module can replace its own subscription without leaking the previous one.

local _, ns = ...

local Bus = {}
ns.Bus = Bus

local listeners = {}
local firing = {}

function Bus.Register(event, key, handler)
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
	end
	for i = 1, #list do
		if list[i].key == key then
			list[i].handler = handler
			return
		end
	end
	list[#list + 1] = { key = key, handler = handler }
end

function Bus.Unregister(event, key)
	local list = listeners[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i].key == key then
			table.remove(list, i)
		end
	end
end

function Bus.UnregisterAll(key)
	for _, list in pairs(listeners) do
		for i = #list, 1, -1 do
			if list[i].key == key then
				table.remove(list, i)
			end
		end
	end
end

function Bus.Fire(event, ...)
	local list = listeners[event]
	if not list then return end
	-- Guard against a handler that fires the same event again.
	if firing[event] then
		ns.SoftError("Bus", "re-entrant fire of " .. tostring(event))
		return
	end
	firing[event] = true
	for i = 1, #list do
		local entry = list[i]
		if entry then
			local ok, err = pcall(entry.handler, ...)
			if not ok then
				ns.SoftError("Bus:" .. tostring(event) .. ":" .. tostring(entry.key), err)
			end
		end
	end
	firing[event] = nil
end

function Bus.CountListeners(event)
	local list = listeners[event]
	return list and #list or 0
end

-- Event names, kept here so a typo is a nil index rather than a silent no-op.
ns.EV = setmetatable({}, {
	__index = function(_, k) error("unknown addon event: " .. tostring(k), 2) end,
})

local events = {
	"CONVERSATION_ADDED", "CONVERSATION_REMOVED", "CONVERSATION_UPDATED",
	"CONVERSATION_SELECTED", "MESSAGE_ADDED", "MESSAGE_UPDATED",
	"UNREAD_CHANGED", "THEME_CHANGED", "SETTINGS_CHANGED", "LAYOUT_CHANGED",
	"PLAYER_INFO_UPDATED", "HISTORY_CLEARED", "COMBAT_STATE_CHANGED",
	"SEARCH_CHANGED", "TYPING_STATE",
}
for i = 1, #events do
	rawset(ns.EV, events[i], events[i])
end
