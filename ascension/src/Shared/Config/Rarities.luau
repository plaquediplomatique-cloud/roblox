--!strict
--[[
	Raretés — du Common au Godly. Une rareté pilote le VISUEL et le SON d'une arme (jamais
	les dégâts, qui viennent de son palier `Tier`). `Fx` est un BUDGET : le client ne dépasse
	jamais ces nombres, quel que soit le nombre de joueurs.
]]

export type Fx = {
	Emit: number, -- particules par impact (budget)
	Trail: boolean, -- traînée pendant le coup
	Aura: boolean, -- particules permanentes sur l'arme
	Light: boolean, -- petite lumière sur l'arme
	Shake: number, -- 0..1 intensité de caméra sur un coup
}

export type Rarity = {
	Id: string,
	Name: string,
	Order: number,
	Color: Color3,
	Accent: Color3,
	Fx: Fx,
	Pity: number?, -- nombre de tirages avant garantie (table de butin)
}

local list: { Rarity } = {
	{
		Id = "Common",
		Name = "Common",
		Order = 1,
		Color = Color3.fromRGB(176, 128, 86),
		Accent = Color3.fromRGB(222, 190, 150),
		Fx = { Emit = 3, Trail = false, Aura = false, Light = false, Shake = 0.1 },
	},
	{
		Id = "Uncommon",
		Name = "Uncommon",
		Order = 2,
		Color = Color3.fromRGB(86, 194, 113),
		Accent = Color3.fromRGB(176, 240, 190),
		Fx = { Emit = 4, Trail = false, Aura = false, Light = false, Shake = 0.15 },
	},
	{
		Id = "Rare",
		Name = "Rare",
		Order = 3,
		Color = Color3.fromRGB(62, 142, 247),
		Accent = Color3.fromRGB(170, 210, 255),
		Fx = { Emit = 6, Trail = true, Aura = false, Light = false, Shake = 0.22 },
	},
	{
		Id = "Epic",
		Name = "Epic",
		Order = 4,
		Color = Color3.fromRGB(162, 92, 255),
		Accent = Color3.fromRGB(214, 180, 255),
		Fx = { Emit = 8, Trail = true, Aura = false, Light = true, Shake = 0.3 },
	},
	{
		Id = "Legendary",
		Name = "Legendary",
		Order = 5,
		Color = Color3.fromRGB(255, 201, 60),
		Accent = Color3.fromRGB(255, 240, 170),
		Fx = { Emit = 10, Trail = true, Aura = true, Light = true, Shake = 0.4 },
	},
	{
		Id = "Mythic",
		Name = "Mythic",
		Order = 6,
		Color = Color3.fromRGB(255, 77, 77),
		Accent = Color3.fromRGB(255, 170, 150),
		Fx = { Emit = 12, Trail = true, Aura = true, Light = true, Shake = 0.5 },
	},
	{
		Id = "Divine",
		Name = "Divine",
		Order = 7,
		Color = Color3.fromRGB(120, 235, 255),
		Accent = Color3.fromRGB(235, 255, 255),
		Fx = { Emit = 14, Trail = true, Aura = true, Light = true, Shake = 0.6 },
	},
	{
		Id = "Cosmic",
		Name = "Cosmic",
		Order = 8,
		Color = Color3.fromRGB(150, 90, 255),
		Accent = Color3.fromRGB(255, 120, 230),
		Fx = { Emit = 16, Trail = true, Aura = true, Light = true, Shake = 0.7 },
	},
	{
		Id = "Secret",
		Name = "Secret",
		Order = 9,
		Color = Color3.fromRGB(255, 122, 26),
		Accent = Color3.fromRGB(255, 220, 120),
		Fx = { Emit = 18, Trail = true, Aura = true, Light = true, Shake = 0.85 },
		Pity = 40,
	},
	{
		Id = "Godly",
		Name = "Godly",
		Order = 10,
		Color = Color3.fromRGB(255, 217, 94),
		Accent = Color3.fromRGB(255, 255, 255),
		Fx = { Emit = 20, Trail = true, Aura = true, Light = true, Shake = 1 },
		Pity = 80,
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.Id] = rarity
end

return {
	List = list,
	ById = byId,
}
