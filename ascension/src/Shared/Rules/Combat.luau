--!strict
--[[
	Combat (règles) — combo, cadence, critiques et dégâts. Fonctions PURES : le serveur les
	appelle avec le profil et un générateur aléatoire ; les tests les appellent avec un
	générateur déterministe. Le client ne calcule jamais un dégât (il affiche ce que le
	serveur renvoie).
]]

local Game = require(script.Parent.Parent.Config.Game)
local Upgrades = require(script.Parent.Upgrades)

local Combat = {}

export type ComboState = { Count: number, LastHit: number }

export type Special = {
	Type: string,
	Chance: number?,
	Threshold: number?,
	Mult: number?,
	N: number?,
	Value: number?,
}

export type Fighter = {
	Damage: number, -- dégâts de l'arme équipée
	AttackSpeed: number, -- coups/s de l'arme
	PowerLevel: number,
	SpeedLevel: number,
	CritChanceLevel: number,
	CritDamageLevel: number,
	Stars: number,
	Special: Special?,
}

export type HitInput = {
	Fighter: Fighter,
	Combo: number, -- combo APRÈS ce coup
	HitIndex: number, -- compteur de coups de la session (Surge)
	TargetHP: number,
	TargetMaxHP: number,
}

export type HitResult = {
	Damage: number,
	Crit: number, -- 0 normal, 1 critique, 2 méga critique
	Double: boolean,
	Surge: boolean,
}

---------------------------------------------------------------------------------------------
-- Combo
---------------------------------------------------------------------------------------------

function Combat.comboWindow(special: Special?): number
	local window = Game.ComboWindow
	if special and special.Type == "ComboWindow" then
		window += special.Value or 0
	end
	return window
end

-- Combo effectif à l'instant `now` : décroît d'un point par pas une fois la fenêtre dépassée.
function Combat.comboAt(state: ComboState, now: number, window: number): number
	local idle = now - state.LastHit
	if idle <= window then
		return state.Count
	end
	local lost = math.floor((idle - window) / Game.ComboDecayStep) + 1
	return math.max(0, state.Count - lost)
end

-- Enregistre un coup : renvoie le nouveau combo (plafonné).
function Combat.comboHit(state: ComboState, now: number, window: number): number
	local current = Combat.comboAt(state, now, window)
	local nextCount = math.min(Game.ComboMax, current + 1)
	state.Count = nextCount
	state.LastHit = now
	return nextCount
end

function Combat.comboMultiplier(count: number): number
	return 1 + math.min(count, Game.ComboMax) * Game.ComboPerStep
end

-- Palier visuel du combo (0..4) : 0, 10, 25, 50, 100.
function Combat.comboTier(count: number): number
	if count >= 100 then
		return 4
	elseif count >= 50 then
		return 3
	elseif count >= 25 then
		return 2
	elseif count >= 10 then
		return 1
	end
	return 0
end

---------------------------------------------------------------------------------------------
-- Cadence
---------------------------------------------------------------------------------------------

function Combat.swingsPerSecond(fighter: Fighter): number
	local speed = fighter.AttackSpeed * (1 + Upgrades.effect("Speed", fighter.SpeedLevel))
	return math.min(speed, 1 / Game.MinSwingInterval)
end

function Combat.swingInterval(fighter: Fighter): number
	return 1 / Combat.swingsPerSecond(fighter)
end

---------------------------------------------------------------------------------------------
-- Dégâts
---------------------------------------------------------------------------------------------

function Combat.critChance(fighter: Fighter): number
	local chance = Game.BaseCritChance + Upgrades.effect("CritChance", fighter.CritChanceLevel)
	if fighter.Special and fighter.Special.Type == "CritChance" then
		chance += fighter.Special.Value or 0
	end
	return math.min(chance, Game.CritChanceCap)
end

function Combat.critMultiplier(fighter: Fighter): number
	return Game.BaseCritMult + Upgrades.effect("CritDamage", fighter.CritDamageLevel)
end

-- Dégâts d'un coup « normal » sans combo ni critique (affichés dans l'UI : « Damage »).
function Combat.baseDamage(fighter: Fighter): number
	local power = 1 + Upgrades.effect("Power", fighter.PowerLevel)
	local stars = 1 + Game.AscensionStarDamage * fighter.Stars
	return fighter.Damage * power * stars
end

-- « Power » affiché / classement : dégâts par seconde espérés (critiques inclus, sans combo).
function Combat.powerRating(fighter: Fighter): number
	local crit = Combat.critChance(fighter)
	local expected = Combat.baseDamage(fighter) * (1 + crit * (Combat.critMultiplier(fighter) - 1))
	return math.floor(expected * Combat.swingsPerSecond(fighter))
end

function Combat.resolveHit(input: HitInput, random: () -> number): HitResult
	local fighter = input.Fighter
	local damage = Combat.baseDamage(fighter) * Combat.comboMultiplier(input.Combo)

	local crit = 0
	if random() < Combat.critChance(fighter) then
		crit = 1
		local mult = Combat.critMultiplier(fighter)
		if random() < Game.MegaCritShare then
			crit = 2
			mult *= Game.MegaCritMult
		end
		damage *= mult
	end

	local special = fighter.Special
	local double, surge = false, false
	if special then
		if special.Type == "DoubleHit" and random() < (special.Chance or 0) then
			double = true
			damage *= 2
		elseif special.Type == "EveryNth" and special.N and input.HitIndex % special.N == 0 then
			surge = true
			damage *= special.Mult or 2
		elseif
			special.Type == "LowHpBonus"
			and input.TargetMaxHP > 0
			and input.TargetHP / input.TargetMaxHP <= (special.Threshold or 0.3)
		then
			damage *= special.Mult or 1.5
		end
	end

	return { Damage = math.max(1, math.ceil(damage)), Crit = crit, Double = double, Surge = surge }
end

return Combat
