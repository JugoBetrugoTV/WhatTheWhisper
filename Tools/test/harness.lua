-- Shared loading for every test: brings the addon up exactly the way the client
-- does, from the manifests the client reads.
--
-- The important part is that nothing here lists libraries. The list is walked
-- out of WhatTheWhisper/Libs/Libs.xml, so the tests load precisely what ships,
-- in the order it ships, and a mistake in that manifest fails the whole suite
-- rather than hiding behind a hand-maintained copy that happens to be right.
--
-- Nothing outside WhatTheWhisper/ is ever read. That is the point: if a test
-- passes here, it passes for somebody who unzipped only the addon folder.

local Harness = {}

local ROOT = "/home/user/WhatTheWhisper/"
local ADDON = ROOT .. "WhatTheWhisper/"
Harness.ROOT, Harness.ADDON = ROOT, ADDON

local function readFile(path)
	local fh = io.open(path, "r")
	if not fh then return nil end
	local body = fh:read("*a")
	fh:close()
	return body
end
Harness.ReadFile = readFile

-- Walks a WoW UI manifest depth first, following <Include> into nested XML the
-- way the client does, and returns the Lua files in load order. Paths in these
-- files use backslashes and are relative to the file that names them.
local function collect(xmlPath, out, seen)
	out, seen = out or {}, seen or {}
	local body = readFile(xmlPath)
	if not body then
		error("manifest not found: " .. xmlPath)
	end
	if seen[xmlPath] then
		error("manifest included twice: " .. xmlPath)
	end
	seen[xmlPath] = true

	local dir = xmlPath:match("^(.*)/[^/]*$") .. "/"
	-- One pass over the file so Script and Include stay in document order; the
	-- client loads them in the order they appear, and so must we.
	for tag, file in body:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
		local rel = file:gsub("\\", "/")
		if tag == "Script" then
			out[#out + 1] = dir .. rel
		elseif tag == "Include" then
			collect(dir .. rel, out, seen)
		end
	end
	return out
end
Harness.Collect = collect

-- The embedded libraries, in manifest order.
function Harness.LibraryFiles()
	return collect(ADDON .. "Libs/Libs.xml")
end

-- The addon's own files, in manifest order.
function Harness.AddonFiles()
	return collect(ADDON .. "WhatTheWhisper.xml")
end

-- Loads the embedded libraries. Each file is called with the two arguments the
-- client passes every addon chunk -- the addon name and its private table --
-- because a library that reads them must see what it would see in the game.
function Harness.LoadLibraries(onError)
	local files = Harness.LibraryFiles()
	for i = 1, #files do
		local path = files[i]
		local chunk, err = loadfile(path)
		if not chunk then
			if onError then onError("load " .. path, err) else error(err) end
		else
			local ok, runErr = pcall(chunk, "WhatTheWhisper", {})
			if not ok then
				if onError then onError("run " .. path, runErr) else error(runErr) end
			end
		end
	end
	return files
end

-- Loads the addon itself into a fresh private namespace and returns it.
function Harness.LoadAddon(onError)
	local ns = {}
	local files = Harness.AddonFiles()
	for i = 1, #files do
		local path = files[i]
		local chunk, err = loadfile(path)
		if not chunk then
			if onError then onError("load " .. path, err) else error(err) end
		else
			local ok, runErr = pcall(chunk, "WhatTheWhisper", ns)
			if not ok then
				if onError then onError("run " .. path, runErr) else error(runErr) end
			end
		end
	end
	return ns, files
end

-- Libraries then addon, which is the order the TOC declares.
function Harness.Load(onError)
	Harness.LoadLibraries(onError)
	return Harness.LoadAddon(onError)
end

return Harness
