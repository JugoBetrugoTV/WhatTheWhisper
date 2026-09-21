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

-- Forever -- "Camelot" in Blizzard's own interface source -- is the one flavour
-- the project ID cannot be trusted for, so it is asked about first.
--
-- Its files sit in the mainline family: Blizzard_BNet ships only a Mainline
-- directory and loads it with [AllowLoadGameType mainline], and that file opens
-- with `WOW_PROJECT_ID = WOW_PROJECT_ID or WOW_PROJECT_MAINLINE`. So a client
-- that is emphatically not Retail can answer WOW_PROJECT_MAINLINE to the
-- question every other flavour answers honestly, and asking the ID first would
-- have named Forever "Retail" and given it Retail's thirteen classes.
--
-- The interface number has no such ambiguity. 1.60.x is Forever and nothing
-- else: Classic Era is 1.13-1.15 (11300-11599) and TBC starts at 20000, so the
-- whole 16xxx-19xxx range belongs to this client line and to no other.
local FOREVER_FLOOR, FOREVER_CEILING = 16000, 20000

local flavor
if tocVersion >= FOREVER_FLOOR and tocVersion < FOREVER_CEILING then
	flavor = "forever"
elseif projectID and _G.WOW_PROJECT_MAINLINE and projectID == _G.WOW_PROJECT_MAINLINE then
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
Compat.isForever    = (flavor == "forever")
Compat.isClassicEra = (flavor == "classic")
Compat.isTBC        = (flavor == "tbc")
Compat.isWrath      = (flavor == "wrath")
Compat.isCata       = (flavor == "cata")
Compat.isMoP        = (flavor == "mop")
-- "Modern" means the 9.0+ Lua API shape (C_ namespaces widely available).
-- Forever is modern by engine and Vanilla by content, which is the whole point
-- of it: the API surface is the current one, the world has nine classes.
Compat.isModern     = Compat.isRetail or Compat.isForever or Compat.isMoP or Compat.isCata
Compat.isClassicLike = not (Compat.isRetail or Compat.isForever)

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

-- The client's own naming rules, applied before anything is sent.
--
-- This is not cosmetic. SendChatMessage accepts any string: whisper a name that
-- cannot exist and the message is added, echoed nowhere, and the only sign that
-- nobody received it is one line in the default chat frame -- which this addon
-- may well be hiding. So a name that the game could never issue is refused at
-- the point the player types it, and the ones that merely turn out not to be
-- online are caught afterwards by the server's reply.
--
-- Returns true, or false plus a reason token the caller turns into text.
local NAME_MIN_CHARS, NAME_MAX_CHARS = 2, 12
local REALM_MAX_CHARS = 32

function Compat.ValidatePlayerName(name)
	if type(name) ~= "string" then return false, "empty" end
	name = gsub(gsub(name, "^%s+", ""), "%s+$", "")
	if name == "" then return false, "empty" end

	-- A BattleTag is a different namespace with different rules: digits are part
	-- of it, and the discriminator is what makes it unique.
	if strfind(name, "^BN:") or strfind(name, "#") then
		local tag = gsub(name, "^BN:", "")
		local base, discriminator = strmatch(tag, "^([^#]+)#(%d+)$")
		if not base or base == "" then return false, "battletag" end
		if #discriminator < 3 then return false, "battletag" end
		return true
	end

	local base, realm = strmatch(name, "^([^%-]+)%-(.+)$")
	base = base or name

	-- Escape sequences would be interpreted by the chat frame, so they are
	-- rejected before length is even considered.
	if strfind(base, "|") or (realm and strfind(realm, "|")) then
		return false, "name"
	end
	-- Letters only. Bytes above 0x7F are left alone because that is where every
	-- accented letter in a European name lives; what is refused is what the
	-- client refuses -- digits, spaces and punctuation.
	if strfind(base, "%d") or strfind(base, "%s") or strfind(base, "%p") then
		return false, "name"
	end
	local length = ns.Text.Len(base)
	if length < NAME_MIN_CHARS or length > NAME_MAX_CHARS then
		return false, "length"
	end

	if realm then
		realm = gsub(realm, "%s+", "")
		if realm == "" then return false, "realm" end
		if strfind(realm, "%d") then return false, "realm" end
		if ns.Text.Len(realm) > REALM_MAX_CHARS then return false, "realm" end
	end
	return true
end

Compat.NAME_MIN_CHARS, Compat.NAME_MAX_CHARS = NAME_MIN_CHARS, NAME_MAX_CHARS

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

-- Your own character, without the realm. Never secret -- the client does not
-- hide you from yourself -- so this one needs no probe.
function Compat.PlayerName()
	return (UnitName("player"))
end

-- A unit's name, spelled the way this addon spells names, or nil.
--
-- UnitName is one of the calls that answers with a *secret value* in restricted
-- content: an arena opponent's name is deliberately not knowable, and reading
-- one -- including comparing it to the empty string, or running gsub over it --
-- is a hard error that taints whatever ran it. An arena target therefore printed
-- an error for every avatar the addon drew.
--
-- nil means "this unit is not one we may identify", which in an arena is the
-- correct answer rather than a fault. Name and realm are probed separately
-- because the client can hide either one on its own.
function Compat.UnitFullName(unit)
	local ok, name, realm = pcall(UnitName, unit)
	if not ok then return nil end
	name = Compat.ReadableText(name)
	if not name or name == "" then return nil end
	-- A realm takes three answers, not two. Not given means "the same realm as
	-- yours", which is knowable. Given but unreadable means we do not know which
	-- realm, and filling in your own would put a stranger's portrait on a
	-- friend's thread -- so that unit is simply not identified.
	if realm ~= nil then
		realm = Compat.ReadableText(realm)
		if realm == nil then return nil end
		if realm ~= "" then
			return name .. "-" .. gsub(realm, "%s+", "")
		end
	end
	return Compat.NormalizeName(name)
end

--------------------------------------------------------------------------------
-- Chat
--------------------------------------------------------------------------------

-- Chat payloads are not always readable.
--
-- In arenas, rated battlegrounds and other restricted content the client hands
-- out *secret values* instead of strings. An addon may not look inside one: any
-- read is a hard error, and the attempt taints whatever ran it.
--
-- The client has its own answer to "is this one of those", and it is the one to
-- use: `issecretvalue` and `hasanysecretvalues` are globals wherever secret
-- values exist. Older clients have neither, and also have no secret values, so
-- there the answer is simply no.
local issecretvalue = _G.issecretvalue
local hasanysecretvalues = _G.hasanysecretvalues

function Compat.IsSecretValue(value)
	if not issecretvalue then return false end
	local ok, secret = pcall(issecretvalue, value)
	return ok and secret == true
end

-- Whether any of these is one. Asked of a whole event's arguments at once,
-- before anything has looked at any of them.
function Compat.HasAnySecretValues(...)
	if not hasanysecretvalues then return false end
	local ok, any = pcall(hasanysecretvalues, ...)
	return ok and any == true
end

-- Whether the client is withholding chat from addons at all right now. True
-- inside an arena or a rated battleground, false everywhere else. This is the
-- question to ask before putting a message aside, and again before taking it
-- back out.
local inChatLockdown = _G.C_ChatInfo and _G.C_ChatInfo.InChatMessagingLockdown
function Compat.InChatMessagingLockdown()
	if not inChatLockdown then return false end
	local ok, locked = pcall(inChatLockdown)
	return ok and locked == true
end

-- Whether the client is applying secret restrictions right now.
--
-- A third question again, and the broadest one. `issecretvalue` existing says
-- the client *can* withhold values; InChatMessagingLockdown says chat in
-- particular is being withheld; this says the restricted state is switched on
-- at all. All four supported clients ship C_Secrets, so the presence of the
-- function is not a flavour test and must not be used as one -- it is the
-- answer that varies, not the API.
--
-- Returns nil, not false, on a client that does not answer. "I was not told"
-- and "I was told no" read the same in an `if`, and the difference is the whole
-- point of asking: nothing here is allowed to turn into "Classic has no
-- secrets". Nothing in the event path branches on this; it is what a bug report
-- needs in order to say whether the player was under restrictions when the
-- thing went wrong.
function Compat.HasSecretRestrictions()
	local secrets = _G.C_Secrets
	if not secrets or type(secrets.HasSecretRestrictions) ~= "function" then
		return nil
	end
	local ok, restricted = pcall(secrets.HasSecretRestrictions)
	if not ok then return nil end
	return restricted == true
end

-- Whether the client will carry a whisper the player has typed here.
--
-- This asks InChatMessagingLockdown and nothing else, and the reason is worth
-- writing down because getting it wrong shipped once.
--
-- C_ChatInfo.AreOutgoingAddonChatMessagesRestricted looks like the precise
-- answer and is not. Blizzard's own documentation: "Returns false if addons are
-- allowed to send outgoing chat messages. This is controlled on a realm-by-realm
-- basis (tournament realms allow it)". That is about SendAddonMessage -- the
-- hidden channel addons talk to each other on -- and it is a property of the
-- realm, not of where the player is standing. On an ordinary realm it says
-- restricted, permanently, and gating whispers on it refused every message the
-- player ever typed with "Whispers cannot be sent from here."
--
-- This addon does not send addon messages at all, so that function has no
-- caller here and should not acquire one.
--
-- InChatMessagingLockdown is the documented signal for player chat: "API
-- security restrictions regarding chat messaging are in effect". It is true in
-- an arena or a rated battleground and false everywhere else.
function Compat.OutgoingChatRestricted()
	return Compat.InChatMessagingLockdown()
end

-- Whether the client still has anything to say about a chat line. A line ages
-- out of the client's store and never comes back; being told so is the
-- difference between giving up at once and waiting out a timeout for nothing.
-- Returns nil on a client that does not answer, which means "keep asking".
function Compat.IsValidChatLine(lineID)
	local info = _G.C_ChatInfo
	if not info or type(info.IsValidChatLine) ~= "function" then return nil end
	if type(lineID) ~= "number" then return false end
	local ok, valid = pcall(info.IsValidChatLine, lineID)
	if not ok then return nil end
	return valid == true
end

-- Returns the value when it can be read, and nil when it cannot. nil is a normal
-- answer here, not a fault: being in an arena is not an error.
--
-- The fallback path, for a client with no `issecretvalue`, does the reading
-- inside a pcall -- including the comparison, because the result of a read on a
-- secret is itself secret.
function Compat.ReadableText(value)
	if value == nil then return nil end
	if issecretvalue then
		if Compat.IsSecretValue(value) then return nil end
		return type(value) == "string" and value or nil
	end
	local ok, readable = pcall(function()
		return type(value) == "string" and strfind(value, "", 1, true) == 1
	end)
	if not ok or readable ~= true then return nil end
	return value
end

-- The same question for a value that is meant to be a number. A Battle.net
-- account id arrives beside the text and can be withheld on its own; testing it
-- for truth, or using it as a table key, is a read like any other.
function Compat.ReadableNumber(value)
	if value == nil then return nil end
	if Compat.IsSecretValue(value) then return nil end
	return type(value) == "number" and value or nil
end

-- The message the client would not hand over live.
--
-- A chat line's ID is never secret. Keeping it is what makes a withheld message
-- recoverable: once the restriction lifts, the client will answer for that line,
-- and a whisper sent to you in an arena ends up in its conversation after the
-- arena instead of being lost. Returns text, sender, guid -- each nil on its own
-- if the client still will not say.
function Compat.GetChatLine(lineID)
	local info = _G.C_ChatInfo
	if not info or type(lineID) ~= "number" then return nil end
	local function ask(fn)
		if type(fn) ~= "function" then return nil end
		local ok, value = pcall(fn, lineID)
		if not ok then return nil end
		return Compat.ReadableText(value)
	end
	return ask(info.GetChatLineText), ask(info.GetChatLineSenderName),
		ask(info.GetChatLineSenderGUID)
end

-- What the client told us, or nil.
--
-- Two different kinds of "nothing", answered the same way on purpose: a field
-- the client has not resolved yet comes back as an empty string, and one it will
-- not resolve at all -- in an arena, a battleground, any restricted content --
-- comes back as a secret value, where even the test against "" would be a read
-- and a hard error. Both mean "we have not been told", which the rest of the
-- addon already knows how to wait for.
--
-- Every reader below that hands a client string outward goes through these, so
-- that nothing further away has to know restricted content exists.
local function knownText(value)
	value = Compat.ReadableText(value)
	if value == nil or value == "" then return nil end
	return value
end

-- type() reads the tag rather than the contents, so it is safe on a secret.
-- Passing one on as a number would only move the error somewhere harder to find.
local function knownNumber(value)
	if type(value) ~= "number" then return nil end
	return value
end

-- Sending, through whichever door this client leaves open.
--
-- Retail moved chat behind C_ChatInfo and Battle.net behind C_BattleNet; the
-- bare globals are still there on the Classic flavours and still there on Retail
-- as of 12.1, but a function that is being moved is a function to stop reaching
-- for directly. Same arguments either way -- the namespaced versions are the
-- same functions under a new roof -- so this is a lookup, not two code paths.
local function sendChat(...)
	local info = _G.C_ChatInfo
	if info and type(info.SendChatMessage) == "function" then
		return pcall(info.SendChatMessage, ...)
	end
	if type(_G.SendChatMessage) == "function" then
		return pcall(_G.SendChatMessage, ...)
	end
	return false
end

function Compat.SendWhisper(target, text)
	if not target or not text or text == "" then return false end
	return (sendChat(text, "WHISPER", nil, target))
end

-- A call that did not throw is not a message that was sent. Two APIs, two
-- contracts, and merging them would take the weaker promise for both.
--
-- C_BattleNet.SendWhisper returns a boolean saying whether it went. Only true is
-- true: nil from it is not modesty, it is the function not having answered the
-- question it is documented to answer, and reporting that as delivered puts a
-- tick beside a message nobody received.
--
-- BNSendWhisper, the old global, returns nothing at all. There the call coming
-- back without throwing is the best signal there is, and reading its silence as
-- failure would mark every message on a client that only has it as undelivered.
function Compat.SendBNWhisper(bnetAccountID, text)
	if type(bnetAccountID) ~= "number" or not text or text == "" then return false end
	local battlenet = _G.C_BattleNet
	if battlenet and type(battlenet.SendWhisper) == "function" then
		local ok, sent = pcall(battlenet.SendWhisper, bnetAccountID, text)
		return ok and sent == true
	end
	if type(_G.BNSendWhisper) == "function" then
		return (pcall(_G.BNSendWhisper, bnetAccountID, text))
	end
	return false
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
	guid = Compat.ReadableText(guid)
	if not guid or guid == "" then return nil end
	if type(_G.GetPlayerInfoByGUID) ~= "function" then return nil end
	local ok, _, englishClass, localizedRace, englishRace, sex, name, realm =
		pcall(_G.GetPlayerInfoByGUID, guid)
	if not ok then return nil end
	return knownText(englishClass), knownText(englishRace), knownNumber(sex),
		knownText(name), knownText(realm), knownText(localizedRace)
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
		local full = Compat.UnitFullName(unit)
		if full ~= fullName then return nil end
		return select(2, UnitClass(unit)), UnitLevel(unit)
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
	if not ok then return nil end
	name = knownText(name)
	if not name then return nil end
	return name, knownNumber(level), knownText(classFile), online == true
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
			local name = knownText(info.name)
			if not name then return nil end
			return name, knownNumber(info.level), knownText(info.className),
				info.connected == true
		end
		return nil
	end
	if type(_G.GetFriendInfo) == "function" then
		local ok, name, level, class, _, connected = pcall(_G.GetFriendInfo, index)
		name = ok and knownText(name) or nil
		if name then
			return name, knownNumber(level), knownText(class), connected == true
		end
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
			local name = knownText(info.fullName)
			if not name then return nil end
			return name, knownNumber(info.level), knownText(info.filename),
				knownText(info.fullGuildName), knownText(info.area)
		end
		return nil
	end
	if type(_G.GetWhoInfo) == "function" then
		local ok, name, guild, level, _, _, zone = pcall(_G.GetWhoInfo, index)
		name = ok and knownText(name) or nil
		if name then
			return name, knownNumber(level), nil, knownText(guild), knownText(zone)
		end
	end
	return nil
end

-- Only ever called straight from a click so any hardware-event requirement holds.
-- Protected. The client allows this during a hardware event and blocks it
-- everywhere else -- and a blocked call is not a quiet failure: it shows an
-- ADDON_ACTION_BLOCKED warning naming this addon. pcall does not help, because
-- nothing throws. The only defence is never calling it outside a click, which
-- is why PlayerInfo.LookUp is the single entry point and both of its callers
-- are click handlers.
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

-- Three separate questions, because they have three separate answers.
--
-- "Battle.net exists here" is not "the deprecated send alias exists": Retail has
-- moved sending to C_BattleNet.SendWhisper and the old global is on its way out,
-- so defining the whole feature in terms of it would switch Battle.net off on
-- the one client where it matters most. The friend list and the send are asked
-- about apart, and either modern or legacy satisfies each.
local bn = _G.C_BattleNet

-- There is a Battle.net at all: friends can be listed and accounts looked up.
Compat.hasBattleNet = (type(bn) == "table" and
		(type(bn.GetFriendAccountInfo) == "function"
			or type(bn.GetAccountInfoByID) == "function"))
	or type(_G.BNGetNumFriends) == "function"

-- ...and a whisper can be sent to one.
Compat.canSendBattleNet = (type(bn) == "table" and type(bn.SendWhisper) == "function")
	or type(_G.BNSendWhisper) == "function"

-- ...and the friends list can be walked, which is how a withheld account id is
-- recovered from the name beside it.
Compat.canResolveBattleNetFriends =
	(type(bn) == "table" and type(bn.GetFriendAccountInfo) == "function")
	or type(_G.BNGetFriendInfo) == "function"

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
			return info.bnetAccountID, knownText(info.battleTag),
				knownText(info.accountName),
				(ga and ga.isOnline) == true,
				ga and knownText(ga.characterName) or nil,
				ga and knownText(ga.clientProgram) or nil
		end
		return nil
	end
	if type(_G.BNGetFriendInfo) == "function" then
		local id, tag, name, online = parseLegacyFriend(index)
		return id, tag, name, online
	end
	return nil
end

-- A loop whose end depends on the client answering honestly is a loop that can
-- fail to end.
local MAX_BN_FRIENDS = 2000

function Compat.GetNumBNFriends()
	if type(_G.BNGetNumFriends) == "function" then
		local ok, n = pcall(_G.BNGetNumFriends)
		if ok and type(n) == "number" then return n end
	end
	-- No count to ask for: walk the list until it stops answering. This is the
	-- path a client that has dropped the old globals takes, and it is the reason
	-- the count is not allowed to be what decides whether Battle.net exists.
	local battlenet = _G.C_BattleNet
	if type(battlenet) ~= "table"
		or type(battlenet.GetFriendAccountInfo) ~= "function" then
		return 0
	end
	for i = 1, MAX_BN_FRIENDS do
		local ok, info = pcall(battlenet.GetFriendAccountInfo, i)
		if not ok or not info then return i - 1 end
	end
	return MAX_BN_FRIENDS
end

-- Battle.net account IDs are only stable within a session; the BattleTag is the
-- durable key, so conversations store the tag and resolve the ID on demand.
function Compat.ResolveBNAccountID(battleTag)
	if not battleTag or not Compat.canResolveBattleNetFriends then return nil end
	for i = 1, Compat.GetNumBNFriends() do
		local id, tag = Compat.GetBNFriendInfo(i)
		if tag and tag == battleTag then return id end
	end
	return nil
end

-- The account id behind a Battle.net display name.
--
-- The id arrives beside a whisper and is sometimes the one thing the client
-- withholds. It cannot be guessed, but it can be looked up: a Battle.net whisper
-- only comes from somebody on your friends list, and that list has both. Returns
-- nil when no friend matches, which has to mean "do not know" rather than a
-- best guess -- a conversation filed under the wrong person is worse than none.
-- The whole list is walked, not stopped at the first hit.
--
-- The account name is a display name, not an identifier -- the BattleTag with
-- its discriminator is the durable one, and that is exactly what a withheld
-- whisper does not come with. Two friends can present the same display name, and
-- "first match wins" would quietly file the message under whichever of them the
-- client happened to list first.
--
-- Nought matches means nil. One means that one. Two or more means nil as well,
-- because a message in the wrong person's thread is worse than one left in the
-- chat frame, and this is the whole rule the Battle.net path is built on.
function Compat.ResolveBNAccountByName(accountName)
	if type(accountName) ~= "string" or accountName == "" then return nil end
	local found
	for i = 1, Compat.GetNumBNFriends() do
		local id, _, name = Compat.GetBNFriendInfo(i)
		if name and name == accountName and type(id) == "number" then
			if found and found ~= id then return nil end
			found = id
		end
	end
	return found
end

function Compat.GetBNAccountInfoByID(bnetAccountID)
	if not bnetAccountID or not Compat.hasBattleNet then return nil end
	if type(_G.C_BattleNet) == "table" and _G.C_BattleNet.GetAccountInfoByID then
		local ok, info = pcall(_G.C_BattleNet.GetAccountInfoByID, bnetAccountID)
		if ok and info then
			local ga = info.gameAccountInfo
			return knownText(info.battleTag), knownText(info.accountName),
				(ga and ga.isOnline) == true,
				ga and knownText(ga.characterName) or nil
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

-- Battle.net presence, which is the one case the client answers directly rather
-- than leaving the addon to infer it. Returns nil when it does not know.
function Compat.IsBNOnline(bnetAccountID)
	if not bnetAccountID then return nil end
	local tag, _, online = Compat.GetBNAccountInfoByID(bnetAccountID)
	if tag == nil then return nil end
	return online and true or false
end

-- Where this client writes its saved variables, in the form a player needs to
-- navigate to it. The account folder is not something an addon can read, so it
-- is named as a placeholder rather than guessed at.
function Compat.SavedVariablesFolder()
	local flavourFolder = ({
		retail = "_retail_", mop = "_classic_", cata = "_classic_",
		wrath = "_classic_", tbc = "_classic_era_", classic = "_classic_era_",
	})[Compat.flavor]
	-- Forever's install folder is not something this addon can know: the client
	-- is still in beta under a borrowed product code, and the name it ships
	-- under is Blizzard's to choose. Naming the wrong folder in an export dialog
	-- sends a player hunting through a directory that is not there, so the
	-- unknown case says it is unknown instead.
	if not flavourFolder then
		return "World of Warcraft\\<version>\\WTF\\Account\\<account>\\SavedVariables"
	end
	return "World of Warcraft\\" .. flavourFolder
		.. "\\WTF\\Account\\<account>\\SavedVariables"
end

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

-- Fonts that can draw a given writing system, in the order they are preferred.
--
-- A client ships the fonts for its own locale and no others. On a German
-- install there is no Korean or Chinese glyph anywhere: asking the default font
-- for 한국어 gets three empty boxes, which is exactly what the language picker
-- looked like. So the addon asks the client what it has rather than assuming,
-- and what it does not have, it does not try to draw.
--
-- Latin and Cyrillic are absent from this table on purpose: every client draws
-- them with the font it is already using, so there is nothing to look up.
local SCRIPT_FONTS = {
	korean = {
		"Fonts\\2002.TTF", "Fonts\\2002B.TTF",
		"Fonts\\K_Damage.TTF", "Fonts\\K_Pagetext.TTF",
	},
	hans = {
		"Fonts\\ARKai_T.ttf", "Fonts\\ARKai_C.ttf", "Fonts\\ARHei.ttf",
		"Fonts\\ZYKai_T.ttf", "Fonts\\ZYHei.ttf",
	},
	hant = {
		"Fonts\\bLEI00D.TTF", "Fonts\\bHEI00M.TTF", "Fonts\\bHEI01B.TTF",
		"Fonts\\bKAI00M.TTF", "Fonts\\arheiuhk_bd.TTF", "Fonts\\ARKai_T.ttf",
	},
}

local scriptFonts = {}

-- The first font this client actually has for that script, or nil when it has
-- none -- which is a fact about the install, not a failure.
function Compat.FontForScript(script)
	if not script then return nil end
	local cached = scriptFonts[script]
	if cached ~= nil then return cached or nil end
	local candidates = SCRIPT_FONTS[script]
	local found = false
	if candidates then
		for i = 1, #candidates do
			if Compat.ValidateFont(candidates[i]) then
				found = candidates[i]
				break
			end
		end
	end
	scriptFonts[script] = found
	return found or nil
end

-- Every script this addon has strings in is either one the client draws anyway
-- or one it needs a font for. Answering "yes" for the first kind is what keeps
-- the picker from hiding French on a Chinese client.
local ALWAYS_DRAWN = { latin = true, cyrillic = true }

function Compat.CanDrawScript(script)
	if not script or ALWAYS_DRAWN[script] then return true end
	return Compat.FontForScript(script) ~= nil
end

-- Blizzard's own chat filter can hide a line's text and hand the addon a
-- placeholder. That is moderation, not a restriction on addons, and it is not
-- ours to work around: the most an addon may do is show that something is there
-- and let the player ask for it.
function Compat.IsChatLineCensored(lineID)
	local info = _G.C_ChatInfo
	if not info or type(info.IsChatLineCensored) ~= "function" then return false end
	if type(lineID) ~= "number" then return false end
	local ok, censored = pcall(info.IsChatLineCensored, lineID)
	return ok and censored == true
end

-- Only ever from a click. Blizzard's rule, and the right one: revealing a line
-- somebody chose to filter is a decision for the person reading it.
function Compat.UncensorChatLine(lineID)
	local info = _G.C_ChatInfo
	if not info or type(info.UncensorChatLine) ~= "function" then return false end
	if type(lineID) ~= "number" then return false end
	return (pcall(info.UncensorChatLine, lineID))
end

-- How the game itself presents whispers: "inline" keeps them in the chat frame,
-- "popout" gives each one its own chat tab. Both are handled, but the second
-- means the game opens a window of its own beside this addon's, which is a thing
-- the player should get to decide about knowingly.
function Compat.GetWhisperMode()
	if type(_G.GetCVar) ~= "function" then return nil end
	local ok, mode = pcall(_G.GetCVar, "whisperMode")
	if not ok then return nil end
	return Compat.ReadableText(mode)
end

function Compat.SetWhisperMode(mode)
	if type(_G.SetCVar) ~= "function" then return false end
	return (pcall(_G.SetCVar, "whisperMode", mode))
end

-- The taskbar flash the game does for a whisper when its window is in the
-- background. Ours goes through the same call so a player who has it switched
-- off in the game keeps it switched off here.
function Compat.FlashClientIcon()
	if type(_G.FlashClientIcon) ~= "function" then return false end
	return (pcall(_G.FlashClientIcon))
end

-- The addon compartment: the list behind the button beside the minimap that
-- modern clients keep every addon's entry in. Only there on Retail, and only
-- once -- re-registering the same entry on a reload would give the player two.
--
-- Returns the entry so its text and icon can be changed later, or nil where
-- there is no compartment to register with, which is not a failure.
function Compat.RegisterAddonCompartment(entry)
	local compartment = _G.AddonCompartmentFrame
	if not compartment or type(compartment.RegisterAddon) ~= "function" then
		return nil
	end
	local registered = compartment.registeredAddons
	if type(registered) == "table" then
		for i = 1, #registered do
			if registered[i] == entry or (registered[i] and registered[i].text == entry.text) then
				return entry
			end
		end
	end
	if not pcall(compartment.RegisterAddon, compartment, entry) then return nil end
	return entry
end

function Compat.RefreshAddonCompartment()
	local compartment = _G.AddonCompartmentFrame
	if not compartment or type(compartment.UpdateDisplay) ~= "function" then return end
	pcall(compartment.UpdateDisplay, compartment)
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
