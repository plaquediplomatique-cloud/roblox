--!strict
--[[
	Vfx — effets d'impact POOLÉS et BORNÉS (skill roblox-animation-vfx / render-performance).

	* aucun émetteur créé pendant le jeu : un pool fixe de « blocs d'impact » préchauffés, réutilisés ;
	* budget global de particules par seconde : au-delà, les effets des AUTRES joueurs sont réduits
	  (les siens restent entiers — le feeling du joueur passe avant la décoration) ;
	* le nombre de particules d'un coup vient de la rareté de l'arme (Config/Rarities.Fx.Emit) ;
	* anneaux de choc : quelques parties néon réutilisées, animées par tween.
]]

local TweenService = game:GetService("TweenService")

local Vfx = {}

local TEX = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local IMPACT_POOL = 14
local RING_POOL = 5
local BUDGET_PER_SECOND = 260

type ImpactPart = {
	Part: Part,
	Spark: ParticleEmitter,
	Flash: ParticleEmitter,
	Debris: ParticleEmitter,
	FreeAt: number,
}

local folder: Folder? = nil
local impacts: { ImpactPart } = {}
local rings: { { Part: Part, FreeAt: number } } = {}
local budgetWindowStart = 0
local budgetUsed = 0

local function newEmitter(parent: Instance, name: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Texture = TEX
	emitter.LightEmission = 0.8
	emitter.Parent = parent
	return emitter
end

local function newImpact(root: Folder): ImpactPart
	local part = Instance.new("Part")
	part.Name = "Impact"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = root

	local spark = newEmitter(part, "Spark")
	spark.Lifetime = NumberRange.new(0.25, 0.5)
	spark.Speed = NumberRange.new(14, 30)
	spark.SpreadAngle = Vector2.new(180, 180)
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	spark.Drag = 4
	spark.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })

	local flash = newEmitter(part, "Flash")
	flash.Texture = TEX_SMOKE
	flash.Lifetime = NumberRange.new(0.12, 0.2)
	flash.Speed = NumberRange.new(0, 0)
	flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	flash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	flash.LightEmission = 1

	local debris = newEmitter(part, "Debris")
	debris.LightEmission = 0.2
	debris.Lifetime = NumberRange.new(0.5, 0.9)
	debris.Speed = NumberRange.new(8, 20)
	debris.SpreadAngle = Vector2.new(60, 60)
	debris.Acceleration = Vector3.new(0, -60, 0)
	debris.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1) })
	debris.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })

	return { Part = part, Spark = spark, Flash = flash, Debris = debris, FreeAt = 0 }
end

function Vfx.start()
	local root = Instance.new("Folder")
	root.Name = "Vfx"
	root.Parent = workspace
	folder = root
	for _ = 1, IMPACT_POOL do
		table.insert(impacts, newImpact(root))
	end
	for _ = 1, RING_POOL do
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Transparency = 1
		ring.Size = Vector3.new(0.2, 1, 1)
		ring.CFrame = CFrame.new(0, -500, 0)
		ring.Parent = root
		table.insert(rings, { Part = ring, FreeAt = 0 })
	end
end

-- Budget par fenêtre d'une seconde. Renvoie le nombre de particules autorisé (<= wanted).
local function spend(wanted: number, priority: boolean): number
	local now = os.clock()
	if now - budgetWindowStart >= 1 then
		budgetWindowStart = now
		budgetUsed = 0
	end
	local remaining = BUDGET_PER_SECOND - budgetUsed
	if priority then
		budgetUsed += wanted
		return wanted
	end
	local allowed = math.max(0, math.min(wanted, remaining))
	budgetUsed += allowed
	return allowed
end

local function acquire(): ImpactPart?
	local now = os.clock()
	local oldest: ImpactPart? = nil
	for _, impact in impacts do
		if impact.FreeAt <= now then
			return impact
		end
		if oldest == nil or impact.FreeAt < oldest.FreeAt then
			oldest = impact
		end
	end
	return oldest -- pool épuisé : on recycle le plus ancien (jamais d'allocation)
end

-- Impact : `emit` = budget de la rareté ; `crit` 0/1/2 ; `local_` = effet du joueur local.
function Vfx.impact(position: Vector3, color: Color3, accent: Color3, emit: number, crit: number, local_: boolean)
	local impact = acquire()
	if not impact then
		return
	end
	local multiplier = if crit == 2 then 2.4 elseif crit == 1 then 1.6 else 1
	local count = spend(math.floor(emit * multiplier), local_)
	if count <= 0 then
		return
	end
	impact.FreeAt = os.clock() + 1.1
	impact.Part.CFrame = CFrame.new(position)
	local sequence = ColorSequence.new(color, accent)
	impact.Spark.Color = sequence
	impact.Flash.Color = ColorSequence.new(accent)
	impact.Debris.Color = ColorSequence.new(color)
	impact.Spark:Emit(count)
	impact.Flash:Emit(if crit > 0 then 2 else 1)
	impact.Debris:Emit(math.max(1, count // 3))
end

-- Anneau de choc (crit / méga / mort d'un boss).
function Vfx.ring(position: Vector3, color: Color3, size: number)
	local slot: { Part: Part, FreeAt: number }? = nil
	local now = os.clock()
	for _, candidate in rings do
		if candidate.FreeAt <= now then
			slot = candidate
			break
		end
	end
	if not slot then
		return
	end
	slot.FreeAt = now + 0.5
	local part = slot.Part
	part.Color = color
	part.Transparency = 0.2
	part.Size = Vector3.new(0.3, 2, 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(
		part,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, size, size), Transparency = 1 }
	):Play()
end

-- Gerbe de particules (mort d'un mannequin, montée de niveau).
function Vfx.burst(position: Vector3, color: Color3, accent: Color3, count: number)
	Vfx.impact(position, color, accent, count, 1, true)
end

function Vfx.folder(): Folder?
	return folder
end

return Vfx
