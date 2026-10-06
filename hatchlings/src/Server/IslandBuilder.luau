--!strict
--[[
	IslandBuilder — construit l'île « Mochi Meadow » par code : disque d'herbe pastel, bord
	de sable, dessous rocheux flottant, place centrale avec fontaine, 6 emplacements joueurs
	(plot d'apparition + nid), arbres en fleurs, buissons, lampes, nuages.

	Budget : ~400 parts ancrées, aucune texture ni mesh externe, tout en SmoothPlastic.
	Sol (surface supérieure) à y = 0, île centrée sur l'origine.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local IslandLayout = require(Shared.Rules.IslandLayout)
local Theme = require(Shared.Config.Theme)

export type SlotSpot = {
	index: number,
	spawnCFrame: CFrame, -- où apparaît le personnage
	nestCFrame: CFrame, -- où est posé l'œuf (sur le nid)
}

local ISLAND_RADIUS = 62
local SLOT_COUNT = 6
local SLOT_RADIUS = 34
local PLAZA_RADIUS = 14

local C = {
	grass = Color3.fromRGB(176, 228, 150),
	grassDark = Color3.fromRGB(150, 208, 132),
	sand = Color3.fromRGB(255, 232, 186),
	plaza = Color3.fromRGB(255, 244, 224),
	path = Color3.fromRGB(255, 236, 200),
	rock = Color3.fromRGB(176, 150, 170),
	rockDeep = Color3.fromRGB(140, 120, 150),
	trunk = Color3.fromRGB(190, 150, 130),
	blossom = { Color3.fromRGB(255, 183, 213), Color3.fromRGB(255, 205, 225), Color3.fromRGB(198, 236, 190) },
	flowers = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 214, 120),
		Color3.fromRGB(255, 170, 200),
		Color3.fromRGB(190, 170, 255),
	},
	hay = Color3.fromRGB(255, 220, 140),
	hayDark = Color3.fromRGB(232, 190, 110),
	water = Color3.fromRGB(150, 215, 255),
	cloud = Color3.fromRGB(255, 250, 252),
}

local IslandBuilder = {}

local function make(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	collide: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Disque horizontal : un cylindre Roblox a son axe sur X, on le couche avec une rotation en Z.
local function disc(
	parent: Instance,
	name: string,
	radius: number,
	thickness: number,
	centerY: number,
	color: Color3,
	collide: boolean
): Part
	return make(
		parent,
		name,
		Enum.PartType.Cylinder,
		Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(0, centerY, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		collide
	)
end

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	at: Vector3,
	color: Color3,
	collide: boolean
): Part
	return make(parent, name, Enum.PartType.Ball, Vector3.one * diameter, CFrame.new(at), color, collide)
end

local function at(point: IslandLayout.Point, y: number): Vector3
	return Vector3.new(point.x, y, point.z)
end

local function polar(radius: number, angle: number): Vector3
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Sol : herbe, bord de sable, dessous rocheux en marches décroissantes.
local function buildGround(root: Folder)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = root

	disc(ground, "Grass", ISLAND_RADIUS, 2, -1, C.grass, true)
	disc(ground, "SandRim", ISLAND_RADIUS + 4, 2, -1.1, C.sand, true)
	local radius, y = ISLAND_RADIUS + 1, -2.1
	for i, shrink in { 0.92, 0.78, 0.6, 0.4, 0.2 } do
		local r = (ISLAND_RADIUS + 1) * shrink
		disc(ground, "Rock" .. i, r, 6, y - 3, if i % 2 == 0 then C.rockDeep else C.rock, false)
		y -= 5
		radius = r
	end
	ball(ground, "RockTip", radius * 1.2, Vector3.new(0, y - 4, 0), C.rockDeep, false)

	-- place centrale
	disc(ground, "Plaza", PLAZA_RADIUS, 0.3, 0.05, C.plaza, true)
	disc(ground, "PlazaRing", PLAZA_RADIUS - 2.2, 0.34, 0.07, C.path, false)
end

-- Fontaine centrale (vasque, eau, jet).
local function buildFountain(root: Folder)
	local fountain = Instance.new("Folder")
	fountain.Name = "Fountain"
	fountain.Parent = root

	disc(fountain, "Basin", 6, 1.2, 0.8, C.plaza, true)
	local water = disc(fountain, "Water", 5.2, 0.2, 1.45, C.water, false)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.25
	make(
		fountain,
		"Pillar",
		Enum.PartType.Cylinder,
		Vector3.new(4.5, 1.6, 1.6),
		CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.plaza,
		true
	)
	local top = ball(fountain, "Orb", 2.6, Vector3.new(0, 5.8, 0), C.water, false)
	top.Material = Enum.Material.Neon
	top.Transparency = 0.2

	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.LightEmission = 0.5
	spray.Rate = 14
	spray.Lifetime = NumberRange.new(1.2, 1.8)
	spray.Speed = NumberRange.new(5, 8)
	spray.Acceleration = Vector3.new(0, -14, 0)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.Size = NumberSequence.new(0.5, 0.1)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = top
end

-- Un emplacement : plot pastel (apparition) + nid de paille (œuf) à côté.
local function buildSlot(root: Folder, slot: IslandLayout.Slot): SlotSpot
	local folder = Instance.new("Folder")
	folder.Name = "Slot" .. slot.index
	folder.Parent = root

	local pastel = Theme.slotPastels[(slot.index - 1) % #Theme.slotPastels + 1]
	local look = Vector3.new(slot.look.x, 0, slot.look.z)
	local spawnAt = at(slot.spawn, 0)

	local pad = make(
		folder,
		"SpawnPad",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, 8, 8),
		CFrame.new(spawnAt + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		pastel,
		true
	)
	pad.CanCollide = true
	disc(folder, "PadShadow", 4.4, 0.2, 0.12, C.plaza, false).Position = spawnAt + Vector3.new(0, 0.12, 0)

	-- chemin plaza → plot
	local from = polar(PLAZA_RADIUS - 1, math.atan2(slot.spawn.z, slot.spawn.x))
	local length = (spawnAt - from).Magnitude
	make(
		folder,
		"Path",
		Enum.PartType.Block,
		Vector3.new(4.5, 0.2, length),
		CFrame.lookAt((from + spawnAt) / 2 + Vector3.new(0, 0.12, 0), spawnAt + Vector3.new(0, 0.12, 0)),
		C.path,
		false
	)

	-- nid : socle de paille + couronne de boules
	local nestPos = at(slot.nest, 0)
	local base = disc(folder, "NestBase", 4, 0.7, 0.3, C.hay, true)
	base.Position = nestPos + Vector3.new(0, 0.3, 0)
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2
		ball(
			folder,
			"Straw",
			1.4,
			nestPos + Vector3.new(math.cos(angle) * 3.7, 0.9, math.sin(angle) * 3.7),
			if i % 2 == 0 then C.hay else C.hayDark,
			false
		)
	end

	return {
		index = slot.index,
		spawnCFrame = CFrame.lookAt(spawnAt + Vector3.new(0, 3.2, 0), spawnAt + Vector3.new(0, 3.2, 0) + look),
		nestCFrame = CFrame.new(nestPos + Vector3.new(0, 0.65, 0)),
	}
end

local function buildTree(parent: Instance, position: Vector3, scale: number, random: Random)
	local tree = Instance.new("Model")
	tree.Name = "Tree"
	tree.Parent = parent
	local trunkHeight = 7 * scale
	make(
		tree,
		"Trunk",
		Enum.PartType.Cylinder,
		Vector3.new(trunkHeight, 1.5 * scale, 1.5 * scale),
		CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.trunk,
		true
	)
	local color = C.blossom[random:NextInteger(1, #C.blossom)]
	local top = position + Vector3.new(0, trunkHeight + 2 * scale, 0)
	ball(tree, "Canopy", 9 * scale, top, color, false)
	ball(tree, "Canopy", 6.5 * scale, top + Vector3.new(3 * scale, -1.2 * scale, 1.5 * scale), color, false)
	ball(tree, "Canopy", 6 * scale, top + Vector3.new(-2.5 * scale, -1 * scale, -2 * scale), color, false)
end

local function buildScenery(root: Folder, slots: { IslandLayout.Slot })
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = root
	local random = Random.new(7)

	-- arbres en fleurs entre les emplacements
	for k = 0, 11 do
		local angle = math.rad(15 + 30 * k)
		buildTree(scenery, polar(50 + random:NextNumber(-2, 2), angle), random:NextNumber(0.85, 1.2), random)
	end

	-- buissons du bord (collision) + murs invisibles : on ne tombe pas de l'île
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = root
	for i = 0, 35 do
		local angle = i / 36 * math.pi * 2
		local rim = polar(ISLAND_RADIUS - 1, angle)
		ball(scenery, "Bush", 4.4, rim + Vector3.new(0, 1.6, 0), C.grassDark, true)
		local wallPos = polar(ISLAND_RADIUS + 0.5, angle) + Vector3.new(0, 18, 0)
		local wall = make(
			walls,
			"Wall",
			Enum.PartType.Block,
			Vector3.new(12, 40, 2),
			CFrame.lookAt(wallPos, Vector3.new(0, 18, 0)),
			C.grass,
			true
		)
		wall.Transparency = 1
	end

	-- fleurs : on évite les plots, les nids et la place
	local function blocked(x: number, z: number): boolean
		if math.sqrt(x * x + z * z) < PLAZA_RADIUS + 2 then
			return true
		end
		for _, slot in slots do
			if IslandLayout.distance({ x = x, z = z }, slot.spawn) < 6 then
				return true
			end
			if IslandLayout.distance({ x = x, z = z }, slot.nest) < 6 then
				return true
			end
		end
		return false
	end
	local placed = 0
	while placed < 70 do
		local r = math.sqrt(random:NextNumber(0, 1)) * (ISLAND_RADIUS - 6)
		local a = random:NextNumber(0, math.pi * 2)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if not blocked(x, z) then
			placed += 1
			local color = C.flowers[random:NextInteger(1, #C.flowers)]
			ball(scenery, "Flower", 0.9, Vector3.new(x, 0.35, z), color, false)
			ball(scenery, "FlowerHeart", 0.4, Vector3.new(x, 0.62, z), Color3.fromRGB(255, 200, 90), false)
		end
	end

	-- lampes douces entre les chemins
	for k = 0, 5 do
		local angle = math.rad(30 + 60 * k)
		local base = polar(22, angle)
		make(
			scenery,
			"LampPost",
			Enum.PartType.Cylinder,
			Vector3.new(6, 0.5, 0.5),
			CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			C.rockDeep,
			true
		)
		local bulb = ball(scenery, "LampBulb", 1.8, base + Vector3.new(0, 6.4, 0), Color3.fromRGB(255, 226, 170), false)
		bulb.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 214, 160)
		light.Range = 20
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = bulb
	end

	-- nuages décoratifs autour de l'île
	for _ = 1, 10 do
		local center = polar(random:NextNumber(85, 150), random:NextNumber(0, math.pi * 2))
			+ Vector3.new(0, random:NextNumber(-30, 40), 0)
		for puff = 1, 3 do
			local cloud = ball(
				scenery,
				"Cloud",
				random:NextNumber(14, 24),
				center + Vector3.new((puff - 2) * 11, random:NextNumber(-2, 2), random:NextNumber(-4, 4)),
				C.cloud,
				false
			)
			cloud.Transparency = 0.08
		end
	end
end

function IslandBuilder.build(): { SlotSpot }
	local old = workspace:FindFirstChild("Island")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Island"

	local slots = IslandLayout.slots(SLOT_COUNT, SLOT_RADIUS)
	local spots: { SlotSpot } = {}

	buildGround(root)
	buildFountain(root)
	for _, slot in slots do
		table.insert(spots, buildSlot(root, slot))
	end
	buildScenery(root, slots)

	root.Parent = workspace
	return spots
end

IslandBuilder.slotCount = SLOT_COUNT

return IslandBuilder
