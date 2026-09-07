-- WhatTheWhisper -- What we can honestly know about the other player.
--
-- WoW gives an addon no lookup for "tell me about this name". What it does give:
--   * the sender GUID on every chat event   -> class, race, (faction by race)
--   * the guild roster                      -> class, level, online
--   * the friends list                      -> class, level, online
--   * units currently in range              -> class, level
--   * an explicit /who, user-initiated only -> class, level, guild, zone
--
-- Everything below is one of those. Nothing is invented, and any field we do not
-- know stays nil so the UI can leave it out instead of showing a placeholder.

local _, ns = ...
local Compat = ns.Compat

local PlayerInfo = {}
ns.PlayerInfo = PlayerInfo

local cache = {}
local cacheCount = 0
local CACHE_LIMIT = 600

local lastWho = 0
local pendingWho

local function entry(fullName, create)
	if not fullName then return nil end
	local e = cache[fullName]
	if e then
		e.touched = GetTime()
		return e
	end
	if not create then return nil end
	if cacheCount >= CACHE_LIMIT then
		-- Drop the least recently touched quarter rather than clearing outright.
		local ordered = {}
		for name, info in pairs(cache) do
			ordered[#ordered + 1] = { name = name, t = info.touched or 0 }
		end
		table.sort(ordered, function(a, b) return a.t < b.t end)
		for i = 1, math.floor(#ordered / 4) do
			cache[ordered[i].name] = nil
			cacheCount = cacheCount - 1
		end
	end
	e = { touched = GetTime() }
	cache[fullName] = e
	cacheCount = cacheCount + 1
	return e
end

local function changed(fullName)
	ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, fullName)
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

-- Called for every incoming and outgoing whisper. The GUID is the most reliable
-- source we ever get, so it wins over everything else.
function PlayerInfo.Observe(fullName, guid)
	if not fullName then return end
	local e = entry(fullName, true)
	local dirty = false
	if guid and guid ~= "" and e.guid ~= guid then
		e.guid = guid
		local class, race = Compat.GetPlayerInfoByGUID(guid)
		if class and class ~= e.class then e.class = class dirty = true end
		if race and race ~= e.race then
			e.race = race
			local faction = Compat.FactionForRace(race)
			if faction then e.faction = faction end
			dirty = true
		end
	end
	if not e.class then
		local class, level = Compat.ClassFromVisibleUnit(fullName)
		if class then
			e.class = class
			if level and level > 0 then e.level = level end
			dirty = true
		end
	end
	e.lastSeen = time()
	if dirty then changed(fullName) end
end

function PlayerInfo.Set(fullName, fields)
	if not fullName or not fields then return end
	local e = entry(fullName, true)
	local dirty = false
	for k, v in pairs(fields) do
		if v ~= nil and e[k] ~= v then
			e[k] = v
			dirty = true
		end
	end
	if dirty then changed(fullName) end
end

function PlayerInfo.Get(fullName)
	return entry(fullName, false)
end

function PlayerInfo.GetClass(fullName)
	local e = cache[fullName]
	return e and e.class
end

function PlayerInfo.IsOnline(fullName)
	local e = cache[fullName]
	if not e then return nil end
	return e.online
end

--------------------------------------------------------------------------------
-- Roster scanning
--------------------------------------------------------------------------------

local function scanGuild()
	local n = Compat.GetNumGuildMembers()
	if n == 0 then return end
	for i = 1, n do
		local name, level, classFile, online = Compat.GetGuildRosterInfo(i)
		if name then
			local full = Compat.NormalizeName(name)
			local e = cache[full]
			if e then
				e.class = classFile or e.class
				e.level = level or e.level
				e.online = online
				e.source = "guild"
			end
		end
	end
	ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, nil)
end

local function scanFriends()
	local n = Compat.GetNumFriends()
	for i = 1, n do
		local name, level, _, connected = Compat.GetFriendInfo(i)
		if name then
			local full = Compat.NormalizeName(name)
			local e = cache[full]
			if e then
				e.level = level or e.level
				e.online = connected
				e.source = e.source or "friend"
			end
		end
	end
	ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, nil)
end

PlayerInfo.ScanGuild = scanGuild
PlayerInfo.ScanFriends = scanFriends

--------------------------------------------------------------------------------
-- /who, only ever from a click
--------------------------------------------------------------------------------

function PlayerInfo.RequestWho(fullName)
	if not Compat.canWho then return false end
	local now = GetTime()
	if now - lastWho < (Compat.whoThrottle or 5) then return false end
	lastWho = now
	pendingWho = fullName
	local base = fullName:match("^([^%-]+)") or fullName
	return Compat.SendWho(base) and true or false
end

-- Consumes the results of a /who we asked for. Blizzard's own frame also
-- receives them; we never suppress that.
function PlayerInfo.HandleWhoResults()
	if not pendingWho then return end
	local target = pendingWho
	pendingWho = nil

	local getNum = _G.C_FriendList and _G.C_FriendList.GetNumWhoResults
	local getInfo = _G.C_FriendList and _G.C_FriendList.GetWhoInfo
	local count = 0
	if getNum then
		local ok, n = pcall(getNum)
		count = (ok and n) or 0
	elseif _G.GetNumWhoResults then
		count = _G.GetNumWhoResults() or 0
	end

	for i = 1, count do
		local name, level, classFile, guild, zone
		if getInfo then
			local ok, info = pcall(getInfo, i)
			if ok and info then
				name, level, classFile, guild, zone =
					info.fullName, info.level, info.filename, info.fullGuildName, info.area
			end
		elseif _G.GetWhoInfo then
			local ok, n, g, l, _, _, z = pcall(_G.GetWhoInfo, i)
			if ok then name, guild, level, zone = n, g, l, z end
		end
		if name then
			local full = Compat.NormalizeName(name)
			if full == target then
				PlayerInfo.Set(full, {
					level = level, class = classFile, guild = guild,
					zone = zone, online = true, source = "who",
				})
				return
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Display helpers
--------------------------------------------------------------------------------

-- One short line for the conversation header: "Level 70 Shaman - Blackrock".
function PlayerInfo.StatusLine(fullName, isBN)
	if isBN then
		return nil
	end
	local e = cache[fullName]
	local parts = {}
	if e then
		if e.level and e.level > 0 then
			parts[#parts + 1] = string.format(_G.LEVEL and (_G.LEVEL .. " %d") or "Level %d", e.level)
		end
		if e.class then
			local localized = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[e.class]
			parts[#parts + 1] = localized or e.class
		end
	end
	if Compat.IsCrossRealm(fullName) then
		parts[#parts + 1] = Compat.RealmOf(fullName)
	end
	if #parts == 0 then return nil end
	return table.concat(parts, " \194\183 ")   -- middle dot
end

function PlayerInfo.Wipe()
	wipe(cache)
	cacheCount = 0
end
