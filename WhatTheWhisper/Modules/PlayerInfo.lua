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
		local class, race, _, _, _, localizedRace = Compat.GetPlayerInfoByGUID(guid)
		if class and class ~= e.class then e.class = class dirty = true end
		if race and race ~= e.race then
			e.race = race
			-- The English name is what the faction table is keyed on; the
			-- localized one is what a German player expects to read.
			e.raceName = localizedRace or race
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
	-- Presence carries its own provenance, separate from where the profile data
	-- came from: how long an answer stays true depends on whether the client
	-- will tell us when it changes.
	if fields.online ~= nil then
		e.presenceAt = time()
		e.presenceSource = fields.presenceSource or fields.source or "observed"
	end
	if dirty then changed(fullName) end
end

--------------------------------------------------------------------------------
-- Presence
--------------------------------------------------------------------------------

-- Sources the client keeps up to date on its own: the guild roster and the
-- friends list both push an event when somebody logs in or out, so what they
-- last told us stays true until they tell us otherwise.
local LIVE_SOURCES = { guild = true, friend = true, bnet = true }

-- Everything else is a single observation at a point in time. Somebody who
-- whispered you was unquestionably online *then*; ten minutes later that is a
-- guess, and a green dot that is a guess is worse than no dot -- so it expires
-- back to "unknown" rather than going stale.
local PRESENCE_TTL = 600

-- The strongest presence evidence there is, and the one the addon was throwing
-- away: a message from somebody means they are online, and the server accepting
-- a message to them means the same. Every conversation has at least one.
function PlayerInfo.NoteActivity(fullName)
	if not fullName then return end
	local e = entry(fullName, true)
	local wasOnline = e.online
	e.online = true
	e.presenceAt = time()
	e.presenceSource = "message"
	e.lastSeen = e.presenceAt
	if not wasOnline then changed(fullName) end
end

function PlayerInfo.Get(fullName)
	return entry(fullName, false)
end

function PlayerInfo.GetClass(fullName)
	local e = cache[fullName]
	return e and e.class
end

-- true, false, or nil for "the client has not told us". nil is a real answer
-- and the UI draws nothing for it.
function PlayerInfo.IsOnline(fullName)
	local e = cache[fullName]
	if not e or e.online == nil then return nil end
	if LIVE_SOURCES[e.presenceSource] then return e.online end
	if not e.presenceAt then return e.online end
	if (time() - e.presenceAt) > PRESENCE_TTL then return nil end
	return e.online
end

PlayerInfo.PRESENCE_TTL = PRESENCE_TTL

--------------------------------------------------------------------------------
-- Roster scanning
--------------------------------------------------------------------------------

-- Writes one roster row into a cached entry and says whether anything a player
-- could see changed: the class, the level, or the answer to "online?". The time
-- of the sighting always moves, and so can which roster it came from -- someone
-- in the guild and on the friends list is seen by both -- but on their own
-- neither is news.
local function note(key, e, class, level, online, source)
	local wasOnline = PlayerInfo.IsOnline(key)
	local anyChanged = (class and e.class ~= class) or (level and e.level ~= level)
	e.class = class or e.class
	e.level = level or e.level
	e.online = online
	e.presenceAt = time()
	e.presenceSource = source
	return anyChanged or PlayerInfo.IsOnline(key) ~= wasOnline
end

-- Both rosters are rescanned whole on every update, and in a large guild that
-- update arrives every few seconds -- another addon asking for the roster is
-- enough. Announcing each scan redrew the sidebar, the header and the details
-- panel every time whether or not anyone in them had changed, so only a scan
-- that changed something is announced.
local function scanGuild()
	local n = Compat.GetNumGuildMembers()
	if n == 0 then return end
	local anyChanged = false
	for i = 1, n do
		local name, level, classFile, online = Compat.GetGuildRosterInfo(i)
		if name then
			local key = Compat.NormalizeName(name)
			local e = cache[key]
			if e then
				if e.source ~= "guild" then anyChanged = true end
				e.source = "guild"
				if note(key, e, classFile, level, online, "guild") then anyChanged = true end
			end
		end
	end
	if anyChanged then ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, nil) end
end

local function scanFriends()
	local n = Compat.GetNumFriends()
	local anyChanged = false
	for i = 1, n do
		local name, level, _, connected = Compat.GetFriendInfo(i)
		if name then
			local key = Compat.NormalizeName(name)
			local e = cache[key]
			if e then
				if not e.source then
					e.source = "friend"
					anyChanged = true
				end
				if note(key, e, nil, level, connected, "friend") then anyChanged = true end
			end
		end
	end
	if anyChanged then ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, nil) end
end

PlayerInfo.ScanGuild = scanGuild
PlayerInfo.ScanFriends = scanFriends

--------------------------------------------------------------------------------
-- /who results the player asked for
--------------------------------------------------------------------------------

-- The addon never sends a /who. C_FriendList.SendWho is restricted on every
-- supported client and blocked outright from addon code, click or no click,
-- with an ADDON_ACTION_BLOCKED warning naming this addon. But when the player
-- types /who themselves, the answer is there for anyone to read, and it is the
-- only source of a stranger's guild and zone -- so every result that names
-- somebody this addon has a thread with is taken in. Nobody else is recorded.
function PlayerInfo.HandleWhoResults()
	local anyChanged = false
	for i = 1, Compat.GetNumWhoResults() do
		local name, level, classFile, guild, zone = Compat.GetWhoInfo(i)
		local key = name and Compat.NormalizeName(name)
		if key and (cache[key] or ns.ConversationManager.Get(key)) then
			PlayerInfo.Set(key, {
				level = level, class = classFile, guild = guild,
				zone = zone, online = true, source = "who",
				presenceSource = "who",
			})
			anyChanged = true
		end
	end
	return anyChanged
end

--------------------------------------------------------------------------------
-- Display helpers
--------------------------------------------------------------------------------

-- One line for the conversation header, built only out of what the client has
-- actually told us: "Level 70 Shaman - <Wildhammer Clan> - Stormwind City".
-- Anything unknown is simply absent; nothing here is a placeholder.
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
		-- Guild and zone come from a /who, are recorded, and were never shown.
		if e.guild and e.guild ~= "" then
			parts[#parts + 1] = "<" .. e.guild .. ">"
		end
		if e.zone and e.zone ~= "" then
			parts[#parts + 1] = e.zone
		end
	end
	if Compat.IsCrossRealm(fullName) then
		parts[#parts + 1] = Compat.RealmOf(fullName)
	end
	if #parts == 0 then return nil end
	return table.concat(parts, " \194\183 ")   -- middle dot
end

-- The shortest honest line about somebody: what they are doing right now if the
-- client has said, otherwise the one fact most worth the space. Used under the
-- name when the details panel is already spelling everything else out, so that
-- the header carries something rather than nothing.
function PlayerInfo.ShortLine(fullName, isBN)
	if isBN then return nil end
	local online = PlayerInfo.IsOnline(fullName)
	if online ~= nil then return online and "online" or "offline" end
	local e = cache[fullName]
	if e and e.class then
		local names = _G.LOCALIZED_CLASS_NAMES_MALE
		return "class", (names and names[e.class]) or e.class
	end
	if Compat.IsCrossRealm(fullName) then
		return "text", Compat.RealmOf(fullName)
	end
	return nil
end

-- The word for the status dot, so a tooltip can say what the colour means.
function PlayerInfo.PresenceLabel(fullName)
	local online = PlayerInfo.IsOnline(fullName)
	if online == nil then return nil end
	return online and "online" or "offline"
end

function PlayerInfo.Wipe()
	wipe(cache)
	cacheCount = 0
end
