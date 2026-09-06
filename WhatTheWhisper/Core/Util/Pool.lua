-- WhatTheWhisper -- Object pooling.
--
-- Frames are never destroyed in WoW, so a chat client that creates one per
-- message leaks for the whole session. Every repeated visual element in this
-- addon (message bubbles, sidebar rows, tabs, menu items, toasts) comes from a
-- pool and is recycled.

local _, ns = ...

local Pool = {}
ns.Pool = Pool

local tremove, tinsert = table.remove, table.insert

local mt = {}
mt.__index = mt

-- create(pool)          -> new object
-- reset(pool, object)   -> return object to a neutral state
function Pool.New(create, reset)
	return setmetatable({
		create = create,
		reset = reset,
		free = {},
		active = {},
		activeCount = 0,
		created = 0,
	}, mt)
end

function mt:Acquire()
	local obj = tremove(self.free)
	if not obj then
		obj = self.create(self)
		self.created = self.created + 1
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
