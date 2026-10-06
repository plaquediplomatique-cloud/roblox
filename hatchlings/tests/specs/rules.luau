--[[ Tests : incubation, tirage pondéré, emplacements, disposition de l'île. ]]

local Incubation = load("Rules/Incubation")
local Hatch = load("Rules/Hatch")
local SlotAllocator = load("Rules/SlotAllocator")
local IslandLayout = load("Rules/IslandLayout")

T.describe("Incubation", function()
	T.it("remaining ne descend jamais sous 0", function()
		T.eq(Incubation.remaining(110, 100), 10)
		T.eq(Incubation.remaining(100, 130), 0)
	end)
	T.it("isReady est vrai à l'instant exact", function()
		T.expect(not Incubation.isReady(100, 99.9))
		T.expect(Incubation.isReady(100, 100))
	end)
	T.it("progress est borné et gère une durée nulle", function()
		T.eq(Incubation.progress(0, 10, 5), 0.5)
		T.eq(Incubation.progress(0, 10, -3), 0)
		T.eq(Incubation.progress(0, 10, 99), 1)
		T.eq(Incubation.progress(5, 5, 5), 1)
	end)
	T.it("formatClock arrondit au supérieur", function()
		T.eq(Incubation.formatClock(0), "0:00")
		T.eq(Incubation.formatClock(0.2), "0:01")
		T.eq(Incubation.formatClock(7), "0:07")
		T.eq(Incubation.formatClock(65), "1:05")
	end)
end)

T.describe("Hatch", function()
	local rarities = { { id = "A", weight = 70 }, { id = "B", weight = 30 } }
	local pets = { A = { "a1", "a2" }, B = { "b1" } }

	T.it("pickWeighted respecte les bornes de chaque tranche", function()
		T.eq(Hatch.pickWeighted(rarities, 0), "A")
		T.eq(Hatch.pickWeighted(rarities, 0.699), "A")
		T.eq(Hatch.pickWeighted(rarities, 0.7), "B")
		T.eq(Hatch.pickWeighted(rarities, 1), "B")
	end)
	T.it("pickIndex couvre 1..n", function()
		T.eq(Hatch.pickIndex(2, 0), 1)
		T.eq(Hatch.pickIndex(2, 0.5), 2)
		T.eq(Hatch.pickIndex(2, 1), 2)
	end)
	T.it("roll choisit un pet dans la rareté tirée", function()
		local rarity, pet = Hatch.roll(rarities, pets, 0.9, 0.3)
		T.eq(rarity, "B")
		T.eq(pet, "b1")
		local r2, p2 = Hatch.roll(rarities, pets, 0.1, 0.6)
		T.eq(r2, "A")
		T.eq(p2, "a2")
	end)
	T.it("une rareté sans pet est ignorée", function()
		local rarity = Hatch.roll(rarities, { A = {}, B = { "b1" } }, 0.1, 0)
		T.eq(rarity, "B")
	end)
end)

T.describe("Catalogue (config réelle)", function()
	local Rarities = load("Config/Rarities")
	local Pets = load("Config/Pets")

	T.it("les poids de rareté totalisent 100", function()
		local total = 0
		for _, id in Rarities.order do
			total += Rarities.info[id].weight
		end
		T.eq(total, 100)
	end)
	T.it("chaque pet a un id unique et une rareté connue", function()
		local seen = {}
		for _, def in Pets.list do
			T.expect(not seen[def.id], "id en double : " .. def.id)
			seen[def.id] = true
			T.expect(Rarities.info[def.rarity] ~= nil, "rareté inconnue : " .. def.id)
			T.expect(def.size > 0.5 and def.size < 2, "taille hors plage : " .. def.id)
		end
	end)
	T.it("chaque rareté a au moins un pet, et plus c'est rare, moins il y en a", function()
		local counts = {}
		for _, def in Pets.list do
			counts[def.rarity] = (counts[def.rarity] or 0) + 1
		end
		local previous = math.huge
		for _, id in Rarities.order do
			T.expect((counts[id] or 0) >= 1, "aucun pet " .. id)
			T.expect(counts[id] <= previous, "trop de pets " .. id)
			previous = counts[id]
		end
	end)
	T.it("distribution simulée proche des poids (20 000 éclosions)", function()
		local weighted, byRarity = {}, {}
		for _, id in Rarities.order do
			table.insert(weighted, { id = id, weight = Rarities.info[id].weight })
			byRarity[id] = {}
		end
		for _, def in Pets.list do
			table.insert(byRarity[def.rarity], def.id)
		end
		math.randomseed(1234)
		local counts, n = {}, 20000
		for _ = 1, n do
			local rarity = Hatch.roll(weighted, byRarity, math.random(), math.random())
			counts[rarity] = (counts[rarity] or 0) + 1
		end
		for _, id in Rarities.order do
			local expected = Rarities.info[id].weight
			T.near((counts[id] or 0) / n * 100, expected, math.max(1, expected * 0.2), id)
		end
	end)
end)

T.describe("SlotAllocator", function()
	T.it("donne le plus petit emplacement libre et réutilise les trous", function()
		T.eq(SlotAllocator.acquire({}, 3), 1)
		T.eq(SlotAllocator.acquire({ true, true }, 3), 3)
		T.eq(SlotAllocator.acquire({ [1] = true, [3] = true }, 3), 2)
	end)
	T.it("renvoie nil quand le serveur est plein", function()
		T.eq(SlotAllocator.acquire({ true, true, true }, 3), nil)
	end)
end)

T.describe("IslandLayout", function()
	local radius = 34
	local slots = IslandLayout.slots(6, radius)

	T.it("les points d'apparition sont sur le cercle, équirépartis", function()
		T.eq(#slots, 6)
		local origin = { x = 0, z = 0 }
		for _, slot in slots do
			T.near(IslandLayout.distance(slot.spawn, origin), radius, 1e-6, "rayon")
		end
		local gap = IslandLayout.distance(slots[1].spawn, slots[2].spawn)
		T.near(IslandLayout.distance(slots[2].spawn, slots[3].spawn), gap, 1e-6, "écart")
		T.expect(gap > 20, "emplacements trop serrés : " .. gap)
	end)
	T.it("l'œuf est à portée du joueur mais loin des autres emplacements", function()
		for _, slot in slots do
			local own = IslandLayout.distance(slot.spawn, slot.nest)
			T.expect(own > 5 and own < 9, "nid hors plage : " .. own)
			for _, other in slots do
				if other.index ~= slot.index then
					T.expect(
						IslandLayout.distance(slot.nest, other.spawn) > own * 2,
						"nid trop proche d'un autre joueur"
					)
				end
			end
		end
	end)
	T.it("le regard est unitaire et pointe vers le centre", function()
		for _, slot in slots do
			T.near(math.sqrt(slot.look.x ^ 2 + slot.look.z ^ 2), 1, 1e-6, "norme")
			T.expect(slot.look.x * slot.spawn.x + slot.look.z * slot.spawn.z < 0, "doit regarder le centre")
		end
	end)
end)
