--!strict
--[[
	IslandLayout — géométrie pure des emplacements joueurs, en coordonnées (x, z) au sol.

	L'île est ronde, centrée sur l'origine. Chaque emplacement a un point d'apparition au
	bord de la place et un nid pour l'œuf juste à côté (décalé sur la tangente), le joueur
	regardant vers le centre.
]]

export type Point = { x: number, z: number }

export type Slot = {
	index: number,
	spawn: Point,
	nest: Point,
	look: Point, -- direction unitaire (vers le centre de l'île)
}

local IslandLayout = {}

IslandLayout.nestOffset = 6.5 -- distance spawn → nid (studs)

function IslandLayout.slots(count: number, radius: number): { Slot }
	local result: { Slot } = {}
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local ux, uz = math.cos(angle), math.sin(angle)
		-- tangente : l'œuf est à la droite du joueur qui regarde le centre
		local tx, tz = -uz, ux
		table.insert(result, {
			index = index,
			spawn = { x = ux * radius, z = uz * radius },
			nest = {
				x = ux * (radius - 1.5) + tx * IslandLayout.nestOffset,
				z = uz * (radius - 1.5) + tz * IslandLayout.nestOffset,
			},
			look = { x = -ux, z = -uz },
		})
	end
	return result
end

function IslandLayout.distance(a: Point, b: Point): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

return IslandLayout
