--!strict
--[[
	Products — monétisation. Les identifiants Roblox (0 ici) se renseignent après création des
	Game Passes / Developer Products sur le Creator Hub. Principes :
	  * rien ne vend de dégâts bruts ni de niveaux ;
	  * le total XP issu de l'argent réel est plafonné (Config/Game.PaidXPMultiplierCap) ;
	  * les cosmétiques (auras, skins de coup, emotes) n'affectent aucune statistique.
]]

export type Pass = {
	Id: string,
	Name: string,
	Desc: string,
	PassId: number,
	Effect: { Kind: string, Value: number },
}

export type DevProduct = {
	Id: string,
	Name: string,
	Desc: string,
	ProductId: number,
	Grant: { Kind: string, Value: number },
}

local passes: { Pass } = {
	{
		Id = "DoubleXP",
		Name = "2x XP",
		Desc = "Permanently doubles XP gain.",
		PassId = 0,
		Effect = { Kind = "XPMult", Value = 1 },
	},
	{
		Id = "LuckyCoins",
		Name = "Coin Magnet",
		Desc = "+50% coins from kills.",
		PassId = 0,
		Effect = { Kind = "CoinMult", Value = 0.5 },
	},
	{
		Id = "ExtraPlot",
		Name = "Grand Base",
		Desc = "Doubles your base decoration slots.",
		PassId = 0,
		Effect = { Kind = "DecorSlots", Value = 6 },
	},
	{
		Id = "AuraPack",
		Name = "Aura Pack",
		Desc = "Cosmetic hit auras. No stats.",
		PassId = 0,
		Effect = { Kind = "Cosmetic", Value = 1 },
	},
}

local products: { DevProduct } = {
	{
		Id = "XPBoost15",
		Name = "XP Boost (15 min)",
		Desc = "+100% XP for 15 minutes.",
		ProductId = 0,
		Grant = { Kind = "XPBoostMinutes", Value = 15 },
	},
	{
		Id = "CoinPackS",
		Name = "Coin Pack",
		Desc = "30 minutes of coin income.",
		ProductId = 0,
		Grant = { Kind = "CoinMinutes", Value = 30 },
	},
	{
		Id = "CoinPackL",
		Name = "Big Coin Pack",
		Desc = "180 minutes of coin income.",
		ProductId = 0,
		Grant = { Kind = "CoinMinutes", Value = 180 },
	},
}

local passById: { [string]: Pass } = {}
for _, pass in passes do
	passById[pass.Id] = pass
end
local productById: { [string]: DevProduct } = {}
for _, product in products do
	productById[product.Id] = product
end

return {
	Passes = passes,
	Products = products,
	PassById = passById,
	ProductById = productById,
}
