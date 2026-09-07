"""The acceptance test: build the release the way the packager would, then load
the addon out of that folder and nothing else.

This is the check the whole embedding exercise exists for. Reading the .pkgmeta
and agreeing it looks right is not the same as producing the archive and proving
the result works, because the failure everyone ships is "it worked on my machine
because a sibling Ace3 folder was there".

So: stage the release into a scratch directory, assert on what is and is not in
it, then run the mock client against that staged copy with the repository
deliberately out of reach.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ADDON = os.path.join(ROOT, "WhatTheWhisper")

errors = []
notes = []


def err(message):
    errors.append(message)


# ---------------------------------------------------------------------------
# Stage the release
# ---------------------------------------------------------------------------

pkgmeta = os.path.join(ROOT, ".pkgmeta")
ignored = set()
if os.path.exists(pkgmeta):
    body = open(pkgmeta, encoding="utf-8").read()
    in_ignore = False
    for line in body.split("\n"):
        if re.match(r'^\S', line):
            in_ignore = line.strip().startswith("ignore:")
            continue
        entry = line.strip()
        if in_ignore and entry.startswith("-"):
            ignored.add(entry.lstrip("-").strip())

staging = tempfile.mkdtemp(prefix="wtw-release-")
release = os.path.join(staging, "WhatTheWhisper")

# package-as plus move-folders lifts WhatTheWhisper/WhatTheWhisper to the top,
# which is the same thing as copying the addon folder and dropping everything
# the ignore list names.
shutil.copytree(ADDON, release)
for name in ignored:
    stray = os.path.join(release, name)
    if os.path.exists(stray):
        shutil.rmtree(stray) if os.path.isdir(stray) else os.remove(stray)

# ---------------------------------------------------------------------------
# What the player receives
# ---------------------------------------------------------------------------

tocs = sorted(f for f in os.listdir(release) if f.endswith(".toc"))
if not tocs:
    err("the release contains no TOC file")
notes.append("release contains %d TOC files" % len(tocs))

libs = os.path.join(release, "Libs")
if not os.path.isdir(libs):
    err("the release has no Libs folder -- this is the broken zip we are avoiding")
else:
    embedded = sorted(d for d in os.listdir(libs) if os.path.isdir(os.path.join(libs, d)))
    if "LibStub" not in embedded:
        err("the release ships no LibStub")
    for required in ("CallbackHandler-1.0", "AceAddon-3.0", "AceConsole-3.0",
                     "AceEvent-3.0", "AceDB-3.0", "AceLocale-3.0"):
        if required not in embedded:
            err("the release is missing %s" % required)
    notes.append("release embeds: %s" % ", ".join(embedded))

for unwanted in ("Tools", "Ace3", ".git"):
    if os.path.exists(os.path.join(release, unwanted)):
        err("the release contains %s, which should not ship" % unwanted)

# A sibling addon folder in the archive would mean the player has to install two
# things, which is exactly what this project must not require.
siblings = [d for d in os.listdir(staging) if d != "WhatTheWhisper"]
if siblings:
    err("the release contains folders beside the addon: %s" % ", ".join(siblings))

art = os.path.join(release, "Art")
if not os.path.isdir(art) or not os.listdir(art):
    err("the release ships no Art folder")

total = sum(len(files) for _, _, files in os.walk(release))
notes.append("release holds %d files under a single WhatTheWhisper folder" % total)

# ---------------------------------------------------------------------------
# Load it, with the repository out of reach
# ---------------------------------------------------------------------------

# The harness hardcodes the repository path, so the staged run gets its own
# copy pointed at the staged addon. If anything in the addon reaches outside its
# own folder, there is nothing there to find and the run fails.
runner = os.path.join(staging, "load.lua")
mock = open(os.path.join(ROOT, "Tools/test/mock_wow.lua"), encoding="utf-8").read()
open(os.path.join(staging, "mock_wow.lua"), "w", encoding="utf-8").write(mock)

open(runner, "w", encoding="utf-8").write('''
-- Loads the staged release the way the client would: Libs.xml first, then the
-- addon manifest, with nothing outside this folder on the path.
local STAGING = %r
local ADDON = STAGING .. "/WhatTheWhisper/"
dofile(STAGING .. "/mock_wow.lua")
local M = _G.WOWMOCK

_G.SlashCmdList = {}
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
_G.UnitSex = function() return 2 end
_G.GetCurrentRegion = function() return 3 end

local function read(path)
	local fh = io.open(path, "r")
	if not fh then error("missing: " .. path) end
	local body = fh:read("*a") fh:close() return body
end

local function collect(xmlPath, out)
	out = out or {}
	local dir = xmlPath:match("^(.*)/[^/]*$") .. "/"
	for tag, file in read(xmlPath):gmatch("<(%%a+)%%s+file=\\"([^\\"]+)\\"") do
		local rel = file:gsub("\\\\", "/")
		if tag == "Script" then out[#out + 1] = dir .. rel
		elseif tag == "Include" then collect(dir .. rel, out) end
	end
	return out
end

-- Read the TOC so the load order is the one the client would use, not one this
-- script decided on.
local toc
for _, name in ipairs({ "WhatTheWhisper_Mainline.toc", "WhatTheWhisper.toc" }) do
	local fh = io.open(ADDON .. name, "r")
	if fh then toc = fh:read("*a") fh:close() break end
end
if not toc then error("no TOC in the release") end

local ns = {}
local loaded = 0
for line in toc:gmatch("[^\\r\\n]+") do
	local entry = line:match("^%%s*(.-)%%s*$")
	if entry ~= "" and not entry:match("^#") then
		local path = ADDON .. entry:gsub("\\\\", "/")
		if path:match("%%.xml$") then
			for _, file in ipairs(collect(path)) do
				local chunk, err = loadfile(file)
				if not chunk then error("compile " .. file .. ": " .. tostring(err)) end
				local ok, runErr = pcall(chunk, "WhatTheWhisper", ns)
				if not ok then error("run " .. file .. ": " .. tostring(runErr)) end
				loaded = loaded + 1
			end
		end
	end
end

M.loggedIn = true
M.FireEvent("ADDON_LOADED", "WhatTheWhisper")
M.FireEvent("PLAYER_LOGIN")
M.RunFrames(4)

assert(_G.LibStub, "LibStub did not load from the release")
for _, major in ipairs({ "AceAddon-3.0", "AceConsole-3.0", "AceEvent-3.0",
	"AceDB-3.0", "AceLocale-3.0", "CallbackHandler-1.0" }) do
	assert(_G.LibStub:GetLibrary(major, true), major .. " missing from the release")
end
assert(ns.db and ns.db.profile, "the addon did not initialise")
assert(ns.addon, "no AceAddon object")

-- And it actually works, not just loads.
local guid = "G-THRALL"
M.guids = { [guid] = { class = "SHAMAN", race = "Orc", name = "Thrall", realm = "Blackrock" } }
M.FireEvent("CHAT_MSG_WHISPER", "hello", "Thrall", "Common", "", "Thrall",
	"", 0, 0, "", 0, 1, guid)
M.RunFrames(2)
local id = ns.Compat.NormalizeName("Thrall")
assert(ns.ConversationManager.Get(id), "a whisper did not create a conversation")

ns.UI.Show()
M.RunFrames(6)
assert(ns.MainWindow.Existing():IsShown(), "the window did not open")

if #M.errors > 0 then
	error("errors during the staged run: " .. table.concat(M.errors, " | "))
end
print(("staged release loaded %%d files and works"):format(loaded))
''' % staging)

result = subprocess.run(["lua5.1", runner], capture_output=True, text=True, cwd=staging)
if result.returncode != 0:
    err("the staged release failed to load:\n      %s"
        % (result.stderr.strip() or result.stdout.strip()).replace("\n", "\n      "))
else:
    notes.append(result.stdout.strip())

shutil.rmtree(staging, ignore_errors=True)

print("\n".join("  " + n for n in notes))
if errors:
    print("\nPACKAGE ERRORS:")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("package ok")
