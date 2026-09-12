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

-- SendWho is protected: the client allows it during a hardware event and blocks
-- it everywhere else, and a blocked call is not a silent no-op -- it puts an
-- ADDON_ACTION_BLOCKED warning in front of the player with this addon's name on
-- it. So nothing that is not a click may send one, and that is what this checks:
-- opening a thread, receiving a whisper, refreshing the window -- none of them.
M.whoSent = {}
M.now = M.now + 2000
CM.Select(nil)
M.RunFrames(4)
CM.Select(thrall)
M.RunFrames(8)
whisper("noch eine", "Thrall", "G-THRALL")
ns.UI.RefreshAll()
M.RunFrames(8)
eq("opening a thread sends no /who", #M.whoSent, 0)

check("but the addon knows one would help", PI.NeedsLookup(thrall) == true)

-- The click does send it. This is the only path that may.
M.whoSent = {}
check("asking for it sends one", PI.LookUp(thrall) == true)
eq("asked by name", M.whoSent[1], "n-Thrall")
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

-- Asked again straight away, it stands down rather than spamming the server.
M.whoSent = {}
check("nothing left to learn, so no second /who", PI.NeedsLookup(thrall) == false)
check("and the button does not fire one", PI.LookUp(thrall) == false)
eq("nothing was sent", #M.whoSent, 0)

-- Nothing came back, so they are not logged in.
CM.GetOrCreate("Jaina-Blackrock")
M.whoResults = {}
M.now = M.now + 100
check("a lookup for somebody else does go out",
	PI.LookUp("Jaina-Blackrock") == true)
M.FireEvent("WHO_LIST_UPDATE")
M.RunTimers(2)
eq("an empty /who means offline", PI.IsOnline("Jaina-Blackrock"), false)

-- Replacing results the player is reading is worse than a missing line.
_G.WhoFrame:Show()
M.whoSent = {}
M.now = M.now + 1000
check("nothing is sent while the Who window is open",
	PI.LookUp(ns.Compat.NormalizeName("Muradin")) == false)
eq("really nothing", #M.whoSent, 0)
_G.WhoFrame:Hide()

-- /who only ever searches your own realm, so asking about somebody else's is
-- a request that can never be answered.
M.whoSent = {}
check("no /who across realms", PI.LookUp("Thrall-Draenor") == false)
eq("and none sent", #M.whoSent, 0)

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

	-- And a whisper: the message cannot be stored, so the addon must stop
	-- taking whispers out of the chat frame rather than swallow them.
	ns.Debug.ClearDegraded()
	eq("not degraded to begin with", ns.Debug.IsDegraded(), false)
	local conversationsBefore = ns.ConversationManager.Count()
	M.FireEvent("CHAT_MSG_WHISPER", M.Secret(), "Arenagegner", "Common", "",
		"Arenagegner", "", 0, 0, "", 0, 1, "G-ARENA")
	M.RunTimers(2)
	eq("an unreadable whisper raises nothing", softErrors, 0)
	eq("and creates no half-empty thread",
		ns.ConversationManager.Count(), conversationsBefore)
	check("the chat frame gets its whispers back", ns.Debug.IsDegraded())
	check("and it was counted", ns.ChatEvents.UnreadableCount() > 0)
	ns.Debug.ClearDegraded()
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

eq("nothing errored", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
