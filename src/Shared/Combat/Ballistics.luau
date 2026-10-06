--!strict
--[[
	Ballistics — modèle de dégâts, chute de dégâts, armure et pénétration (wallbang).

	Règles :
	  * Dégâts = base × multiplicateur de zone × chute selon la distance × perte de
	    pénétration, arrondis à l'entier (les joueurs raisonnent en "taps" : 4 balles
	    corps au VK-12, one-tap tête, etc.).
	  * Armure (bouclier) : absorbe 66 % de chaque impact tant qu'il en reste. Le total
	    (PV + bouclier) est un réservoir : 100 PV + 50 bouclier = 150 PV effectifs.
	  * Pénétration : chaque surface traversée consomme `épaisseur × résistance(matériau)`
	    sur le budget de pénétration de l'arme et réduit les dégâts. Au plus 2 surfaces.
]]

local Types = require(script.Parent.Parent.Types)

local Ballistics = {}

Ballistics.MAX_HEALTH = 100
Ballistics.MAX_ARMOR = 50
Ballistics.ARMOR_ABSORB = 0.66
Ballistics.MAX_PENETRATIONS = 2

-- Indexé par NOM de matériau : robuste (les EnumItem ne sont pas des singletons hors du
-- moteur, ex. dans les tests Lune) et lisible pour les level designers.
local RESISTANCE: { [string]: number } = {
	Glass = 0.15,
	Fabric = 0.3,
	Foil = 0.4,
	Wood = 0.6,
	WoodPlanks = 0.7,
	Neon = 0.8,
	Plastic = 0.9,
	SmoothPlastic = 0.9,
	Brick = 1.5,
	Pavement = 1.5,
	Cobblestone = 1.5,
	Concrete = 1.6,
	Slate = 1.6,
	Marble = 1.6,
	Granite = 1.8,
	Rock = 2.0,
	Basalt = 2.0,
	CorrodedMetal = 2.2,
	Metal = 2.4,
	DiamondPlate = 3.0,
	ForceField = math.huge,
}

function Ballistics.resistance(material: Enum.Material): number
	return RESISTANCE[material.Name] or 1.0
end

--[[ Multiplicateur de distance : interpolation linéaire entre points (portée, mult). ]]
function Ballistics.falloff(profile: Types.DamageProfile, distance: number): number
	local points = profile.falloff
	local count = #points
	if count == 0 then
		return 1
	end
	if distance <= points[1].range then
		return points[1].multiplier
	end
	for index = 2, count do
		local previous = points[index - 1]
		local current = points[index]
		if distance <= current.range then
			local t = (distance - previous.range) / (current.range - previous.range)
			return previous.multiplier + (current.multiplier - previous.multiplier) * t
		end
	end
	return points[count].multiplier
end

function Ballistics.zoneMultiplier(profile: Types.DamageProfile, zone: Types.HitZone): number
	if zone == "Head" then
		return profile.headMultiplier
	elseif zone == "Limb" then
		return profile.limbMultiplier
	end
	return 1
end

function Ballistics.damage(
	profile: Types.DamageProfile,
	zone: Types.HitZone,
	distance: number,
	penetrationMultiplier: number
): number
	local raw = profile.base
		* Ballistics.zoneMultiplier(profile, zone)
		* Ballistics.falloff(profile, distance)
		* penetrationMultiplier
	return math.max(1, math.floor(raw + 0.5))
end

--[[
	Applique des dégâts à (PV, bouclier). Renvoie (PV, bouclier, perte PV, perte bouclier).
]]
function Ballistics.apply(health: number, armor: number, damage: number): (number, number, number, number)
	local armorLoss = math.min(armor, damage * Ballistics.ARMOR_ABSORB)
	local healthLoss = math.min(health, damage - armorLoss)
	return health - healthLoss, armor - armorLoss, healthLoss, armorLoss
end

--[[
	Coût de pénétration d'une surface. Renvoie le multiplicateur de dégâts restant et le
	budget restant, ou nil si la balle est arrêtée.
]]
function Ballistics.penetrate(
	budget: number,
	thickness: number,
	material: Enum.Material,
	impenetrable: boolean
): (number?, number)
	if impenetrable then
		return nil, 0
	end
	local cost = thickness * Ballistics.resistance(material)
	if cost >= budget then
		return nil, 0
	end
	local multiplier = 1 - 0.6 * (cost / budget)
	return multiplier, budget - cost
end

--[[ Nombre de balles nécessaires pour tuer (pour l'UI de l'Armory et la doc). ]]
function Ballistics.shotsToKill(profile: Types.DamageProfile, zone: Types.HitZone, distance: number, armor: number): number
	local health, shield = Ballistics.MAX_HEALTH, armor
	local perShot = Ballistics.damage(profile, zone, distance, 1) * math.max(1, profile.pellets)
	local shots = 0
	while health > 0 and shots < 100 do
		health, shield = Ballistics.apply(health, shield, perShot)
		shots += 1
	end
	return shots
end

return Ballistics
