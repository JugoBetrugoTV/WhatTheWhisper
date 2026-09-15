-- WhatTheWhisper -- Object pooling.
--
-- Frames are never destroyed in WoW, so a chat client that creates one per
-- message leaks for the whole session. Every repeated visual element in this
-- addon (message bubbles, sidebar rows, tabs, menu items, toasts) comes from a
-- pool and is recycled.

local _, ns = ...

local Pool = {}
ns.Pool = Pool

local tremove = table.remove

local mt = {}
mt.__index = mt

-- Every pool registers itself so /wtw diag can show, in one line each, how many
-- objects were ever created against how many are in use. A pool whose created
-- count keeps climbing while the visible count does not is a leak, and that is
-- exactly the shape this makes visible.
local registry = {}
Pool.registry = registry

-- create(pool)          -> new object
-- reset(pool, object)   -> return object to a neutral state
-- name                  -> label for diagnostics; optional but always worth it
function Pool.New(create, reset, name)
	local pool = setmetatable({
		create = create,
		reset = reset,
		name = name or "pool",
		free = {},
		active = {},
		activeCount = 0,
		created = 0,
		peak = 0,
	}, mt)
	registry[#registry + 1] = pool
	return pool
end

-- Growth is logged at each doubling rather than per object: a pool settling at
-- 40 bubbles should say so six times over a session, not forty.
local function noteGrowth(self)
	if self.created < self.peak * 2 and self.created > 4 then return end
	self.peak = self.created
	local Debug = ns.Debug
	if Debug then
		Debug.Log("pool", "%s grew to %d objects (%d in use)",
			self.name, self.created, self.activeCount)
	end
end

function mt:Acquire()
	local obj = tremove(self.free)
	if not obj then
		obj = self.create(self)
		self.created = self.created + 1
		noteGrowth(self)
	end
	self.active[obj] = true
	self.activeCount = self.activeCount + 1
	return obj
end

function mt:Release(obj)
	if not obj or not self.active[obj] then return end
	self.active[obj] = nil
	self.activeCount = self.activeCount - 1
	if self.reset then self.reset(self, obj) end
	self.free[#self.free + 1] = obj
end

function mt:ReleaseAll()
	for obj in pairs(self.active) do
		self.active[obj] = nil
		if self.reset then self.reset(self, obj) end
		self.free[#self.free + 1] = obj
	end
	self.activeCount = 0
end

function mt:EnumerateActive()
	return pairs(self.active)
end

function mt:Stats()
	return self.created, self.activeCount, #self.free
end

-- One line per pool, widest first: the shape of the addon's frame budget.
function Pool.Snapshot()
	local lines = {}
	for i = 1, #registry do
		local pool = registry[i]
		lines[#lines + 1] = {
			name = pool.name, created = pool.created,
			active = pool.activeCount, free = #pool.free,
		}
	end
	table.sort(lines, function(a, b)
		if a.created ~= b.created then return a.created > b.created end
		return a.name < b.name
	end)
	return lines
end

function Pool.TotalCreated()
	local total = 0
	for i = 1, #registry do total = total + registry[i].created end
	return total
end

--------------------------------------------------------------------------------
-- Table pool: keeps transient tables out of the garbage collector's way.
--------------------------------------------------------------------------------

local tablePool = {}

function Pool.GetTable()
	local t = tremove(tablePool)
	if t then return t end
	return {}
end

function Pool.ReleaseTable(t)
	if type(t) ~= "table" then return end
	wipe(t)
	if #tablePool < 64 then
		tablePool[#tablePool + 1] = t
	end
end
