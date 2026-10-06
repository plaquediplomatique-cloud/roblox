--!strict
--[[
	Pool — réutilisation d'objets coûteux (Parts d'effets, Attachments, Sounds, Beams…).

	Un FPS génère des centaines d'effets par seconde (muzzle flash, traceurs, impacts,
	douilles). Créer/détruire des Instances à ce rythme provoque des pics de GC et de
	réplication locale. Le pool pré-alloue, recycle, et plafonne la taille : au-delà de
	`max`, l'objet le plus ancien encore actif est recyclé de force (dégradation propre au
	lieu d'une explosion mémoire).
]]

export type Pool<T> = {
	get: (self: Pool<T>) -> T,
	release: (self: Pool<T>, object: T) -> (),
	prewarm: (self: Pool<T>, count: number) -> (),
	active: (self: Pool<T>) -> number,
	destroy: (self: Pool<T>) -> (),
}

local PoolClass = {}
PoolClass.__index = PoolClass

function PoolClass.get(self: any): any
	local object
	local free = self._free
	if #free > 0 then
		object = table.remove(free)
	elseif self._activeCount >= self._max then
		-- Recyclage forcé du plus ancien objet actif.
		object = table.remove(self._order, 1)
		self._active[object] = nil
		self._activeCount -= 1
		self._reset(object)
	else
		object = self._factory()
	end
	self._active[object] = true
	self._activeCount += 1
	table.insert(self._order, object)
	return object
end

function PoolClass.release(self: any, object: any)
	if not self._active[object] then
		return
	end
	self._active[object] = nil
	self._activeCount -= 1
	local order = self._order
	local index = table.find(order, object)
	if index then
		table.remove(order, index)
	end
	self._reset(object)
	table.insert(self._free, object)
end

function PoolClass.prewarm(self: any, count: number)
	for _ = 1, count do
		local object = self._factory()
		self._reset(object)
		table.insert(self._free, object)
	end
end

function PoolClass.active(self: any): number
	return self._activeCount
end

function PoolClass.destroy(self: any)
	local function kill(object: any)
		if typeof(object) == "Instance" then
			object:Destroy()
		end
	end
	for _, object in self._free do
		kill(object)
	end
	for object in self._active do
		kill(object)
	end
	table.clear(self._free)
	table.clear(self._active)
	table.clear(self._order)
	self._activeCount = 0
end

local Pool = {}

function Pool.new<T>(factory: () -> T, reset: (T) -> (), max: number): Pool<T>
	local self = {
		_factory = factory,
		_reset = reset,
		_max = max,
		_free = {},
		_active = {},
		_order = {},
		_activeCount = 0,
	}
	return (setmetatable(self, PoolClass) :: any) :: Pool<T>
end

return Pool
