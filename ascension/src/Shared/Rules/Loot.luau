--!strict
--[[
	Loot (règles) — tirages de coffres et de boss, purs et déterministes avec un RNG injecté.

	Équité : les chances sont publiques, un compteur de pitié augmente la probabilité de
	l'arme du boss, et un tirage n'offre jamais une arme déjà possédée ni plus puissante que
	la progression du joueur (pas de raccourci pour sauter les niveaux).
]]

local Config = require(script.Parent.Parent.Config.Loot)
local WeaponCatalog = require(script.Parent.WeaponCatalog)

local Loot = {}

export type Drop = { Kind: "Weapon", WeaponId: string } | { Kind: "Coins", Minutes: number }

local function pickWeighted(weights: { [string]: number }, random: () -> number): string
	local total = 0
	local keys: { string } = {}
	for key, weight in weights do
		total += weight
		table.insert(keys, key)
	end
	table.sort(keys) -- ordre stable => résultat déterministe pour un RNG donné
	local roll = random() * total
	for _, key in keys do
		roll -= weights[key]
		if roll <= 0 then
			return key
		end
	end
	return keys[#keys]
end

Loot.pickWeighted = pickWeighted

-- Tirage d'un coffre. `maxTier` = palier de la meilleure arme principale débloquée + 2.
function Loot.rollChest(chestId: string, owned: { [string]: boolean }, maxTier: number, random: () -> number): Drop
	local chest = Config.ById[chestId]
	if not chest then
		return { Kind = "Coins", Minutes = 1 }
	end
	local rarity = pickWeighted(chest.Weights, random)
	local candidates: { WeaponCatalog.Weapon } = {}
	for _, weapon in WeaponCatalog.huntedByRarity(rarity, "Chest") do
		if not owned[weapon.Id] and weapon.Tier <= maxTier then
			table.insert(candidates, weapon)
		end
	end
	if #candidates == 0 then
		return { Kind = "Coins", Minutes = chest.CoinMinutes }
	end
	local pick = candidates[math.floor(random() * #candidates) + 1]
	return { Kind = "Weapon", WeaponId = pick.Id }
end

-- Chance de l'arme d'un boss, avec pitié.
function Loot.bossWeaponChance(pity: number): number
	return math.min(Config.BossWeaponPityCap, Config.BossWeaponChance + Config.BossWeaponPityStep * pity)
end

-- Arme de chasse d'un boss de zone (identifiant de zone), nil s'il n'y en a pas.
function Loot.bossWeapon(zoneId: string): WeaponCatalog.Weapon?
	for _, weapon in WeaponCatalog.Hunted do
		if weapon.Source == "Boss" and weapon.BossZone == zoneId then
			return weapon
		end
	end
	return nil
end

return Loot
