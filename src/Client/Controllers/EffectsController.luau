--!strict
--[[
	EffectsController — "juice" visuel, entièrement poolé.

	* Muzzle flash : sphère néon à échelle aléatoire (1 frame), lumière ponctuelle
	  (40 ms), gerbe d'étincelles, fumée de canon après tir soutenu.
	* Traceurs : segment néon qui VOYAGE à vitesse finie (lecture de la trajectoire).
	* Impacts : étincelles (métal), poussière (béton), éclats (bois/verre), gerbe
	  d'énergie (personnage) / éclat cyan (bouclier) + impact de balle persistant.
	* Douilles : simulation balistique maison (pas de physique moteur), rebond au sol.
	* Chargeurs : éjectés physiquement (groupe de collision "Effects").
	* Kill effects : Voltage, Désintégration, Shatter, Rift + flash d'élimination.
	Tout est plafonné : au-delà, le plus ancien effet est recyclé (aucune dérive mémoire).
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Pool = require(Shared.Util.Pool)

export type ImpactKind = "World" | "Character" | "Armor"

local EffectsController = {}

local folder: Folder
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"

type Tracer = {
	part: BasePart,
	from: Vector3,
	direction: Vector3,
	distance: number,
	travelled: number,
	speed: number,
	length: number,
}
type Shell = { part: BasePart, velocity: Vector3, life: number, bounced: boolean, spin: Vector3 }
type Flash = { part: BasePart, light: PointLight, life: number }

local tracers: { Tracer } = {}
local shells: { Shell } = {}
local flashes: { Flash } = {}

-- Les pools recyclent de force leur objet le plus ancien quand ils sont pleins : un
-- `task.delay` lancé pour une utilisation précédente ne doit alors plus toucher l'objet.
-- Chaque utilisation reçoit un jeton ; un rappel dont le jeton est périmé ne fait rien.
local generations: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function claim(object: Instance): number
	local token = (generations[object] or 0) + 1
	generations[object] = token
	return token
end

local function current(object: Instance, token: number): boolean
	return generations[object] == token
end

-- Plafonds des listes animées, sous la taille de leur pool (aucun recyclage forcé d'un
-- objet encore animé par une autre entrée).
local MAX_TRACERS = 56
local MAX_FLASHES = 20

local flashPool: Pool.Pool<BasePart>
local tracerPool: Pool.Pool<BasePart>
local impactPool: Pool.Pool<BasePart>
local holePool: Pool.Pool<BasePart>
local shellPool: Pool.Pool<BasePart>

local rng = Random.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function basePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	return part
end

local function emitter(
	parent: Instance,
	name: string,
	texture: string,
	color: Color3,
	size: number,
	lifetime: NumberRange,
	speed: NumberRange,
	lightEmission: number
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = lightEmission
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = lifetime
	e.Speed = speed
	e.SpreadAngle = Vector2.new(35, 35)
	e.Rate = 0
	e.Enabled = true
	e.Drag = 4
	e.Acceleration = Vector3.new(0, -30, 0)
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = parent
	return e
end

local function geometryRoots(): { Instance }
	local roots: { Instance } = {}
	for _, name in { "Arenas", "Hub" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(roots, f)
		end
	end
	return roots
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function EffectsController.muzzleFlash(cframe: CFrame, color: Color3, scale: number, smoke: boolean)
	if #flashes >= MAX_FLASHES then
		local oldest = table.remove(flashes, 1) :: Flash
		oldest.light.Enabled = false
		flashPool:release(oldest.part)
	end
	local part = flashPool:get()
	local size = scale * rng:NextNumber(0.55, 0.95)
	part.Size = Vector3.new(size, size, size * 1.6)
	part.CFrame = cframe * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
	part.Color = color
	part.Transparency = 0.1
	local light = part:FindFirstChildOfClass("PointLight") :: PointLight
	light.Color = color
	light.Enabled = true
	light.Range = 10 * scale + 6
	local sparks = part:FindFirstChild("Sparks") :: ParticleEmitter
	sparks.Color = ColorSequence.new(color)
	sparks:Emit(math.floor(4 * scale + 2))
	if smoke then
		local puff = part:FindFirstChild("Smoke") :: ParticleEmitter
		puff:Emit(2)
	end
	table.insert(flashes, { part = part, light = light, life = 0.045 })
end

function EffectsController.tracer(
	from: Vector3,
	to: Vector3,
	color: Color3,
	width: number,
	speed: number,
	length: number
)
	if width <= 0 then
		return
	end
	local offset = to - from
	local distance = offset.Magnitude
	if distance < 2 then
		return
	end
	if #tracers >= MAX_TRACERS then
		local oldest = table.remove(tracers, 1) :: Tracer
		tracerPool:release(oldest.part)
	end
	local part = tracerPool:get()
	part.Color = color
	part.Size = Vector3.new(width, width, math.min(length, distance))
	part.Transparency = 0.05
	table.insert(tracers, {
		part = part,
		from = from,
		direction = offset / distance,
		distance = distance,
		travelled = 0,
		speed = speed,
		length = math.min(length, distance),
	})
end

function EffectsController.bulletHole(position: Vector3, normal: Vector3)
	local hole = holePool:get()
	local token = claim(hole)
	hole.CFrame = CFrame.lookAt(position + normal * 0.02, position + normal * 2) * CFrame.Angles(0, math.pi / 2, 0)
	hole.Transparency = 0.15
	task.delay(10, function()
		if hole.Parent and current(hole, token) then
			TweenService:Create(hole, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			task.delay(1.6, function()
				if current(hole, token) then
					holePool:release(hole)
				end
			end)
		end
	end)
end

function EffectsController.impact(position: Vector3, normal: Vector3, material: Enum.Material, kind: ImpactKind)
	local anchor = impactPool:get()
	local token = claim(anchor)
	anchor.CFrame = CFrame.lookAt(position, position + normal)
	local sparks = anchor:FindFirstChild("Sparks") :: ParticleEmitter
	local dust = anchor:FindFirstChild("Dust") :: ParticleEmitter
	local energy = anchor:FindFirstChild("Energy") :: ParticleEmitter
	if kind == "Character" then
		energy.Color = ColorSequence.new(Color3.fromRGB(255, 70, 85))
		energy:Emit(14)
	elseif kind == "Armor" then
		energy.Color = ColorSequence.new(Color3.fromRGB(110, 200, 255))
		energy:Emit(12)
		sparks:Emit(6)
	else
		local metallic = material == Enum.Material.Metal
			or material == Enum.Material.DiamondPlate
			or material == Enum.Material.CorrodedMetal
		local soft = material == Enum.Material.Wood
			or material == Enum.Material.WoodPlanks
			or material == Enum.Material.Snow
		local glass = material == Enum.Material.Glass or material == Enum.Material.Ice
		sparks.Color = ColorSequence.new(if glass then Color3.fromRGB(200, 235, 255) else Color3.fromRGB(255, 210, 140))
		sparks:Emit(if metallic then 12 elseif glass then 10 else 4)
		dust.Color = ColorSequence.new(if soft then Color3.fromRGB(150, 120, 90) else Color3.fromRGB(150, 150, 155))
		dust:Emit(if metallic then 2 else 5)
		EffectsController.bulletHole(position, normal)
	end
	task.delay(1.2, function()
		if current(anchor, token) then
			impactPool:release(anchor)
		end
	end)
end

--[[ Impact au bout d'une trajectoire : on retrouve normale/matériau par un raycast court. ]]
function EffectsController.impactAt(origin: Vector3, endpoint: Vector3, kind: ImpactKind)
	if kind ~= "World" then
		EffectsController.impact(endpoint, (origin - endpoint).Unit, Enum.Material.Plastic, kind)
		return
	end
	rayParams.FilterDescendantsInstances = geometryRoots()
	local direction = (endpoint - origin).Unit
	local result = Workspace:Raycast(endpoint - direction * 1.5, direction * 3, rayParams)
	if result then
		EffectsController.impact(result.Position, result.Normal, result.Material, "World")
	end
end

function EffectsController.shell(cframe: CFrame, velocity: Vector3, size: number)
	local part = shellPool:get()
	part.Size = Vector3.new(size * 2.4, size, size)
	part.CFrame = cframe
	part.Transparency = 0
	table.insert(shells, {
		part = part,
		velocity = velocity,
		life = 1.6,
		bounced = false,
		spin = Vector3.new(rng:NextNumber(-20, 20), rng:NextNumber(-20, 20), rng:NextNumber(-20, 20)),
	})
	while #shells > 40 do
		local oldest = table.remove(shells, 1) :: Shell
		shellPool:release(oldest.part)
	end
end

--[[ Chargeur éjecté : copie physique du chargeur du viewmodel, qui tombe et rebondit. ]]
function EffectsController.dropMag(source: BasePart, velocity: Vector3)
	local mag = source:Clone()
	for _, child in mag:GetChildren() do
		child:Destroy()
	end
	mag.Anchored = false
	mag.CanCollide = true
	mag.Massless = false
	mag.CollisionGroup = "Effects"
	mag.Size *= 1.4
	mag.CFrame = source.CFrame
	mag.Parent = folder
	mag.AssemblyLinearVelocity = velocity
	mag.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
	task.delay(4, function()
		mag:Destroy()
	end)
end

function EffectsController.explosion(position: Vector3)
	local anchor = impactPool:get()
	local token = claim(anchor)
	anchor.CFrame = CFrame.new(position)
	local energy = anchor:FindFirstChild("Energy") :: ParticleEmitter
	energy.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70))
	energy:Emit(80)
	local sphere = basePart("Blast")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(2, 2, 2)
	sphere.CFrame = CFrame.new(position)
	sphere.Color = Color3.fromRGB(255, 200, 120)
	sphere.Transparency = 0
	sphere.Parent = folder
	TweenService:Create(sphere, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(56, 56, 56),
		Transparency = 1,
	}):Play()
	task.delay(0.7, function()
		sphere:Destroy()
		if current(anchor, token) then
			impactPool:release(anchor)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Kill effects (sur le personnage ragdollé de la victime, côté client uniquement)
---------------------------------------------------------------------------------------------

local function bodyParts(model: Model): { BasePart }
	local list = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			table.insert(list, descendant)
		end
	end
	return list
end

local function fadeOut(model: Model, duration: number)
	for _, part in bodyParts(model) do
		task.spawn(function()
			local start = os.clock()
			while os.clock() - start < duration and part.Parent do
				part.LocalTransparencyModifier = (os.clock() - start) / duration
				RunService.RenderStepped:Wait()
			end
			part.LocalTransparencyModifier = 1
		end)
	end
end

local function eliminationFlash(model: Model, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	TweenService:Create(highlight, TweenInfo.new(0.45), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	task.delay(0.5, function()
		highlight:Destroy()
	end)
end

function EffectsController.killEffect(model: Model, effectId: string, color: Color3)
	eliminationFlash(model, color)
	local parts = bodyParts(model)
	if #parts == 0 then
		return
	end
	if effectId == "ke_voltage" then
		for _ = 1, 5 do
			local a, b = parts[rng:NextInteger(1, #parts)], parts[rng:NextInteger(1, #parts)]
			local a0 = Instance.new("Attachment")
			a0.Parent = a
			local a1 = Instance.new("Attachment")
			a1.Parent = b
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Color = ColorSequence.new(Color3.fromRGB(120, 230, 255))
			beam.LightEmission = 1
			beam.Width0 = 0.25
			beam.Width1 = 0.1
			beam.Segments = 12
			beam.CurveSize0 = rng:NextNumber(-3, 3)
			beam.CurveSize1 = rng:NextNumber(-3, 3)
			beam.FaceCamera = true
			beam.Parent = a
			task.delay(0.7, function()
				a0:Destroy()
				a1:Destroy()
				beam:Destroy()
			end)
		end
	elseif effectId == "ke_disintegrate" then
		for _, part in parts do
			local e =
				emitter(part, "Dust", SPARK_TEXTURE, color, 0.35, NumberRange.new(0.6, 1.1), NumberRange.new(2, 5), 1)
			e.Acceleration = Vector3.new(0, 8, 0)
			e:Emit(8)
			task.delay(1.5, function()
				e:Destroy()
			end)
		end
		fadeOut(model, 0.9)
	elseif effectId == "ke_shatter" then
		for _, part in parts do
			for _ = 1, 2 do
				local cube = basePart("Shard")
				cube.Anchored = false
				cube.CanCollide = true
				cube.CollisionGroup = "Effects"
				cube.Size = Vector3.new(0.4, 0.4, 0.4)
				cube.Color = color
				cube.Transparency = 0
				cube.CFrame = part.CFrame * CFrame.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), 0)
				cube.Parent = folder
				cube.AssemblyLinearVelocity =
					Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(6, 20), rng:NextNumber(-14, 14))
				TweenService
					:Create(
						cube,
						TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ Transparency = 1 }
					)
					:Play()
				task.delay(1.4, function()
					cube:Destroy()
				end)
			end
		end
		fadeOut(model, 0.05)
	elseif effectId == "ke_rift" then
		local center = (model:GetPivot()).Position
		local core = basePart("Rift")
		core.Shape = Enum.PartType.Ball
		core.Material = Enum.Material.Neon
		core.Color = Color3.fromRGB(10, 0, 20)
		core.Size = Vector3.new(0.5, 0.5, 0.5)
		core.Transparency = 0
		core.CFrame = CFrame.new(center)
		core.Parent = folder
		local ring = emitter(
			core,
			"Ring",
			SPARK_TEXTURE,
			Color3.fromRGB(220, 80, 255),
			0.5,
			NumberRange.new(0.4, 0.7),
			NumberRange.new(-12, -8),
			1
		)
		ring.SpreadAngle = Vector2.new(180, 180)
		ring:Emit(60)
		TweenService:Create(
			core,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = Vector3.new(6, 6, 6) }
		):Play()
		task.delay(0.45, function()
			TweenService:Create(
				core,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = Vector3.new(0.1, 0.1, 0.1) }
			):Play()
		end)
		fadeOut(model, 0.5)
		task.delay(0.9, function()
			core:Destroy()
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Boucle
---------------------------------------------------------------------------------------------

local function update(dt: number)
	for index = #flashes, 1, -1 do
		local flash = flashes[index]
		flash.life -= dt
		if flash.life <= 0 then
			flash.light.Enabled = false
			flash.part.Transparency = 1
			flashPool:release(flash.part)
			table.remove(flashes, index)
		end
	end
	for index = #tracers, 1, -1 do
		local tracer = tracers[index]
		tracer.travelled += tracer.speed * dt
		local head = math.min(tracer.travelled, tracer.distance)
		local tail = math.max(head - tracer.length, 0)
		if tail >= tracer.distance - 0.01 then
			tracerPool:release(tracer.part)
			table.remove(tracers, index)
		else
			local mid = tracer.from + tracer.direction * ((head + tail) / 2)
			tracer.part.Size = Vector3.new(tracer.part.Size.X, tracer.part.Size.Y, math.max(head - tail, 0.05))
			tracer.part.CFrame = CFrame.lookAt(mid, mid + tracer.direction)
		end
	end
	if #shells > 0 then
		rayParams.FilterDescendantsInstances = geometryRoots()
	end
	for index = #shells, 1, -1 do
		local shell = shells[index]
		shell.life -= dt
		if shell.life <= 0 then
			shellPool:release(shell.part)
			table.remove(shells, index)
			continue
		end
		shell.velocity += Vector3.new(0, -Workspace.Gravity * 0.6, 0) * dt
		local position = shell.part.Position
		local move = shell.velocity * dt
		local hit = if move.Magnitude > 0 then Workspace:Raycast(position, move, rayParams) else nil
		if hit and not shell.bounced then
			shell.bounced = true
			shell.velocity = (shell.velocity - 2 * shell.velocity:Dot(hit.Normal) * hit.Normal) * 0.35
			shell.part.CFrame = CFrame.new(hit.Position + hit.Normal * 0.05) * shell.part.CFrame.Rotation
		elseif hit then
			shell.velocity = Vector3.zero
		else
			local spin = shell.spin * dt
			shell.part.CFrame = (shell.part.CFrame + move) * CFrame.Angles(spin.X, spin.Y, spin.Z)
		end
		if shell.life < 0.3 then
			shell.part.Transparency = 1 - shell.life / 0.3
		end
	end
end

function EffectsController.start()
	folder = Instance.new("Folder")
	folder.Name = "LocalEffects"
	folder.Parent = Workspace

	flashPool = Pool.new(function(): BasePart
		local part = basePart("MuzzleFlash")
		part.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Brightness = 4
		light.Range = 12
		light.Shadows = false
		light.Enabled = false
		light.Parent = part
		emitter(
			part,
			"Sparks",
			SPARK_TEXTURE,
			Color3.fromRGB(255, 200, 120),
			0.12,
			NumberRange.new(0.05, 0.12),
			NumberRange.new(18, 34),
			1
		)
		local smoke = emitter(
			part,
			"Smoke",
			SMOKE_TEXTURE,
			Color3.fromRGB(140, 140, 145),
			0.6,
			NumberRange.new(0.6, 1.2),
			NumberRange.new(1, 2),
			0
		)
		smoke.Acceleration = Vector3.new(0, 3, 0)
		smoke.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		part.Parent = folder
		return part
	end, function(part: BasePart)
		part.Transparency = 1
	end, 24)

	tracerPool = Pool.new(function(): BasePart
		local part = basePart("Tracer")
		part.Parent = folder
		return part
	end, function(part: BasePart)
		part.Transparency = 1
		part.CFrame = CFrame.new(0, -1000, 0)
	end, 64)

	impactPool = Pool.new(function(): BasePart
		local part = basePart("Impact")
		emitter(
			part,
			"Sparks",
			SPARK_TEXTURE,
			Color3.fromRGB(255, 210, 140),
			0.14,
			NumberRange.new(0.12, 0.3),
			NumberRange.new(16, 34),
			1
		)
		local dust = emitter(
			part,
			"Dust",
			SMOKE_TEXTURE,
			Color3.fromRGB(150, 150, 155),
			0.9,
			NumberRange.new(0.4, 0.9),
			NumberRange.new(2, 6),
			0
		)
		dust.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		dust.Acceleration = Vector3.new(0, -4, 0)
		local energy = emitter(
			part,
			"Energy",
			FIRE_TEXTURE,
			Color3.fromRGB(255, 70, 85),
			0.45,
			NumberRange.new(0.12, 0.25),
			NumberRange.new(6, 14),
			1
		)
		energy.SpreadAngle = Vector2.new(70, 70)
		part.Parent = folder
		return part
	end, function(_part: BasePart) end, 48)

	holePool = Pool.new(function(): BasePart
		local part = basePart("BulletHole")
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(12, 12, 14)
		part.Size = Vector3.new(0.04, 0.32, 0.32)
		part.Parent = folder
		return part
	end, function(part: BasePart)
		part.Transparency = 1
	end, 90)

	shellPool = Pool.new(function(): BasePart
		local part = basePart("Shell")
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Metal
		part.Color = Color3.fromRGB(200, 160, 70)
		part.Parent = folder
		return part
	end, function(part: BasePart)
		part.Transparency = 1
		part.CFrame = CFrame.new(0, -1000, 0)
	end, 48)

	flashPool:prewarm(6)
	tracerPool:prewarm(16)
	impactPool:prewarm(10)
	RunService.RenderStepped:Connect(update)
end

return EffectsController
