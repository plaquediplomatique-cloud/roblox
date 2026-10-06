--!strict
--[[
	Decor — catalogue de décoration de la base. Un objet = une recette d'assets (Shared/Assets)
	+ un prix. Les emplacements (slots) de la base sont définis par Server/Services/BaseService.
]]

export type Item = {
	Id: string,
	Name: string,
	Recipe: string, -- clé de Assets/Catalog
	Cost: number, -- pièces
	MinLevel: number,
	Category: string,
}

local function d(id: string, name: string, recipe: string, cost: number, minLevel: number, category: string): Item
	return { Id = id, Name = name, Recipe = recipe, Cost = cost, MinLevel = minLevel, Category = category }
end

local list: { Item } = {
	d("PlantPot", "Potted Plant", "Plant", 0, 1, "Plants"),
	d("Lamp", "Floor Lamp", "FloorLamp", 40, 1, "Light"),
	d("Crate", "Wooden Crate", "Crate", 60, 1, "Storage"),
	d("Barrel", "Barrel", "Barrel", 80, 2, "Storage"),
	d("Bench", "Garden Bench", "Bench", 120, 3, "Furniture"),
	d("Table", "Round Table", "Table", 200, 4, "Furniture"),
	d("Chair", "Toy Chair", "Chair", 150, 4, "Furniture"),
	d("Sofa", "Cozy Sofa", "Sofa", 600, 8, "Furniture"),
	d("Bookshelf", "Bookshelf", "Bookshelf", 500, 8, "Furniture"),
	d("Bed", "Toy Bed", "Bed", 900, 10, "Furniture"),
	d("Chest", "Treasure Chest", "ChestProp", 1500, 12, "Storage"),
	d("Flag", "Banner Flag", "Flag", 800, 10, "Banner"),
	d("Signpost", "Signpost", "Signpost", 300, 5, "Banner"),
	d("Statue", "Hero Statue", "Statue", 6000, 25, "Statues"),
	d("Trophy", "Golden Trophy", "Trophy", 12000, 30, "Statues"),
	d("Fountain", "Brick Fountain", "Fountain", 25000, 35, "Statues"),
	d("CrystalCluster", "Crystal Cluster", "CrystalProp", 15000, 30, "Nature"),
	d("PineTree", "Pine Tree", "PineTree", 2500, 15, "Nature"),
	d("FlowerBed", "Flower Bed", "FlowerBed", 700, 6, "Plants"),
	d("Anvil", "Anvil", "Anvil", 2000, 14, "Machines"),
	d("Forge", "Mini Forge", "Forge", 20000, 32, "Machines"),
	d("Generator", "Brick Generator", "Generator", 90000, 45, "Machines"),
	d("Platform", "Podium", "Podium", 3000, 18, "Statues"),
	d("NeonSign", "Neon Sign", "NeonSign", 150000, 60, "Light"),
}

local byId: { [string]: Item } = {}
for _, item in list do
	byId[item.Id] = item
end

return {
	List = list,
	ById = byId,
	BaseSlots = 6,
}
