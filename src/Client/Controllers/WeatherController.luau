--!strict
--[[
	WeatherController — météo et particules d'ambiance de la carte courante (client).

	* Pluie (Kestrel), neige (Spire), poussière en suspension (Helix, hub), étincelles
	  (Monolith) : un émetteur invisible suit la caméra ; seules les particules proches
	  existent, quelle que soit la taille de la carte.
	* Abri : un rayon vers le ciel toutes les 0,3 s coupe pluie et neige sous un toit
	  (quais, tunnels, intérieurs) ; poussière et étincelles restent (ambiance intérieure).
	* Éclairs lointains (Kestrel) : flash d'étalonnage bref puis tonnerre retardé selon la
	  distance ; jamais avec « flashs réduits ».
	* Budget : particules vivantes ≤ ~900 sur ordinateur, moitié sur mobile ; tout se coupe
	  avec le réglage vidéo « Météo et particules d'ambiance ».
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Maps = require(Shared.Config.Maps)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsController = require(script.Parent.SettingsController)
local LightingController = require(script.Parent.LightingController)
local AudioController = require(script.Parent.AudioController)

local WeatherController = {}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SHELTER_INTERVAL = 0.3

type Profile = {
	rate: number, -- particules / s à intensité 1 (ordinateur)
	height: number, -- hauteur de l'émetteur au-dessus de la caméra
	size: Vector3, -- volume d'émission
	sheltered: boolean, -- coupé sous un toit
	configure: (emitter: ParticleEmitter) -> (),
}

local PROFILES: { [Types.WeatherKind]: Profile } = {
	Rain = {
		rate = 1100,
		height = 26,
		size = Vector3.new(90, 1, 90),
		sheltered = true,
		configure = function(e: ParticleEmitter)
			e.Texture = SPARK_TEXTURE
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
			e.Squash = NumberSequence.new(-3) -- étirement maximal : des traits, pas des points
			e.Size = NumberSequence.new(0.1)
			e.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.8, 0.65),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.LightEmission = 0.12
			e.LightInfluence = 0.65 -- visible la nuit, plus brillante sous les lampes
			e.Speed = NumberRange.new(72, 88)
			e.Acceleration = Vector3.new(2, -30, 1)
			e.Lifetime = NumberRange.new(0.6, 0.8)
			e.SpreadAngle = Vector2.new(4, 4)
			e.EmissionDirection = Enum.NormalId.Bottom
		end,
	},
	Snow = {
		rate = 130,
		height = 16,
		size = Vector3.new(70, 1, 70),
		sheltered = true,
		configure = function(e: ParticleEmitter)
			e.Texture = SMOKE_TEXTURE
			e.Orientation = Enum.ParticleOrientation.FacingCamera
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.12) })
			e.Color = ColorSequence.new(Color3.fromRGB(240, 244, 255))
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.1, 0.2),
				NumberSequenceKeypoint.new(0.85, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.LightEmission = 0.3
			e.LightInfluence = 0.8
			e.Speed = NumberRange.new(3, 6)
			e.Acceleration = Vector3.new(5, -2.5, 2)
			e.Lifetime = NumberRange.new(5.5, 7.5)
			e.SpreadAngle = Vector2.new(35, 35)
			e.RotSpeed = NumberRange.new(-60, 60)
			e.EmissionDirection = Enum.NormalId.Bottom
		end,
	},
	Motes = {
		rate = 26,
		height = 0,
		size = Vector3.new(44, 18, 44),
		sheltered = false,
		configure = function(e: ParticleEmitter)
			e.Texture = SPARK_TEXTURE
			e.Orientation = Enum.ParticleOrientation.FacingCamera
			e.Size = NumberSequence.new(0.07)
			e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 215))
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(0.7, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.LightEmission = 0.6
			e.LightInfluence = 0.6
			e.Speed = NumberRange.new(0.1, 0.5)
			e.Acceleration = Vector3.new(0.15, 0.05, 0.1)
			e.Lifetime = NumberRange.new(7, 10)
			e.SpreadAngle = Vector2.new(180, 180)
		end,
	},
	Embers = {
		rate = 22,
		height = 0,
		size = Vector3.new(44, 18, 44),
		sheltered = false,
		configure = function(e: ParticleEmitter)
			e.Texture = SPARK_TEXTURE
			e.Orientation = Enum.ParticleOrientation.FacingCamera
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.04) })
			e.Color = ColorSequence.new(Color3.fromRGB(220, 120, 255))
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.LightEmission = 1
			e.LightInfluence = 0
			e.Speed = NumberRange.new(0.3, 0.9)
			e.Acceleration = Vector3.new(0, 0.35, 0)
			e.Lifetime = NumberRange.new(5, 8)
			e.SpreadAngle = Vector2.new(180, 180)
		end,
	},
}

local anchor: Part
local emitter: ParticleEmitter? = nil
local profile: Profile? = nil
local weather: Types.Weather? = nil
local currentMap = ""
local sheltered = false
local shelterClock = 0
local rateTarget = 0
local rateCurrent = 0
local nextLightning = 0
local shelterParams = RaycastParams.new()
shelterParams.FilterType = Enum.RaycastFilterType.Include

local function geometryRoots(): { Instance }
	local roots: { Instance } = {}
	for _, name in { "Arenas", "Hub" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(roots, folder)
		end
	end
	return roots
end

local function enabled(): boolean
	return SettingsController.get().Video.Weather
end

local function deviceScale(): number
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 0.5 else 1
end

local function clearEmitter()
	if emitter then
		emitter:Destroy()
		emitter = nil
	end
	profile = nil
	rateCurrent = 0
end

local function build(kind: Types.WeatherKind)
	clearEmitter()
	local selected = PROFILES[kind]
	if not selected then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "Weather_" .. kind
	e.Rate = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = false
	selected.configure(e)
	e.Parent = anchor
	anchor.Size = selected.size
	emitter = e
	profile = selected
end

function WeatherController.applyMap(mapId: string)
	if mapId == currentMap then
		return
	end
	currentMap = mapId
	local info = Maps.get(mapId)
	weather = if info then info.weather else nil
	AudioController.setMapAmbience(if info then info.ambience else nil)
	local w = weather
	if w and w.kind ~= "None" then
		build(w.kind)
	else
		clearEmitter()
	end
	nextLightning = os.clock() + math.random(12, 25)
end

local function refreshArena()
	local kind = ClientState.arena()
	if kind == "Match" then
		local data = ClientState.matchData()
		if data then
			WeatherController.applyMap(data.map)
		end
	else
		WeatherController.applyMap("hub")
	end
end

local function lightning(camera: Camera)
	local settings = SettingsController.get().Video
	if settings.ReducedFlashes then
		return
	end
	LightingController.lightningFlash(math.random() * 0.4 + 0.6)
	-- Tonnerre retardé : ~340 m/s, l'éclair est « à 300-700 studs ».
	local distance = math.random(300, 700)
	local angle = math.random() * math.pi * 2
	local origin = camera.CFrame.Position
	task.delay(distance / 340 * 0.9, function()
		AudioController.playAt(
			"Ambient.Thunder",
			origin + Vector3.new(math.cos(angle) * distance * 0.5, 120, math.sin(angle) * distance * 0.5)
		)
	end)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local e, p, w = emitter, profile, weather
	if not (camera and e and p and w) then
		return
	end
	local position = camera.CFrame.Position
	local forward = camera.CFrame.LookVector
	anchor.CFrame = CFrame.new(position + Vector3.new(forward.X * 12, p.height, forward.Z * 12))

	shelterClock -= dt
	if shelterClock <= 0 then
		shelterClock = SHELTER_INTERVAL
		if p.sheltered then
			shelterParams.FilterDescendantsInstances = geometryRoots()
			sheltered = Workspace:Raycast(position, Vector3.new(0, 80, 0), shelterParams) ~= nil
		else
			sheltered = false
		end
	end
	rateTarget = if enabled() and not sheltered then p.rate * w.intensity * deviceScale() else 0
	rateCurrent += (rateTarget - rateCurrent) * math.min(1, dt * 3)
	e.Rate = if rateCurrent < 1 then 0 else rateCurrent

	if w.lightning and enabled() and os.clock() >= nextLightning then
		nextLightning = os.clock() + math.random(20, 45)
		lightning(camera)
	end
end

function WeatherController.start()
	local folder = Instance.new("Folder")
	folder.Name = "AS_Weather"
	folder.Parent = Workspace
	anchor = Instance.new("Part")
	anchor.Name = "WeatherAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = folder

	ClientState.ArenaChanged:Connect(refreshArena)
	ClientState.MatchChanged:Connect(refreshArena)
	refreshArena()
	RunService.RenderStepped:Connect(update)
end

return WeatherController
