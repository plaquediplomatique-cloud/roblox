--!strict
--[[
	Hatch — tirage pondéré d'un pet. Pur et déterministe : les deux nombres aléatoires
	([0,1[) sont injectés, ce qui permet de tester les probabilités exactement.

	Étape 1 : choisir la rareté selon son poids. Étape 2 : choisir un pet uniformément dans
	cette rareté. Une rareté sans pet est ignorée (son poids est redistribué).
]]

export type Weighted = { id: string, weight: number }

local Hatch = {}

local function clampRoll(roll: number): number
	return math.clamp(roll, 0, 1 - 1e-9)
end

function Hatch.pickWeighted(entries: { Weighted }, roll: number): string
	local total = 0
	for _, entry in entries do
		total += math.max(0, entry.weight)
	end
	assert(total > 0, "Hatch.pickWeighted: poids total nul")
	local target = clampRoll(roll) * total
	local cursor = 0
	local last = entries[1].id
	for _, entry in entries do
		if entry.weight > 0 then
			cursor += entry.weight
			last = entry.id
			if target < cursor then
				return entry.id
			end
		end
	end
	return last
end

function Hatch.pickIndex(count: number, roll: number): number
	assert(count > 0, "Hatch.pickIndex: liste vide")
	return math.floor(clampRoll(roll) * count) + 1
end

function Hatch.roll(
	rarities: { Weighted },
	petIdsByRarity: { [string]: { string } },
	rarityRoll: number,
	petRoll: number
): (string, string)
	local available: { Weighted } = {}
	for _, entry in rarities do
		local pets = petIdsByRarity[entry.id]
		if pets and #pets > 0 then
			table.insert(available, entry)
		end
	end
	local rarityId = Hatch.pickWeighted(available, rarityRoll)
	local pets = petIdsByRarity[rarityId]
	return rarityId, pets[Hatch.pickIndex(#pets, petRoll)]
end

return Hatch
