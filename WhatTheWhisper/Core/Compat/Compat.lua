-- WhatTheWhisper -- Cross-client compatibility layer.
--
-- Everything in this file is written against the *smallest* API surface shared by
-- Classic Era 1.15, TBC 2.5.6, MoP Classic 5.5.4 and Retail 12.1. Where a client
-- offers something better, it is detected here (never assumed) and the flavour
-- files in this folder specialise the behaviour.
--
-- Rule for the rest of the codebase: never call a C_* namespace or a version
-- specific global directly. Go through ns.Compat.

local ADDON_NAME, ns = ...

local Compat = {}
ns.Compat = Compat

local _G = _G
local select, type, pcall, tonumber = select, type, pcall, tonumber
local strmatch, strfind, gsub = string.match, string.find, string.gsub

--------------------------------------------------------------------------------
-- Flavour detection
--------------------------------------------------------------------------------

local buildVersion, buildNumber, _, tocVersion = GetBuildInfo()
tocVersion = tonumber(tocVersion) or 0

-- WOW_PROJECT_ID is authoritative where it exists; the interface number is the
-- fallback for anything that predates it or ships it inconsistently.
local projectID = _G.WOW_PROJECT_ID

local flavor
if projectID and _G.WOW_PROJECT_MAINLINE and projectID == _G.WOW_PROJECT_MAINLINE then
	flavor = "retail"
elseif projectID and _G.WOW_PROJECT_CLASSIC and projectID == _G.WOW_PROJECT_CLASSIC then
	flavor = "classic"
elseif projectID and _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC
	and projectID == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
	flavor = "tbc"
elseif projectID and _G.WOW_PROJECT_MISTS_CLASSIC
	and projectID == _G.WOW_PROJECT_MISTS_CLASSIC then
	flavor = "mop"
elseif tocVersion >= 100000 then
	flavor = "retail"
elseif tocVersion >= 50000 then
	flavor = "mop"
elseif tocVersion >= 40000 then
	flavor = "cata"
elseif tocVersion >= 30000 then
	flavor = "wrath"
elseif tocVersion >= 20000 then
	flavor = "tbc"
else
	flavor = "classic"
end

Compat.flavor       = flavor
Compat.tocVersion   = tocVersion
Compat.buildVersion = buildVersion
Compat.buildNumber  = tonumber(buildNumber) or 0

Compat.isRetail     = (flavor == "retail")
Compat.isClassicEra = (flavor == "classic")
Compat.isTBC        = (flavor == "tbc")
Compat.isWrath      = (flavor == "wrath")
Compat.isCata       = (flavor == "cata")
Compat.isMoP        = (flavor == "mop")
-- "Modern" means the 9.0+ Lua API shape (C_ namespaces widely available).
Compat.isModern     = Compat.isRetail or Compat.isMoP or Compat.isCata
Compat.isClassicLike = not Compat.isRetail

--------------------------------------------------------------------------------
-- Capability probes
--
-- Probing is done once, at load, against a throwaway frame. Probing beats
-- version checks because Blizzard backports things into Classic without warning.
--------------------------------------------------------------------------------

local probeFrame = CreateFrame("Frame")
probeFrame:Hide()
local probeTex = probeFrame:CreateTexture(nil, "BACKGROUND")
local probeFS  = probeFrame:CreateFontString(nil, "BACKGROUND")

local function has(obj, method)
	return type(obj) == "table" and type(obj[method]) == "function"
end

Compat.hasMasks         = has(probeFrame, "CreateMaskTexture") and has(probeTex, "AddMaskTexture")
Compat.hasClipsChildren = has(probeFrame, "SetClipsChildren")
Compat.hasVertexOffset  = has(probeTex, "SetVertexOffset")
Compat.hasColorTexture  = has(probeTex, "SetColorTexture")
Compat.hasHyperlinks    = has(probeFrame, "SetHyperlinksEnabled")
Compat.hasResizeBounds  = has(probeFrame, "SetResizeBounds")
Compat.hasStringHeight  = has(probeFS, "GetStringHeight")
Compat.hasFontValidate  = has(probeFS, "SetFont")

-- Gradients: Dragonflight replaced SetGradientAlpha(orientation, r,g,b,a, r,g,b,a)
-- with SetGradient(orientation, colorA, colorB). TBC 2.5 still has the old one.
local hasNewGradient = false
if has(probeTex, "SetGradient") and type(_G.CreateColor) == "function" then
	hasNewGradient = pcall(function()
		probeTex:SetGradient("HORIZONTAL", _G.CreateColor(0, 0, 0, 1), _G.CreateColor(1, 1, 1, 1))
	end)
end
local hasOldGradient = has(probeTex, "SetGradientAlpha")
Compat.hasGradient = hasNewGradient or hasOldGradient

-- Recorded at load, before any setting exists, so the ring buffer already holds
-- the client's real capabilities by the time anyone types /wtw debug.
ns.Debug.Log("compat",
	"%s toc %s build %s: masks=%s clip=%s gradient=%s(new=%s) hyperlinks=%s resize=%s",
	flavor, tostring(tocVersion), tostring(buildVersion),
	tostring(Compat.hasMasks), tostring(Compat.hasClipsChildren),
	tostring(Compat.hasGradient), tostring(hasNewGradient),
	tostring(Compat.hasHyperlinks), tostring(Compat.hasResizeBounds))

--------------------------------------------------------------------------------
-- Drawing helpers that differ between clients
--------------------------------------------------------------------------------

if hasNewGradient then
	local CreateColor = _G.CreateColor
	function Compat.SetGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
		tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
	end
elseif hasOldGradient then
	function Compat.SetGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
		tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	end
else
	-- No gradient support at all: fall back to the average of the two stops so a
	-- surface still gets a sensible fill instead of disappearing.
	function Compat.SetGradient(tex, _, r1, g1, b1, a1, r2, g2, b2, a2)
		tex:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
	end
end

function Compat.SetClipsChildren(frame, enabled)
	if Compat.hasClipsChildren then
		frame:SetClipsChildren(enabled and true or false)
		return true
	end
	return false
end

function Compat.SetResizeBounds(frame, minW, minH, maxW, maxH)
	if Compat.hasResizeBounds then
		frame:SetResizeBounds(minW, minH, maxW, maxH)
	else
		if frame.SetMinResize then frame:SetMinResize(minW, minH) end
		if frame.SetMaxResize and maxW and maxH then frame:SetMaxResize(maxW, maxH) end
	end
end

--------------------------------------------------------------------------------
-- Pixel perfection
--------------------------------------------------------------------------------

local physicalHeight
function Compat.GetPhysicalHeight()
	if physicalHeight then return physicalHeight end
	if type(_G.GetPhysicalScreenSize) == "function" then
		local ok, _, h = pcall(_G.GetPhysicalScreenSize)
		if ok and h and h > 0 then
			physicalHeight = h
			return h
		end
	end
	physicalHeight = math.max(600, (GetScreenHeight() or 768) * (UIParent:GetEffectiveScale() or 1))
	return physicalHeight
end

-- Invalidate the cached resolution when the display changes.
function Compat.ResetPhysicalHeight()
	physicalHeight = nil
end

--------------------------------------------------------------------------------
-- Names and realms
--------------------------------------------------------------------------------

local myRealm
function Compat.GetRealmName()
	if myRealm then return myRealm end
	local realm
	if type(_G.GetNormalizedRealmName) == "function" then
		realm = _G.GetNormalizedRealmName()
	end
	if not realm or realm == "" then
		realm = GetRealmName() or ""
		realm = gsub(realm, "%s+", "")
		realm = gsub(realm, "'", "")
		realm = gsub(realm, "%-", "")
	end
	myRealm = realm
	return realm
end

-- "Thrall" -> "Thrall-Blackrock"; "Thrall-Draenor" is returned unchanged.
-- Battle.net keys ("BN:tag#1234") pass through untouched.
function Compat.NormalizeName(name)
	if not name or name == "" then return nil end
	if strfind(name, "^BN:") then return name end
	local base, realm = strmatch(name, "^([^%-]+)%-(.+)$")
	if base then
		realm = gsub(realm, "%s+", "")
		return base .. "-" .. realm
	end
	return name .. "-" .. Compat.GetRealmName()
end

-- Display form: drop the realm when it is our own.
function Compat.ShortName(fullName)
	if not fullName then return "" end
	if strfind(fullName, "^BN:") then
		return (gsub(fullName, "^BN:", ""))
	end
	local base, realm = strmatch(fullName, "^([^%-]+)%-(.+)$")
	if not base then return fullName end
	if realm == Compat.GetRealmName() then return base end
	return base
end

function Compat.RealmOf(fullName)
	if not fullName or strfind(fullName, "^BN:") then return nil end
	local _, realm = strmatch(fullName, "^([^%-]+)%-(.+)$")
	return realm
end

function Compat.IsCrossRealm(fullName)
	local realm = Compat.RealmOf(fullName)
	return realm ~= nil and realm ~= Compat.GetRealmName()
end

function Compat.IsBattleNet(key)
	return key and strfind(key, "^BN:") ~= nil
end

local myFullName
function Compat.PlayerFullName()
	if not myFullName then
		myFullName = Compat.NormalizeName(UnitName("player") or "")
	end
	return myFullName
end

--------------------------------------------------------------------------------
-- Chat
--------------------------------------------------------------------------------

function Compat.SendWhisper(target, text)
	if not target or not text or text == "" then return false end
	local ok = pcall(SendChatMessage, text, "WHISPER", nil, target)
	return ok
end

function Compat.SendBNWhisper(bnetAccountID, text)
	if not bnetAccountID or not text or text == "" then return false end
	if type(_G.BNSendWhisper) ~= "function" then return false end
	local ok = pcall(_G.BNSendWhisper, bnetAccountID, text)
	return ok
end

Compat.hasChatFilters = type(_G.ChatFrame_AddMessageEventFilter) == "function"

function Compat.AddMessageEventFilter(event, fn)
	if Compat.hasChatFilters then
		_G.ChatFrame_AddMessageEventFilter(event, fn)
	end
end

function Compat.RemoveMessageEventFilter(event, fn)
	if type(_G.ChatFrame_RemoveMessageEventFilter) == "function" then
		_G.ChatFrame_RemoveMessageEventFilter(event, fn)
	end
end

-- Registering an event that does not exist on this client raises a Lua error, so
-- every optional event goes through here.
function Compat.RegisterEventSafe(frame, event)
	local ok = pcall(frame.RegisterEvent, frame, event)
	return ok
end

--------------------------------------------------------------------------------
-- Player information
--------------------------------------------------------------------------------

-- Returns englishClass, englishRace, sex, name, realm -- any of them may be nil.
function Compat.GetPlayerInfoByGUID(guid)
	if not guid or guid == "" then return nil end
	if type(_G.GetPlayerInfoByGUID) ~= "function" then return nil end
	local ok, _, englishClass, _, englishRace, sex, name, realm = pcall(_G.GetPlayerInfoByGUID, guid)
	if not ok then return nil end
	if realm == "" then realm = nil end
	return englishClass, englishRace, sex, name, realm
end

local CLASS_COLORS = _G.RAID_CLASS_COLORS
function Compat.GetClassColor(classFile)
	if not classFile then return nil end
	local custom = _G.CUSTOM_CLASS_COLORS
	local c = (custom and custom[classFile]) or (CLASS_COLORS and CLASS_COLORS[classFile])
	if c then return c.r, c.g, c.b end
	if type(_G.C_ClassColor) == "table" and _G.C_ClassColor.GetClassColor then
		local ok, col = pcall(_G.C_ClassColor.GetClassColor, classFile)
		if ok and col then return col.r, col.g, col.b end
	end
	return nil
end

-- Class icon atlas coordinates. CLASS_ICON_TCOORDS exists on every client.
function Compat.GetClassIconCoords(classFile)
	local t = _G.CLASS_ICON_TCOORDS
	if t and classFile and t[classFile] then
		local c = t[classFile]
		return c[1], c[2], c[3], c[4]
	end
	return nil
end

Compat.CLASS_ICON_TEXTURE = "Interface\\WorldStateFrame\\Icons-Classes"

-- Race -> faction. Used only as a hint; unknown races report nil rather than a guess.
local RACE_FACTION = {
	Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
	Draenei = "Alliance", Worgen = "Alliance", VoidElf = "Alliance", LightforgedDraenei = "Alliance",
	DarkIronDwarf = "Alliance", KulTiran = "Alliance", Mechagnome = "Alliance", EarthenAlliance = "Alliance",
	Orc = "Horde", Scourge = "Horde", Undead = "Horde", Tauren = "Horde", Troll = "Horde",
	BloodElf = "Horde", Goblin = "Horde", Nightborne = "Horde", HighmountainTauren = "Horde",
	MagharOrc = "Horde", ZandalariTroll = "Horde", Vulpera = "Horde", EarthenHorde = "Horde",
}

function Compat.FactionForRace(englishRace)
	if not englishRace then return nil end
	return RACE_FACTION[englishRace]
end

-- Try to read a class from a unit token that currently exists.
local UNIT_SCAN = { "target", "mouseover", "focus" }
function Compat.ClassFromVisibleUnit(fullName)
	if not fullName then return nil end
	local function check(unit)
		if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
		local n, r = UnitName(unit)
		if not n then return nil end
		local full = (r and r ~= "") and (n .. "-" .. gsub(r, "%s+", "")) or Compat.NormalizeName(n)
		if full == fullName then
			return select(2, UnitClass(unit)), UnitLevel(unit)
		end
		return nil
	end
	for i = 1, #UNIT_SCAN do
		local class, level = check(UNIT_SCAN[i])
		if class then return class, level end
	end
	local prefix, count
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers and GetNumGroupMembers() or 40
	else
		prefix, count = "party", 4
	end
	for i = 1, count do
		local class, level = check(prefix .. i)
		if class then return class, level end
	end
	return nil
end

function Compat.SetPortraitTexture(texture, unit)
	if type(_G.SetPortraitTexture) == "function" and UnitExists(unit) then
		local ok = pcall(_G.SetPortraitTexture, texture, unit)
		return ok
	end
	return false
end

--------------------------------------------------------------------------------
-- Guild / friends / social actions
--------------------------------------------------------------------------------

function Compat.RequestGuildRoster()
	if type(_G.C_GuildInfo) == "table" and _G.C_GuildInfo.GuildRoster then
		pcall(_G.C_GuildInfo.GuildRoster)
	elseif type(_G.GuildRoster) == "function" then
		pcall(_G.GuildRoster)
	end
end

function Compat.GetNumGuildMembers()
	if type(_G.GetNumGuildMembers) ~= "function" then return 0 end
	local ok, n = pcall(_G.GetNumGuildMembers)
	return (ok and n) or 0
end

-- name, level, classFile, online
function Compat.GetGuildRosterInfo(index)
	if type(_G.GetGuildRosterInfo) ~= "function" then return nil end
	local ok, name, _, _, level, _, _, _, _, online, _, classFile = pcall(_G.GetGuildRosterInfo, index)
	if not ok or not name then return nil end
	return name, level, classFile, online
end

function Compat.GetNumFriends()
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.GetNumFriends then
		local ok, n = pcall(_G.C_FriendList.GetNumFriends)
		return (ok and n) or 0
	end
	if type(_G.GetNumFriends) == "function" then
		return _G.GetNumFriends() or 0
	end
	return 0
end

-- name, level, classFile(localized on old clients), online
function Compat.GetFriendInfo(index)
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.GetFriendInfoByIndex then
		local ok, info = pcall(_G.C_FriendList.GetFriendInfoByIndex, index)
		if ok and info then
			return info.name, info.level, info.className, info.connected
		end
		return nil
	end
	if type(_G.GetFriendInfo) == "function" then
		local ok, name, level, class, _, connected = pcall(_G.GetFriendInfo, index)
		if ok and name then return name, level, class, connected end
	end
	return nil
end

function Compat.AddFriend(name)
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.AddFriend then
		return pcall(_G.C_FriendList.AddFriend, name)
	elseif type(_G.AddFriend) == "function" then
		return pcall(_G.AddFriend, name)
	end
	return false
end

function Compat.AddIgnore(name)
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.AddOrDelIgnore then
		return pcall(_G.C_FriendList.AddOrDelIgnore, name)
	elseif type(_G.AddOrDelIgnore) == "function" then
		return pcall(_G.AddOrDelIgnore, name)
	end
	return false
end

function Compat.IsIgnored(name)
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.IsIgnored then
		local ok, res = pcall(_G.C_FriendList.IsIgnored, name)
		return ok and res or false
	end
	return false
end

function Compat.InviteUnit(name)
	if type(_G.C_PartyInfo) == "table" and _G.C_PartyInfo.InviteUnit then
		return pcall(_G.C_PartyInfo.InviteUnit, name)
	elseif type(_G.InviteUnit) == "function" then
		return pcall(_G.InviteUnit, name)
	end
	return false
end

-- Number of results from the last /who.
function Compat.GetNumWhoResults()
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.GetNumWhoResults then
		local ok, n = pcall(_G.C_FriendList.GetNumWhoResults)
		return (ok and n) or 0
	end
	if type(_G.GetNumWhoResults) == "function" then
		local ok, n = pcall(_G.GetNumWhoResults)
		return (ok and n) or 0
	end
	return 0
end

-- Returns fullName, level, classFile, guild, zone for one /who result.
-- The modern API hands back a table; the legacy one a positional list.
function Compat.GetWhoInfo(index)
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.GetWhoInfo then
		local ok, info = pcall(_G.C_FriendList.GetWhoInfo, index)
		if ok and info then
			return info.fullName, info.level, info.filename, info.fullGuildName, info.area
		end
		return nil
	end
	if type(_G.GetWhoInfo) == "function" then
		local ok, name, guild, level, _, _, zone = pcall(_G.GetWhoInfo, index)
		if ok and name then return name, level, nil, guild, zone end
	end
	return nil
end

-- Only ever called straight from a click so any hardware-event requirement holds.
function Compat.SendWho(name)
	if type(_G.C_FriendList) == "table" and _G.C_FriendList.SendWho then
		return pcall(_G.C_FriendList.SendWho, "n-" .. name)
	elseif type(_G.SendWho) == "function" then
		return pcall(_G.SendWho, "n-" .. name)
	end
	return false
end

Compat.canInvite   = (type(_G.C_PartyInfo) == "table" and _G.C_PartyInfo.InviteUnit ~= nil)
	or type(_G.InviteUnit) == "function"
Compat.canAddFriend = (type(_G.C_FriendList) == "table" and _G.C_FriendList.AddFriend ~= nil)
	or type(_G.AddFriend) == "function"
Compat.canIgnore    = (type(_G.C_FriendList) == "table" and _G.C_FriendList.AddOrDelIgnore ~= nil)
	or type(_G.AddOrDelIgnore) == "function"
Compat.canWho       = (type(_G.C_FriendList) == "table" and _G.C_FriendList.SendWho ~= nil)
	or type(_G.SendWho) == "function"

--------------------------------------------------------------------------------
-- Battle.net
--------------------------------------------------------------------------------

Compat.hasBattleNet = type(_G.BNGetNumFriends) == "function"
	and type(_G.BNSendWhisper) == "function"

local function parseLegacyFriend(index)
	-- BNGetFriendInfo's signature changed several times. Rather than depend on a
	-- position, pick the values out of the return list by shape.
	local results = { pcall(_G.BNGetFriendInfo, index) }
	if not results[1] then return nil end
	local id, battleTag, accountName, isOnline
	for i = 2, #results do
		local v = results[i]
		if type(v) == "number" and not id then
			id = v
		elseif type(v) == "string" then
			if strfind(v, "#%d+$") and not battleTag then
				battleTag = v
			elseif not accountName then
				accountName = v
			end
		elseif type(v) == "boolean" and isOnline == nil then
			isOnline = v
		end
	end
	if not id then return nil end
	return id, battleTag, accountName, isOnline
end

-- Returns bnetAccountID, battleTag, accountName, isOnline, characterName, client
function Compat.GetBNFriendInfo(index)
	if type(_G.C_BattleNet) == "table" and _G.C_BattleNet.GetFriendAccountInfo then
		local ok, info = pcall(_G.C_BattleNet.GetFriendAccountInfo, index)
		if ok and info then
			local ga = info.gameAccountInfo
			return info.bnetAccountID, info.battleTag, info.accountName,
				(ga and ga.isOnline) or false,
				(ga and ga.characterName) or nil,
				(ga and ga.clientProgram) or nil
		end
		return nil
	end
	if type(_G.BNGetFriendInfo) == "function" then
		local id, tag, name, online = parseLegacyFriend(index)
		return id, tag, name, online
	end
	return nil
end

function Compat.GetNumBNFriends()
	if not Compat.hasBattleNet then return 0 end
	local ok, n = pcall(_G.BNGetNumFriends)
	return (ok and n) or 0
end

-- Battle.net account IDs are only stable within a session; the BattleTag is the
-- durable key, so conversations store the tag and resolve the ID on demand.
function Compat.ResolveBNAccountID(battleTag)
	if not battleTag or not Compat.hasBattleNet then return nil end
	for i = 1, Compat.GetNumBNFriends() do
		local id, tag = Compat.GetBNFriendInfo(i)
		if tag and tag == battleTag then return id end
	end
	return nil
end

function Compat.GetBNAccountInfoByID(bnetAccountID)
	if not bnetAccountID or not Compat.hasBattleNet then return nil end
	if type(_G.C_BattleNet) == "table" and _G.C_BattleNet.GetAccountInfoByID then
		local ok, info = pcall(_G.C_BattleNet.GetAccountInfoByID, bnetAccountID)
		if ok and info then
			local ga = info.gameAccountInfo
			return info.battleTag, info.accountName, (ga and ga.isOnline) or false,
				(ga and ga.characterName) or nil
		end
	end
	for i = 1, Compat.GetNumBNFriends() do
		local id, tag, name, online, char = Compat.GetBNFriendInfo(i)
		if id == bnetAccountID then return tag, name, online, char end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

local SOUNDKIT = _G.SOUNDKIT or {}

function Compat.PlaySoundKit(kitID, channel)
	if not kitID then return false end
	if type(_G.PlaySound) ~= "function" then return false end
	return pcall(_G.PlaySound, kitID, channel or "Master")
end

function Compat.PlaySoundFile(path, channel)
	if not path or path == "" then return false end
	if type(_G.PlaySoundFile) ~= "function" then return false end
	local ok, played = pcall(_G.PlaySoundFile, path, channel or "Master")
	return ok and played ~= false
end

-- Sound kits that exist unchanged on all four clients.
Compat.SOUNDS = {
	TELL_MESSAGE   = SOUNDKIT.TELL_MESSAGE or 3081,
	MENU_OPEN      = SOUNDKIT.IG_MAINMENU_OPEN or 851,
	MENU_CLOSE     = SOUNDKIT.IG_MAINMENU_CLOSE or 854,
	CHARACTER_OPEN = SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839,
	CHARACTER_CLOSE= SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840,
	QUEST_SELECT   = SOUNDKIT.IG_QUEST_LIST_SELECT or 798,
	MAIL_OPEN      = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,
	READY_CHECK    = SOUNDKIT.READY_CHECK or 8960,
	RAID_WARNING   = SOUNDKIT.RAID_WARNING or 8959,
	MAP_PING       = SOUNDKIT.MAP_PING or 3175,
	FRIEND_JOIN    = SOUNDKIT.UI_BNET_TOAST or 18019,
}

--------------------------------------------------------------------------------
-- Fonts
--------------------------------------------------------------------------------

local defaultFont
function Compat.GetDefaultFont()
	if defaultFont then return defaultFont end
	local candidates = { _G.ChatFontNormal, _G.GameFontNormal, _G.SystemFont_Shadow_Med1 }
	for i = 1, #candidates do
		local fo = candidates[i]
		if fo and fo.GetFont then
			local path = fo:GetFont()
			if path and path ~= "" then
				defaultFont = path
				return path
			end
		end
	end
	defaultFont = "Fonts\\FRIZQT__.TTF"
	return defaultFont
end

-- SetFont silently keeps the previous face when the path is unusable, so the
-- only reliable test is to set it and read it back.
local fontProbe = probeFrame:CreateFontString(nil, "BACKGROUND")
fontProbe:SetFont(Compat.GetDefaultFont(), 12, "")

local validatedFonts = {}
function Compat.ValidateFont(path)
	if not path or path == "" then return false end
	local cached = validatedFonts[path]
	if cached ~= nil then return cached end
	local ok = pcall(fontProbe.SetFont, fontProbe, path, 12, "")
	local result = false
	if ok then
		local current = fontProbe:GetFont()
		result = (current == path)
	end
	-- restore so a failed probe cannot leave the probe in a broken state
	pcall(fontProbe.SetFont, fontProbe, Compat.GetDefaultFont(), 12, "")
	validatedFonts[path] = result
	return result
end

--------------------------------------------------------------------------------
-- Colour picker
--------------------------------------------------------------------------------

-- Retail 10.2.5+ takes an options table; everything older assigns fields on the
-- global frame. Both paths are covered because MoP Classic sits in between.
function Compat.ShowColorPicker(r, g, b, a, onChange, onCancel)
	local frame = _G.ColorPickerFrame
	if not frame then return false end

	local prev = { r = r, g = g, b = b, a = a }
	local function changed()
		local nr, ng, nb
		if frame.GetColorRGB then
			nr, ng, nb = frame:GetColorRGB()
		end
		local na = 1
		if _G.OpacitySliderFrame and _G.OpacitySliderFrame.GetValue then
			na = 1 - _G.OpacitySliderFrame:GetValue()
		elseif frame.GetColorAlpha then
			na = frame:GetColorAlpha()
		end
		onChange(nr or r, ng or g, nb or b, na)
	end
	local function cancelled()
		if onCancel then onCancel(prev.r, prev.g, prev.b, prev.a) end
	end

	if frame.SetupColorPickerAndShow then
		local ok = pcall(frame.SetupColorPickerAndShow, frame, {
			r = r, g = g, b = b, opacity = a, hasOpacity = true,
			swatchFunc = changed, opacityFunc = changed, cancelFunc = cancelled,
		})
		if ok then return true end
	end

	frame.func = changed
	frame.opacityFunc = changed
	frame.cancelFunc = cancelled
	frame.hasOpacity = true
	frame.opacity = 1 - (a or 1)
	frame.previousValues = { r, g, b, 1 - (a or 1) }
	if frame.SetColorRGB then frame:SetColorRGB(r, g, b) end
	frame:Hide()
	frame:Show()
	return true
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

-- C_Timer exists on all four clients, but routing it here keeps the rule that
-- nothing outside this file touches a C_ namespace.
function Compat.After(delay, fn)
	if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
		_G.C_Timer.After(delay, fn)
		return true
	end
	return false
end

function Compat.GetServerTime()
	if type(_G.GetServerTime) == "function" then
		local ok, t = pcall(_G.GetServerTime)
		if ok and t then return t end
	end
	return time()
end

function Compat.InstanceType()
	local inInstance, instanceType = IsInInstance()
	if not inInstance then return nil end
	return instanceType
end

function Compat.SetHyperlinksEnabled(frame, enabled)
	if Compat.hasHyperlinks then
		frame:SetHyperlinksEnabled(enabled and true or false)
		return true
	end
	return false
end

-- Blizzard's handler for real game links (items, spells, achievements...).
function Compat.ShowGameLink(link, text, button)
	if type(_G.SetItemRef) == "function" then
		pcall(_G.SetItemRef, link, text, button or "LeftButton")
		return true
	end
	return false
end

-- Calls back when the player points the default chat box at a whisper target,
-- which is what "/w Thrall " does before a single word is typed.
--
-- ChatEdit_UpdateHeader is the function Blizzard calls whenever that header
-- changes, and hooksecurefunc only adds to it -- nothing of Blizzard's is
-- replaced, so a chat box the addon knows nothing about keeps working exactly
-- as it did. Returns whether the hook could be installed at all.
function Compat.HookWhisperCompose(callback)
	if type(_G.hooksecurefunc) ~= "function"
		or type(_G.ChatEdit_UpdateHeader) ~= "function" then
		return false
	end
	local lastTarget
	_G.hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
		if type(editBox) ~= "table" or not editBox.GetAttribute then return end
		local ok, chatType = pcall(editBox.GetAttribute, editBox, "chatType")
		if not ok or chatType ~= "WHISPER" then
			lastTarget = nil
			return
		end
		local gotTarget, target = pcall(editBox.GetAttribute, editBox, "tellTarget")
		if not gotTarget or type(target) ~= "string" or target == "" then return end
		-- The header updates on every keystroke; only a change of target is news.
		if target == lastTarget then return end
		lastTarget = target
		callback(target)
	end)
	return true
end

function Compat.SetTooltipHyperlink(tooltip, link)
	if tooltip and tooltip.SetHyperlink then
		return pcall(tooltip.SetHyperlink, tooltip, link)
	end
	return false
end

ns.ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Art\\"
