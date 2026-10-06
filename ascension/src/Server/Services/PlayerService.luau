--!strict
--[[
	PlayerService — état d'exécution de chaque joueur (profil + combo + cadence + réplication).

	* `State` regroupe tout ce que le serveur sait d'un joueur : profil vivant, état de combo,
	  seau de coups, cache du combattant, clés « sales » à répliquer.
	* Réplication : les services marquent des clés (`mark`) ; une seule boucle Heartbeat envoie
	  un `Sync` coalescé (au plus toutes les 0,1 s par joueur) avec les sous-tables modifiées.
	  Les valeurs dérivées (dégâts, puissance…) sont recalculées côté client avec les mêmes
	  règles pures : jamais de chiffre dérivé sur le réseau.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Profile = require(Shared.Rules.Profile)
local Combat = require(Shared.Rules.Combat)
local Economy = require(Shared.Rules.Economy)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local DataService = require(script.Parent.DataService)

local PlayerService = {}

export type State = {
	Player: Player,
	Profile: Profile.Profile,
	Combo: Combat.ComboState,
	HitIndex: number,
	Tokens: number,
	TokenAt: number,
	Fighter: Combat.Fighter?,
	Dirty: { [string]: boolean },
	LastSync: number,
	WeeklyKills: number,
	Passes: { [string]: boolean },
	PlotIndex: number?,
	JoinedAt: number,
	LastHitAt: number,
	Swings: number,
}

local states: { [Player]: State } = {}
local SYNC_INTERVAL = 0.1

function PlayerService.create(player: Player, profile: Profile.Profile): State
	local now = os.clock()
	local state: State = {
		Player = player,
		Profile = profile,
		Combo = { Count = 0, LastHit = 0 },
		HitIndex = 0,
		Tokens = Game.SwingBurst,
		TokenAt = now,
		Fighter = nil,
		Dirty = {},
		LastSync = 0,
		WeeklyKills = 0,
		Passes = {},
		PlotIndex = nil,
		JoinedAt = now,
		LastHitAt = 0,
		Swings = 0,
	}
	states[player] = state
	return state
end

function PlayerService.get(player: Player): State?
	return states[player]
end

function PlayerService.all(): { [Player]: State }
	return states
end

function PlayerService.destroy(player: Player)
	states[player] = nil
end

-- Marque des clés du profil à répliquer (et le profil à sauvegarder).
function PlayerService.mark(state: State, ...: string)
	for _, key in { ... } do
		state.Dirty[key] = true
	end
	DataService.markDirty(state.Player)
end

function PlayerService.invalidateFighter(state: State)
	state.Fighter = nil
end

-- Combattant courant (arme équipée + améliorations), mis en cache jusqu'à changement.
function PlayerService.fighter(state: State): Combat.Fighter
	local cached = state.Fighter
	if cached then
		return cached
	end
	local profile = state.Profile
	local weapon = WeaponCatalog.ById[profile.Equipped] or WeaponCatalog.Main[1]
	local fighter: Combat.Fighter = {
		Damage = weapon.Damage,
		AttackSpeed = weapon.AttackSpeed,
		PowerLevel = profile.Upgrades.Power,
		SpeedLevel = profile.Upgrades.Speed,
		CritChanceLevel = profile.Upgrades.CritChance,
		CritDamageLevel = profile.Upgrades.CritDamage,
		Stars = profile.Stars,
		Special = weapon.Special,
	}
	state.Fighter = fighter
	return fighter
end

function PlayerService.weapon(state: State): WeaponCatalog.Weapon
	return WeaponCatalog.ById[state.Profile.Equipped] or WeaponCatalog.Main[1]
end

function PlayerService.hasPass(state: State, id: string): boolean
	return state.Passes[id] == true
end

-- Indice (1..10) de la zone la plus avancée débloquée.
function PlayerService.bestZone(state: State): number
	local best = 1
	for _, zone in Zones.List do
		if state.Profile.Zones[zone.Id] and zone.Index > best then
			best = zone.Index
		end
	end
	return best
end

-- Bonus de base : +2 % de pièces par objet de décor posé (plafonné à +24 %).
function PlayerService.baseBonus(state: State): number
	local placed = 0
	for _ in state.Profile.Base.Slots do
		placed += 1
	end
	return math.min(0.24, placed * 0.02)
end

-- Contexte économique pour un coup (combo = combo après le coup).
function PlayerService.economyContext(state: State, combo: number, now: number): Economy.Context
	local weapon = PlayerService.weapon(state)
	local special = weapon.Special
	local specialXP, specialCoins = 0, 0
	if special and special.Type == "XPBonus" then
		specialXP = special.Value or 0
	elseif special and special.Type == "CoinBonus" then
		specialCoins = special.Value or 0
	end
	return {
		WeaponXPBoost = weapon.XPBoost,
		XPUpgradeLevel = state.Profile.Upgrades.XP,
		FortuneLevel = state.Profile.Upgrades.Fortune,
		Stars = state.Profile.Stars,
		Combo = combo,
		PassXP = state.Passes.DoubleXP == true,
		BoostXP = state.Profile.Boosts.XP > now,
		PassCoins = state.Passes.LuckyCoins == true,
		SpecialXP = specialXP,
		SpecialCoins = specialCoins + PlayerService.baseBonus(state),
	}
end

---------------------------------------------------------------------------------------------
-- Réplication
---------------------------------------------------------------------------------------------

local function payloadFor(state: State, keys: { [string]: boolean }?): { [string]: any }
	local payload: { [string]: any } = {}
	local profile = state.Profile :: any
	if keys == nil then
		for key, value in profile do
			if key ~= "Purchases" and key ~= "Version" then
				payload[key] = value
			end
		end
	else
		for key in keys do
			payload[key] = profile[key]
		end
	end
	return payload
end

function PlayerService.fullSync(state: State)
	state.Dirty = {}
	local payload = payloadFor(state, nil)
	payload.Passes = state.Passes
	payload.Full = true
	Net.event("Sync"):FireClient(state.Player, payload)
end

function PlayerService.start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, state in states do
			if next(state.Dirty) ~= nil and now - state.LastSync >= SYNC_INTERVAL then
				local keys = state.Dirty
				state.Dirty = {}
				state.LastSync = now
				Net.event("Sync"):FireClient(player, payloadFor(state, keys))
			end
		end
	end)
end

return PlayerService
