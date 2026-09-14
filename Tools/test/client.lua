-- The clients this addon says it supports, and what each of them actually is.
--
-- One place, because a mock that drifts from the real client stops being a test
-- and becomes a second implementation that agrees with the first. Every flavour
-- here is a statement about a shipping client: what it has, what it does not,
-- and -- in CONTRACT below -- which functions the addon is entitled to expect.
--
-- Used by Tools/test/run.lua (does the whole addon come up?) and
-- Tools/test/flavour.lua (does it actually work?).

local Client = {}

local M = _G.WOWMOCK


local PROFILES = {
	retail = { build = { "12.1.0", "60000", "Sep 06 2026", 120100 }, project = 1 },
	-- The same client with the deprecated globals already gone.
	modern = { build = { "12.1.0", "60000", "Sep 06 2026", 120100 }, project = 1,
		modernOnly = true },
	mop    = { build = { "5.5.4", "60000", "Sep 06 2026", 50504 }, project = 19 },
	tbc    = { build = { "2.5.6", "60000", "Sep 06 2026", 20506 }, project = 5,
		legacy = true, noMasks = true, noClip = true },
	-- Classic Era 1.15.9 has Battle.net: friends, whispers, the lot, through the
	-- same C_BattleNet the other flavours use. Switching it off here modelled a
	-- client that does not exist and quietly excused the addon from working on
	-- one that does. What Classic genuinely lacks is the modern social API and
	-- the 12.0 chat restrictions, and those are what the flags now say.
	classic = { build = { "1.15.9", "60000", "Sep 06 2026", 11509 }, project = 2,
		legacy = true, noMasks = true, noClip = true, noModernSocial = true },
}

Client.PROFILES = PROFILES

-- Applies one of them to the mock. Everything below this point is a statement
-- about a shipping client, not a convenience for the code under test.
function Client.Setup(flavour, locale)
	local profile = PROFILES[flavour] or PROFILES.retail
	M.build = profile.build
	_G.WOW_PROJECT_ID = profile.project
	_G.locale = nil
	M.locale = locale or "enUS"

	-- The fonts that client would actually have on disk. A Korean install has the
	-- Korean ones and not the Chinese ones, and a German install has neither, which
	-- is the whole reason the addon probes instead of assuming.
	local LOCALE_FONTS = {
		koKR = { "Fonts\\2002.TTF", "Fonts\\2002B.TTF", "Fonts\\K_Damage.TTF" },
		zhCN = { "Fonts\\ARKai_T.ttf", "Fonts\\ARKai_C.ttf", "Fonts\\ARHei.ttf" },
		zhTW = { "Fonts\\bLEI00D.TTF", "Fonts\\bHEI00M.TTF", "Fonts\\bKAI00M.TTF" },
	}
	for _, path in ipairs(LOCALE_FONTS[M.locale] or {}) do
		M.fontFiles[path] = true
	end

	-- Retail, with nothing but the modern API. Blizzard has moved chat behind
	-- C_ChatInfo and Battle.net behind C_BattleNet, and the bare globals are on
	-- their way out -- so one profile removes them outright. An addon that still
	-- works here is an addon that will still work when they go.
	if profile.modernOnly then
		_G.SendChatMessage = nil
		_G.BNSendWhisper = nil
		_G.BNGetNumFriends = nil
		_G.BNGetFriendInfo = nil
		_G.GetPlayerInfoByGUID = _G.GetPlayerInfoByGUID
	end

	if profile.project ~= 1 then
	-- The addon compartment is a Retail thing; everywhere else the button next
	-- to the minimap is the only way in.
		_G.AddonCompartmentFrame = nil
	end
	if profile.legacy then
	-- 9.x era rendering API: no new SetGradient, no SetResizeBounds.
		M.Disable("Texture", "SetGradient")
		M.Disable("Frame", "SetResizeBounds")
		_G.GetPhysicalScreenSize = nil
	end
	if profile.noMasks then
		M.Disable("Frame", "CreateMaskTexture")
		M.Disable("Texture", "AddMaskTexture")
	end
	if profile.noClip then
		M.Disable("Frame", "SetClipsChildren")
	end
	-- Secret values and the chat restrictions around them arrived with Retail 12.0.
	-- Nowhere else has them, so nowhere else should be handed the functions that
	-- report them: an addon that works on Classic only because the mock pretended
	-- Classic answers those questions is an addon that has not been tested on
	-- Classic at all.
	if profile.project ~= 1 then
		_G.issecretvalue = nil
		_G.hasanysecretvalues = nil
		_G.C_ChatInfo.InChatMessagingLockdown = nil
		_G.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
		_G.C_ChatInfo.GetChatLineText = nil
		_G.C_ChatInfo.GetChatLineSenderName = nil
		_G.C_ChatInfo.GetChatLineSenderGUID = nil
		_G.C_ChatInfo.IsValidChatLine = nil
		_G.C_ChatInfo.IsChatLineCensored = nil
		_G.C_ChatInfo.UncensorChatLine = nil
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

-- The functions the addon may rely on, per flavour, written down so a mock
-- cannot quietly grow one the real client does not have -- which is exactly how
-- a wrong implementation starts looking correct. `present` must exist after
-- Setup; `absent` must not.
Client.CONTRACT = {
	retail = {
		present = {
			"C_ChatInfo.SendChatMessage",
			"C_BattleNet.SendWhisper",
			"C_BattleNet.GetFriendAccountInfo",
			"C_BattleNet.GetAccountInfoByID",
			"C_ChatInfo.InChatMessagingLockdown",
			"C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
			"C_ChatInfo.GetChatLineText",
			"C_ChatInfo.GetChatLineSenderName",
			"C_ChatInfo.GetChatLineSenderGUID",
			"C_ChatInfo.IsValidChatLine",
			"C_ChatInfo.IsChatLineCensored",
			"C_ChatInfo.UncensorChatLine",
			"C_FriendList.SendWho",
			"issecretvalue",
			"hasanysecretvalues",
			"AddonCompartmentFrame",
		},
		absent = {},
	},
	-- The same client with the deprecated aliases already withdrawn.
	modern = {
		present = { "C_ChatInfo.SendChatMessage", "C_BattleNet.SendWhisper" },
		absent = { "SendChatMessage", "BNSendWhisper", "BNGetNumFriends" },
	},
	-- MoP Classic: modern namespaces, no 12.0 chat restrictions.
	mop = {
		present = {
			"C_ChatInfo.SendChatMessage", "C_BattleNet.SendWhisper",
			"C_BattleNet.GetFriendAccountInfo", "C_FriendList.SendWho",
		},
		absent = {
			"issecretvalue", "hasanysecretvalues",
			"C_ChatInfo.InChatMessagingLockdown", "C_ChatInfo.IsValidChatLine",
			"AddonCompartmentFrame",
		},
	},
	-- TBC Anniversary: as MoP for our purposes.
	tbc = {
		present = {
			"C_ChatInfo.SendChatMessage", "C_BattleNet.SendWhisper",
			"C_BattleNet.GetFriendAccountInfo", "C_FriendList.SendWho",
		},
		absent = {
			"issecretvalue", "hasanysecretvalues",
			"C_ChatInfo.InChatMessagingLockdown", "AddonCompartmentFrame",
		},
	},
	-- Classic Era 1.15.9 has Battle.net -- friends, whispers, account lookup --
	-- and does not have the modern social API or the 12.0 restrictions.
	classic = {
		present = {
			"C_ChatInfo.SendChatMessage", "C_BattleNet.SendWhisper",
			"C_BattleNet.GetFriendAccountInfo", "C_BattleNet.GetAccountInfoByID",
		},
		absent = {
			"C_FriendList", "issecretvalue", "hasanysecretvalues",
			"C_ChatInfo.InChatMessagingLockdown", "AddonCompartmentFrame",
		},
	},
}

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
