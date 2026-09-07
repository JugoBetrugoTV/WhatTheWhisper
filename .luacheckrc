-- Static analysis config for WhatTheWhisper.
std = "lua51"
max_line_length = false
codes = true
-- `function obj:Method()` closures that do not touch self are idiomatic here,
-- and Ace/WoW callbacks frequently ignore their first argument.
self = false
exclude_files = { "Ace3/**", "Tools/test/**" }

-- The addon namespace arrives as a vararg, so every file starts with `local _, ns = ...`
globals = {
	"WhatTheWhisper",
	"BINDING_HEADER_WHATTHEWHISPER",
	"BINDING_NAME_WHATTHEWHISPER_TOGGLE",
	"BINDING_NAME_WHATTHEWHISPER_EXPOSE",
	"BINDING_NAME_WHATTHEWHISPER_REPLY",
	"WhatTheWhisperDB",
	"WhatTheWhisperHistoryDB",
	"UISpecialFrames",
}

read_globals = {
	-- core
	"CreateFrame", "CreateFont", "UIParent", "Minimap", "GameTooltip",
	"ColorPickerFrame", "OpacitySliderFrame", "DEFAULT_CHAT_FRAME", "LibStub",
	"SettingsPanel", "InterfaceOptionsFrame", "HideUIPanel", "Settings",
	"InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
	-- info
	"GetBuildInfo", "GetLocale", "GetRealmName", "GetNormalizedRealmName",
	"GetTime", "GetServerTime", "time", "date", "GetScreenHeight", "GetScreenWidth",
	"GetPhysicalScreenSize", "GetCursorPosition", "GetFramerate",
	"WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
	"WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC",
	-- units and social
	"UnitName", "UnitClass", "UnitLevel", "UnitExists", "UnitIsPlayer", "UnitRace",
	"UnitFactionGroup", "UnitSex", "IsInInstance", "IsInRaid", "IsInGroup",
	"GetNumGroupMembers", "InCombatLockdown", "IsShiftKeyDown", "IsControlKeyDown",
	"IsAltKeyDown", "GetPlayerInfoByGUID", "Ambiguate", "SetPortraitTexture",
	"C_FriendList", "C_PartyInfo", "C_BattleNet", "C_GuildInfo", "C_ClassColor",
	"C_CreatureInfo", "C_Timer", "C_AddOns",
	"BNGetNumFriends", "BNGetFriendInfo", "BNSendWhisper",
	"GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster",
	"GetNumFriends", "GetFriendInfo", "AddFriend", "AddOrDelIgnore", "InviteUnit",
	"SendWho", "GetNumWhoResults", "GetWhoInfo",
	-- chat
	"SendChatMessage", "ChatFrame_AddMessageEventFilter",
	"ChatFrame_RemoveMessageEventFilter", "SetItemRef", "FlashClientIcon",
	-- sound
	"PlaySound", "PlaySoundFile", "SOUNDKIT",
	-- constants
	"RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS", "CLASS_ICON_TCOORDS",
	"LOCALIZED_CLASS_NAMES_MALE", "ERR_CHAT_PLAYER_NOT_FOUND_S", "LEVEL",
	"WEEKDAY_SUNDAY", "WEEKDAY_MONDAY", "WEEKDAY_TUESDAY", "WEEKDAY_WEDNESDAY",
	"WEEKDAY_THURSDAY", "WEEKDAY_FRIDAY", "WEEKDAY_SATURDAY",
	"ICON_LIST", "ICON_TAG_LIST", "MAX_CHAT_MSG_LENGTH",
	"UPPER_LEFT_VERTEX", "LOWER_LEFT_VERTEX", "UPPER_RIGHT_VERTEX", "LOWER_RIGHT_VERTEX",
	-- lua-ish helpers WoW adds
	"wipe", "tinsert", "tremove", "strsplit", "strtrim", "strjoin", "format",
	"strmatch", "strfind", "strsub", "gsub", "strlower", "strupper",
	"max", "min", "abs", "floor", "ceil", "geterrorhandler", "hooksecurefunc",
	"securecall", "securecallfunction", "debugstack", "debugprofilestop",
	"CreateColor", "IsLoggedIn",
}
