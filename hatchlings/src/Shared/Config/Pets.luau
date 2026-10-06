--!strict
--[[
	Pets — catalogue des 8 créatures de la base (2 / 2 / 2 / 1 / 1 par rareté).

	Chaque pet est une simple description : PetFactory la transforme en modèle 3D construit
	par code (aucun asset externe). Pour ajouter un pet : une entrée ici, rien d'autre — la
	collection, le tirage et le rendu la prennent en compte automatiquement.
]]

export type EarShape = "Round" | "Long" | "Pointy" | "None"
export type TailShape = "Ball" | "Fluffy" | "None"
export type Extra = "None" | "Horn" | "Wings" | "Halo"

export type PetDef = {
	id: string,
	name: string,
	rarity: string, -- clé de Rarities.info
	body: Color3,
	belly: Color3,
	accent: Color3, -- oreilles, queue, ailes
	ears: EarShape,
	tail: TailShape,
	extra: Extra,
	size: number, -- échelle du modèle (1 = ~3.5 studs de haut)
	glow: boolean, -- étincelles + lumière douce (Epic et Legendary)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { PetDef } = {
	-- Common
	{
		id = "pebble_pup",
		name = "Pebble Pup",
		rarity = "Common",
		body = rgb(214, 190, 160),
		belly = rgb(250, 238, 220),
		accent = rgb(168, 140, 112),
		ears = "Round",
		tail = "Ball",
		extra = "None",
		size = 1,
		glow = false,
	},
	{
		id = "leaf_bun",
		name = "Leaf Bun",
		rarity = "Common",
		body = rgb(168, 226, 160),
		belly = rgb(238, 250, 226),
		accent = rgb(120, 196, 128),
		ears = "Long",
		tail = "Ball",
		extra = "None",
		size = 1,
		glow = false,
	},
	-- Uncommon
	{
		id = "peach_kit",
		name = "Peach Kit",
		rarity = "Uncommon",
		body = rgb(255, 190, 160),
		belly = rgb(255, 238, 224),
		accent = rgb(255, 150, 130),
		ears = "Pointy",
		tail = "Fluffy",
		extra = "None",
		size = 1.05,
		glow = false,
	},
	{
		id = "cloud_lamb",
		name = "Cloud Lamb",
		rarity = "Uncommon",
		body = rgb(244, 248, 255),
		belly = rgb(255, 255, 255),
		accent = rgb(200, 214, 240),
		ears = "Round",
		tail = "Fluffy",
		extra = "None",
		size = 1.05,
		glow = false,
	},
	-- Rare
	{
		id = "berry_fox",
		name = "Berry Fox",
		rarity = "Rare",
		body = rgb(214, 120, 190),
		belly = rgb(255, 232, 244),
		accent = rgb(150, 80, 160),
		ears = "Pointy",
		tail = "Fluffy",
		extra = "None",
		size = 1.1,
		glow = false,
	},
	{
		id = "moon_owl",
		name = "Moon Owl",
		rarity = "Rare",
		body = rgb(132, 150, 236),
		belly = rgb(226, 232, 255),
		accent = rgb(86, 100, 190),
		ears = "None",
		tail = "None",
		extra = "Wings",
		size = 1.1,
		glow = false,
	},
	-- Epic
	{
		id = "sun_dragon",
		name = "Sun Dragon",
		rarity = "Epic",
		body = rgb(255, 156, 80),
		belly = rgb(255, 226, 150),
		accent = rgb(255, 100, 70),
		ears = "None",
		tail = "Ball",
		extra = "Wings",
		size = 1.2,
		glow = true,
	},
	-- Legendary
	{
		id = "aurora_unicorn",
		name = "Aurora Unicorn",
		rarity = "Legendary",
		body = rgb(250, 240, 255),
		belly = rgb(255, 255, 255),
		accent = rgb(255, 170, 220),
		ears = "Pointy",
		tail = "Fluffy",
		extra = "Horn",
		size = 1.3,
		glow = true,
	},
}

local byId: { [string]: PetDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
}
