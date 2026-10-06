--!strict
--[[
	SlotAllocator — attribue le plus petit emplacement libre (1..max) à un joueur.
	`taken[i]` est tronqué à truthy quand l'emplacement i est occupé.
]]

local SlotAllocator = {}

function SlotAllocator.acquire(taken: { [number]: any }, max: number): number?
	for index = 1, max do
		if not taken[index] then
			return index
		end
	end
	return nil
end

return SlotAllocator
