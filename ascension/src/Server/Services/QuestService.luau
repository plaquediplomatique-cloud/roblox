--!strict
--[[
	QuestService — quêtes quotidiennes/hebdomadaires, succès, récompense de connexion et temps de jeu.

	Tout est piloté par le bus d'événements : le combat ne connaît pas les quêtes. La progression
	canonique vit dans le profil (côté serveur) ; le client n'envoie que « je réclame » et le
	serveur vérifie que l'objectif est atteint (réclamation idempotente).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Quests = require(Shared.Rules.Quests)
local Achievements = require(Shared.Rules.Achievements)
local Daily = require(Shared.Rules.Daily)
local QuestConfig = require(Shared.Config.Quests)
local DailyConfig = require(Shared.Config.Daily)
local GameEvents = require(script.Parent.Parent.GameEvents)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local WeaponService = require(script.Parent.WeaponService)

type State = PlayerService.State

local QuestService = {}

local TICK = 5

local function record(state: State, metric: string, amount: number)
	local done = Quests.record(state.Profile.Quests, metric, amount)
	PlayerService.mark(state, "Quests")
	for _, id in done do
		local def = QuestConfig.ById[id]
		ProgressionService.notify(
			state,
			"Quest",
			"Quest complete!",
			{ l = { (string.gsub(def.Text, "{n}", tostring(def.Target))) } }
		)
	end
end

local function evaluate(state: State)
	local fresh = Achievements.evaluate(state.Profile)
	if #fresh > 0 then
		PlayerService.mark(state, "Achievements")
		for _, achievement in fresh do
			ProgressionService.notify(state, "Achievement", "Achievement unlocked!", { l = { achievement.Name } })
		end
	end
end

local function ensureQuests(state: State)
	if Quests.ensure(state.Profile.Quests, os.time(), state.Player.UserId) then
		PlayerService.mark(state, "Quests")
	end
end

function QuestService.claimQuest(state: State, id: string)
	ensureQuests(state)
	local def = Quests.claim(state.Profile.Quests, id)
	if not def then
		return
	end
	PlayerService.mark(state, "Quests")
	ProgressionService.grant(
		state,
		{ Coins = def.Reward.Coins, XP = def.Reward.XP, Chest = def.Reward.Chest, Boost = nil },
		"Quest reward"
	)
end

function QuestService.claimAchievement(state: State, id: string)
	local achievement = Achievements.claim(state.Profile, id)
	if not achievement then
		return
	end
	PlayerService.mark(state, "Achievements")
	local reward = achievement.Reward
	if reward.Weapon then
		WeaponService.grant(state, reward.Weapon, "Achievement")
	end
	ProgressionService.grant(
		state,
		{ Coins = reward.Coins, XP = nil, Chest = reward.Chest, Boost = nil },
		achievement.Name
	)
end

function QuestService.claimDaily(state: State)
	local day, reward = Daily.claim(state.Profile.Daily, os.time())
	if not day or not reward then
		return
	end
	PlayerService.mark(state, "Daily")
	ProgressionService.grant(state, reward, ("Daily reward — day %d"):format(day))
end

function QuestService.start()
	GameEvents.ProfileLoaded:Connect(function(state)
		ensureQuests(state)
		evaluate(state)
	end)

	GameEvents.Hit:Connect(function(state, info)
		record(state, "Hits", 1)
		if info.Crit > 0 then
			record(state, "Crits", 1)
		end
		record(state, "Combo", info.Combo)
	end)
	GameEvents.Kill:Connect(function(state)
		record(state, "Kills", 1)
		evaluate(state)
	end)
	GameEvents.BossDefeated:Connect(function(state)
		record(state, "Bosses", 1)
		evaluate(state)
	end)
	GameEvents.LevelUp:Connect(function(state, old, new)
		record(state, "Levels", new - old)
		evaluate(state)
	end)
	GameEvents.UpgradeBought:Connect(function(state)
		record(state, "Upgrades", 1)
	end)
	GameEvents.WeaponAcquired:Connect(evaluate)
	GameEvents.ZoneUnlocked:Connect(evaluate)
	GameEvents.Ascended:Connect(evaluate)

	ServerNet.on("ClaimDaily", function(player)
		local state = PlayerService.get(player)
		if state then
			QuestService.claimDaily(state)
		end
	end)
	ServerNet.on("ClaimQuest", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			QuestService.claimQuest(state, payload.id)
		end
	end)
	ServerNet.on("ClaimAchievement", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			QuestService.claimAchievement(state, payload.id)
		end
	end)

	-- Temps de jeu + renouvellement des quêtes à minuit + succès basés sur le temps/les coups.
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				local state = PlayerService.get(player)
				if state then
					state.Profile.Stats.PlaySeconds += TICK
					PlayerService.mark(state, "Stats")
					ensureQuests(state)
					evaluate(state)
				end
			end
		end
	end)
end

QuestService.DailyDays = #DailyConfig.Days

return QuestService
