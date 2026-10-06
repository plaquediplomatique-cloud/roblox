--!strict
--[[
	EggService — cycle de vie des œufs : un œuf par joueur, posé dans son nid.

	États (attribut `State` sur le modèle) :
	  Incubating → l'œuf couve ; `StartedAt` / `ReadyAt` (temps serveur) pilotent le minuteur
	               affiché par le client ;
	  Ready      → l'œuf tremble, le ProximityPrompt « Hatch » devient utilisable.

	Le serveur reste seul juge : le prompt n'est accepté que du propriétaire, une seule fois,
	et seulement si Incubation.isReady(ReadyAt, maintenant). Le tirage se fait ici.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.Egg)
local Hatch = require(Shared.Rules.Hatch)
local Incubation = require(Shared.Rules.Incubation)
local Net = require(Shared.Net)
local PetService = require(script.Parent.PetService)
local Pets = require(Shared.Config.Pets)
local Rarities = require(Shared.Config.Rarities)
local Theme = require(Shared.Config.Theme)

type Egg = {
	owner: Player,
	model: Model,
	prompt: ProximityPrompt,
	nest: CFrame,
	rest: CFrame, -- pose de repos du modèle (la secousse pivote autour de sa base)
	ready: boolean,
	readyAt: number,
	hatching: boolean,
	shake: number, -- phase de la secousse
}

local eggs: { [Player]: Egg } = {}
local deliveredFirst: { [Player]: boolean } = {}
local remote: RemoteEvent
local random = Random.new()

local EggService = {}

local SHELL = Color3.fromRGB(255, 248, 232)

local function ball(model: Model, name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * diameter
	p.Position = at
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

-- Œuf pastel tacheté : grosse bille + petite bille au sommet = silhouette d'œuf.
local function buildEggModel(nest: CFrame, accent: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Egg"
	local base = nest.Position
	local shell = ball(model, "Shell", 4.6, base + Vector3.new(0, 2.3, 0), SHELL)
	shell.CanQuery = true -- cible du ProximityPrompt
	ball(model, "Top", 3.4, base + Vector3.new(0, 4.1, 0), SHELL)
	local spots: { { at: Vector3, size: number } } = {
		{ at = Vector3.new(1.5, 2.2, -1.9), size = 1.1 },
		{ at = Vector3.new(-1.9, 3.0, -1.2), size = 0.9 },
		{ at = Vector3.new(0.4, 4.4, -1.6), size = 0.8 },
		{ at = Vector3.new(-0.9, 1.3, -2.1), size = 0.7 },
		{ at = Vector3.new(1.4, 3.7, -1.1), size = 0.6 },
	}
	for _, spot in spots do
		ball(model, "Spot", spot.size, base + spot.at, accent)
	end
	model.PrimaryPart = shell
	return model
end

local function makePrompt(model: Model): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hatch"
	prompt.ObjectText = "Your egg"
	prompt.HoldDuration = EggConfig.promptHoldSeconds
	prompt.MaxActivationDistance = EggConfig.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = model.PrimaryPart
	return prompt
end

local function burst(position: Vector3, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(14, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Size = NumberSequence.new(1.4, 0)
	emitter.Parent = anchor
	emitter:Emit(40)
	task.delay(2, function()
		anchor:Destroy()
	end)
end

local spawnEgg

-- Éclosion : validations serveur, tirage, annonce, puis œuf suivant.
local function tryHatch(triggerer: Player, egg: Egg)
	if triggerer ~= egg.owner or egg.hatching or eggs[triggerer] ~= egg then
		return
	end
	if not Incubation.isReady(egg.readyAt, workspace:GetServerTimeNow()) then
		return
	end
	egg.hatching = true

	local weighted = {}
	local byRarity: { [string]: { string } } = {}
	for _, id in Rarities.order do
		table.insert(weighted, { id = id, weight = Rarities.info[id].weight })
		byRarity[id] = {}
	end
	for _, def in Pets.list do
		table.insert(byRarity[def.rarity], def.id)
	end
	local rarityId, petId = Hatch.roll(weighted, byRarity, random:NextNumber(), random:NextNumber())

	local origin = egg.nest.Position + Vector3.new(0, 3, 0)
	local isNew = PetService.add(egg.owner, petId, origin)
	burst(origin, Rarities.info[rarityId].color)
	remote:FireAllClients(egg.owner.Name, egg.owner.UserId, petId, isNew)

	eggs[triggerer] = nil
	egg.model:Destroy()
	task.delay(EggConfig.nextEggDelay, function()
		if egg.owner.Parent and eggs[egg.owner] == nil then
			spawnEgg(egg.owner, egg.nest)
		end
	end)
end

function spawnEgg(player: Player, nest: CFrame)
	local first = not deliveredFirst[player]
	deliveredFirst[player] = true
	local duration = if first then EggConfig.firstHatchSeconds else EggConfig.hatchSeconds
	local now = workspace:GetServerTimeNow()

	local accent = Theme.slotPastels[random:NextInteger(1, #Theme.slotPastels)]
	local model = buildEggModel(nest, accent)
	local egg: Egg = {
		owner = player,
		model = model,
		prompt = makePrompt(model),
		nest = nest,
		rest = model:GetPivot(),
		ready = false,
		readyAt = now + duration,
		hatching = false,
		shake = 0,
	}

	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("State", "Incubating")
	model:SetAttribute("StartedAt", now)
	model:SetAttribute("ReadyAt", egg.readyAt)
	model.Parent = workspace
	CollectionService:AddTag(model, Net.eggTag)
	eggs[player] = egg

	egg.prompt.Triggered:Connect(function(triggerer)
		tryHatch(triggerer, egg)
	end)
end

function EggService.give(player: Player, nest: CFrame)
	spawnEgg(player, nest)
end

function EggService.remove(player: Player)
	local egg = eggs[player]
	if egg then
		egg.model:Destroy()
	end
	eggs[player] = nil
	deliveredFirst[player] = nil
end

function EggService.start()
	local folder = Instance.new("Folder")
	folder.Name = Net.folderName
	folder.Parent = ReplicatedStorage
	remote = Instance.new("RemoteEvent")
	remote.Name = Net.petHatched
	remote.Parent = folder

	RunService.Heartbeat:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		for _, egg in eggs do
			if not egg.ready and Incubation.isReady(egg.readyAt, now) then
				egg.ready = true
				egg.model:SetAttribute("State", "Ready")
				egg.prompt.Enabled = true
			end
			if egg.ready and not egg.hatching then
				-- secousse brève toutes les ~1.6 s : « je suis prêt ! »
				egg.shake += dt
				local cycle = egg.shake % 1.6
				local angle = if cycle < 0.5 then math.sin(cycle * 40) * math.rad(9) * (1 - cycle / 0.5) else 0
				egg.model:PivotTo(
					egg.rest * CFrame.new(0, -2.3, 0) * CFrame.Angles(0, 0, angle) * CFrame.new(0, 2.3, 0)
				)
			end
		end
	end)
end

return EggService
