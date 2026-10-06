--!strict
--[[
	Loot — coffres et tables de butin des boss. Les chances sont publiques (affichées en jeu) :
	aucun coffre ne se vend en Robux, donc aucun tirage payant (règles de la plateforme).

	Un tirage choisit d'abord une rareté (poids), puis une arme de chasse de cette rareté
	que le joueur n'a pas encore ; sinon des pièces de consolation. Le compteur de « pitié »
	garantit la rareté la plus haute après N échecs.
]]

export type Chest = {
	Id: string,
	Name: string,
	Color: Color3,
	Weights: { [string]: number }, -- rareté -> poids
	CoinMinutes: number, -- consolation (minutes de revenu)
}

local chests: { Chest } = {
	{
		Id = "Bronze",
		Name = "Bronze Chest",
		Color = Color3.fromRGB(190, 120, 70),
		Weights = { Common = 60, Uncommon = 30, Rare = 10 },
		CoinMinutes = 3,
	},
	{
		Id = "Silver",
		Name = "Silver Chest",
		Color = Color3.fromRGB(205, 215, 230),
		Weights = { Uncommon = 45, Rare = 38, Epic = 15, Legendary = 2 },
		CoinMinutes = 6,
	},
	{
		Id = "Golden",
		Name = "Golden Chest",
		Color = Color3.fromRGB(255, 205, 70),
		Weights = { Rare = 40, Epic = 40, Legendary = 17, Mythic = 3 },
		CoinMinutes = 12,
	},
}

local byId: { [string]: Chest } = {}
for _, chest in chests do
	byId[chest.Id] = chest
end

return {
	Chests = chests,
	ById = byId,
	-- Boss : chance de lâcher l'arme du boss, + chance de coffre. Augmente avec la contribution.
	BossWeaponChance = 0.06,
	BossWeaponPityStep = 0.02, -- +2 % cumulés par boss sans arme (jusqu'à BossWeaponPityCap)
	BossWeaponPityCap = 0.5,
	BossChestChance = 0.6,
	BossChestId = "Silver",
}
