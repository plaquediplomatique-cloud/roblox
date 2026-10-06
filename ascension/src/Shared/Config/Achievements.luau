--!strict
--[[
	Achievements — succès à paliers générés depuis une table compacte. Chaque palier est un
	succès indépendant (Id = "<Métrique>_<n>") ; le serveur évalue les métriques du profil.
]]

export type Achievement = {
	Id: string,
	Name: string,
	Metric: string,
	Target: number,
	Reward: { Coins: number?, Weapon: string?, Chest: string? },
}

type Track = {
	Metric: string,
	Name: string, -- {n} remplacé
	Targets: { number },
	Reward: { { Coins: number?, Weapon: string?, Chest: string? } },
}

local tracks: { Track } = {
	{
		Metric = "Hits",
		Name = "Land {n} hits",
		Targets = { 100, 1000, 10000, 100000, 1000000 },
		Reward = {
			{ Coins = 5 },
			{ Weapon = "RubberChicken", Coins = 10 },
			{ Chest = "Silver" },
			{ Chest = "Golden" },
			{ Chest = "Golden", Coins = 200 },
		},
	},
	{
		Metric = "Level",
		Name = "Reach level {n}",
		Targets = { 10, 30, 60, 90, 120 },
		Reward = { { Coins = 10 }, { Coins = 20 }, { Chest = "Silver" }, { Chest = "Golden" }, { Coins = 500 } },
	},
	{
		Metric = "Weapons",
		Name = "Collect {n} weapons",
		Targets = { 6, 15, 30, 45, 70 },
		Reward = { { Coins = 10 }, { Chest = "Bronze" }, { Chest = "Silver" }, { Chest = "Golden" }, { Coins = 800 } },
	},
	{
		Metric = "BestCombo",
		Name = "Reach a x{n} combo",
		Targets = { 10, 25, 50, 100 },
		Reward = { { Coins = 5 }, { Coins = 15 }, { Chest = "Silver" }, { Chest = "Golden" } },
	},
	{
		Metric = "Bosses",
		Name = "Defeat {n} bosses",
		Targets = { 1, 10, 50, 200 },
		Reward = { { Chest = "Bronze" }, { Chest = "Silver" }, { Chest = "Golden" }, { Coins = 1000 } },
	},
	{
		Metric = "Ascensions",
		Name = "Ascend {n} times",
		Targets = { 1, 3, 5 },
		Reward = { { Chest = "Golden" }, { Coins = 3000 }, { Weapon = "CrownOfBlades" } },
	},
	{
		Metric = "PlayHours",
		Name = "Play for {n} hours",
		Targets = { 1, 5, 24 },
		Reward = { { Coins = 20 }, { Chest = "Silver" }, { Chest = "Golden" } },
	},
	{
		Metric = "Zones",
		Name = "Unlock {n} zones",
		Targets = { 3, 6, 10 },
		Reward = { { Coins = 20 }, { Chest = "Silver" }, { Chest = "Golden" } },
	},
}

local list: { Achievement } = {}
local byId: { [string]: Achievement } = {}
for _, track in tracks do
	for i, target in track.Targets do
		local achievement: Achievement = {
			Id = track.Metric .. "_" .. tostring(target),
			Name = (string.gsub(track.Name, "{n}", tostring(target))),
			Metric = track.Metric,
			Target = target,
			Reward = track.Reward[i],
		}
		table.insert(list, achievement)
		byId[achievement.Id] = achievement
	end
end

return { List = list, ById = byId }
