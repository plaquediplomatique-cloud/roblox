--!strict
--[[
	MapBuilder — instancie un blueprint MapKit en Model Roblox jouable.

	* Une Part par primitive, ancrée, CanTouch désactivé (aucun coût d'événements Touched),
	  regroupées par dossier logique (Floor, Geometry, Cover, Trim, Props, Lights, Markers).
	* Tags CollectionService + attributs pour tout ce que le gameplay doit retrouver :
	  SpawnPoint, SpawnBarrier, SiteZone, CalloutZone, HubTerminal, WeaponPedestal,
	  BotAnchor, TrainingZone, LeaderboardDisplay, KillVolume…
	* Filtrage par mode : barrières de mode, spawns et sites spécifiques (Monolith).
	* Validation automatique (Studio) : aucune ligne de vue entre spawns adverses, chaque
	  spawn a un sol sous les pieds. Un level designer est averti dès le lancement.
	* Streaming : la carte d'un match est "Persistent" (toujours chargée chez les joueurs :
	  équité compétitive), ou "PersistentPerPlayer" pour les arènes locales.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Util.Logger)
local Theme = require(Shared.Config.Theme)
local MapKit = require(script.Parent.MapKit)

local log = Logger.new("MapBuilder")

export type Blueprint = {
	id: string,
	build: (kit: MapKit.Kit) -> (),
	intro: { CFrame },
	overview: CFrame,
}

export type Zone = {
	name: string,
	cframe: CFrame,
	size: Vector3,
}

export type MapInstance = {
	id: string,
	model: Model,
	origin: CFrame,
	spawns: { [string]: { CFrame } },
	sites: { [string]: Zone },
	callouts: { Zone },
	barriers: { BasePart },
	intro: { CFrame },
	overview: CFrame,
	killY: number,
}

local MapBuilder = {}

local function modeAllowed(modesAttribute: any, modeId: string?): boolean
	if type(modesAttribute) ~= "string" or modesAttribute == "" then
		return true
	end
	if modeId == nil then
		return false
	end
	for mode in string.gmatch(modesAttribute, "[^,]+") do
		if mode == modeId then
			return true
		end
	end
	return false
end

local function resolveMaterial(name: string): Enum.Material
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and material then
		return material :: Enum.Material
	end
	return Enum.Material.SmoothPlastic
end

local function createPart(prim: MapKit.Prim): BasePart
	local part: BasePart
	if prim.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if prim.shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		elseif prim.shape == "Ball" then
			block.Shape = Enum.PartType.Ball
		end
		part = block
	end
	part.Name = prim.name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = prim.collide
	part.CanQuery = prim.query
	part.CastShadow = prim.shadow
	part.Material = resolveMaterial(prim.material)
	part.Color = prim.color
	part.Transparency = prim.transparency
	part.Reflectance = prim.reflectance
	part.Size = prim.size
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function attachSign(part: BasePart, sign: MapKit.SignSpec)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = (Enum.NormalId :: any)[sign.face] :: Enum.NormalId
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.ZOffset = 0.05
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = sign.background
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.TextColor3 = sign.color
	label.FontFace = Theme.fonts.display
	label.TextScaled = true
	label.Text = sign.text
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = sign.color
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
end

local function attachLight(part: BasePart, spec: MapKit.LightSpec)
	if spec.kind == "Point" then
		local light = Instance.new("PointLight")
		light.Color = spec.color
		light.Brightness = spec.brightness
		light.Range = spec.range
		light.Shadows = spec.shadows
		light.Parent = part
	elseif spec.kind == "Spot" then
		local light = Instance.new("SpotLight")
		light.Color = spec.color
		light.Brightness = spec.brightness
		light.Range = spec.range
		light.Shadows = spec.shadows
		light.Angle = spec.angle or 90
		light.Face = (Enum.NormalId :: any)[spec.face or "Bottom"] :: Enum.NormalId
		light.Parent = part
	else
		local light = Instance.new("SurfaceLight")
		light.Color = spec.color
		light.Brightness = spec.brightness
		light.Range = spec.range
		light.Shadows = spec.shadows
		light.Angle = spec.angle or 120
		light.Face = (Enum.NormalId :: any)[spec.face or "Bottom"] :: Enum.NormalId
		light.Parent = part
	end
end

local function attachPrompt(part: BasePart, label: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = label
	prompt.ObjectText = "AETHER"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = part
end

local function validate(instance: MapInstance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { instance.model }
	local attack: { CFrame } = instance.spawns.Attack or {}
	local defense: { CFrame } = instance.spawns.Defense or {}
	for _, a in attack do
		for _, d in defense do
			local eyeA = a.Position + Vector3.new(0, 1.7, 0)
			local eyeD = d.Position + Vector3.new(0, 1.7, 0)
			if Workspace:Raycast(eyeA, eyeD - eyeA, params) == nil then
				log:warn(("[%s] ligne de vue directe entre spawns adverses %s <-> %s"):format(instance.id, tostring(a.Position), tostring(d.Position)))
			end
		end
	end
	for side, list in instance.spawns do
		for _, spawnCFrame in list do
			if Workspace:Raycast(spawnCFrame.Position, Vector3.new(0, -8, 0), params) == nil then
				log:warn(("[%s] spawn %s sans sol : %s"):format(instance.id, side, tostring(spawnCFrame.Position)))
			end
		end
	end
end

function MapBuilder.build(blueprint: Blueprint, origin: CFrame, parent: Instance, modeId: string?): MapInstance
	local started = os.clock()
	local kit = MapKit.new()
	blueprint.build(kit)

	local model = Instance.new("Model")
	model.Name = "Map_" .. blueprint.id
	model:SetAttribute("MapId", blueprint.id)
	model:SetAttribute("Mode", modeId or "")
	local folders: { [string]: Folder } = {}
	local function folderFor(group: string): Folder
		local folder = folders[group]
		if not folder then
			local created = Instance.new("Folder")
			created.Name = group
			created.Parent = model
			folders[group] = created
			return created
		end
		return folder
	end

	-- Spawns spécifiques au mode : s'il en existe pour un côté, ils remplacent les autres.
	local modeSpecificSides: { [string]: boolean } = {}
	for _, prim in kit.prims do
		if table.find(prim.tags, "SpawnPoint") and prim.attributes.Modes ~= nil and modeAllowed(prim.attributes.Modes, modeId) then
			modeSpecificSides[prim.attributes.Side] = true
		end
	end

	local instance: MapInstance = {
		id = blueprint.id,
		model = model,
		origin = origin,
		spawns = {},
		sites = {},
		callouts = {},
		barriers = {},
		intro = {},
		overview = origin * blueprint.overview,
		killY = origin.Position.Y - 30,
	}

	for _, prim in kit.prims do
		local isSpawn = table.find(prim.tags, "SpawnPoint") ~= nil
		local isModeBarrier = table.find(prim.tags, "ModeBarrier") ~= nil
		local isSite = table.find(prim.tags, "SiteZone") ~= nil
		if isModeBarrier and not modeAllowed(prim.attributes.Modes, modeId) then
			continue
		end
		if isSite and prim.attributes.Modes ~= nil and not modeAllowed(prim.attributes.Modes, modeId) then
			continue
		end
		if isSpawn then
			local side = prim.attributes.Side
			local specific = prim.attributes.Modes ~= nil
			if specific and not modeAllowed(prim.attributes.Modes, modeId) then
				continue
			end
			if not specific and modeSpecificSides[side] then
				continue
			end
		end

		local part = createPart(prim)
		local worldCFrame = origin * prim.cframe
		part.CFrame = worldCFrame
		for key, value in prim.attributes do
			part:SetAttribute(key, value)
		end
		for _, tag in prim.tags do
			part:AddTag(tag)
		end
		if prim.sign then
			attachSign(part, prim.sign)
		end
		if prim.light then
			attachLight(part, prim.light)
		end
		if table.find(prim.tags, "HubTerminal") then
			attachPrompt(part, tostring(prim.attributes.Label or "Interagir"))
		end
		part.Parent = folderFor(prim.group)

		if isSpawn then
			local side = tostring(prim.attributes.Side)
			local list = instance.spawns[side] or {}
			table.insert(list, worldCFrame)
			instance.spawns[side] = list
		elseif isSite then
			instance.sites[tostring(prim.attributes.Site)] = { name = tostring(prim.attributes.Site), cframe = worldCFrame, size = prim.size }
		elseif table.find(prim.tags, "CalloutZone") then
			table.insert(instance.callouts, { name = tostring(prim.attributes.Callout), cframe = worldCFrame, size = prim.size })
		elseif table.find(prim.tags, "SpawnBarrier") then
			table.insert(instance.barriers, part)
		end
	end

	for _, keyframe in blueprint.intro do
		table.insert(instance.intro, origin * keyframe)
	end

	model.Parent = parent
	if RunService:IsStudio() then
		validate(instance)
	end
	log:info(("carte %s construite (%d parts, %.0f ms)"):format(blueprint.id, #kit.prims, (os.clock() - started) * 1000))
	return instance
end

--[[ Zone (CFrame + taille) contenant-elle un point ? (sites, callouts, zones) ]]
function MapBuilder.contains(zone: Zone, position: Vector3): boolean
	local localPoint = zone.cframe:PointToObjectSpace(position)
	local half = zone.size * 0.5
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

--[[ Active / désactive les barrières de spawn (phase de préparation). ]]
function MapBuilder.setBarriers(instance: MapInstance, active: boolean)
	for _, barrier in instance.barriers do
		barrier.CanCollide = active
		barrier.CanQuery = active
		barrier.Transparency = if active then 0.2 else 1
	end
end

return MapBuilder
