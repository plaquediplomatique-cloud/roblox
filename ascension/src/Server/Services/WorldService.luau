--!strict
--[[
	WorldService — construit le monde par code : village central et 9 royaumes, chacun avec
	son sol, ses mannequins de terrain, son arène de boss, son décor semé (props modulaires),
	ses portails. Déterministe (graine par zone) : le monde est identique à chaque lancement.

	Budget (cf. roblox-render-performance) : pièces ancrées sans collision sauf les grosses,
	petites pièces sans ombre, décor limité à `SCATTER_COUNT` modèles par zone ; le streaming
	de Workspace décharge ce qui est loin du joueur.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Builder = require(Shared.Assets.Builder)
local Props = require(Shared.Assets.Props)
local Spec = require(Shared.Assets.Spec)
local Zones = require(Shared.Config.Zones)
local ZoneLayout = require(Shared.Rules.ZoneLayout)
local BaseLayout = require(Shared.Rules.BaseLayout)
local NumberFormat = require(Shared.Rules.NumberFormat)
local DummyService = require(script.Parent.DummyService)

local WorldService = {}

local SCATTER_COUNT = 46
local VILLAGE_SCATTER = 90

local worldFolder: Folder? = nil

-- Repère « face au centre » : -Z regarde `target`.
local function facing(position: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	local back = flat.Unit
	return CFrame.fromMatrix(position, Vector3.yAxis:Cross(back), Vector3.yAxis, back)
end

WorldService.facing = facing

local function place(model: Model, cframe: CFrame, scale: number?, parent: Instance)
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(cframe)
	model.Parent = parent
end

local function addProp(
	name: string,
	palette: Spec.Palette,
	seed: number,
	cframe: CFrame,
	scale: number?,
	parent: Instance
)
	local model = Builder.model(name, Props.build(name, palette, seed))
	place(model, cframe, scale, parent)
	return model
end

local function addSpecs(specs: { Spec.Spec }, parent: Instance)
	for _, spec in specs do
		Builder.part(spec).Parent = parent
	end
end

local function billboard(adornee: BasePart, lines: { string }, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(240, 20 + 24 * #lines)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 24)
		label.Position = UDim2.fromOffset(0, (i - 1) * 24)
		label.Font = if i == 1 then Enum.Font.FredokaOne else Enum.Font.GothamMedium
		label.TextSize = if i == 1 then 22 else 15
		label.TextColor3 = if i == 1 then color else Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Text = line
		label.Parent = gui
	end
	gui.Parent = adornee
end

---------------------------------------------------------------------------------------------
-- Sol, bordure, îlots flottants
---------------------------------------------------------------------------------------------

local function buildGround(zone: Zones.Zone, parent: Folder)
	local center = ZoneLayout.center(zone.Index)
	local radius = ZoneLayout.radius(zone.Index)
	local pal = zone.Palette
	local ground = Spec.cyl(4, radius * 2, center + Vector3.new(0, -2, 0), pal.Ground, {
		Name = "Ground",
		Material = zone.Material,
		Collide = true,
		Shadow = false,
	})
	local skirt = Spec.cyl(1.2, radius * 2 + 6, center + Vector3.new(0, -3.4, 0), pal.Prop, {
		Name = "Skirt",
		Material = Enum.Material.Slate,
		Collide = true,
		Shadow = false,
	})
	local glow = Spec.cyl(0.4, radius * 2 + 7, center + Vector3.new(0, -3.9, 0), pal.Accent, {
		Name = "EdgeGlow",
		Neon = true,
		Shadow = false,
	})
	addSpecs({ ground, skirt, glow }, parent)
	-- Anneau intérieur décoratif (sentier circulaire) autour du champ de mannequins.
	local path = Spec.cyl(0.12, radius * 0.9, center + Vector3.new(0, 0.05, 0), pal.Prop:Lerp(pal.Glow, 0.15), {
		Name = "PlazaTile",
		Material = Enum.Material.Cobblestone,
		Shadow = false,
	})
	addSpecs({ path }, parent)
	-- Dessous des royaumes flottants : pierre en cône.
	if ZoneLayout.Altitude[zone.Index] > 0 then
		local under: { Spec.Spec } = {}
		for i = 1, 5 do
			table.insert(
				under,
				Spec.cyl(
					16,
					radius * 2 * (1 - i * 0.17),
					center + Vector3.new(0, -4 - i * 15, 0),
					pal.Prop:Lerp(Color3.new(0, 0, 0), 0.2 + i * 0.08),
					{ Name = "Under" .. i, Material = Enum.Material.Slate, Collide = i == 1, Shadow = false }
				)
			)
		end
		addSpecs(under, parent)
	end
end

---------------------------------------------------------------------------------------------
-- Décor semé
---------------------------------------------------------------------------------------------

local function scatter(zone: Zones.Zone, parent: Folder, count: number, minRadius: number, maxRadius: number)
	local rng = Random.new(zone.Index * 7919)
	local center = ZoneLayout.center(zone.Index)
	local palette = Props.zonePalette(zone.Palette)
	local arena = ZoneLayout.bossArena(zone.Index)
	local spawn = ZoneLayout.spawn(zone.Index).Position
	local dummies = ZoneLayout.dummyPositions(zone.Index)
	local propsFolder = Instance.new("Folder")
	propsFolder.Name = "Scatter"
	local placed = 0
	local attempts = 0
	while placed < count and attempts < count * 12 do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber(minRadius * minRadius, maxRadius * maxRadius))
		local position = center + Vector3.new(math.sin(angle) * distance, 0, math.cos(angle) * distance)
		local flatArena = Vector3.new(position.X - arena.X, 0, position.Z - arena.Z).Magnitude
		local flatSpawn = Vector3.new(position.X - spawn.X, 0, position.Z - spawn.Z).Magnitude
		local clear = flatArena > 34 and flatSpawn > 22
		for _, dummyPosition in dummies do
			if (Vector3.new(position.X - dummyPosition.X, 0, position.Z - dummyPosition.Z)).Magnitude < 14 then
				clear = false
			end
		end
		if clear then
			local name = zone.Scatter[rng:NextInteger(1, #zone.Scatter)]
			local scale = rng:NextNumber(0.9, 1.5)
			local yaw = rng:NextNumber(0, math.pi * 2)
			addProp(
				name,
				palette,
				rng:NextInteger(1, 10000),
				CFrame.new(position) * CFrame.Angles(0, yaw, 0),
				scale,
				propsFolder
			)
			placed += 1
		end
	end
	propsFolder.Parent = parent
end

---------------------------------------------------------------------------------------------
-- Dummies, arène, portails
---------------------------------------------------------------------------------------------

local function buildDummyField(zone: Zones.Zone, parent: Folder)
	local center = ZoneLayout.center(zone.Index)
	local palette = Props.zonePalette(zone.Palette)
	for _, position in ZoneLayout.dummyPositions(zone.Index) do
		DummyService.create({
			Kind = "Field",
			ZoneIndex = zone.Index,
			Pivot = facing(position, center),
		})
	end
	-- Anneau lumineux au centre du champ (repère visuel de la zone d'entraînement).
	local ring =
		Spec.cyl(0.2, if zone.Index == 1 then 130 else 84, center + Vector3.new(0, 0.15, 0), zone.Palette.Accent, {
			Name = "TrainingRing",
			Neon = true,
			Transparency = 0.55,
			Shadow = false,
		})
	Builder.part(ring).Parent = parent
	if zone.Index == 1 then
		addProp("Fountain", palette, 1, CFrame.new(center), 1.4, parent)
	else
		addProp("Orb", palette, 1, CFrame.new(center), 1.6, parent)
	end
end

local function buildArena(zone: Zones.Zone, parent: Folder)
	local arena = ZoneLayout.bossArena(zone.Index)
	local center = ZoneLayout.center(zone.Index)
	local palette = Props.zonePalette(zone.Palette)
	local base = CFrame.new(arena)
	local platform = addProp("Platform", palette, 1, base, 2.2, parent)
	platform.Name = "BossPlatform"
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local offset = Vector3.new(math.sin(angle) * 24, 0, math.cos(angle) * 24)
		addProp("Pillar", palette, i, CFrame.new(arena + offset), 1.2, parent)
		addProp("Brazier", palette, i, CFrame.new(arena + offset * 0.72), 1.3, parent)
	end
	local sign = Instance.new("Part")
	sign.Name = "BossSignAnchor"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.Transparency = 1
	sign.Size = Vector3.one
	sign.Position = arena + Vector3.new(0, 34, 0)
	sign.Parent = parent
	billboard(sign, { zone.BossName, "Boss arena" }, zone.Palette.Accent, 0)
	-- Un grand décor de fond derrière l'arène.
	local back = (arena - center)
	local backDir = if back.Magnitude > 1 then back.Unit else Vector3.new(0, 0, -1)
	local landmark = if zone.Index == 1
		then "Tower"
		elseif zone.Index == 6 or zone.Index >= 8 then "Pillar"
		else "Mountain"
	addProp(landmark, palette, 3, CFrame.new(arena + backDir * 36), if landmark == "Mountain" then 1.1 else 2, parent)
end

local function buildPortals(zone: Zones.Zone, parent: Folder, onInteract: (Player, string) -> ())
	local palette = Props.zonePalette(zone.Palette)
	local spawn = ZoneLayout.spawn(zone.Index)
	local gate = addProp("Gate", palette, 1, spawn * CFrame.new(0, -3.9, 14), 1.1, parent)
	local pad = Instance.new("Part")
	pad.Name = "ReturnPortal"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = zone.Palette.Accent
	pad.Transparency = 0.4
	pad.Size = Vector3.new(9, 12, 0.6)
	pad.CFrame = spawn * CFrame.new(0, 2.1, 14)
	pad.Parent = gate
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Return Home"
	prompt.ObjectText = zone.Name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player)
		onInteract(player, "Home")
	end)
end

local function buildVillageGates(parent: Folder, onInteract: (Player, string) -> ())
	local village = Zones.List[1]
	local palette = Props.zonePalette(village.Palette)
	local count = Zones.Count - 1
	for i = 2, Zones.Count do
		local zone = Zones.List[i]
		-- Portails sur un arc au nord de la place (côté +Z, à l'intérieur de l'anneau des bases).
		local angle = math.rad(-72 + (i - 2) * (144 / (count - 1)))
		local position = Vector3.new(math.sin(angle) * 92, 0, math.cos(angle) * 92 * 0.55 - 8)
		local cframe = facing(position, Vector3.new(0, 0, 0))
		local gate = addProp("Arch", Props.zonePalette(zone.Palette), i, cframe, 1.15, parent)
		local pane = Instance.new("Part")
		pane.Name = "Portal"
		pane.Anchored = true
		pane.CanCollide = false
		pane.CanQuery = false
		pane.Material = Enum.Material.Neon
		pane.Color = zone.Palette.Glow
		pane.Transparency = 0.35
		pane.Size = Vector3.new(6.5, 8.5, 0.5)
		pane.CFrame = cframe * CFrame.new(0, 5.2, 0)
		pane.Parent = gate
		local cost = if zone.UnlockCoins > 0 then NumberFormat.compact(zone.UnlockCoins) .. " coins" else "Free"
		billboard(pane, { zone.Name, ("Level %d  ·  %s"):format(zone.MinLevel, cost) }, zone.Palette.Glow, 7)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Enter"
		prompt.ObjectText = zone.Name
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = pane
		prompt.Triggered:Connect(function(player)
			onInteract(player, zone.Id)
		end)
	end
	-- Statues de bienvenue de chaque côté de la place.
	addProp("Statue", palette, 1, CFrame.new(-30, 0, 20), 1.5, parent)
	addProp("Statue", palette, 2, CFrame.new(30, 0, 20), 1.5, parent)
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function WorldService.folder(): Folder
	assert(worldFolder, "WorldService.build n'a pas été appelé")
	return worldFolder
end

-- onInteract(player, zoneId | "Home") : invoqué par les portails (ShopService/ZoneService).
function WorldService.build(onInteract: (Player, string) -> ())
	local world = Instance.new("Folder")
	world.Name = "World"
	worldFolder = world
	for _, zone in Zones.List do
		local folder = Instance.new("Folder")
		folder.Name = zone.Id
		buildGround(zone, folder)
		buildDummyField(zone, folder)
		buildArena(zone, folder)
		if zone.Index == 1 then
			-- Place (au centre) et périphérie ; l'anneau des parcelles (BaseLayout) reste dégagé.
			scatter(zone, folder, VILLAGE_SCATTER // 2, 62, BaseLayout.Ring - BaseLayout.PlotSize)
			scatter(
				zone,
				folder,
				VILLAGE_SCATTER // 2,
				BaseLayout.Ring + BaseLayout.PlotSize,
				ZoneLayout.VillageRadius - 12
			)
			buildVillageGates(folder, onInteract)
		else
			scatter(zone, folder, SCATTER_COUNT, 14, ZoneLayout.Radius - 10)
			buildPortals(zone, folder, onInteract)
		end
		folder.Parent = world
	end
	world.Parent = workspace
end

return WorldService
