--!strict
--[[
	Daily — récompenses de connexion sur 7 jours (série). Les montants sont exprimés en
	« minutes de revenu » de la zone actuelle du joueur : la récompense reste pertinente
	du premier au dernier niveau (Rules/Economy.coinsPerMinute / xpPerMinute).
]]

export type Reward = {
	Coins: number?, -- minutes de revenu en pièces
	XP: number?, -- minutes de revenu en XP
	Chest: string?, -- identifiant de coffre (Config/Loot)
	Boost: { Kind: string, Minutes: number }?,
	Label: string,
}

local days: { Reward } = {
	{ Coins = 5, Label = "5 min of coins" },
	{ XP = 5, Label = "5 min of XP" },
	{ Coins = 10, Label = "10 min of coins" },
	{ Boost = { Kind = "XP", Minutes = 10 }, Label = "10 min XP boost" },
	{ Coins = 20, XP = 10, Label = "Coins + XP bundle" },
	{ Chest = "Silver", Label = "Silver chest" },
	{ Chest = "Golden", Coins = 30, Label = "Golden chest + coins" },
}

return {
	Days = days,
	ClaimWindowHours = 48, -- au-delà, la série retombe à 1
	CooldownHours = 20, -- une réclamation toutes les 20 h minimum (même jour calendaire UTC évité)
}
