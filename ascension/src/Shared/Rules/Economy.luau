--!strict
--[[
	Economy (règles) — multiplicateurs d'XP / pièces et gains. Pures.

	Anti pay-to-win : le multiplicateur d'XP issu de l'argent réel (Game Pass + boost) est
	plafonné par Config/Game.PaidXPMultiplierCap ; il se multiplie avec la progression
	gratuite (améliorations, armes, combo) sans jamais la remplacer.
]]

local Game = require(script.Parent.Parent.Config.Game)
local Upgrades = require(script.Parent.Upgrades)
local Curves = require(script.Parent.Curves)

local Economy = {}

export type Context = {
	WeaponXPBoost: number,
	XPUpgradeLevel: number,
	FortuneLevel: number,
	Stars: number,
	Combo: number,
	PassXP: boolean, -- Game Pass 2x XP
	BoostXP: boolean, -- boost temporaire actif
	PassCoins: boolean,
	SpecialXP: number, -- bonus d'arme (0.15 = +15 %)
	SpecialCoins: number,
}

function Economy.paidXPMultiplier(passXP: boolean, boostXP: boolean): number
	local mult = 1
	if passXP then
		mult += 1
	end
	if boostXP then
		mult += 1
	end
	return math.min(mult, Game.PaidXPMultiplierCap)
end

function Economy.xpMultiplier(ctx: Context): number
	local combo = 1 + math.min(ctx.Combo, Game.ComboMax) * Game.ComboPerStep
	return ctx.WeaponXPBoost
		* (1 + Upgrades.effect("XP", ctx.XPUpgradeLevel))
		* (1 + Game.AscensionStarXP * ctx.Stars)
		* (1 + ctx.SpecialXP)
		* Economy.paidXPMultiplier(ctx.PassXP, ctx.BoostXP)
		* combo
end

function Economy.coinMultiplier(ctx: Context): number
	local pass = if ctx.PassCoins then 1.5 else 1
	return (1 + Upgrades.effect("Fortune", ctx.FortuneLevel))
		* (1 + Game.AscensionStarCoins * ctx.Stars)
		* (1 + ctx.SpecialCoins)
		* pass
end

-- XP d'un coup : part des dégâts réellement infligés (jamais plus que les PV restants).
function Economy.hitXP(zoneIndex: number, damageDealt: number, maxHP: number, ctx: Context): number
	if maxHP <= 0 then
		return 0
	end
	local share = math.min(1, damageDealt / maxHP)
	return Curves.xpPerKill(zoneIndex) * share * Economy.xpMultiplier(ctx)
end

function Economy.killCoins(zoneIndex: number, ctx: Context): number
	return math.max(1, math.floor(Curves.coinsPerKill(zoneIndex) * Economy.coinMultiplier(ctx)))
end

-- Récompense exprimée en minutes de revenu de la zone courante.
function Economy.minutesToCoins(minutes: number, zoneIndex: number): number
	return math.floor(Curves.coinsPerMinute(zoneIndex) * minutes)
end

function Economy.minutesToXP(minutes: number, zoneIndex: number): number
	return math.floor(Curves.xpPerMinute(zoneIndex) * minutes)
end

return Economy
