-- WhatTheWhisper -- Addon lifecycle.
--
-- Uses the Ace3 libraries embedded under Libs/: AceAddon for the lifecycle,
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
	-- The minimap and everything hanging off it are rebuilt on every world
	-- transition, and an addon that loaded after us may have raised itself over
	-- our button in the meantime. Re-asserting here is what keeps the icon on
	-- screen through a zone change, a reload and a loading screen.
	ns.Minimap.Update()
	self:ShowWelcome()
end

-- First run: one line, once, account wide. Not a popup, not a tour, not a
-- window that steals the screen while somebody is reading a whisper -- the
-- addon only has to say that it is there and how to open it.
function addon:ShowWelcome()
	local global = ns.db and ns.db.global
	if not global or global.seenWelcome then return end
	global.seenWelcome = true
	ns.Print(L["WhatTheWhisper is ready. Type /wtw to open it."])
	ns.Debug.Log("ui", "first run welcome shown")
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
	local command = input:match("^(%S*)")
	command = (command or ""):lower()

	if command == "" then
		ns.UI.Toggle()
	elseif command == "show" or command == "open" then
		ns.UI.Show()
	elseif command == "hide" or command == "close" then
		ns.UI.Hide()
	elseif command == "config" or command == "options" or command == "settings" then
		ns.SettingsUI.Toggle()
	elseif command == "clear" then
		ns.UI.ConfirmClearAll()
	elseif command == "reset" then
		ns.UI.ConfirmResetSettings()
	elseif command == "expose" or command == "overview" then
		ns.Expose.Toggle()
	elseif command == "debug" then
		self:HandleDebugCommand(input:match("^%S*%s+(.*)$"))
	elseif command == "diag" then
		self:PrintDiagnostics()
	elseif command == "help" or command == "?" then
		ns.Print(L["Commands:"])
		ns.Print(L["/wtw - toggle the messenger"])
		ns.Print(L["/wtw show / hide - open or close the messenger"])
		ns.Print(L["/wtw config - open settings"])
		ns.Print(L["/wtw <name> - open a conversation"])
		ns.Print(L["/wtw clear - clear all history"])
		ns.Print(L["/wtw reset - restore default settings"])
		ns.Print(L["/wtw diag - print client diagnostics"])
		ns.Print(L["/wtw debug - toggle developer logging"])
	else
		local name = input
		local id = Compat.NormalizeName(ns.Text.UpperFirst(name))
		ns.ConversationManager.GetOrCreate(id)
		ns.UI.Show()
		ns.ConversationManager.Select(id)
		ns.UI.EnsureConversationOpen(id, true)
	end
end

-- /wtw debug            toggle
-- /wtw debug on|off     set explicitly
-- /wtw debug log        dump the recent ring buffer, whether or not logging is on
function addon:HandleDebugCommand(argument)
	argument = (argument or ""):lower():match("^%s*(%S*)") or ""
	if argument == "log" or argument == "dump" then
		local recent = ns.Debug.Recent(30)
		if #recent == 0 then
			ns.Print(L["Nothing logged yet."])
			return
		end
		for i = 1, #recent do ns.Print(recent[i]) end
		return
	end

	local enabled
	if argument == "on" then
		enabled = ns.Debug.Toggle(true)
	elseif argument == "off" then
		enabled = ns.Debug.Toggle(false)
	else
		enabled = ns.Debug.Toggle()
	end
	ns.Print(enabled and L["Debug logging on."] or L["Debug logging off."])
	if enabled then
		ns.Print(L["/wtw debug log - show the last few entries"])
	end
	if ns.SettingsUI.IsShown() then ns.SettingsUI.Refresh() end
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
	ns.Print(("errors=%d degraded=%s debug=%s"):format(
		ns.Debug.ErrorCount(), tostring(ns.Debug.IsDegraded()), tostring(ns.Debug.IsEnabled())))

	-- Pools, busiest first. Only the ones that ever produced something: a list
	-- of twenty zeroes hides the one number worth reading.
	local pools = ns.Pool.Snapshot()
	local shown = 0
	for i = 1, #pools do
		local entry = pools[i]
		if entry.created > 0 and shown < 6 then
			shown = shown + 1
			ns.Print(("pool %s: %d created, %d in use, %d free"):format(
				entry.name, entry.created, entry.active, entry.free))
		end
	end
	ns.Print(("pooled objects total: %d"):format(ns.Pool.TotalCreated()))
end

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

_G.BINDING_HEADER_WHATTHEWHISPER = "WhatTheWhisper"
_G.BINDING_NAME_WHATTHEWHISPER_TOGGLE = L["WhatTheWhisper"]
_G.BINDING_NAME_WHATTHEWHISPER_EXPOSE = L["All windows"]
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
