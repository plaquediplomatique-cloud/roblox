--!strict
--[[
	Upgrades (règles) — coût et effet des améliorations permanentes. Fonctions pures.
]]

local Config = require(script.Parent.Parent.Config.Upgrades)

local Upgrades = {}

function Upgrades.maxLevel(id: string): number
	local def = Config.ById[id]
	return if def then def.Max else 0
end

-- Coût pour passer du niveau `level` au suivant (nil si au maximum / inconnu).
function Upgrades.cost(id: string, level: number): number?
	local def = Config.ById[id]
	if not def or level >= def.Max or level < 0 then
		return nil
	end
	return math.floor(def.BaseCost * def.Growth ^ level + 0.5)
end

-- Effet cumulé au niveau donné (additif : Per * niveau).
function Upgrades.effect(id: string, level: number): number
	local def = Config.ById[id]
	if not def then
		return 0
	end
	return def.Per * math.clamp(level, 0, def.Max)
end

export type BuyResult = { Ok: boolean, Reason: string?, Cost: number?, NewLevel: number? }

-- Vérifie un achat sans rien modifier ; l'appelant débite et incrémente si Ok.
function Upgrades.check(id: string, level: number, coins: number): BuyResult
	local def = Config.ById[id]
	if not def then
		return { Ok = false, Reason = "Unknown upgrade" }
	end
	local cost = Upgrades.cost(id, level)
	if not cost then
		return { Ok = false, Reason = "Max level" }
	end
	if coins < cost then
		return { Ok = false, Reason = "Not enough coins", Cost = cost }
	end
	return { Ok = true, Cost = cost, NewLevel = level + 1 }
end

return Upgrades
