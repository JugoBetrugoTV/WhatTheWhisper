-- WhatTheWhisper -- Notification sounds.
--
-- Only sound kits that exist unchanged on all four clients are offered, plus
-- any file the user points at and anything LibSharedMedia provides if another
-- addon already loaded it. Nothing is faked: a kit that will not play on this
-- client is not in the list.

local _, ns = ...
local Compat = ns.Compat

local Sounds = {}
ns.Sounds = Sounds

local GetTime = GetTime

-- id -> { label, kit } ; "none" and "custom" are handled specially.
Sounds.LIBRARY = {
	{ id = "none",           label = "None" },
	{ id = "TELL_MESSAGE",   label = "Whisper" },
	{ id = "READY_CHECK",    label = "Ready check" },
	{ id = "RAID_WARNING",   label = "Raid warning" },
	{ id = "MAP_PING",       label = "Map ping" },
	{ id = "QUEST_SELECT",   label = "Soft click" },
	{ id = "MENU_OPEN",      label = "Panel open" },
	{ id = "MENU_CLOSE",     label = "Panel close" },
	{ id = "CHARACTER_OPEN", label = "Sheet open" },
	{ id = "FRIEND_JOIN",    label = "Friend online" },
	{ id = "custom",         label = "Custom file" },
}

local function settings()
	return (ns.db and ns.db.profile and ns.db.profile.sounds) or ns.defaults.profile.sounds
end

--------------------------------------------------------------------------------
-- Suppression rules
--------------------------------------------------------------------------------

function Sounds.IsSuppressed()
	local s = settings()
	if s.dnd then return true, "dnd" end
	if s.muteCombat and InCombatLockdown() then return true, "combat" end

	local instanceType = Compat.InstanceType()
	if instanceType then
		if instanceType == "party" and s.muteDungeon then return true, "dungeon" end
		if instanceType == "raid" and s.muteRaid then return true, "raid" end
		if instanceType == "arena" and s.muteArena then return true, "arena" end
		if instanceType == "pvp" and s.muteBattleground then return true, "battleground" end
	end
	return false
end

--------------------------------------------------------------------------------
-- Playback
--------------------------------------------------------------------------------

local function playSoundID(id)
	if not id or id == "none" then return false end
	local s = settings()
	if id == "custom" then
		if s.customFile and s.customFile ~= "" then
			return Compat.PlaySoundFile(s.customFile, "Master")
		end
		return false
	end
	-- LibSharedMedia entries are stored as "LSM:<name>".
	local lsmName = id:match("^LSM:(.+)$")
	if lsmName then
		local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
		local path = LSM and LSM:Fetch("sound", lsmName, true)
		if path then return Compat.PlaySoundFile(path, "Master") end
		return false
	end
	local kit = Compat.SOUNDS[id]
	if not kit then return false end
	return Compat.PlaySoundKit(kit, "Master")
end

Sounds.PlayID = playSoundID

-- event: "newMessage" | "hiddenMessage" | "mention" | "openConv" | "closeConv"
function Sounds.Play(event, conv)
	local s = settings()
	if conv and conv.muted then return false end
	if Sounds.IsSuppressed() then return false end

	-- One sound per conversation per cooldown window, so a burst of five
	-- messages is one notification, not five.
	if conv and (event == "newMessage" or event == "hiddenMessage" or event == "mention") then
		local cooldown = tonumber(s.cooldown) or 0
		if cooldown > 0 then
			local now = GetTime()
			if now - (conv.lastSoundAt or 0) < cooldown then return false end
			conv.lastSoundAt = now
		end
	end

	return playSoundID(s[event])
end

function Sounds.Preview(id)
	local suppressed = Sounds.IsSuppressed()
	if suppressed then
		-- A preview the user explicitly asked for always plays.
		local s = settings()
		local dnd = s.dnd
		s.dnd = false
		local played = playSoundID(id)
		s.dnd = dnd
		return played
	end
	return playSoundID(id)
end

--------------------------------------------------------------------------------
-- Option list
--------------------------------------------------------------------------------

function Sounds.Options()
	local out = {}
	for i = 1, #Sounds.LIBRARY do
		out[#out + 1] = { value = Sounds.LIBRARY[i].id, label = Sounds.LIBRARY[i].label }
	end
	local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
	if LSM then
		local list = LSM:List("sound")
		for i = 1, #list do
			out[#out + 1] = { value = "LSM:" .. list[i], label = list[i] }
		end
	end
	return out
end
