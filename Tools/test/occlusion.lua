-- Nothing the player is meant to read is painted over by the addon itself.
--
-- A frame draws above everything its parent draws, whatever the draw layers
-- say. So a label or a glyph put on a frame, with a child frame whose fill
-- covers the same spot, is never seen -- it is there by every measure a test
-- would take, and invisible in the game. That is how the magnifier in both
-- search fields spent its whole life under the field's own background, until a
-- picture of the window showed the gap.
--
-- This walks every window the addon draws and asks, for each string with text
-- and each glyph: does an opaque texture on one of its own frame's descendants
-- cover its centre? Siblings and other windows are left alone -- a menu over a
-- window is meant to cover it.

local ROOT = "/home/user/WhatTheWhisper/"
dofile(ROOT .. "Tools/test/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local pass, fail = 0, 0
local reported = {}
local function check(label, ok, detail)
	if ok then pass = pass + 1 return end
	fail = fail + 1
	if not reported[label] then
		reported[label] = true
		print("FAIL [occlusion] " .. label .. (detail and ("\n      " .. tostring(detail)) or ""))
	end
end

local Harness = dofile(ROOT .. "Tools/test/harness.lua")
local ns = Harness.Load()
M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(2)
ns.Options.Set("messages.openOnWhisper", false)

local CM, UI = ns.ConversationManager, ns.UI
M.guids = {
	["G-JAINA"] = { class = "MAGE", race = "Human", name = "Jaina", realm = "Blackrock" },
	["G-THRALL"] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" },
}
local line = 500
local function whisper(text, from, guid)
	line = line + 1
	M.FireEvent("CHAT_MSG_WHISPER", text, from, "Common", "", from, "", 0, 0, "", 0, line, guid)
	M.RunTimers(1)
end

--------------------------------------------------------------------------------
-- The audit
--------------------------------------------------------------------------------

local function effectiveAlpha(node)
	local a, hops = 1, 0
	while node and hops < 64 do
		a = a * (node._alpha or 1)
		node, hops = node._parent, hops + 1
	end
	return a
end

local function isDescendant(frame, ancestor)
	local node, hops = frame and frame._parent, 0
	while node and hops < 64 do
		if node == ancestor then return true end
		node, hops = node._parent, hops + 1
	end
	return false
end

-- Where a frame lets its children be seen: clipping ancestors cut it down.
local function visibleRect(region)
	local l, b, w, h = M.Geometry(region)
	local r, t = l + w, b + h
	local node, hops = region._parent, 0
	while node and hops < 64 do
		if node._clipsChildren then
			local nl, nb, nw, nh = M.Geometry(node)
			l, b = math.max(l, nl), math.max(b, nb)
			r, t = math.min(r, nl + nw), math.min(t, nb + nh)
		end
		node, hops = node._parent, hops + 1
	end
	return l, b, r, t
end

local function opaque(tex)
	if tex._kind ~= "Texture" or tex._isMask or tex._gEmpty then return false end
	if tex._layer == "HIGHLIGHT" then return false end
	if not M.EffectivelyVisible(tex) then return false end
	local a = effectiveAlpha(tex)
	if tex._color then a = a * (tex._color[4] == nil and 1 or tex._color[4])
	elseif tex._texture then a = a * ((tex._vertex and tex._vertex[4]) or 1)
	else return false end
	return a >= 0.5
end

local function describe(region)
	local trail, node, hops = {}, region, 0
	while node and hops < 6 do
		trail[#trail + 1] = node._name or node._kind or "?"
		node, hops = node._parent, hops + 1
	end
	return ("%s %q"):format(table.concat(trail, "<"),
		tostring(region._text or region.__wtwIcon or ""))
end

local function audit(scene)
	M.RunFrames(4)
	-- Everything opaque, grouped by the frame it is drawn on.
	local covers = {}
	for _, tex in ipairs(M.regions) do
		if opaque(tex) then covers[#covers + 1] = tex end
	end
	local checked = 0
	for _, region in ipairs(M.regions) do
		local readable = (region._kind == "FontString" and region._text and region._text ~= "")
			or (region._kind == "Texture" and region.__wtwIcon)
		if readable and M.EffectivelyVisible(region) and effectiveAlpha(region) > 0.05
			and not region._gEmpty then
			local l, b, r, t = visibleRect(region)
			if r > l and t > b then
				checked = checked + 1
				-- Five points, not one: a rounded fill is several pieces, and a
				-- centre that lands exactly on the seam between two of them is
				-- covered all the same.
				local w, h = r - l, t - b
				local points = {
					{ l + w / 2, b + h / 2 }, { l + w / 4, b + h / 4 }, { l + 3 * w / 4, b + h / 4 },
					{ l + w / 4, b + 3 * h / 4 }, { l + 3 * w / 4, b + 3 * h / 4 },
				}
				local owner = region._parent
				local covered, by = 0, nil
				for _, p in ipairs(points) do
					for _, tex in ipairs(covers) do
						local frame = tex._parent
						if frame ~= owner and isDescendant(frame, owner) then
							local tl, tb, tr, tt = visibleRect(tex)
							if p[1] >= tl and p[1] <= tr and p[2] >= tb and p[2] <= tt then
								covered, by = covered + 1, tex
								break
							end
						end
					end
				end
				if covered >= 3 then
					check(scene .. ": nothing covers " .. describe(region), false,
						"under " .. describe(by) .. " on a child frame")
				end
				pass = pass + 1
			end
		end
	end
	check(scene .. ": the scene has something to check", checked > 0)
end

--------------------------------------------------------------------------------
-- Every window, every state that changes what is on it
--------------------------------------------------------------------------------

UI.Show()
M.RunFrames(10)
audit("empty messenger")

whisper("Hey! Bist du noch on?", "Jaina", "G-JAINA")
whisper("Wir brauchen noch einen Heiler :)", "Jaina", "G-JAINA")
whisper("Bist du schon im Dungeon?", "Thrall", "G-THRALL")
local jaina = ns.Compat.NormalizeName("Jaina")
CM.Select(jaina)
CM.SendMessage(jaina, "Klar, bin dabei!")
M.RunTimers(1)
M.RunFrames(20)
audit("messenger with a thread")

local window = ns.MainWindow.Get()
window.sidebar.header.search:SetText("Jai")
M.RunFrames(4)
audit("messenger while searching")
window.sidebar.header.search:SetText("")

ns.Menu.Open(UI.BuildConversationMenu(CM.Get(jaina)), { anchor = window })
audit("conversation menu")
ns.Menu.Close()

ns.EmojiPicker.Open(window.view.composer.emoji, window.view.composer)
audit("emoji picker")
ns.EmojiPicker.Toggle(window.view.composer.emoji, window.view.composer)

ns.SettingsUI.Show()
M.RunFrames(10)
for _, category in ipairs(ns.Options.BuildSchema()) do
	ns.SettingsUI.SelectCategory(category.id)
	M.RunFrames(4)
	audit("settings: " .. category.id)
end
ns.SettingsUI.SetFilter("zzzz-nothing")
M.RunFrames(4)
audit("settings with no results")
ns.SettingsUI.SetFilter("")
ns.SettingsUI.Hide()

ns.Popout.Open(jaina)
M.RunFrames(10)
audit("popout")
ns.Popout.CloseAll()

ns.Toast.Show(CM.Get(jaina), CM.Get(jaina).messages[1])
M.RunFrames(6)
audit("notification card")

ns.Dialogs.ShowExport(CM.Get(jaina))
M.RunFrames(6)
audit("export dialog")

--------------------------------------------------------------------------------

check("no mock errors", #M.errors == 0, table.concat(M.errors, "\n      "))
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
