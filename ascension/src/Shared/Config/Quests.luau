--!strict
--[[
	Quests — définitions des quêtes quotidiennes et hebdomadaires (séparées de la progression
	du joueur, stockée dans le profil). `Metric` = compteur incrémenté par QuestService via le
	bus d'événements. Récompenses en minutes de revenu (cf. Config/Daily).
]]

export type Quest = {
	Id: string,
	Text: string, -- {n} remplacé par la cible
	Metric: string,
	Target: number,
	Reward: { Coins: number?, XP: number?, Chest: string? },
	Weekly: boolean?,
}

local daily: { Quest } = {
	{ Id = "D_Hits_A", Text = "Land {n} hits", Metric = "Hits", Target = 150, Reward = { Coins = 4 } },
	{ Id = "D_Hits_B", Text = "Land {n} hits", Metric = "Hits", Target = 400, Reward = { Coins = 8, XP = 3 } },
	{ Id = "D_Kills_A", Text = "Defeat {n} dummies", Metric = "Kills", Target = 25, Reward = { XP = 5 } },
	{ Id = "D_Kills_B", Text = "Defeat {n} dummies", Metric = "Kills", Target = 60, Reward = { Coins = 8, XP = 4 } },
	{ Id = "D_Crits_A", Text = "Land {n} critical hits", Metric = "Crits", Target = 20, Reward = { Coins = 5 } },
	{ Id = "D_Crits_B", Text = "Land {n} critical hits", Metric = "Crits", Target = 60, Reward = { XP = 6 } },
	{ Id = "D_Combo_A", Text = "Reach a x{n} combo", Metric = "Combo", Target = 15, Reward = { Coins = 5 } },
	{ Id = "D_Combo_B", Text = "Reach a x{n} combo", Metric = "Combo", Target = 40, Reward = { Coins = 10 } },
	{ Id = "D_Upgrade", Text = "Buy {n} upgrades", Metric = "Upgrades", Target = 3, Reward = { XP = 5 } },
	{ Id = "D_Boss", Text = "Defeat {n} boss", Metric = "Bosses", Target = 1, Reward = { Chest = "Bronze" } },
	{ Id = "D_Level", Text = "Gain {n} levels", Metric = "Levels", Target = 3, Reward = { Coins = 8 } },
}

local weekly: { Quest } = {
	{
		Id = "W_Bosses",
		Text = "Defeat {n} bosses",
		Metric = "Bosses",
		Target = 8,
		Reward = { Chest = "Golden", Coins = 30 },
		Weekly = true,
	},
	{
		Id = "W_Hits",
		Text = "Land {n} hits",
		Metric = "Hits",
		Target = 5000,
		Reward = { Chest = "Silver", Coins = 25 },
		Weekly = true,
	},
}

local byId: { [string]: Quest } = {}
for _, quest in daily do
	byId[quest.Id] = quest
end
for _, quest in weekly do
	byId[quest.Id] = quest
end

return {
	Daily = daily,
	Weekly = weekly,
	ById = byId,
	DailyCount = 3,
}
