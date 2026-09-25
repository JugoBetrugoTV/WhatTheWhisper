-- Who you are talking to: online state, and the profile line under the name.
--
-- The client has no "tell me about this name" lookup, so everything here is
-- assembled out of the few things it does say. What made the status dot almost
-- never appear was that the strongest evidence of all -- a message from
-- somebody -- was being thrown away, so only friends and guildmates ever had
-- one. And guild and zone were recorded from a /who and then never shown.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local CM, PI = ns.ConversationManager, ns.PlayerInfo
M.guids = {
	["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}
ns.db.profile.messages.openOnWhisper = false
ns.db.profile.messages.openOnCompose = false

local function whisper(text, sender, guid)
	M.FireEvent("CHAT_MSG_WHISPER", text, sender, "Common", "", sender, "", 0, 0, "", 0, 1, guid)
	M.RunTimers(2)
end

local thrall = ns.Compat.NormalizeName("Thrall")

--------------------------------------------------------------------------------
-- A message is presence
--------------------------------------------------------------------------------

eq("nothing known about a stranger", PI.IsOnline(thrall), nil)

whisper("hallo", "Thrall", "G-THRALL")
eq("somebody who just wrote is online", PI.IsOnline(thrall), true)

-- And the dot actually gets drawn, which is the part the player sees.
ns.UI.Show()
CM.Select(thrall)
M.RunFrames(8)
local avatar = ns.MainWindow.Get().view.header.avatar
check("the status dot is on screen", avatar.status:IsShown())

--------------------------------------------------------------------------------
-- ...but only for as long as it is still true
--------------------------------------------------------------------------------

-- A green dot that is really a guess about somebody who logged out an hour ago
-- is worse than no dot, so a one-off observation expires back to "unknown".
local realTime = _G.time
local clock = realTime()
_G.time = function() return clock end
PI.NoteActivity(thrall)
eq("fresh observation still counts", PI.IsOnline(thrall), true)
clock = clock + PI.PRESENCE_TTL + 1
eq("a stale one goes back to unknown", PI.IsOnline(thrall), nil)

-- The guild roster and the friends list push an event whenever somebody logs in
-- or out, so what they said stays true until they say otherwise.
PI.Set(thrall, { online = true, presenceSource = "guild" })
clock = clock + PI.PRESENCE_TTL * 10
eq("a live source does not expire", PI.IsOnline(thrall), true)
_G.time = realTime

--------------------------------------------------------------------------------
-- The server correcting us
--------------------------------------------------------------------------------

CM.GetOrCreate("Nobody-Blackrock")
CM.SendMessage("Nobody-Blackrock", "hallo?")
M.RunTimers(2)
M.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Nobody' is currently playing.")
M.RunTimers(2)
eq("no player named means offline", PI.IsOnline("Nobody-Blackrock"), false)

-- "X has come online" and "X has gone offline" are the only presence updates
-- that arrive unasked, and they are read out of the client's own format string
-- so they work in every locale.
M.FireEvent("CHAT_MSG_SYSTEM", "|Hplayer:Thrall|h[Thrall]|h has come online.")
M.RunTimers(2)
eq("coming online is noticed", PI.IsOnline(thrall), true)
M.FireEvent("CHAT_MSG_SYSTEM", "Thrall has gone offline.")
M.RunTimers(2)
eq("and so is going offline", PI.IsOnline(thrall), false)

-- Somebody the player has no thread with is none of our business.
M.FireEvent("CHAT_MSG_SYSTEM", "|Hplayer:Stranger|h[Stranger]|h has come online.")
M.RunTimers(2)
eq("a stranger is not cached", PI.IsOnline(ns.Compat.NormalizeName("Stranger")), nil)

--------------------------------------------------------------------------------
-- The profile line
--------------------------------------------------------------------------------

M.whoResults = {
	{ name = "Thrall", level = 70, class = "SHAMAN",
	  guild = "Wildhammer Clan", zone = "Orgrimmar" },
}

-- The addon never sends a /who itself. SendWho is restricted on every client and
-- blocked from addon code even inside a click -- the report was exactly that, an
-- ADDON_ACTION_BLOCKED from "Look up" -- so nothing may call it: not opening a
-- thread, not a whisper, not a refresh, not the Look up entry.
M.whoSent = {}
M.actionsBlocked = {}
M.now = M.now + 2000
CM.Select(nil)
M.RunFrames(4)
CM.Select(thrall)
M.RunFrames(8)
whisper("noch eine", "Thrall", "G-THRALL")
ns.UI.RefreshAll()
M.RunFrames(8)
ns.UI.ShowProfileLinks(thrall)
M.RunFrames(2)
ns.Dialogs.HideAll()
eq("nothing sends a /who", #M.whoSent, 0)
eq("and nothing was blocked", #M.actionsBlocked, 0)

-- But when the player types /who themselves, the answer is read.
M.FireEvent("WHO_LIST_UPDATE")
M.RunTimers(2)

local line = PI.StatusLine(thrall)
check("there is a status line", line ~= nil)
check("with the level", line:find("70", 1, true) ~= nil, line)
check("the class", line:find("Shaman", 1, true) ~= nil, line)
-- Recorded from a /who since the first release and never once displayed.
check("the guild", line:find("Wildhammer Clan", 1, true) ~= nil, line)
check("and the zone", line:find("Orgrimmar", 1, true) ~= nil, line)
eq("the /who says they are online", PI.IsOnline(thrall), true)

-- Only people the addon has a thread with: a /who for a whole zone is not a
-- reason to start keeping notes on everyone in it.
M.whoResults = {
	{ name = "Fremder", level = 12, class = "ROGUE", guild = "", zone = "Elwynn Forest" },
}
M.FireEvent("WHO_LIST_UPDATE")
M.RunTimers(2)
eq("a stranger in the results is not recorded", PI.Get(ns.Compat.NormalizeName("Fremder")), nil)
M.whoResults = {}

--------------------------------------------------------------------------------
-- The details panel
--------------------------------------------------------------------------------

-- The long form of the same facts. Its whole point is that a field the client
-- has never answered says so, instead of leaving a gap that reads as a bug.
CM.Select(thrall)
M.RunFrames(8)
local panel = ns.MainWindow.Get().view.profile
check("the details panel is open by default", panel:IsShown())

local function panelText()
	local out = {}
	for i = 1, #panel.rows do
		if panel.rows[i]:IsShown() then
			out[#out + 1] = (panel.rows[i].label:GetText() or "")
				.. "=" .. (panel.rows[i].value:GetText() or "")
		end
	end
	return table.concat(out, " | ")
end

local shown = panelText()
check("it names the class", shown:find("Shaman", 1, true) ~= nil, shown)
check("the level", shown:find("70", 1, true) ~= nil, shown)
check("the guild", shown:find("Wildhammer Clan", 1, true) ~= nil, shown)
check("the zone", shown:find("Orgrimmar", 1, true) ~= nil, shown)
-- The realm was the one thing the header only showed for cross-realm players,
-- and the one thing the report asked for by name.
check("and the realm", shown:find("Blackrock", 1, true) ~= nil, shown)

-- A thread with nothing known keeps every row and says which are blank, so the
-- player can see the addon knows the field exists.
CM.GetOrCreate("Unknownperson-Blackrock")
CM.Select("Unknownperson-Blackrock")
M.RunFrames(8)
local blank = panelText()
check("an unknown player still gets every row",
	select(2, blank:gsub("|", "")) >= 4, blank)
check("and the blanks say so", blank:find("not known", 1, true) ~= nil, blank)
check("with a way to fill them in", panel.lookup:IsShown())

-- The button gets a row of its own; tucked into whatever gap the last column
-- leaves, it lands on a value the moment the field list changes.
do
	local function box(f)
		local l, b, w, h = M.Geometry(f)
		return l, b, l + w, b + h
	end
	local bl, bb, br, bt = box(panel.lookup)
	local overlaps = 0
	for i = 1, #panel.rows do
		local row = panel.rows[i]
		if row:IsShown() then
			local rl, rb, rr, rt = box(row)
			if bl < rr and br > rl and bb < rt and bt > rb then
				overlaps = overlaps + 1
			end
		end
	end
	eq("the lookup button sits clear of every row", overlaps, 0)

	-- It is outlined rather than filled. A filled button rests on bg3, and the
	-- panel it sits on *is* bg3 -- so it was the same colour as its own
	-- background: a label in the corner with no button around it.
	check("and has an edge, so it looks like a button",
		(panel.lookup.surface.borderRole or nil) ~= nil,
		tostring(panel.lookup.surface.borderRole))
	-- And the panel is wide enough that the facts are not stacked in one column
	-- using a quarter of the window.
	local rowsShown = 0
	for i = 1, #panel.rows do
		if panel.rows[i]:IsShown() then rowsShown = rowsShown + 1 end
	end
	local tallest = 0
	for i = 1, #panel.rows do
		if panel.rows[i]:IsShown() then
			local _, b = M.Geometry(panel.rows[i])
			tallest = math.max(tallest, b)
		end
	end
	check("the facts are laid out in columns, not a stack",
		(panel:GetHeight() or 0) < rowsShown * 18 + 40,
		("%d rows in %.0fpx"):format(rowsShown, panel:GetHeight() or 0))
end

-- With the panel open the header must not repeat it: the same six facts one
-- line above the other is noise, so the header says the thing the panel cannot
-- -- whether they are there right now.
CM.Select(thrall)
M.RunFrames(8)
local headerLine = ns.MainWindow.Get().view.header.status:GetText() or ""
check("the header does not repeat the panel",
	headerLine:find("Wildhammer", 1, true) == nil, headerLine)
check("it says whether they are online instead",
	headerLine ~= "" and headerLine:lower():find("online") ~= nil, headerLine)

-- ...and with the panel closed it carries the long line again, because then it
-- is the only place those facts appear.
ns.Options.Set("layout.showProfile", false)
M.RunFrames(6)
headerLine = ns.MainWindow.Get().view.header.status:GetText() or ""
check("the closed panel hands the facts back to the header",
	headerLine:find("Wildhammer", 1, true) ~= nil, headerLine)
ns.Options.Set("layout.showProfile", true)
M.RunFrames(6)

-- Switching it off is a setting, not a local flag, so the checkbox and the
-- header button are the same switch.
ns.Options.Set("layout.showProfile", false)
M.RunFrames(6)
check("the setting closes the panel", not panel:IsShown())
ns.Options.Set("layout.showProfile", true)
M.RunFrames(6)
check("and opens it again", panel:IsShown())
CM.Select(thrall)
M.RunFrames(6)

--------------------------------------------------------------------------------
-- The sequence a real session actually produces
--------------------------------------------------------------------------------

-- Taken from an in-game screenshot: the player writes first, gets an away
-- message back, then real whispers. The away message is their client answering,
-- which proves they are online and carries the guid class and race come from --
-- and both were being dropped, so that thread had no status line and no race.
do
	M.guids["G-HEX"] = { class = "WARLOCK", race = "Undead",
		localizedRace = "Untoter", name = "Hexomeisto", realm = "Aegwynn" }
	local hex = ns.Compat.NormalizeName("Hexomeisto")

	CM.SendMessage(hex, ".")
	M.RunTimers(2)
	eq("nothing known from an outgoing message alone", PI.IsOnline(hex), nil)

	M.FireEvent("CHAT_MSG_AFK", "AFK", "Hexomeisto", "Common", "", "Hexomeisto",
		"", 0, 0, "", 0, 3, "G-HEX")
	M.RunTimers(2)
	eq("an away message proves they are online", PI.IsOnline(hex), true)
	local e = PI.Get(hex)
	eq("and carries their class", e and e.class, "WARLOCK")
	eq("and their race", e and e.race, "Undead")
	-- English keys the faction table; the localized name is what gets read.
	eq("kept in the player's own language for display", e and e.raceName, "Untoter")

	CM.Select(hex)
	M.RunFrames(8)
	local header = ns.MainWindow.Get().view.header
	check("so the header has a line under the name",
		(header.status:GetText() or "") ~= "", ("%q"):format(header.status:GetText() or ""))
end

-- The client answers with empty strings, not nils, for a guid it knows nothing
-- about. Passing those through turns "not told yet" into a value that a better
-- answer later can never replace.
do
	M.guids["G-BLANK"] = { class = "", race = "", name = "", realm = "" }
	local blank = ns.Compat.NormalizeName("Blankperson")
	CM.GetOrCreate(blank)
	PI.Observe(blank, "G-BLANK")
	local e = PI.Get(blank)
	eq("an empty class is not recorded as a class", e and e.class, nil)
	eq("nor an empty race as a race", e and e.race, nil)
end

--------------------------------------------------------------------------------
-- Payloads the client will not let us read
--------------------------------------------------------------------------------

-- In an arena the client delivers chat payloads as secret values instead of
-- strings. Reading one is a hard error that taints the caller, and the addon was
-- reading every one of them without asking: an arena filled the chat frame with
-- errors, and the whisper that triggered one was never handled, so no window
-- opened.
do
	local secret = M.Secret()
	eq("a secret payload is refused rather than read",
		ns.Compat.ReadableText(secret), nil)
	eq("an ordinary string still comes back",
		ns.Compat.ReadableText("hallo"), "hallo")
	eq("and nil stays nil", ns.Compat.ReadableText(nil), nil)

	-- The system messages that flooded the screen. Counted through SoftError,
	-- because that is where a handler's error actually lands: ns.Guard pcalls
	-- every event, so a raised error never reaches the mock's own list and
	-- asserting on that list would pass no matter what.
	local softErrors = 0
	local realSoftError = ns.SoftError
	ns.SoftError = function(context, err)
		softErrors = softErrors + 1
		return realSoftError(context, err)
	end

	for _ = 1, 20 do
		M.FireEvent("CHAT_MSG_SYSTEM", M.Secret())
		M.RunTimers(1)
	end
	eq("twenty of them raise nothing at all", softErrors, 0)

	-- And a whisper. It cannot be read now, but the chat line it arrived on can
	-- be asked about later, so it is put aside rather than lost -- and until it
	-- comes back the chat frame has to keep showing it, because that is the only
	-- copy the player has.
	ns.Debug.ClearDegraded()
	ns.Deferred.Clear()
	M.chatLockdown = true
	M.chatLines[4242] = { text = "gl hf", sender = "Arenagegner", guid = "G-ARENA" }

	local conversationsBefore = ns.ConversationManager.Count()
	local ARENA_WHISPER = { M.Secret(), M.Secret(), "Common", "", "Arenagegner",
		"", 0, 0, "", 0, 4242, 1, "G-ARENA" }
	check("the chat frame keeps a whisper the addon cannot read",
		M.ChatFrameWouldShow("CHAT_MSG_WHISPER", unpack(ARENA_WHISPER)))

	M.FireEvent("CHAT_MSG_WHISPER", unpack(ARENA_WHISPER))
	M.RunTimers(2)
	eq("an unreadable whisper raises nothing", softErrors, 0)
	eq("and creates no half-empty thread",
		ns.ConversationManager.Count(), conversationsBefore)
	eq("it is held instead of dropped", ns.Deferred.Count(), 1)
	check("and it was counted", ns.ChatEvents.UnreadableCount() > 0)

	-- Still in the arena: the client answers for nothing, so nothing moves.
	ns.Deferred.Flush()
	M.RunTimers(2)
	eq("nothing is released while chat is still withheld", ns.Deferred.Count(), 1)
	eq("and no thread appears early",
		ns.ConversationManager.Count(), conversationsBefore)

	-- The arena ends.
	M.chatLockdown = false
	M.RunTimers(4)
	eq("the held whisper is released once chat comes back", ns.Deferred.Count(), 0)
	eq("and now there is a thread",
		ns.ConversationManager.Count(), conversationsBefore + 1)
	local recovered = ns.ConversationManager.Get(
		ns.Compat.NormalizeName("Arenagegner"))
	check("with the message in it", recovered ~= nil
		and #recovered.messages == 1
		and recovered.messages[1][3] == "gl hf",
		recovered and #recovered.messages or "no thread")
	eq("no errors while releasing it", softErrors, 0)

	-- An ordinary whisper in the same session is still taken out of the chat
	-- frame: being in an arena once is not a reason to stop doing the job.
	check("and an ordinary whisper is still suppressed",
		not M.ChatFrameWouldShow("CHAT_MSG_WHISPER", "hallo", "Thrall", "Common",
			"", "Thrall", "", 0, 0, "", 0, 4243, 1, "G-THRALL"))

	ns.Deferred.Clear()
	M.chatLines[4242] = nil
	ns.Debug.ClearDegraded()
	ns.SoftError = realSoftError
end

--------------------------------------------------------------------------------
-- Units the client will not let us read either
--------------------------------------------------------------------------------

-- The payload is not the only thing an arena hides. The opponent you have
-- targeted has a secret *name*: UnitName hands back a secret value, and the
-- addon read it on every avatar it drew, looking for a live portrait. So one
-- whisper in an arena printed an error for each bus event that followed it --
-- conversation added, message added, conversation updated, conversation
-- selected, player info updated, and every keystroke in the search box.
do
	local softErrors = {}
	local realSoftError = ns.SoftError
	ns.SoftError = function(context, err)
		softErrors[#softErrors + 1] = tostring(context) .. ": " .. tostring(err)
		return realSoftError(context, err)
	end

	-- tostring on a secret value is itself a read. A failure message written the
	-- ordinary way would therefore blow up on its way to being printed, and the
	-- run would end with a traceback instead of the name of the broken check.
	local function describe(value)
		local ok, text = pcall(tostring, value)
		return ok and text or "<a value the client will not let us read>"
	end

	-- Targeted, visible, and unknowable: an arena opponent.
	M.units = M.units or {}
	M.units.target = { name = M.Secret(), realm = M.Secret(),
		class = "ROGUE", level = 70 }

	-- Called directly and through a pcall, because the whole failure is that it
	-- raises: without the pcall a regression aborts the file instead of naming
	-- itself, and the assertions below it never run at all.
	local scanned, found = pcall(ns.Compat.ClassFromVisibleUnit, thrall)
	check("a secret unit name is refused rather than read",
		scanned and found == nil, describe(found))

	-- Now the whole round the screenshot showed, with that unit targeted. The
	-- calls the addon would normally make from inside an event go through its
	-- own guard here for the same reason: a regression is then counted as the
	-- error flood it is, rather than aborting the file on the first one.
	local window = ns.MainWindow.Get()
	M.FireEvent("CHAT_MSG_WHISPER_INFORM", "so-bad", "Bonkarleif-Outland",
		"Common", "", "Bonkarleif-Outland", "", 0, 0, "", 0, 2, "G-BONK")
	M.RunTimers(2)
	M.RunFrames(8)
	ns.Guard("test.Select", CM.Select, "Bonkarleif-Outland")
	M.RunFrames(8)
	ns.Guard("test.SetFilter", window.sidebar.SetFilter, window.sidebar, "bon")
	M.RunFrames(4)
	ns.Guard("test.SetFilter", window.sidebar.SetFilter, window.sidebar, "")
	M.RunFrames(4)
	M.FireEvent("PLAYER_TARGET_CHANGED")
	ns.Bus.Fire(ns.EV.PLAYER_INFO_UPDATED, "Bonkarleif-Outland")
	M.RunFrames(8)

	eq("an arena target raises nothing at all", #softErrors, 0,
		table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))
	check("and the thread was still created",
		CM.Get("Bonkarleif-Outland") ~= nil)

	-- A name we *can* read still resolves, so the probe did not simply switch
	-- the feature off.
	M.units.target = { name = "Thrall", realm = "", class = "SHAMAN", level = 70 }
	eq("a readable unit still answers",
		ns.Compat.ClassFromVisibleUnit(thrall), "SHAMAN")

	-- Half a secret is still a secret: the realm alone is enough to throw.
	M.units.target = { name = "Thrall", realm = M.Secret(), class = "SHAMAN" }
	eq("a secret realm is refused too",
		ns.Compat.ClassFromVisibleUnit(thrall), nil)

	M.units.target = nil

	-- The GUID that rides along with a whisper is a payload like any other, and
	-- it goes straight into GetPlayerInfoByGUID, whose own answers the client
	-- can withhold field by field. Both were read without asking.
	local looked = { pcall(ns.Compat.GetPlayerInfoByGUID, M.Secret()) }
	check("a secret guid is refused rather than looked up",
		looked[1] and looked[2] == nil, describe(looked[2]))

	M.guids["G-HIDDEN"] = { class = M.Secret(), race = M.Secret(),
		name = M.Secret(), realm = M.Secret(), sex = M.Secret() }
	local ok, class, race, sex, name, realm =
		pcall(ns.Compat.GetPlayerInfoByGUID, "G-HIDDEN")
	check("a guid whose answers are secret raises nothing", ok, describe(class))
	if ok then
		-- Nothing invented, and -- just as important -- nothing passed on: a
		-- secret handed to a caller is only an error somewhere further away.
		check("and invents no class", class == nil, describe(class))
		check("nor a race", race == nil, describe(race))
		check("nor a sex", sex == nil, describe(sex))
		check("nor a name", name == nil, describe(name))
		check("nor a realm", realm == nil, describe(realm))
	end

	local before = CM.Count()
	M.FireEvent("CHAT_MSG_WHISPER", "hallo", "Arenafreund", "Common", "",
		"Arenafreund", "", 0, 0, "", 0, 1, M.Secret())
	M.RunTimers(2)
	M.RunFrames(4)
	eq("a whisper carrying a secret guid still lands", CM.Count(), before + 1)

	-- Every other reader that hands a client string outward, held to the same
	-- rule. None of these is restricted content today. Neither was a whisper,
	-- until it was, and finding that out the way the arena was found out costs
	-- an evening of screenshots.
	local function refuses(label, reader, fixture, hidden, readable, expected)
		fixture(hidden)
		local got = { pcall(reader, 1) }
		check(label .. " is refused when the client hides it",
			got[1] and got[2] == nil, describe(got[2]))
		fixture(readable)
		local fine = { pcall(reader, 1) }
		check(label .. " still answers when it does not",
			fine[1] and fine[2] == expected, describe(fine[2]))
		fixture(nil)
	end

	refuses("a friend's name", ns.Compat.GetFriendInfo,
		function(rows) M.friends = rows end,
		{ { name = M.Secret(), level = M.Secret(), class = M.Secret() } },
		{ { name = "Jaina-Blackrock", level = 70, class = "MAGE" } },
		"Jaina-Blackrock")

	refuses("a guildmate's name", ns.Compat.GetGuildRosterInfo,
		function(rows) M.guildRoster = rows end,
		{ { name = M.Secret(), level = M.Secret(), class = M.Secret() } },
		{ { name = "Muradin-Blackrock", level = 70, class = "WARRIOR" } },
		"Muradin-Blackrock")

	refuses("a /who result", ns.Compat.GetWhoInfo,
		function(rows) M.whoResults = rows end,
		{ { name = M.Secret(), level = M.Secret(), class = M.Secret(),
			guild = M.Secret(), zone = M.Secret() } },
		{ { name = "Thrall-Blackrock", level = 70, class = "SHAMAN",
			guild = "Frostwolf", zone = "Orgrimmar" } },
		"Thrall-Blackrock")

	-- Battle.net is keyed by account id rather than an index, so it gets the
	-- same treatment by hand.
	M.bnet = M.bnet or {}
	M.bnet[99] = { tag = M.Secret(), name = M.Secret(), character = M.Secret() }
	local okBN, tag, account, online, character =
		pcall(ns.Compat.GetBNAccountInfoByID, 99)
	check("a hidden Battle.net account raises nothing", okBN, describe(tag))
	if okBN then
		check("and invents no BattleTag", tag == nil, describe(tag))
		check("nor an account name", account == nil, describe(account))
		check("nor a character", character == nil, describe(character))
		check("and online is still a boolean", online == true or online == false,
			describe(online))
	end
	M.bnet[99] = nil

	eq("and none of that raised anything either", #softErrors, 0,
		table.concat(softErrors, "; ", 1, math.min(#softErrors, 4)))

	ns.Guard("test.Select", CM.Select, thrall)
	M.RunFrames(4)
	ns.SoftError = realSoftError
end

--------------------------------------------------------------------------------
-- Battle.net
--------------------------------------------------------------------------------

-- The client answers presence directly for Battle.net, and that answer was
-- being skipped: those threads never had a dot at all.
M.bnet = { [42] = { tag = "Somebody#1234", name = "Somebody", character = "Alt" } }
eq("Battle.net presence comes from the client",
	ns.Compat.IsBNOnline(42), true)
eq("and nil for an account it does not know", ns.Compat.IsBNOnline(999), nil)

local bn = CM.GetOrCreate("BN:Somebody#1234", { name = "Somebody" })
bn.isBN = true
bn.bnetAccountID = 42
CM.Select(bn.id)
M.RunFrames(8)
check("a Battle.net thread has a status dot too", avatar.status:IsShown())
eq("and no invented level or class line", PI.StatusLine(bn.id, true), nil)

--------------------------------------------------------------------------------
-- A roster update that changes nothing
--------------------------------------------------------------------------------

-- In a large guild GUILD_ROSTER_UPDATE arrives every few seconds -- any addon
-- asking for the roster is enough -- and every scan was announced, which
-- redrew the sidebar, the header and the details panel whether or not anybody
-- in them had changed.
do
	local key = "Muradin-Blackrock"
	CM.GetOrCreate(key)
	PI.Set(key, { class = "WARRIOR" })
	local announced = 0
	ns.Bus.Register(ns.EV.PLAYER_INFO_UPDATED, "test.roster", function() announced = announced + 1 end)
	M.guildRoster = { { name = key, level = 70, class = "WARRIOR", online = true } }
	M.FireEvent("GUILD_ROSTER_UPDATE")
	eq("a roster that says something new is announced", announced, 1)
	eq("and the guildmate reads as online", PI.IsOnline(key), true)
	for _ = 1, 5 do M.FireEvent("GUILD_ROSTER_UPDATE") end
	eq("the same roster again is not", announced, 1)
	M.guildRoster[1].online = false
	M.FireEvent("GUILD_ROSTER_UPDATE")
	eq("a guildmate logging off is", announced, 2)
	eq("and reads as offline", PI.IsOnline(key), false)
	M.guildRoster[1].level = 71
	M.FireEvent("GUILD_ROSTER_UPDATE")
	eq("so is a level", announced, 3)
	ns.Bus.Unregister(ns.EV.PLAYER_INFO_UPDATED, "test.roster")
	M.guildRoster = nil
end

--------------------------------------------------------------------------------

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
