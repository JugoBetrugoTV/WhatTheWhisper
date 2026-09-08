-- UI audit: measures what the addon actually builds.
--
-- Every check here reads geometry and colour off the constructed frames rather
-- than off the source, because the gap between "the code says 16" and "the pixel
-- is at 16" is exactly where layout bugs live. Four things are checked:
--
--   * containment  -- nothing sticks out of its parent, nothing lands off screen
--   * alignment    -- shared edges line up, and coordinates land on whole pixels
--   * targets      -- anything clickable is big enough to click
--   * contrast     -- every text colour is legible on the surface behind it
--
-- Run at three UI scales and across every skin, because a value that happens to
-- be integral at scale 1.0 usually is not at 0.64.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local failed = {}
local function check(label, ok, detail)
	if ok then pass = pass + 1 else
		fail = fail + 1
		if not failed[label] then
			failed[label] = true
			print("FAIL " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
		end
	end
end
local function eq(label, got, want)
	check(label, got == want, ("got %s, want %s"):format(tostring(got), tostring(want)))
end

-- Libraries and addon files both come from the shipped manifests, so these
-- tests load exactly what a player who unzipped only WhatTheWhisper/ gets.
local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")

local CM = ns.ConversationManager
local guid = "G-THRALL"
M.guids = {
	[guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
}

--------------------------------------------------------------------------------
-- Build a populated interface to measure
--------------------------------------------------------------------------------

local function whisper(text, from, sender)
	M.FireEvent("CHAT_MSG_WHISPER", text, from, "Common", "", from, "", 0, 0, "", 0, 1, sender)
end

whisper("hey", "Thrall", guid)
whisper("Are you around for the raid tonight? We are short two healers.", "Thrall", guid)
whisper("kurz", "Jaina", "G-JAINA")
whisper("https://example.com/a/very/long/path/that/keeps/going and some words after it",
	"Jaina", "G-JAINA")
whisper("Übergrößenträger Straße ünnötig", "Thrall", guid)

ns.UI.Show()
local thrall = ns.Compat.NormalizeName("Thrall")
CM.Select(thrall)
CM.SendMessage(thrall, "on my way")
CM.SendMessage(thrall, "this one is a good deal longer, long enough to wrap onto a "
	.. "second line inside the bubble so the padding is measured on a multi-line body")
M.RunFrames(20)

local window = ns.MainWindow.Get()

--------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------

local function rect(f)
	local l, b, w, h = M.Geometry(f)
	return l, b, w, h, l + w, b + h
end

local function describe(node)
	local trail, hops = {}, 0
	local up = node
	while up and hops < 6 do
		trail[#trail + 1] = (up._name or up._wtwTag or up._kind or "?")
		up = up._parent
		hops = hops + 1
	end
	return ("%s[%s] text=%q at %.2f,%.2f %.2fx%.2f"):format(
		node._kind or "?", table.concat(trail, "<"), tostring(node._text or ""),
		select(1, rect(node)), select(2, rect(node)),
		select(3, rect(node)), select(4, rect(node)))
end

-- Nodes worth auditing: shown, sized, and actually under the window.
local function auditable(root)
	local out = {}
	local nodes = M.Descendants(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if M.EffectivelyShown(node, root) then
			local _, _, w, h = rect(node)
			if w > 1 and h > 1 then out[#out + 1] = node end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Containment: nothing may spill out of the window
--------------------------------------------------------------------------------

-- Shadows and glows are drawn deliberately outside their frame, and scroll
-- viewports hold content taller than themselves. Both are legitimate.
local function allowedOverflow(node)
	-- Checked before anything else: inside a scroll viewport the client clips,
	-- so content taller than the window is the mechanism working rather than
	-- something spilling out.
	local parent = node._parent
	while parent do
		if parent.__wtwViewport then return math.huge end
		parent = parent._parent
	end
	-- Shadows and glows are drawn deliberately outside the frame they belong to.
	if node._kind ~= "Frame" and node._layer == "BACKGROUND" then return 40 end
	return 2
end

local function checkContainment(label, root)
	local rl, rb, rw, rh = rect(root)
	local rr, rt = rl + rw, rb + rh
	local worst, worstNode = 0, nil
	local nodes = auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		local l, b, w, h = rect(node)
		local slack = allowedOverflow(node)
		if slack ~= math.huge then
			local over = math.max(rl - l, rb - b, (l + w) - rr, (b + h) - rt) - slack
			if over > worst then worst, worstNode = over, node end
		end
	end
	check(label .. ": nothing spills out of the window", worst <= 0,
		worstNode and (describe(worstNode) .. " overflows by " .. ("%.2f"):format(worst)
			.. " (window " .. ("%.0f,%.0f %.0fx%.0f"):format(rl, rb, rw, rh) .. ")"))
end

checkContainment("main window", window)

--------------------------------------------------------------------------------
-- On screen: the window must never open where it cannot be grabbed
--------------------------------------------------------------------------------

local screenW, screenH = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
local wl, wb, ww, wh = rect(window)
check("the window opens on screen horizontally", wl < screenW and wl + ww > 0,
	("left %.0f width %.0f screen %.0f"):format(wl, ww, screenW))
check("the window opens on screen vertically", wb < screenH and wb + wh > 0,
	("bottom %.0f height %.0f screen %.0f"):format(wb, wh, screenH))
check("the title bar is reachable", wb + wh <= screenH + 1 and wb + wh > 0,
	("top %.0f screen %.0f"):format(wb + wh, screenH))

--------------------------------------------------------------------------------
-- Alignment: shared edges must actually be shared
--------------------------------------------------------------------------------

local EPS = 0.51

local function alignsX(label, a, b, edge)
	local av = edge == "left" and select(1, rect(a)) or select(5, rect(a))
	local bv = edge == "left" and select(1, rect(b)) or select(5, rect(b))
	check(label, math.abs(av - bv) < EPS, ("%.3f vs %.3f"):format(av, bv))
end

local sidebar, view = window.sidebar, window.view

alignsX("the sidebar and the header start at the same left edge",
	sidebar, window.titlebar, "left")
check("the conversation view begins exactly where the sidebar ends",
	math.abs(select(5, rect(sidebar)) - select(1, rect(view))) < EPS,
	("sidebar right %.3f, view left %.3f"):format(select(5, rect(sidebar)), select(1, rect(view))))
check("the view reaches the right edge of the window",
	math.abs(select(5, rect(view)) - select(5, rect(window))) < EPS)

local composer, list = view.composer, view.list
check("the composer sits at the bottom of the view",
	math.abs(select(2, rect(composer)) - select(2, rect(view))) < EPS)
check("the message list ends where the composer begins",
	select(2, rect(list)) >= select(6, rect(composer)) - EPS,
	("list bottom %.3f, composer top %.3f"):format(
		select(2, rect(list)), select(6, rect(composer))))
check("the list and the composer share a left edge",
	math.abs(select(1, rect(list)) - select(1, rect(view))) < EPS)

--------------------------------------------------------------------------------
-- Hit targets
--------------------------------------------------------------------------------

-- 20px at scale 1.0 is roughly a 5mm target on a 1080p 24" display. Anything
-- smaller is a coin toss with a mouse.
--
-- A drag strip is the exception, and a real one rather than a loophole: a
-- splitter or a scrollbar is aimed at along one axis only, so it needs height
-- but not width. Those get a 10px minor axis, which is what desktop toolkits
-- use, and only when the major axis is long enough to aim at.
local MIN_TARGET = 20
local MIN_STRIP_MINOR = 10
local MIN_STRIP_MAJOR = 100

local function targetIsBigEnough(w, h)
	if w >= MIN_TARGET and h >= MIN_TARGET then return true end
	local minor, major = math.min(w, h), math.max(w, h)
	return minor >= MIN_STRIP_MINOR and major >= MIN_STRIP_MAJOR
end

local function checkTargets(label, root)
	local small, sample = 0, nil
	local nodes = auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if node._kind == "Frame" and node._mouseEnabled then
			local _, _, w, h = rect(node)
			local hl, hr, ht, hb = node._hitLeft or 0, node._hitRight or 0,
				node._hitTop or 0, node._hitBottom or 0
			-- Negative hit-rect insets shrink; positive ones (WoW's convention
			-- for SetHitRectInsets is inward) are what the addon uses to grow a
			-- thin control's clickable area, stored negative.
			local tw, th = w - hl - hr, h - ht - hb
			if not targetIsBigEnough(tw, th) then
				small = small + 1
				sample = sample or (describe(node) .. (" target %.1fx%.1f"):format(tw, th))
			end
		end
	end
	check(label, small == 0, sample)
end

checkTargets("every clickable element is big enough to hit", window)

--------------------------------------------------------------------------------
-- The 1-2px pass: baselines, optical centring, markers inside their cards
--------------------------------------------------------------------------------

-- A row's name and its timestamp are different sizes. Anchored by their tops
-- they would sit on different baselines by a couple of pixels, which is exactly
-- the kind of thing that reads as "off" without anyone being able to say why.
local function baselineOf(fs, reference)
	local size = ns.Theme.FontSize(fs.__wtwToken) or 12
	local top = select(6, rect(fs))
	-- The drawn baseline sits one ascent below the top of the box.
	return top - size * 0.78, size, reference
end

local rows = {}
for row in sidebar.rowPool:EnumerateActive() do rows[#rows + 1] = row end
check("the sidebar built rows to measure", #rows > 0)

for i = 1, math.min(#rows, 3) do
	local row = rows[i]
	if row.name and row.time and row.time:IsShown() then
		local nameBase = baselineOf(row.name)
		local timeBase = baselineOf(row.time)
		check("row " .. i .. ": the name and its timestamp share a baseline",
			math.abs(nameBase - timeBase) <= 1.0,
			("name baseline %.2f, timestamp baseline %.2f"):format(nameBase, timeBase))
	end
	-- The selected marker belongs inside the row's card, not in the gutter
	-- beside it, or it reads as the window border rather than as this row.
	if row.accent then
		local cardLeft = select(1, rect(row)) + ns.S.SM
		local accentLeft = select(1, rect(row.accent))
		check("row " .. i .. ": the selected marker sits inside the card",
			accentLeft >= cardLeft - 0.51,
			("marker at %.2f, card edge at %.2f"):format(accentLeft, cardLeft))
	end
	-- Left edges of the stacked text must agree exactly; a one pixel step
	-- between a name and the preview under it is visible as a ragged column.
	if row.name and row.preview then
		check("row " .. i .. ": the name and preview share a left edge",
			math.abs(select(1, rect(row.name)) - select(1, rect(row.preview))) < EPS)
	end
end

-- Every row in the list must use the same margins: one row indented differently
-- from its neighbours is the most visible layout bug there is.
if #rows > 1 then
	local lefts, rights = {}, {}
	for i = 1, #rows do
		lefts[i] = select(1, rect(rows[i])) 
		rights[i] = select(5, rect(rows[i]))
	end
	local sameLeft, sameRight = true, true
	for i = 2, #rows do
		if math.abs(lefts[i] - lefts[1]) > EPS then sameLeft = false end
		if math.abs(rights[i] - rights[1]) > EPS then sameRight = false end
	end
	check("every sidebar row starts at the same left edge", sameLeft)
	check("every sidebar row ends at the same right edge", sameRight)
end

-- Icons must sit optically centred in the buttons that hold them, or a row of
-- title bar controls looks like it was assembled by hand.
local function checkIconCentring(label, root)
	local offenders, sample = 0, nil
	local nodes = auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if node._kind == "Frame" and node._mouseEnabled then
			local kids = M.Descendants(node)
			for k = 1, #kids do
				local kid = kids[k]
				-- __wtwIcon is the marker W.Icon puts on a glyph. Without it this
				-- would also pick up the quads and bands the rounded-rectangle
				-- surface is assembled from, which tile the button on purpose.
				if kid.__wtwIcon and M.EffectivelyShown(kid, node) then
					local bl, bb, bw, bh = rect(node)
					local il, ib, iw, ih = rect(kid)
					-- Only icon buttons: a frame not much bigger than the glyph
					-- it holds. A sidebar row also contains textures, but a pin
					-- badge in its corner is not meant to be centred in the row.
					local isIconButton = bw <= iw * 2.5 and bh <= ih * 2.5
					if iw > 4 and ih > 4 and iw <= bw and ih <= bh and isIconButton then
						local dx = (il + iw / 2) - (bl + bw / 2)
						local dy = (ib + ih / 2) - (bb + bh / 2)
						if math.abs(dx) > 1.0 or math.abs(dy) > 1.0 then
							offenders = offenders + 1
							sample = sample or (describe(kid)
								.. (" off centre by %.2f,%.2f in its button"):format(dx, dy))
						end
					end
				end
			end
		end
	end
	check(label, offenders == 0, sample)
end

checkIconCentring("icons are centred in their buttons", window)

--------------------------------------------------------------------------------
-- Bubbles: padding, alignment and the rhythm they share with the composer
--------------------------------------------------------------------------------

local bubbles = {}
for bubble in view.list.bubblePool:EnumerateActive() do
	if M.EffectivelyShown(bubble, window) then bubbles[#bubbles + 1] = bubble end
end
check("the thread rendered bubbles to measure", #bubbles >= 4, tostring(#bubbles))

local incoming, outgoing = {}, {}
for i = 1, #bubbles do
	local b = bubbles[i]
	local bl, _, bw = rect(b)
	local tl = select(1, rect(b.text))
	-- Text inset from the bubble's own edges, both sides.
	check("a bubble pads its text on the left by the named amount",
		math.abs((tl - bl) - ns.SZ.BUBBLE_PAD_X) < EPS,
		("%.2f, want %d"):format(tl - bl, ns.SZ.BUBBLE_PAD_X))
	local rightPad = (bl + bw) - select(5, rect(b.text))
	check("a bubble pads its text on the right by the same amount",
		math.abs(rightPad - ns.SZ.BUBBLE_PAD_X) < 1.01,
		("%.2f vs %.2f on the left"):format(rightPad, tl - bl))
	check("a bubble is never wider than the cap",
		bw <= ns.SZ.BUBBLE_MAX_ABS + EPS, ("%.1f"):format(bw))

	if b.msg and b.msg[ns.MSG_DIR] == ns.DIR_OUT then
		outgoing[#outgoing + 1] = b
	else
		incoming[#incoming + 1] = b
	end
end

-- One column each side. A bubble that starts a pixel off from the one above it
-- is the single most visible defect a chat client can have.
local function sharedEdge(list, label, pick)
	if #list < 2 then return end
	local first = pick(list[1])
	local same = true
	local worst
	for i = 2, #list do
		local v = pick(list[i])
		if math.abs(v - first) > EPS then
			same = false
			worst = worst or ("%.2f vs %.2f"):format(v, first)
		end
	end
	check(label, same, worst)
end

sharedEdge(incoming, "every incoming bubble starts on the same left edge",
	function(b) return (select(1, rect(b))) end)
sharedEdge(outgoing, "every outgoing bubble ends on the same right edge",
	function(b) return (select(5, rect(b))) end)

-- The thread and the composer under it are one column. The field itself is
-- inset by the two buttons flanking it, so what has to line up is the row: the
-- emoji button with the avatar column, and the send button with the right edge
-- of the outgoing bubbles.
if composer.emoji and #incoming > 0 then
	local avatar = incoming[1].avatar
	if avatar and M.EffectivelyShown(avatar, window) then
		check("the emoji button sits on the avatar column",
			math.abs(select(1, rect(composer.emoji)) - select(1, rect(avatar))) <= 2.01,
			("emoji at %.2f, avatar at %.2f"):format(
				select(1, rect(composer.emoji)), select(1, rect(avatar))))
	end
end
if composer.send and #outgoing > 0 then
	check("the send button ends on the outgoing bubbles' right edge",
		math.abs(select(5, rect(composer.send)) - select(5, rect(outgoing[1]))) <= 2.01,
		("send ends %.2f, bubble ends %.2f"):format(
			select(5, rect(composer.send)), select(5, rect(outgoing[1]))))
end

-- Delivery ticks sit against their bubble at one consistent distance. A mark
-- floating at a different gap on each message reads as debris rather than as
-- status.
local gaps = {}
for i = 1, #outgoing do
	local b = outgoing[i]
	if b.status and M.EffectivelyShown(b.status, window) then
		gaps[#gaps + 1] = {
			gap = select(1, rect(b)) - select(5, rect(b.status)),
			bottom = select(2, rect(b.status)) - select(2, rect(b)),
		}
	end
end
if #gaps > 1 then
	local sameGap, sameBottom = true, true
	for i = 2, #gaps do
		if math.abs(gaps[i].gap - gaps[1].gap) > EPS then sameGap = false end
		if math.abs(gaps[i].bottom - gaps[1].bottom) > EPS then sameBottom = false end
	end
	check("every delivery tick sits the same distance from its bubble", sameGap,
		("%.2f vs %.2f"):format(gaps[#gaps].gap, gaps[1].gap))
	check("and at the same height within it", sameBottom,
		("%.2f vs %.2f"):format(gaps[#gaps].bottom, gaps[1].bottom))
	check("the tick is close enough to read as attached",
		gaps[1].gap >= 0 and gaps[1].gap <= ns.S.MD,
		("%.2f away"):format(gaps[1].gap))
end

-- Group headers carry a time and nothing else, on the side their group sits on.
local headers = {}
for header in view.list.headerPool:EnumerateActive() do
	if M.EffectivelyShown(header, window) then headers[#headers + 1] = header end
end
check("the thread rendered group headers", #headers > 0)
for i = 1, #headers do
	local header = headers[i]
	check("a group header carries no repeated sender name",
		header.name == nil,
		"the name font string is back; a 1:1 thread should not repeat it")
	check("a group header does show a time",
		header.time ~= nil and (header.time._text or "") ~= "")
end

--------------------------------------------------------------------------------
-- Animation timing: one vocabulary, not a duration per call site
--------------------------------------------------------------------------------

local durations = {}
for _, token in ipairs({ "FAST", "BASE", "SLOW", "WINDOW" }) do
	local d = ns.Theme.Duration(token)
	if d then durations[#durations + 1] = { token = token, value = d } end
end
check("the motion scale is defined", #durations >= 3)
for i = 1, #durations do
	local d = durations[i]
	check(("%s is a plausible duration"):format(d.token),
		d.value >= 0 and d.value <= 0.6,
		tostring(d.value) .. "s")
	if i > 1 then
		check(("%s is longer than %s"):format(d.token, durations[i - 1].token),
			d.value >= durations[i - 1].value,
			("%s=%.3f vs %s=%.3f"):format(d.token, d.value,
				durations[i - 1].token, durations[i - 1].value))
	end
end

--------------------------------------------------------------------------------
-- Pixel quality: even heights, centred text, no half-pixel edges
--------------------------------------------------------------------------------

-- Rows in one list must all be the same height. One row a pixel taller than
-- its neighbours is the most visible kind of sloppiness there is.
if #rows > 1 then
	local heights = {}
	for i = 1, #rows do heights[i] = select(4, rect(rows[i])) end
	local uneven, worst = 0, nil
	for i = 2, #heights do
		if math.abs(heights[i] - heights[1]) > EPS then
			uneven = uneven + 1
			worst = worst or ("%.2f vs %.2f"):format(heights[i], heights[1])
		end
	end
	check("every sidebar row is the same height", uneven == 0, worst)
end

-- Text that is meant to sit in the middle of a control has to actually sit
-- there. A label a pixel or two high in its row reads as misaligned even when
-- nobody can say why.
-- A label stacked with another one -- a name with a status line under it -- is
-- deliberately off its container's middle, because it is the top half of a block
-- that is centred as a pair. Detected from the anchors rather than from a marker
-- the addon would have to carry for the tests' benefit.
local function stackedLabels(root)
	local stacked, nodes = {}, auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		for _, point in ipairs(node._points or {}) do
			local target = point[2]
			if target and target._kind == "FontString" and node._kind == "FontString" then
				stacked[node] = true
				stacked[target] = true
			end
		end
	end
	return stacked
end

local function checkVerticalCentring(label, root)
	local off, sample, inspected = 0, nil, 0
	local nodes = auditable(root)
	local stacked = stackedLabels(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if node._kind == "FontString" and (node._text or "") ~= ""
			and not stacked[node]
			and node._justifyV == "MIDDLE" then
			local parent = node._parent
			if parent and M.EffectivelyShown(parent, root) then
				local _, pb, _, ph = rect(parent)
				local _, nb, _, nh = rect(node)
				-- Only judge a label that is meant to fill its parent's height.
				if ph > nh and ph < nh * 4 then
					inspected = inspected + 1
					local drift = ((nb + nh / 2) - (pb + ph / 2))
					if math.abs(drift) > 1.01 then
						off = off + 1
						sample = sample or (describe(node)
							.. (" sits %.2f off its container's middle"):format(drift))
					end
				end
			end
		end
	end
	check(label, off == 0, sample)
	return inspected
end

local centred = checkVerticalCentring("centred text really is centred", window)
check("centred text was actually inspected", centred > 4,
	("only %d labels considered; this check has stopped covering anything"):format(centred))

-- Every edge the addon positions itself must land on a whole pixel at the
-- current scale. A border on a half pixel is drawn across two rows of pixels
-- at half strength each, which is what "blurry 1px border" means.
do
	local px = ns.Pixel.Size(_G.UIParent)
	local blurry, sample = 0, nil
	local nodes = auditable(window)
	for i = 1, #nodes do
		local node = nodes[i]
		if node.__wtwHairline then
			local l, b, w, h = rect(node)
			for _, edge in ipairs({ l, b, l + w, b + h }) do
				local inPixels = edge / px
				if math.abs(inPixels - math.floor(inPixels + 0.5)) > 0.02 then
					blurry = blurry + 1
					sample = sample or (describe(node)
						.. (" has an edge at %.4f, which is %.3f pixels"):format(edge, inPixels))
					break
				end
			end
		end
	end
	check("no hairline lands on a fractional pixel", blurry == 0, sample)
end

--------------------------------------------------------------------------------
-- Truncation: constrained text must be ellipsized, never drawn past its box
--------------------------------------------------------------------------------

-- A font string given an explicit width or anchored on both sides has agreed to
-- fit. If its natural text is wider than that box the client clips it, so the
-- addon has to shorten the string itself -- which is what Text.Ellipsize is for.
local function checkTruncation(label, root)
	local overflowing, sample = 0, nil
	local nodes = auditable(root)
	for i = 1, #nodes do
		local node = nodes[i]
		if node._kind == "FontString" and (node._text or "") ~= "" then
			local points = node._points or {}
			local bounded = node._w ~= nil
			local hasLeft, hasRight = false, false
			for p = 1, #points do
				local anchor = points[p][1]
				if anchor:find("LEFT") or anchor == "LEFT" then hasLeft = true end
				if anchor:find("RIGHT") or anchor == "RIGHT" then hasRight = true end
			end
			if bounded or (hasLeft and hasRight) then
				local box = select(3, rect(node))
				local natural = node:GetStringWidth()
				-- Word wrap is a legitimate answer to not fitting on one line.
				if node._wordWrap == false and natural > box + 1 then
					overflowing = overflowing + 1
					sample = sample or (describe(node)
						.. (" needs %.1f but has %.1f"):format(natural, box))
				end
			end
		end
	end
	check(label, overflowing == 0, sample)
end

checkTruncation("no single-line text is drawn wider than its box", window)

--------------------------------------------------------------------------------
-- Scrollbar: the track lives in its gutter, never over the content
--------------------------------------------------------------------------------

local scroll = view.list
if scroll and scroll.track then
	local trackLeft, _, trackW = rect(scroll.track)
	local trackRight = trackLeft + trackW
	check("the scrollbar track sits at the right edge of the list",
		math.abs(trackRight - select(5, rect(scroll))) <= ns.S.SM + EPS,
		("track ends %.2f, list ends %.2f"):format(trackRight, select(5, rect(scroll))))
	check("the scrollbar track is the full grab width",
		math.abs(trackW - ns.SZ.SCROLLBAR_HIT) < EPS,
		("%.2f, want %d"):format(trackW, ns.SZ.SCROLLBAR_HIT))
	if #outgoing > 0 then
		-- The gutter is reserved: no bubble may run under the scrollbar.
		check("no bubble reaches into the scrollbar gutter",
			select(5, rect(outgoing[1])) <= trackLeft + EPS,
			("bubble ends %.2f, gutter starts %.2f"):format(
				select(5, rect(outgoing[1])), trackLeft))
	end
	if scroll.thumb then
		local thumbLeft, _, thumbW = rect(scroll.thumb)
		check("the scrollbar thumb is centred in its track",
			math.abs((thumbLeft + thumbW / 2) - (trackLeft + trackW / 2)) < EPS,
			("thumb centre %.2f, track centre %.2f"):format(
				thumbLeft + thumbW / 2, trackLeft + trackW / 2))
	end
end

--------------------------------------------------------------------------------
-- Hover hitboxes must match what they highlight
--------------------------------------------------------------------------------

-- A row that accepts the mouse outside its own bounds steals hovers from its
-- neighbour, and the highlight then appears under the wrong row.
if #rows > 1 then
	local overlapping, sample = 0, nil
	for i = 1, #rows - 1 do
		local aBottom, aTop = select(2, rect(rows[i])), select(6, rect(rows[i]))
		local bBottom, bTop = select(2, rect(rows[i + 1])), select(6, rect(rows[i + 1]))
		-- Rows are stacked; whichever is above, their spans must not overlap.
		local overlap = math.min(aTop, bTop) - math.max(aBottom, bBottom)
		if overlap > EPS then
			overlapping = overlapping + 1
			sample = sample or ("rows %d and %d overlap by %.2f"):format(i, i + 1, overlap)
		end
	end
	check("no two sidebar rows overlap each other's hover area",
		overlapping == 0, sample)
end

--------------------------------------------------------------------------------
-- Seams: a hairline divider is exactly one hairline
--------------------------------------------------------------------------------

-- Two panels that each draw their own border at the same boundary produce a
-- two-pixel seam that reads as a mistake. Every hairline the addon draws is one
-- physical pixel; anything thicker at the same place is a doubled border.
do
	local px = ns.Pixel.Size(_G.UIParent)
	local hairlines = {}
	-- Straight off the descendant list rather than through `auditable`: that
	-- filter drops anything under a pixel tall, which is every hairline.
	local nodes = M.Descendants(window)
	for i = 1, #nodes do
		local node = nodes[i]
		if node.__wtwHairline and M.EffectivelyShown(node, window) then
			local _, _, w, h = rect(node)
			local thickness = math.min(w, h)
			hairlines[#hairlines + 1] = { node = node, thickness = thickness }
		end
	end
	local thick, sample = 0, nil
	for i = 1, #hairlines do
		local entry = hairlines[i]
		if entry.thickness > px * 1.51 then
			thick = thick + 1
			sample = sample or (describe(entry.node)
				.. (" is %.3f thick, one pixel is %.3f"):format(entry.thickness, px))
		end
	end
	check("every hairline is one physical pixel", thick == 0, sample)
	check("the window draws hairline dividers at all", #hairlines > 0)
end

--------------------------------------------------------------------------------
-- Closing a window must take everything it owns with it
--------------------------------------------------------------------------------

-- A drop shadow cannot be a child of the window it belongs to, because a child
-- cannot draw behind its parent's own background. That makes it a sibling, and
-- a sibling is not hidden when the window is -- which left a dark rectangle
-- sitting on the world after every close until it was fixed. Anything else
-- anchored to a window from outside it has the same hazard, so the test is
-- about the general shape rather than about shadows.
local function framesAnchoredTo(target)
	local out = {}
	for i = 1, #M.frames do
		local frame = M.frames[i]
		if frame ~= target and frame._parent ~= target then
			for p = 1, #(frame._points or {}) do
				if frame._points[p][2] == target then
					out[#out + 1] = frame
					break
				end
			end
		end
	end
	return out
end

do
	local attached = framesAnchoredTo(window)
	check("something outside the window is anchored to it", #attached > 0,
		"nothing found; this check has stopped covering anything")

	ns.UI.Hide()
	M.RunFrames(20)
	local ghosts, sample = 0, nil
	for i = 1, #attached do
		if attached[i]:IsShown() then
			ghosts = ghosts + 1
			sample = sample or describe(attached[i])
		end
	end
	check("nothing anchored to the window is left on screen after closing it",
		ghosts == 0, sample)

	ns.UI.Show()
	M.RunFrames(20)
	local restored = 0
	for i = 1, #attached do
		if attached[i]:IsShown() then restored = restored + 1 end
	end
	check("and it comes back when the window reopens", restored == #attached,
		("%d of %d returned"):format(restored, #attached))
end

-- The same for a popout, which is created and destroyed far more often.
do
	ns.UI.TogglePopout(thrall)
	M.RunFrames(20)
	local popoutWindow = ns.Popout.Get(thrall)
	if popoutWindow then
		local attached = framesAnchoredTo(popoutWindow)
		ns.UI.DockConversation(thrall)
		M.RunFrames(20)
		-- "Left on screen" means effectively visible: a child of the window
		-- that closed still reports IsShown, it is simply not drawn any more.
		local ghosts = 0
		for i = 1, #attached do
			if M.EffectivelyVisible(attached[i]) then ghosts = ghosts + 1 end
		end
		check("docking a popout leaves nothing of it on screen", ghosts == 0,
			("%d of %d still shown"):format(ghosts, #attached))
	end
end

-- The context menu, which is also what a dropdown opens. Its close path used to
-- clear OnHide outright to avoid recursing, and that removed every hook on the
-- frame -- including the one the drop shadow follows, so a closed menu left its
-- shadow behind. Every dropdown in the settings window did it.
do
	local conv = ns.ConversationManager.Get(thrall)
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
	M.RunFrames(8)
	local menuFrame = _G.WhatTheWhisperContextMenu
	check("the context menu opened", ns.Menu.IsOpen())

	local attached = {}
	for i = 1, #M.frames do
		local frame = M.frames[i]
		for p = 1, #(frame._points or {}) do
			local ref = frame._points[p][2]
			if ref and ref ~= frame and menuFrame and ref == menuFrame then
				attached[#attached + 1] = frame
				break
			end
		end
	end

	ns.Menu.Close()
	M.RunFrames(20)
	check("the menu closed", not ns.Menu.IsOpen())
	local ghosts = 0
	for i = 1, #attached do
		if M.EffectivelyVisible(attached[i]) then ghosts = ghosts + 1 end
	end
	local ghostDesc
	for i = 1, #attached do
		if M.EffectivelyVisible(attached[i]) then
			ghostDesc = ghostDesc or describe(attached[i])
		end
	end
	check("closing the menu leaves nothing of it on screen", ghosts == 0,
		("%d of %d still shown: %s"):format(ghosts, #attached, tostring(ghostDesc)))

	-- Reopening has to work after all that, which is what a guard buys over
	-- clearing the script.
	ns.Menu.Open(ns.UI.BuildConversationMenu(conv))
	M.RunFrames(8)
	check("the menu reopens afterwards", ns.Menu.IsOpen())
	ns.Menu.Close()
	M.RunFrames(20)
	check("and closes again", not ns.Menu.IsOpen())
end

-- Copy and export. There is no clipboard API in the client, so the entire
-- feature is one gesture: the text selected, the keyboard focus in the box,
-- Ctrl+C. Focus is the part that silently fails -- the client ignores SetFocus
-- on an edit box that is not on screen yet -- and both dialogs used to fill
-- themselves and take focus before showing, which is a dialog full of text that
-- Ctrl+C does nothing with.
do
	local conv = ns.ConversationManager.Get(thrall)
	check("the conversation has something to export", #conv.messages > 0)

	ns.Dialogs.ShowExport(conv)
	M.RunFrames(8)
	local dialog = _G.WhatTheWhisperCopyDialog
	check("the export dialog opened", dialog ~= nil and dialog:IsShown())

	local body = dialog.edit:GetText()
	check("the export dialog has the conversation in it",
		body:find(conv.messages[1][ns.MSG_TEXT], 1, true) ~= nil,
		("%d characters"):format(#body))
	check("the export box has keyboard focus", dialog.edit:HasFocus())
	local highlight = dialog.edit:GetHighlight()
	check("all of it is selected, so Ctrl+C takes the lot",
		highlight ~= nil and highlight[1] == 0 and highlight[2] == -1)

	-- Switching format refills the box, and has to leave it just as copyable.
	for _, format in ipairs({ "markdown", "bbcode", "csv", "text" }) do
		local out = ns.Export.Conversation(conv, format)
		check("export produces " .. format, type(out) == "string" and #out > 0)
		dialog:SetContent(out)
		check(format .. ": the box keeps focus after a format change",
			dialog.edit:HasFocus())
	end

	dialog:Hide()
	M.RunFrames(8)
	-- A focused edit box eats the movement keys; leaving one focused behind a
	-- closed dialog is how an addon locks a player in place.
	check("closing the dialog gives the keyboard back", not dialog.edit:HasFocus())

	-- The plain copy path takes the same route.
	ns.Dialogs.ShowCopy("https://example.com/some/path", "Copy URL")
	M.RunFrames(8)
	check("the copy dialog has focus too", dialog.edit:HasFocus())
	eq("and holds exactly what was asked for",
		dialog.edit:GetText(), "https://example.com/some/path")
	dialog:Hide()
	M.RunFrames(8)
end

--------------------------------------------------------------------------------
-- Contrast
--------------------------------------------------------------------------------

-- WCAG relative luminance and contrast ratio. Body text wants 4.5:1, large or
-- secondary text 3:1; a chat client that fails these is unreadable at night.
local function luminance(c)
	local function channel(v)
		if v <= 0.03928 then return v / 12.92 end
		return ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end

local function contrast(fg, bg)
	local a, b = luminance(fg), luminance(bg)
	if a < b then a, b = b, a end
	return (a + 0.05) / (b + 0.05)
end

-- Alpha-blended roles (hover, borders) are composited over their base first,
-- otherwise the ratio is measured against a colour nobody ever sees.
local function over(fg, bg)
	local alpha = fg[4] or 1
	if alpha >= 1 then return fg end
	return {
		fg[1] * alpha + bg[1] * (1 - alpha),
		fg[2] * alpha + bg[2] * (1 - alpha),
		fg[3] * alpha + bg[3] * (1 - alpha), 1,
	}
end

local CONTRAST_PAIRS = {
	{ "textPrimary", "bg1", 4.5, "body text on the window" },
	{ "textPrimary", "bg2", 4.5, "body text on a panel" },
	{ "textSecondary", "bg1", 3.0, "secondary text on the window" },
	{ "textSecondary", "bg2", 3.0, "secondary text on a panel" },
	{ "textMuted", "bg1", 2.2, "muted text on the window" },
	{ "bubbleInText", "bubbleIn", 4.5, "incoming bubble text" },
	{ "bubbleOutText", "bubbleOut", 4.5, "outgoing bubble text" },
	{ "onAccent", "accent", 3.0, "text on an accent button" },
	{ "link", "bg1", 3.0, "links on the window" },
	{ "link", "bubbleIn", 3.0, "links in an incoming bubble" },
	{ "danger", "bg1", 3.0, "the danger colour" },
	{ "success", "bg1", 3.0, "the online dot" },
	{ "warning", "bg1", 3.0, "the away dot" },
}

for _, id in ipairs(ns.Skins.order) do
	ns.Options.Set("appearance.skin", id)
	ns.UI.RefreshAll()
	M.RunFrames(4)
	for _, pair in ipairs(CONTRAST_PAIRS) do
		local role, base, want, what = pair[1], pair[2], pair[3], pair[4]
		local bg = over(ns.Theme.Get(base), { 0, 0, 0, 1 })
		local fg = over(ns.Theme.Get(role), bg)
		local ratio = contrast(fg, bg)
		check(("%s: %s is legible"):format(id, what), ratio >= want,
			("%s on %s is %.2f:1, want %.1f:1"):format(role, base, ratio, want))
	end

	-- A bubble has to read as a surface sitting on the panel, not as text
	-- floating on it. Contrast guidance for a non-text boundary is about
	-- 1.3:1 to be perceptible at all; below that the rounded rectangle is
	-- there in the code and invisible on screen.
	for _, pair in ipairs({
		{ "bubbleIn", "bg1", "the incoming bubble" },
		{ "bubbleOut", "bg1", "the outgoing bubble" },
	}) do
		local bg = over(ns.Theme.Get(pair[2]), { 0, 0, 0, 1 })
		local surface = over(ns.Theme.Get(pair[1]), bg)
		local separation = contrast(surface, bg)
		check(("%s: %s separates from the thread behind it"):format(id, pair[3]),
			separation >= 1.35,
			("%s on %s is only %.2f:1"):format(pair[1], pair[2], separation))
	end

	-- An unresolved colour role renders magenta on purpose; none may survive.
	for _, pair in ipairs(CONTRAST_PAIRS) do
		for _, role in ipairs({ pair[1], pair[2] }) do
			local c = ns.Theme.Get(role)
			check(("%s: %s is a real colour"):format(id, role),
				not (c[1] == 1 and c[2] == 0 and c[3] == 1),
				role .. " is unresolved in " .. id)
		end
	end
end

ns.Options.Set("appearance.skin", "midnight")
ns.UI.RefreshAll()
M.RunFrames(4)

--------------------------------------------------------------------------------
-- Pixel snapping across UI scales
--------------------------------------------------------------------------------

-- ns.Pixel.Size is the width of one physical pixel in the addon's coordinate
-- space; every border and divider has to be a whole multiple of it or it will
-- shimmer. The addon must produce a usable value at every scale the client
-- allows, not just at 1.0.
for _, scale in ipairs({ 0.64, 0.71, 0.85, 1.0 }) do

	_G.UIParent:SetScale(scale)
	ns.Compat.ResetPhysicalHeight()
	ns.Theme.Refresh()
	M.RunFrames(4)
	local px = ns.Pixel.Size(_G.UIParent)
	check(("scale %.2f: one pixel is a sane size"):format(scale),
		px > 0 and px < 4, tostring(px))
	check(("scale %.2f: snapping is idempotent"):format(scale),
		ns.Pixel.Snap(ns.Pixel.Snap(13.37, _G.UIParent), _G.UIParent)
			== ns.Pixel.Snap(13.37, _G.UIParent))
	local snapped = ns.Pixel.Snap(13.37, _G.UIParent)
	check(("scale %.2f: snapping lands on a pixel boundary"):format(scale),
		math.abs(snapped / px - math.floor(snapped / px + 0.5)) < 1e-6,
		("%.6f is %.4f pixels"):format(snapped, snapped / px))
	check(("scale %.2f: snapping moves a value less than one pixel"):format(scale),
		math.abs(snapped - 13.37) <= px)

	checkContainment(("scale %.2f"):format(scale), window)
end


_G.UIParent:SetScale(1)
ns.Compat.ResetPhysicalHeight()
ns.Theme.Refresh()
M.RunFrames(4)

--------------------------------------------------------------------------------
-- Density and font scale must not break containment either
--------------------------------------------------------------------------------

for _, density in ipairs({ "comfortable", "compact" }) do
	ns.Options.Set("appearance.density", density)
	ns.UI.RefreshLayout()
	ns.UI.RefreshAll()
	M.RunFrames(6)
	checkContainment("density " .. density, window)
	checkTargets("density " .. density .. ": targets stay clickable", window)
end
ns.Options.Set("appearance.density", "comfortable")

for _, fontScale in ipairs({ -2, 0, 4 }) do
	ns.Options.Set("appearance.fontScale", fontScale)
	ns.UI.RefreshAll()
	M.RunFrames(6)
	checkContainment("font scale " .. fontScale, window)
end
ns.Options.Set("appearance.fontScale", 0)
ns.UI.RefreshAll()
M.RunFrames(6)

--------------------------------------------------------------------------------
-- The window at its extremes
--------------------------------------------------------------------------------

for _, size in ipairs({
	{ ns.SZ.WINDOW_MIN_W, ns.SZ.WINDOW_MIN_H, "minimum" },
	{ ns.SZ.WINDOW_W, ns.SZ.WINDOW_H, "default" },
	{ ns.SZ.WINDOW_MAX_W, ns.SZ.WINDOW_MAX_H, "maximum" },
}) do
	ns.Options.Set("layout.width", size[1])
	ns.Options.Set("layout.height", size[2])
	ns.UI.RefreshLayout()
	ns.UI.RefreshAll()
	M.RunFrames(6)
	checkContainment("window at its " .. size[3], window)
	checkTargets(size[3] .. " window: targets stay clickable", window)
	check(size[3] .. " window: the sidebar keeps a usable width",
		select(3, rect(sidebar)) >= ns.SZ.SIDEBAR_RAIL_W - EPS,
		("%.1f"):format(select(3, rect(sidebar))))
	check(size[3] .. " window: the composer keeps a usable width",
		select(3, rect(composer)) >= 120,
		("%.1f"):format(select(3, rect(composer))))
end
ns.Options.Set("layout.width", ns.SZ.WINDOW_W)
ns.Options.Set("layout.height", ns.SZ.WINDOW_H)
ns.UI.RefreshLayout()
M.RunFrames(6)

--------------------------------------------------------------------------------
-- The composer with something in it
--------------------------------------------------------------------------------

-- An empty composer is the only state the audit used to see, because the byte
-- counter is hidden until the message is long -- and a hidden frame is not
-- measured. The counter was tucked into the gap between the send button and the
-- divider and stuck straight through it into the message list.
do
	local composer = window.view.composer
	local before = composer:GetHeight()

	composer.input:SetText(("a"):rep(220))
	composer:OnTextChanged(composer.input:GetText())
	M.RunFrames(6)
	check("a long message shows the counter", composer.counter:IsShown())
	check("and the composer made room for it",
		composer:GetHeight() > before,
		("%.1f -> %.1f"):format(before, composer:GetHeight()))
	local cb = select(2, rect(composer.counter))
	local ch = select(4, rect(composer.counter))
	local compTop = select(2, rect(composer)) + select(4, rect(composer))
	check("the counter stays inside the composer", cb + ch <= compTop + EPS,
		("counter top %.1f, composer top %.1f"):format(cb + ch, compTop))
	checkContainment("composer with a counter", window)

	-- Long enough to split, which is a different, wider string in the same spot.
	composer.input:SetText(("Ein ziemlich langer Satz. "):rep(30))
	composer:OnTextChanged(composer.input:GetText())
	M.RunFrames(6)
	check("a message that will split says so", composer.counter:IsShown())
	checkContainment("composer with a split warning", window)

	composer.input:SetText("")
	composer:OnTextChanged("")
	M.RunFrames(6)
	check("and it goes away again", not composer.counter:IsShown())
end

--------------------------------------------------------------------------------
-- The conversation header
--------------------------------------------------------------------------------

-- The name and the line under it were anchored to the avatar's top and bottom
-- edges, which made the gap between them a function of the avatar's height
-- rather than of the type. At the larger font scales they overlapped.
do
	local header = window.view.header
	for _, scale in ipairs({ 0, 2, 4 }) do
		ns.Options.Set("appearance.fontScale", scale)
		ns.UI.RefreshAll()
		M.RunFrames(6)
		local _, nameBottom, _, nameHeight = rect(header.name)
		local _, statusBottom, _, statusHeight = rect(header.status)
		if header.status:IsShown() then
			check(("font scale %d: the name clears the line under it"):format(scale),
				statusBottom + statusHeight <= nameBottom + EPS,
				("status top %.1f, name bottom %.1f"):format(
					statusBottom + statusHeight, nameBottom))
			-- And the pair as a whole sits in the middle of the header, which is
			-- what makes it read as one block rather than two stray labels.
			local hb, hh = select(2, rect(header)), select(4, rect(header))
			local blockCentre = (statusBottom + nameBottom + nameHeight) / 2
			check(("font scale %d: the name and status centre as a pair"):format(scale),
				math.abs(blockCentre - (hb + hh / 2)) <= 2,
				("block centre %.1f, header centre %.1f"):format(blockCentre, hb + hh / 2))
		end
		checkContainment(("header at font scale %d"):format(scale), window)
	end
	ns.Options.Set("appearance.fontScale", 0)
	ns.UI.RefreshAll()
	M.RunFrames(6)

	-- With nothing known about the player there is no second line, and the name
	-- should then be centred rather than sitting where the pair used to start.
	local plain = ns.ConversationManager.GetOrCreate("Nobodyknown-Blackrock")
	ns.ConversationManager.Select(plain.id)
	M.RunFrames(8)
	if not header.status:IsShown() then
		local hb, hh = select(2, rect(header)), select(4, rect(header))
		local nb, nh = select(2, rect(header.name)), select(4, rect(header.name))
		local nameCentre = nb + nh / 2
		check("a name with no status line is centred in the header",
			math.abs(nameCentre - (hb + hh / 2)) <= 2,
			("name centre %.1f, header centre %.1f"):format(nameCentre, hb + hh / 2))
	end
	ns.ConversationManager.Select(thrall)
	M.RunFrames(8)
end

--------------------------------------------------------------------------------
-- Other surfaces
--------------------------------------------------------------------------------

ns.SettingsUI.Show()
M.RunFrames(8)
-- The settings window is a globally named frame, which is how the audit reaches
-- it without the module having to expose an accessor just for the tests.
local settings = _G.WhatTheWhisperSettings
check("the settings window was built", settings ~= nil and settings:IsShown())
if settings then
	local schema = ns.Options.BuildSchema()
	for i = 1, #schema do
		ns.SettingsUI.SelectCategory(schema[i].id)
		M.RunFrames(4)
		checkContainment("settings: " .. schema[i].id, settings)
		checkTargets("settings: " .. schema[i].id .. " targets", settings)
		checkTruncation("settings: " .. schema[i].id .. " text fits", settings)
		checkIconCentring("settings: " .. schema[i].id .. " icons are centred", settings)

		-- Every control in a category shares one right column; a ragged edge
		-- down a settings list is the loudest thing on the screen.
		local controls = {}
		for control in settings.rowPool:EnumerateActive() do
			if control.control and M.EffectivelyShown(control.control, settings) then
				controls[#controls + 1] = control.control
			end
		end
		if #controls > 1 then
			local first = select(5, rect(controls[1]))
			local ragged, worst = 0, nil
			for k = 2, #controls do
				local edge = select(5, rect(controls[k]))
				if math.abs(edge - first) > EPS then
					ragged = ragged + 1
					worst = worst or ("%.2f vs %.2f"):format(edge, first)
				end
			end
			check("settings: " .. schema[i].id .. " controls share a right column",
				ragged == 0, worst)
		end
	end
end
ns.SettingsUI.Hide()

ns.UI.TogglePopout(thrall)
M.RunFrames(8)
local popout = ns.Popout.Get(thrall)
check("a popout window exists", popout ~= nil)
if popout then
	checkContainment("popout", popout)
	checkTargets("popout targets", popout)
	checkTruncation("popout text fits", popout)
	checkIconCentring("popout icons are centred", popout)
end
ns.UI.DockConversation(thrall)
M.RunFrames(6)

--------------------------------------------------------------------------------
-- The overview
--------------------------------------------------------------------------------

-- Real windows moved into a grid, each with its name written above it. Toggling
-- it and asserting nothing errored is not a design check: what matters is that
-- the labels stay off the hint and off each other, and that a card and its name
-- are both on the screen.
do
	-- Enough windows for more than one row, so the grid is actually exercised.
	for _, id in ipairs({ thrall, ns.Compat.NormalizeName("Jaina") }) do
		ns.UI.TogglePopout(id)
	end
	M.RunFrames(10)

	ns.Expose.Open()
	M.RunFrames(12)
	check("the overview opened", ns.Expose.IsOpen())

	local scrimFrame = _G.WhatTheWhisperExpose
	local cards, labels = {}, {}
	for i = 1, #M.frames do
		local frame = M.frames[i]
		if frame.restingRing and M.EffectivelyVisible(frame) then
			cards[#cards + 1] = frame
			labels[#labels + 1] = frame.label
		end
	end
	check("every window is on the board", #cards >= 3, tostring(#cards))

	local sw, sh = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
	local hintFrame
	for i = 1, #M.frames do
		if M.frames[i] == scrimFrame then hintFrame = nil end
	end
	-- The hint is the only FontString parented straight to the scrim.
	for _, region in ipairs(M.regions or {}) do
		if region._parent == scrimFrame and region._kind == "FontString" then
			hintFrame = region
		end
	end

	local offScreen, collided, overHint = 0, 0, 0
	for i = 1, #cards do
		local cl, cb, cw, ch = rect(cards[i])
		if cl < 0 or cb < 0 or cl + cw > sw or cb + ch > sh then offScreen = offScreen + 1 end
		local ll, lb, lw, lh = rect(labels[i])
		if ll < 0 or lb < 0 or ll + lw > sw or lb + lh > sh then offScreen = offScreen + 1 end
		if hintFrame then
			local hl, hb, hw, hh = rect(hintFrame)
			if ll < hl + hw and ll + lw > hl and lb < hb + hh and lb + lh > hb then
				overHint = overHint + 1
			end
		end
		for j = i + 1, #cards do
			local ol, ob, ow, oh = rect(labels[j])
			if ll < ol + ow and ll + lw > ol and lb < ob + oh and lb + lh > ob then
				collided = collided + 1
			end
		end
	end
	eq("nothing on the board is off screen", offScreen, 0)
	eq("no two window names overlap", collided, 0)
	eq("and none of them is written over the hint", overHint, 0)

	-- The ring is the affordance: a card with no edge until you touch it reads
	-- as a picture rather than a target.
	local ringed = 0
	for i = 1, #cards do
		if (cards[i].ring and cards[i].ring.thickness or 0) > 0 then ringed = ringed + 1 end
	end
	eq("every card has a resting outline", ringed, #cards)

	ns.Expose.Close()
	M.RunFrames(12)
	check("the overview closed", not ns.Expose.IsOpen())
	for _, id in ipairs({ thrall, ns.Compat.NormalizeName("Jaina") }) do
		ns.UI.DockConversation(id)
	end
	M.RunFrames(10)
end

--------------------------------------------------------------------------------
-- Icon atlas: every icon the UI asks for has to be inside the sheet
--------------------------------------------------------------------------------

local atlas = ns.ICON_ATLAS
check("the icon atlas is loaded", type(atlas) == "table" and next(atlas) ~= nil)
if type(atlas) == "table" then
	local bad, sample = 0, nil
	local tooSmall, smallSample = 0, nil
	for name, c in pairs(atlas) do
		local l, r, t, b = c[1], c[2], c[3], c[4]
		if not (l >= 0 and r <= 1 and t >= 0 and b <= 1 and r > l and b > t) then
			bad = bad + 1
			sample = sample or (name .. " -> " .. table.concat(c, ", "))
		end
		-- A half-texel inset on each side is what stops a neighbouring icon
		-- bleeding in when the sheet is filtered; a zero-width icon means the
		-- generator and the lookup table disagree.
		if (r - l) <= 0 or (b - t) <= 0 then
			tooSmall = tooSmall + 1
			smallSample = smallSample or name
		end
	end
	eq("every icon's coordinates are inside the sheet", bad, 0)
	eq("no icon is degenerate", tooSmall, 0)
end

--------------------------------------------------------------------------------

eq("nothing errored while auditing", #M.errors, 0,
	table.concat(M.errors, "\n      ", 1, math.min(#M.errors, 6)))

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
