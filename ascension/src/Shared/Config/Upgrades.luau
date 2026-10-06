--!strict
--[[
	Upgrades — améliorations permanentes achetées avec des pièces (le « puits » principal).
	Coût du niveau n (0-indexé) = BaseCost * Growth^n, arrondi (voir Rules/Upgrades).
	Effet cumulé = Per * niveau (additif), appliqué par Rules/Combat et Rules/Economy.
]]

export type Upgrade = {
	Id: string,
	Name: string,
	Desc: string,
	Max: number,
	BaseCost: number,
	Growth: number,
	Per: number,
	Format: string, -- "pct" | "mult" | "flat"
	Icon: string,
}

local list: { Upgrade } = {
	{
		Id = "Power",
		Name = "Power",
		Desc = "+10% damage per level",
		Max = 100,
		BaseCost = 40,
		Growth = 1.15,
		Per = 0.10,
		Format = "pct",
		Icon = "P",
	},
	{
		Id = "Speed",
		Name = "Hit Speed",
		Desc = "+1.5% swing speed per level",
		Max = 40,
		BaseCost = 75,
		Growth = 1.22,
		Per = 0.015,
		Format = "pct",
		Icon = "S",
	},
	{
		Id = "XP",
		Name = "XP Multiplier",
		Desc = "+4% XP per level",
		Max = 50,
		BaseCost = 120,
		Growth = 1.2,
		Per = 0.04,
		Format = "pct",
		Icon = "X",
	},
	{
		Id = "CritChance",
		Name = "Critical Chance",
		Desc = "+0.5% crit chance per level",
		Max = 60,
		BaseCost = 150,
		Growth = 1.18,
		Per = 0.005,
		Format = "pct",
		Icon = "C",
	},
	{
		Id = "CritDamage",
		Name = "Critical Damage",
		Desc = "+5% crit damage per level",
		Max = 60,
		BaseCost = 150,
		Growth = 1.18,
		Per = 0.05,
		Format = "pct",
		Icon = "D",
	},
	{
		Id = "Fortune",
		Name = "Fortune",
		Desc = "+5% coins per level",
		Max = 50,
		BaseCost = 100,
		Growth = 1.2,
		Per = 0.05,
		Format = "pct",
		Icon = "$",
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	byId[upgrade.Id] = upgrade
end

return { List = list, ById = byId }
