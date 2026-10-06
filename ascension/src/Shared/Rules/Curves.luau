--!strict
--[[
	Curves — TOUTES les courbes d'équilibrage du jeu (fonctions pures, testées).

	Philosophie (cf. docs/DESIGN.md) :
	  * les dégâts d'arme suivent le palier : 1.75^(palier-1), arrondis (lisibles) ;
	  * l'XP par kill est dérivée du nombre de kills VOULU pour monter un niveau ;
	  * les mannequins d'une zone ont des PV calés sur la première arme de la zone, si bien
	    qu'une nouvelle arme fait passer de « 9 coups pour un kill » à « 1 coup » : la
	    puissance se SENT, et une nouvelle zone remet un défi.
]]

local Game = require(script.Parent.Parent.Config.Game)
local Zones = require(script.Parent.Parent.Config.Zones)
local NumberFormat = require(script.Parent.NumberFormat)

local Curves = {}

local DAMAGE_GROWTH = 1.75
local XP_GROWTH = 1.115
local FTUE_XP = { 8, 14, 22, 34, 48 } -- premiers niveaux très rapides (première minute)
local KILLS_AT_ZONE_START_BASE = 42
local KILLS_AT_ZONE_START_STEP = 24
local KILLS_PER_MINUTE = 18 -- référence pour exprimer des récompenses en « minutes de revenu »

function Curves.weaponDamage(tier: number): number
	local raw = DAMAGE_GROWTH ^ (tier - 1)
	if raw < 10 then
		return math.max(1, math.ceil(raw))
	end
	return NumberFormat.roundSignificant(raw, 2)
end

function Curves.weaponXPBoost(tier: number): number
	return 1 + 0.04 * (tier - 1)
end

function Curves.xpToNext(level: number): number
	if level < 1 then
		level = 1
	end
	local ftue = FTUE_XP[level]
	if ftue then
		return ftue
	end
	return math.floor(30 * XP_GROWTH ^ (level - 1))
end

-- Index (1..10) de la zone la plus avancée accessible à ce niveau.
function Curves.zoneOfLevel(level: number): number
	local index = 1
	for _, zone in Zones.List do
		if level >= zone.MinLevel then
			index = zone.Index
		end
	end
	return index
end

-- Palier de la première arme d'une zone (1, 7, 13…).
function Curves.zoneStartTier(zoneIndex: number): number
	return (zoneIndex - 1) * Zones.WeaponsPerZone + 1
end

function Curves.dummyHP(zoneIndex: number): number
	return Curves.weaponDamage(Curves.zoneStartTier(zoneIndex)) * Game.DummyHitsToKillAtZoneStart
end

function Curves.bossHP(zoneIndex: number): number
	return Curves.weaponDamage(Curves.zoneStartTier(zoneIndex)) * Game.BossHitsToKillAtZoneStart
end

function Curves.killsAtZoneStart(zoneIndex: number): number
	return KILLS_AT_ZONE_START_BASE + KILLS_AT_ZONE_START_STEP * (zoneIndex - 1)
end

-- XP donnée par un mannequin entier (répartie sur les coups selon les dégâts infligés).
function Curves.xpPerKill(zoneIndex: number): number
	local zone = Zones.List[zoneIndex]
	local base = math.floor(30 * XP_GROWTH ^ (zone.MinLevel - 1))
	if zoneIndex == 1 then
		return 2
	end
	return math.max(1, base / Curves.killsAtZoneStart(zoneIndex))
end

function Curves.coinsPerKill(zoneIndex: number): number
	return math.max(1, math.floor(Game.CoinsPerKillBase * Game.CoinsPerKillGrowth ^ (zoneIndex - 1)))
end

function Curves.bossXP(zoneIndex: number): number
	return Curves.xpPerKill(zoneIndex) * 40
end

function Curves.bossCoins(zoneIndex: number): number
	return Curves.coinsPerKill(zoneIndex) * 60
end

-- Revenu de référence par minute (pour exprimer des récompenses de manière pérenne).
function Curves.coinsPerMinute(zoneIndex: number): number
	return Curves.coinsPerKill(zoneIndex) * KILLS_PER_MINUTE
end

function Curves.xpPerMinute(zoneIndex: number): number
	return Curves.xpPerKill(zoneIndex) * KILLS_PER_MINUTE
end

return Curves
