-- WhatTheWhisper -- Addon lifecycle.
--
-- Uses the Ace3 already present in the repository: AceAddon for the lifecycle,
-- AceDB for profile-aware SavedVariables, AceConsole for slash commands and
-- AceLocale for strings. The UI is deliberately not AceGUI/AceConfig.

local ADDON_NAME, ns = ...

local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("WhatTheWhisper")

local addon = AceAddon:NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = addon

local Compat = ns.Compat

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function addon:OnInitialize()
	ns.db = AceDB:New("WhatTheWhisperDB", ns.defaults, true)

	local function onProfile()
		ns.Theme.Refresh()
		ns.History.ApplyRetention()
		ns.UI.RefreshLayout()
		ns.UI.RefreshAll()
		ns.Minimap.Update()
		if ns.SettingsUI.IsShown() then ns.SettingsUI.Refresh() end
	end
	ns.db.RegisterCallback(self, "OnProfileChanged", onProfile)
	ns.db.RegisterCallback(self, "OnProfileCopied", onProfile)
	ns.db.RegisterCallback(self, "OnProfileReset", onProfile)

	ns.History.Init()
	ns.Theme.Refresh()

	self:RegisterChatCommand("wtw", "HandleCommand")
	self:RegisterChatCommand("whatthewhisper", "HandleCommand")

	ns.Options.panel = self:BuildOptionsStub()
end

function addon:OnEnable()
	ns.ConversationManager.LoadPersisted()
	ns.ChatEvents.Init()
	ns.Combat.Init()
	ns.UI.Init()
	ns.Minimap.Update()

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	self:RegisterEvent("UI_SCALE_CHANGED", "OnScaleChanged")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnScaleChanged")
	self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
end

function addon:OnEnteringWorld()
	-- The guild roster is empty until the server sends it; ask once on login so
	-- class colours resolve for guildmates.
	Compat.RequestGuildRoster()
	ns.PlayerInfo.ScanFriends()
end

function addon:OnScaleChanged()
	Compat.ResetPhysicalHeight()
	ns.Theme.Refresh()
end

function addon:OnLogout()
	-- Trim before the SavedVariables file is written rather than after it is read.
	ns.History.Prune()
	for _, conv in pairs(ns.ConversationManager.All()) do
		if conv.record then ns.History.WriteMeta(conv) end
	end
end

--------------------------------------------------------------------------------
-- Blizzard options stub
--------------------------------------------------------------------------------

function addon:BuildOptionsStub()
	local panel = CreateFrame("Frame", "WhatTheWhisperOptionsPanel", UIParent)
	panel:Hide()

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("WhatTheWhisper")

	local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	body:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	body:SetJustifyH("LEFT")
	body:SetText(L["/wtw config - open settings"])

	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(180, 24)
	button:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -16)
	button:SetText(L["Settings"])
	button:SetScript("OnClick", function()
		if _G.HideUIPanel and _G.SettingsPanel then _G.HideUIPanel(_G.SettingsPanel) end
		if _G.HideUIPanel and _G.InterfaceOptionsFrame then
			_G.HideUIPanel(_G.InterfaceOptionsFrame)
		end
		ns.SettingsUI.Show()
	end)

	Compat.RegisterOptionsPanel(panel, "WhatTheWhisper")
	return panel
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

function addon:HandleCommand(input)
	input = ns.Text.Trim(input or "")
	local command, rest = input:match("^(%S*)%s*(.*)$")
	command = (command or ""):lower()

	if command == "" then
		ns.UI.Toggle()
	elseif command == "config" or command == "options" or command == "settings" then
		ns.SettingsUI.Toggle()
	elseif command == "clear" then
		ns.UI.ConfirmClearAll()
	elseif command == "expose" or command == "overview" then
		ns.Expose.Toggle()
	elseif command == "diag" then
		self:PrintDiagnostics()
	elseif command == "help" or command == "?" then
		ns.Print(L["Commands:"])
		ns.Print(L["/wtw - toggle the messenger"])
		ns.Print(L["/wtw config - open settings"])
		ns.Print(L["/wtw <name> - open a conversation"])
		ns.Print(L["/wtw clear - clear all history"])
		ns.Print(L["/wtw diag - print client diagnostics"])
	else
		local name = input
		local id = Compat.NormalizeName(ns.Text.UpperFirst(name))
		ns.ConversationManager.GetOrCreate(id)
		ns.UI.Show()
		ns.ConversationManager.Select(id)
		ns.UI.EnsureConversationOpen(id, true)
	end
end

function addon:PrintDiagnostics()
	local conversations, messages, bytes = ns.History.Stats()
	ns.Print(("v%s on %s (%s, toc %d)"):format(
		ns.VERSION, Compat.flavorName or Compat.flavor,
		Compat.buildVersion or "?", Compat.tocVersion))
	ns.Print(("masks=%s clip=%s gradient=%s bnet=%s hyperlinks=%s"):format(
		tostring(Compat.hasMasks), tostring(Compat.hasClipsChildren),
		tostring(Compat.hasGradient), tostring(Compat.hasBattleNet),
		tostring(Compat.hasHyperlinks)))
	ns.Print(("history: %d messages in %d conversations, ~%s"):format(
		messages, conversations, ns.Format.Bytes(bytes)))
	ns.Print(("pixel=%.3f font=%s skin=%s"):format(
		ns.Pixel.Size(UIParent), tostring(ns.Theme.fontPath), tostring(ns.Theme.skinID)))
end

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

_G.BINDING_HEADER_WHATTHEWHISPER = "WhatTheWhisper"
_G.BINDING_NAME_WHATTHEWHISPER_TOGGLE = L["WhatTheWhisper"]
_G.BINDING_NAME_WHATTHEWHISPER_EXPOSE = L["Overview"]
_G.BINDING_NAME_WHATTHEWHISPER_REPLY = L["Whisper"]

function ns.BindingToggle()
	ns.UI.Toggle()
end

function ns.BindingExpose()
	ns.Expose.Toggle()
end

-- Jump straight to the most recent unread thread, or the newest one.
function ns.BindingReply()
	local CM = ns.ConversationManager
	local ordered = CM.Ordered()
	local target
	for i = 1, #ordered do
		if ordered[i].unread > 0 then target = ordered[i] break end
	end
	target = target or ordered[1]
	if not target then
		ns.UI.Show()
		return
	end
	ns.UI.Show()
	CM.Select(target.id)
	ns.Anim.After(0.05, function() ns.MainWindow.Get().view:Focus() end)
end
