-- WhatTheWhisper -- SavedVariables schema versioning.
--
-- Both saved files carry the same schema number so they can never drift apart.
-- The runner is here from the first release precisely because the first release
-- is the only moment where adding it is free: once people have data, a format
-- change without a migration path costs them their history.

local _, ns = ...

local Migrations = {}
ns.Migrations = Migrations

-- Bump this when the shape of WhatTheWhisperDB or WhatTheWhisperHistoryDB
-- changes, and add the matching step below.
ns.SCHEMA_VERSION = 1

-- steps[n] converts data written by schema n-1 into schema n. A step must be
-- safe to run on partially converted data: it is called inside pcall, and if it
-- raises, the version is left where it was so the next session tries again
-- rather than treating half-converted data as current.
Migrations.steps = {
	-- [2] = function(db, history) ... end,
}

local function historyIsEmpty(history)
	if type(history) ~= "table" or type(history.chars) ~= "table" then return true end
	for _, store in pairs(history.chars) do
		if type(store) == "table" and type(store.conv) == "table" then
			for _ in pairs(store.conv) do return false end
		end
	end
	return true
end

-- Returns storedVersion, currentVersion, migrated.
function Migrations.Run(db, history)
	local current = ns.SCHEMA_VERSION
	local stored = tonumber(db.global.schemaVersion)

	if not stored then
		-- A fresh install, or one written before versioning existed. Schema 1 is
		-- the first shipped format, so in both cases the data already matches.
		db.global.schemaVersion = current
		history.version = current
		return current, current, false
	end

	if stored == current then
		history.version = current
		return stored, current, false
	end

	if stored > current then
		-- Data from a newer version of the addon. Converting downwards would
		-- lose whatever the newer format added, so nothing is touched.
		ns.Print(("saved data is from a newer version (schema %d > %d); " ..
			"leaving it untouched"):format(stored, current))
		return stored, current, false
	end

	local migrated = false
	for version = stored + 1, current do
		local step = Migrations.steps[version]
		if step then
			local ok, err = pcall(step, db, history)
			if not ok then
				ns.Print(("migration to schema %d failed: %s"):format(version, tostring(err)))
				return stored, current, migrated
			end
			migrated = true
		end
		db.global.schemaVersion = version
		history.version = version
	end
	return current, current, migrated
end

-- Repairs anything that is structurally wrong regardless of version: a history
-- file can be damaged by a crash during the write, and a nil where a table
-- belongs would otherwise throw on the first message.
-- Absent tables are a first run, not damage; only a value of the wrong type is
-- counted, so a clean install never reports a repair.
local function ensureTable(owner, key)
	local value = owner[key]
	if type(value) == "table" then return false end
	owner[key] = {}
	return value ~= nil
end

function Migrations.Repair(history)
	local repaired = 0
	if ensureTable(history, "chars") then repaired = repaired + 1 end
	for key, store in pairs(history.chars) do
		if type(store) ~= "table" then
			history.chars[key] = { conv = {} }
			repaired = repaired + 1
		else
			if ensureTable(store, "conv") then repaired = repaired + 1 end
			for id, record in pairs(store.conv) do
				if type(record) ~= "table" then
					store.conv[id] = nil
					repaired = repaired + 1
				elseif type(record.msgs) ~= "table" then
					if record.msgs ~= nil then repaired = repaired + 1 end
					record.msgs = {}
				else
					-- Drop entries that are not message tuples; a single bad row
					-- would otherwise break every render of that thread.
					local write = 1
					local list = record.msgs
					for i = 1, #list do
						local entry = list[i]
						if type(entry) == "table" and type(entry[ns.MSG_TS]) == "number"
							and type(entry[ns.MSG_TEXT]) == "string" then
							list[write] = entry
							write = write + 1
						else
							repaired = repaired + 1
						end
					end
					for i = write, #list do list[i] = nil end
				end
			end
		end
	end
	return repaired
end

Migrations.HistoryIsEmpty = historyIsEmpty
