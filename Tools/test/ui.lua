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

ns.Expose.Toggle()
M.RunFrames(8)
ns.Expose.Toggle()
M.RunFrames(8)

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
