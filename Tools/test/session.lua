-- A long, random session, with the invariants checked after every step.
--
-- The other suites each drive one thing deliberately. This one drives all of
-- them at once in an order nobody chose: whispers arriving while the settings
-- window is open, a skin change mid-scroll, a popout detached and docked and
-- detached again, a logout in the middle of it. That is where the interesting
-- failures are, because they are the states nobody thought to write a test for.
--
-- Seeded, so a failure is reproducible: `lua Tools/test/session.lua 7 800`
-- replays exactly. The suite runs a fixed set of seeds; a wider sweep is a
-- loop over more of them.
--
-- What it found the first time it ran: twenty settings reads that threw once
-- AceDB had stripped the profile at logout. See Tools/test/shutdown.lua, which
-- is the deliberate version of that discovery.
local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK
_G.SlashCmdList = {}
_G.UnitRace = function() return "Human","Human" end
_G.UnitFactionGroup = function() return "Alliance","Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end
local ns = dofile(ROOT .. "Tools/test/harness.lua").Load()
local CM = ns.ConversationManager
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local soft = {}
ns.SoftError = function(c, e) soft[#soft+1] = c .. ": " .. tostring(e) end

local ARG_SEED = tonumber(arg and arg[1])
local STEPS = tonumber(arg and arg[2]) or 250
local SEEDS = ARG_SEED and { ARG_SEED } or { 1, 2, 3, 4, 5, 6, 7, 8 }

local NAMES = { "Thrall", "Jaina", "Sylvanas", "Anduin", "Muradin", "Vol'jin", "Baine" }
M.guids = M.guids or {}
for i, n in ipairs(NAMES) do
	M.guids["G-" .. n] = { class = ({"SHAMAN","MAGE","ROGUE","PRIEST","WARRIOR","DRUID","HUNTER"})[i],
		race = "Orc", name = n, realm = "Blackrock" }
end
local function pick(t) return t[math.random(#t)] end
local function whisper(name, text)
	M.FireEvent("CHAT_MSG_WHISPER", text, name, "Common", "", name, "", 0, 0, "", 0, 1, "G-" .. name)
end

ns.UI.Show()
M.RunFrames(6)

local failures = {}
local function violation(what, detail)
	failures[#failures + 1] = ("%s -- %s"):format(what, tostring(detail))
end

local function invariants(stepLabel)
	local main = ns.MainWindow.Get()
	if not main then return end
	local list = main.view and main.view.list
	if list then
		-- Layout entries must be ordered by y and carry a positive height.
		for i = 1, #list.layout do
			local e = list.layout[i]
			if type(e.y) ~= "number" or type(e.h) ~= "number" or e.h < 0 then
				violation(stepLabel .. ": layout entry is not a box", i)
				break
			end
			if i > 1 and e.y < list.layout[i-1].y - 0.01 then
				violation(stepLabel .. ": layout went backwards at " .. i,
					("%.1f after %.1f"):format(e.y, list.layout[i-1].y))
				break
			end
		end
		-- Exactly zero or one receipt, and it is the last entry when present.
		local seenReceipt = 0
		for i = 1, #list.layout do
			if list.layout[i].kind == "receipt" then
				seenReceipt = seenReceipt + 1
				if i ~= #list.layout then
					violation(stepLabel .. ": a receipt is not the last entry", i)
				end
			end
		end
		if seenReceipt > 1 then violation(stepLabel .. ": more than one receipt", seenReceipt) end
		if list.conv and list.totalHeight < 0 then
			violation(stepLabel .. ": negative total height", list.totalHeight)
		end
	end
	-- Unread counters never go negative, and the total matches the parts.
	local total = 0
	for _, c in pairs(CM.All()) do
		if (c.unread or 0) < 0 then violation(stepLabel .. ": negative unread", c.id) end
		total = total + (c.unread or 0)
	end
	-- Pools hand out only what they made.
	for _, pool in ipairs(ns.Pool.registry or {}) do
		local created, active = pool:Stats()
		if active > created then
			violation(stepLabel .. ": pool handed out more than it made: " .. tostring(pool.name),
				("%d active of %d created"):format(active, created))
		end
	end
	if ns.Debug.ErrorCount() > 0 then
		violation(stepLabel .. ": the addon counted an internal error",
			ns.Debug.ErrorCount())
	end
	if CM.TotalUnread() ~= total then
		violation(stepLabel .. ": unread total disagrees with the threads",
			("%d vs %d"):format(CM.TotalUnread(), total))
	end
end

local ACTIONS = {
	function() whisper(pick(NAMES), "text " .. math.random(1000)) end,
	function() local n = pick(NAMES) CM.GetOrCreate(ns.Compat.NormalizeName(n))
		CM.SendMessage(ns.Compat.NormalizeName(n), "out " .. math.random(1000)) end,
	function() local n = pick(NAMES) CM.Select(ns.Compat.NormalizeName(n)) end,
	function() ns.UI.TogglePopout(ns.Compat.NormalizeName(pick(NAMES))) end,
	function() ns.UI.Toggle() end,
	function() ns.SettingsUI.Toggle() end,
	function() ns.Expose.Toggle() end,
	function() local l = ns.MainWindow.Get().view.list
		l:SetOffset(math.random(0, 400), false) end,
	function() ns.Options.Set("appearance.skin", pick({"midnight","messenger","dark","minimal","glass","classic"})) end,
	function() ns.Options.Set("appearance.fontScale", math.random(-2, 4)) end,
	function() ns.Options.Set("appearance.density", pick({"comfortable","compact"})) end,
	function() ns.Options.Set("appearance.timestamps", math.random(2) == 1) end,
	function() ns.Options.Set("appearance.dateSeparators", math.random(2) == 1) end,
	function() ns.Options.Set("appearance.grouping", math.random(2) == 1) end,
	function() ns.Options.Set("appearance.bubbles", math.random(2) == 1) end,
	function() ns.Options.Set("appearance.avatars", math.random(2) == 1) end,
	function() ns.Options.Set("messages.deliveryStatus", math.random(2) == 1) end,
	function() ns.Options.Set("appearance.spacing", math.random(0, 2)) end,
	function() ns.Options.Set("appearance.radius", math.random(0, 2)) end,
	function() local n = ns.Compat.NormalizeName(pick(NAMES))
		CM.SetMuted(n, math.random(2) == 1) end,
	function() local n = ns.Compat.NormalizeName(pick(NAMES))
		CM.SetPinned(n, math.random(2) == 1) end,
	function() local n = ns.Compat.NormalizeName(pick(NAMES)) CM.MarkRead(n) end,
	function() local n = ns.Compat.NormalizeName(pick(NAMES)) CM.MarkUnread(n) end,
	function() ns.UI.CloseConversation(ns.Compat.NormalizeName(pick(NAMES))) end,
	function() ns.Search.FilterConversations(pick({ "text", "out", "zz", "" })) end,
	function() ns.Search.Messages(pick({ "text", "out", "zz" }), nil, function() end) end,
	function() ns.Search.Cancel() end,
	function() M.FireEvent("PLAYER_REGEN_DISABLED") end,
	function() M.FireEvent("PLAYER_REGEN_ENABLED") end,
	function() ns.History.Clear(ns.Compat.NormalizeName(pick(NAMES))) end,
	function() ns.UI.RefreshAll() end,

	-- Click something. Whatever is on screen, whichever window is up.
	function()
		local roots = { ns.MainWindow.Get(), _G.WhatTheWhisperSettings,
			_G.WhatTheWhisperContextMenu, _G.WhatTheWhisperCopyDialog,
			_G.WhatTheWhisperPromptDialog, _G.WhatTheWhisperConfirmDialog }
		local targets = {}
		for _, root in ipairs(roots) do
			if root and root.IsShown and root:IsShown() then
				for _, node in ipairs(M.Descendants(root)) do
					local sc = node._scripts
					if sc and (sc.OnMouseUp or sc.OnClick) and node.IsShown and node:IsShown()
						and (node:GetWidth() or 0) > 1 and (node:GetHeight() or 0) > 1 then
						targets[#targets + 1] = node
					end
				end
			end
		end
		if #targets > 0 then
			local node = targets[math.random(#targets)]
			pcall(M.Click, node, math.random(8) == 1 and "RightButton" or "LeftButton")
		end
	end,

	-- Type into the composer and sometimes send it.
	function()
		local view = ns.MainWindow.Get().view
		if not view.composer then return end
		view.composer.input:SetText(("wort "):rep(math.random(1, 40)))
		if math.random(2) == 1 then view.composer:Submit() end
	end,

	-- The emoji picker, and a glyph out of it.
	function()
		local view = ns.MainWindow.Get().view
		if not view.composer or not view.composer.emoji then return end
		ns.EmojiPicker.Toggle(view.composer.emoji, view.composer)
	end,

	-- A context menu, and something out of it.
	function()
		local c = CM.Get(ns.Compat.NormalizeName(pick(NAMES)))
		if not c then return end
		local entries = ns.UI.BuildConversationMenu(c)
		local usable = {}
		for i = 1, #entries do
			if entries[i].onClick and not entries[i].disabled then usable[#usable+1] = entries[i] end
		end
		if #usable > 0 then pcall(usable[math.random(#usable)].onClick) end
	end,

	-- Dialogs: open one, then answer it one way or the other.
	function()
		local c = CM.Get(ns.Compat.NormalizeName(pick(NAMES)))
		if c then ns.UI.ConfirmClear(c) end
		M.RunFrames(2)
		local d = _G.WhatTheWhisperConfirmDialog
		if d and d:IsShown() then
			local button = math.random(2) == 1 and d.accept or d.cancel
			if button and button:IsShown() then pcall(M.Click, button, "LeftButton") end
		end
	end,
	function()
		ns.UI.PromptAlias(ns.Compat.NormalizeName(pick(NAMES)))
		M.RunFrames(2)
		local d = _G.WhatTheWhisperPromptDialog
		if d and d:IsShown() then
			d.input:SetText(math.random(3) == 1 and "" or ("Name" .. math.random(99)))
			local button = math.random(3) == 1 and d.cancel or d.accept
			if button and button:IsShown() then pcall(M.Click, button, "LeftButton") end
		end
	end,

	-- Resizing, which re-lays out everything that measures itself.
	function()
		local w = ns.MainWindow.Get()
		w:SetSize(math.random(ns.SZ.WINDOW_MIN_W, 1400),
			math.random(ns.SZ.WINDOW_MIN_H, 900))
	end,
	function()
		ns.Options.Set("layout.sidebarWidth",
			math.random(ns.SZ.SIDEBAR_MIN_W, ns.SZ.SIDEBAR_MAX_W))
		ns.UI.RefreshAll()
	end,

	-- A logout and a fresh login, which is where saved state meets live state.
	function()
		M.FireEvent("PLAYER_LOGOUT")
		M.RunFrames(2)
		M.FireEvent("PLAYER_LOGIN")
	end,

	-- Somebody comes online or goes away.
	function() M.FireEvent("FRIENDLIST_UPDATE") end,
	function() M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Jaina' is currently playing.") end,
	function() M.FireEvent("BN_FRIEND_INFO_CHANGED") end,
}

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end

for _, seed in ipairs(SEEDS) do
	math.randomseed(seed)
	local errorsBefore, softBefore, failuresBefore = #M.errors, #soft, #failures
	for step = 1, STEPS do
		local which = math.random(#ACTIONS)
		local ok, err = pcall(ACTIONS[which])
		if not ok then
			violation(("seed %d step %d action %d"):format(seed, step, which), err)
		end
		M.RunFrames(2)
		invariants(("seed %d step %d action %d"):format(seed, step, which))
		if #failures - failuresBefore > 4 then break end
	end
	ns.Dialogs.HideAll()
	ns.Menu.Close()
	M.RunFrames(4)

	local label = ("seed %d survives %d steps"):format(seed, STEPS)
	check(label .. ": no error escaped",
		#M.errors == errorsBefore, M.errors[#M.errors])
	check(label .. ": nothing was logged",
		#soft == softBefore, soft[#soft])
	check(label .. ": the invariants held",
		#failures == failuresBefore, failures[#failures])
end

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
