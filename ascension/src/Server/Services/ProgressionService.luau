--!strict
--[[
	ProgressionService — SEUL point d'écriture de l'XP, du niveau et des pièces.

	Tous les gains (coups, quêtes, coffres, quotidien…) passent ici : validation, plafonds,
	événements (GameEvents) et réplication sont centralisés. Les récompenses exprimées en
	« minutes de revenu » sont converties selon le niveau du joueur (pérennes à tout niveau).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Progress = require(Shared.Rules.Progress)
local Economy = require(Shared.Rules.Economy)
local Curves = require(Shared.Rules.Curves)
local Combat = require(Shared.Rules.Combat)
local Loot = require(Shared.Config.Loot)
local Game = require(Shared.Config.Game)
local NumberFormat = require(Shared.Rules.NumberFormat)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)

type State = PlayerService.State

local ProgressionService = {}

local MAX_COINS = 1e18

function ProgressionService.notify(state: State, kind: string, text: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { k = kind, t = text }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	Net.event("Notify"):FireClient(state.Player, payload)
end

function ProgressionService.addXP(state: State, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local profile = state.Profile
	local before = profile.Level
	local powerBefore = Combat.powerRating(PlayerService.fighter(state))
	local result = Progress.addXP(profile.Level, profile.XP, amount)
	profile.Level = result.Level
	profile.XP = result.XP
	PlayerService.mark(state, "Level", "XP")
	GameEvents.XPGained:Fire(state, amount)
	if result.LevelsGained > 0 then
		GameEvents.LevelUp:Fire(state, before, result.Level)
		-- Envoyé un tick plus tard : les armes débloquées par l'événement sont déjà équipées,
		-- ce qui permet d'afficher « +N POWER » exact.
		task.defer(function()
			if state.Player.Parent == nil then
				return
			end
			local powerAfter = Combat.powerRating(PlayerService.fighter(state))
			Net.event("LevelUp"):FireClient(state.Player, {
				From = before,
				To = result.Level,
				PowerGain = math.max(0, powerAfter - powerBefore),
			})
		end)
	end
end

function ProgressionService.addCoins(state: State, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local profile = state.Profile
	profile.Coins = math.min(MAX_COINS, profile.Coins + math.floor(amount))
	PlayerService.mark(state, "Coins")
	GameEvents.CoinsGained:Fire(state, amount)
end

function ProgressionService.spendCoins(state: State, cost: number): boolean
	if cost ~= cost or cost < 0 or state.Profile.Coins < cost then
		return false
	end
	state.Profile.Coins -= cost
	PlayerService.mark(state, "Coins")
	return true
end

function ProgressionService.addChest(state: State, chestId: string, count: number?)
	if not Loot.ById[chestId] then
		return
	end
	local chests = state.Profile.Chests
	chests[chestId] = math.min(1e6, (chests[chestId] or 0) + (count or 1))
	PlayerService.mark(state, "Chests")
end

export type Reward = {
	Coins: number?, -- minutes de revenu
	XP: number?, -- minutes de revenu
	Chest: string?,
	Boost: { Kind: string, Minutes: number }?,
}

-- Convertit et accorde une récompense ; renvoie les lignes à afficher.
function ProgressionService.grant(state: State, reward: Reward, title: string): { string }
	local zoneIndex = Curves.zoneOfLevel(state.Profile.Level)
	local lines: { string } = {}
	if reward.Coins then
		local coins = Economy.minutesToCoins(reward.Coins, zoneIndex)
		ProgressionService.addCoins(state, coins)
		table.insert(lines, "+" .. NumberFormat.compact(coins) .. " coins")
	end
	if reward.XP then
		local xp = Economy.minutesToXP(reward.XP, zoneIndex)
		ProgressionService.addXP(state, xp)
		table.insert(lines, "+" .. NumberFormat.compact(xp) .. " XP")
	end
	if reward.Chest then
		ProgressionService.addChest(state, reward.Chest, 1)
		table.insert(lines, Loot.ById[reward.Chest].Name)
	end
	if reward.Boost and reward.Boost.Kind == "XP" then
		ProgressionService.addXPBoost(state, reward.Boost.Minutes)
		table.insert(lines, ("%d min XP boost"):format(reward.Boost.Minutes))
	end
	if #lines > 0 then
		ProgressionService.notify(state, "Reward", title, { l = lines })
	end
	return lines
end

function ProgressionService.addXPBoost(state: State, minutes: number)
	local now = os.time()
	local boosts = state.Profile.Boosts
	boosts.XP = math.max(now, boosts.XP) + math.floor(minutes * 60)
	PlayerService.mark(state, "Boosts")
end

-- Récompense « minutes » pour les produits développeur.
function ProgressionService.grantCoinMinutes(state: State, minutes: number)
	local zoneIndex = Curves.zoneOfLevel(state.Profile.Level)
	ProgressionService.addCoins(state, Economy.minutesToCoins(minutes, zoneIndex))
end

ProgressionService.MaxLevel = Game.MaxLevel

return ProgressionService
