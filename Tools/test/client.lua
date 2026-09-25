-- The clients this addon says it supports, and what each of them actually is.
--
-- One place, because a mock that drifts from the real client stops being a test
-- and becomes a second implementation that agrees with the first. Every flavour
-- here is a statement about a shipping client: what it has, what it does not,
-- and -- in CONTRACT below -- which functions the addon is entitled to expect.
--
-- Used by Tools/test/run.lua (does the whole addon come up?) and
-- Tools/test/flavour.lua (does it actually work?).
--
-- PROVENANCE. Every entry below was checked against Blizzard's own generated API
-- documentation in Gethe/wow-ui-source at the tags for the exact shipping
-- builds this addon supports -- 12.1.0, 5.5.4, 2.5.6, 1.15.9 and 1.60.1 -- by
-- looking for the function's Name and Namespace in
-- Interface/AddOns/Blizzard_APIDocumentationGenerated. Nothing here is inferred
-- from when Retail first received an API: Classic gets them by backport, which
-- is precisely how the previous version of this file came to be wrong.

local Client = {}

local M = _G.WOWMOCK


local PROFILES = {
	-- The shipping clients. Their API surface is very nearly identical: the
	-- modern namespaces, the chat-line APIs, the secret-value APIs and the
	-- restriction APIs are all present on every one of them, verified at the
	-- tags above. The addon compartment is the only thing on this list that
	-- really is Retail-only.
	retail  = { build = { "12.1.0", "60000", "Sep 06 2026", 120100 }, project = 1 },

	-- World of Warcraft: Forever, which Blizzard's own source calls Camelot.
	-- Build 1.60.1.69893, interface 16001.
	--
	-- The project ID is deliberately WOW_PROJECT_MAINLINE here, because that is
	-- what the client is expected to answer: Forever loads the mainline family
	-- of Blizzard_BNet, whose first line is
	--   WOW_PROJECT_ID = WOW_PROJECT_ID or WOW_PROJECT_MAINLINE
	-- So this profile is also the test that Compat reads the interface number
	-- before the project ID. Set the ID to 2 and it would still have to say
	-- "forever"; let Compat ask the ID first and this profile says "retail".
	forever = { build = { "1.60.1", "69893", "Sep 15 2026", 16001 }, project = 1 },
	mop     = { build = { "5.5.4", "60000", "Sep 06 2026", 50504 }, project = 19,
		noCompartment = true },
	tbc     = { build = { "2.5.6", "60000", "Sep 06 2026", 20506 }, project = 5,
		noCompartment = true },
	classic = { build = { "1.15.9", "60000", "Sep 06 2026", 11509 }, project = 2,
		noCompartment = true },

	-- Not a shipping client: Retail with the deprecated aliases already
	-- withdrawn, so the addon is made to prove it does not lean on them.
	modern  = { build = { "12.1.0", "60000", "Sep 06 2026", 120100 }, project = 1,
		modernOnly = true },

	-- Also not a shipping client. An older, poorer one, kept so the fallbacks in
	-- Compat are exercised by something rather than by nothing. It is labelled
	-- for what it is: this is not what Classic Era looks like.
	fallback = { build = { "1.15.9", "60000", "Sep 06 2026", 11509 }, project = 2,
		noCompartment = true, legacyRendering = true, noModernSocial = true,
		noModernChat = true, noBNetNamespace = true, noSecrets = true },
}

Client.PROFILES = PROFILES

-- Applies one of them to the mock.
function Client.Setup(flavour, locale)
	local profile = PROFILES[flavour] or PROFILES.retail
	M.build = profile.build
	_G.WOW_PROJECT_ID = profile.project
	_G.locale = nil
	M.locale = locale or "enUS"

	-- The fonts that client would actually have on disk. A Korean install has
	-- the Korean ones and not the Chinese ones, and a German install has
	-- neither, which is the whole reason the addon probes instead of assuming.
	local LOCALE_FONTS = {
		koKR = { "Fonts\\2002.TTF", "Fonts\\2002B.TTF", "Fonts\\K_Damage.TTF" },
		zhCN = { "Fonts\\ARKai_T.ttf", "Fonts\\ARKai_C.ttf", "Fonts\\ARHei.ttf" },
		zhTW = { "Fonts\\bLEI00D.TTF", "Fonts\\bHEI00M.TTF", "Fonts\\bKAI00M.TTF" },
	}
	for _, path in ipairs(LOCALE_FONTS[M.locale] or {}) do
		M.fontFiles[path] = true
	end

	-- The addon compartment is the one thing on this list that really is
	-- Retail-only: no reference to it anywhere in the 5.5.4, 2.5.6 or 1.15.9
	-- interface source.
	if profile.noCompartment then
		_G.AddonCompartmentFrame = nil
	end

	-- Retail with the deprecated aliases already withdrawn. An addon that still
	-- works here is one that will still work when they go.
	if profile.modernOnly then
		_G.SendChatMessage = nil
		_G.BNSendWhisper = nil
		_G.BNGetNumFriends = nil
		_G.BNGetFriendInfo = nil
	end

	-- Everything below models the deliberately-poorer fallback client, not any
	-- client Blizzard ships. SetGradient in its modern form, SetResizeBounds,
	-- CreateMaskTexture, SetClipsChildren and GetPhysicalScreenSize are all used
	-- by Blizzard's own interface code on all four shipping versions.
	if profile.legacyRendering then
		M.Disable("Texture", "SetGradient")
		M.Disable("Frame", "SetResizeBounds")
		M.Disable("Frame", "CreateMaskTexture")
		M.Disable("Texture", "AddMaskTexture")
		M.Disable("Frame", "SetClipsChildren")
		_G.GetPhysicalScreenSize = nil
	end
	if profile.noModernChat then
		_G.C_ChatInfo = {}
	end
	if profile.noBNetNamespace then
		_G.C_BattleNet = nil
	end
	-- The other half of "poorer": a client with no secret values at all, so the
	-- branches in Compat that run when `issecretvalue` is missing are exercised
	-- by something rather than by nothing. No shipping client looks like this --
	-- all four have the globals -- which is exactly why it is only here.
	if profile.noSecrets then
		_G.issecretvalue = nil
		_G.hasanysecretvalues = nil
		_G.C_Secrets = nil
	end
	if profile.noModernSocial then
		_G.C_PartyInfo = nil
		_G.C_FriendList = nil
		_G.GetNumFriends = function() return 0 end
		_G.GetFriendInfo = function() return nil end
		_G.AddFriend = function() end
		_G.AddOrDelIgnore = function() end
		_G.InviteUnit = function() end
		_G.SendWho = function() end
	end

	return profile
end

--------------------------------------------------------------------------------
-- What each client is entitled to have
--------------------------------------------------------------------------------

-- Verified, not assumed. See PROVENANCE at the top of this file.
--
-- The four shipping clients share one surface, so it is written once and the
-- differences are listed against it rather than four nearly-identical lists
-- pretending to be independent findings.
local SHIPPING = {
	-- C_ChatInfo: all nine on 12.1.0, 5.5.4, 2.5.6 and 1.15.9.
	"C_ChatInfo.SendChatMessage",
	"C_ChatInfo.InChatMessagingLockdown",
	"C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
	"C_ChatInfo.GetChatLineText",
	"C_ChatInfo.GetChatLineSenderName",
	"C_ChatInfo.GetChatLineSenderGUID",
	"C_ChatInfo.IsValidChatLine",
	"C_ChatInfo.IsChatLineCensored",
	"C_ChatInfo.UncensorChatLine",
	-- C_BattleNet: Classic Era has these too, which is why its Battle.net works.
	"C_BattleNet.SendWhisper",
	"C_BattleNet.GetFriendAccountInfo",
	"C_BattleNet.GetAccountInfoByID",
	-- C_FriendList and C_PartyInfo: present on all four, so the addon takes the
	-- namespaced branch on Classic Era and not the legacy one.
	"C_FriendList.SendWho",
	"C_FriendList.GetFriendInfoByIndex",
	"C_FriendList.GetNumFriends",
	"C_FriendList.GetWhoInfo",
	"C_FriendList.GetNumWhoResults",
	"C_PartyInfo.InviteUnit",
	-- The secret-value globals, and the runtime question about them.
	"issecretvalue",
	"hasanysecretvalues",
	"C_Secrets.HasSecretRestrictions",
}

local function shipping(extraPresent, absent)
	local present = {}
	for i = 1, #SHIPPING do present[i] = SHIPPING[i] end
	for _, name in ipairs(extraPresent or {}) do present[#present + 1] = name end
	return { present = present, absent = absent or {} }
end

Client.CONTRACT = {
	retail  = shipping({ "AddonCompartmentFrame" }),
	-- Every name in SHIPPING is in the 1.60.1 generated documentation: all nine
	-- C_ChatInfo entries, the three C_BattleNet ones, C_FriendList, C_PartyInfo
	-- and C_Secrets.HasSecretRestrictions. Forever is the current engine with
	-- Vanilla's world on it, not an old client.
	--
	-- The addon compartment is the one thing this contract will not claim either
	-- way. Blizzard_Minimap loads it with [AllowLoadGameType mainline], and
	-- whether Forever is inside that family for that line cannot be read off the
	-- source with confidence: the same TOC writes "[AllowLoadGameType mainline]
	-- [ExcludeLoadGameType camelot]" elsewhere, which says it is, and
	-- Blizzard_ChatFrameBase writes "[AllowLoadGameType mainline, camelot]",
	-- which says it is not. The addon asks _G.AddonCompartmentFrame at runtime
	-- and behaves either way, so the honest contract is silence rather than a
	-- guess dressed up as a finding.
	forever = shipping(),
	-- No reference to the addon compartment anywhere in their interface source.
	mop     = shipping(nil, { "AddonCompartmentFrame" }),
	tbc     = shipping(nil, { "AddonCompartmentFrame" }),
	classic = shipping(nil, { "AddonCompartmentFrame" }),
	-- Retail minus the deprecated aliases.
	modern  = shipping({ "AddonCompartmentFrame" },
		{ "SendChatMessage", "BNSendWhisper", "BNGetNumFriends" }),
	-- The deliberately-poorer client. Not a statement about any real build.
	fallback = {
		present = { "SendChatMessage", "BNSendWhisper", "BNGetNumFriends" },
		absent = {
			"C_ChatInfo.SendChatMessage", "C_BattleNet", "C_FriendList",
			"C_PartyInfo", "AddonCompartmentFrame",
			"issecretvalue", "hasanysecretvalues", "C_Secrets",
		},
	},
}

-- Which clients are expected to answer the restriction questions at all.
--
-- Read off the contract rather than off the flavour's name, so this cannot drift
-- from what the file above says the client has. All four shipping clients
-- answer; only the artificial fallback, which has the APIs taken away on
-- purpose, does not.
function Client.HasChatRestrictionAPI(flavour)
	local contract = Client.CONTRACT[flavour]
	if not contract then return false end
	for _, path in ipairs(contract.present or {}) do
		if path == "C_ChatInfo.InChatMessagingLockdown" then return true end
	end
	return false
end

-- Resolves "C_ChatInfo.SendChatMessage" against the globals.
function Client.Lookup(path)
	local value = _G
	for part in string.gmatch(path, "[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

return Client
