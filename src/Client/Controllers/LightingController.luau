--!strict
--[[
	LightingController — ambiance par carte + post-process dynamique.

	* Profil de la carte courante (Shared/Config/Maps) appliqué localement : heure,
	  ambiance, exposition, Atmosphere, étalonnage, bloom, rayons de soleil.
	  (En match local, plusieurs arènes coexistent : chaque client éclaire la SIENNE.)
	* Couches dynamiques indépendantes, combinées chaque frame :
	    - dégâts reçus : flash rouge + léger "punch" de contraste,
	    - bas PV : désaturation progressive + teinte rouge (tunnel),
	    - kill : "pop" de saturation/luminosité très bref (récompense visuelle),
	    - menus : flou + profondeur de champ (le hub reste vivant derrière l'UI),
	    - lunette : profondeur de champ serrée.
	* Réglages respectés : Bloom / DoF / SunRays, "flashs réduits" (accessibilité).
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Maps = require(Shared.Config.Maps)
local Theme = require(Shared.Config.Theme)
local MathUtil = require(Shared.Util.MathUtil)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsController = require(script.Parent.SettingsController)

local LightingController = {}

local grade: ColorCorrectionEffect
local damage: ColorCorrectionEffect
local bloom: BloomEffect
local sunRays: SunRaysEffect
local dof: DepthOfFieldEffect
local blur: BlurEffect
local atmosphere: Atmosphere

local profile: Types.LightingProfile? = nil
local flash = 0
local pop = 0
local lowHealth = 0
local menuBlur = 0
local menuTarget = 0
local scoped = false
local currentMap = ""

local function make<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return (instance :: any) :: T
end

function LightingController.applyMap(mapId: string)
	local info = Maps.get(mapId)
	if not info or currentMap == mapId then
		return
	end
	currentMap = mapId
	local p = info.lighting
	profile = p
	Lighting.ClockTime = p.clockTime
	Lighting.Brightness = p.brightness
	Lighting.Ambient = p.ambient
	Lighting.OutdoorAmbient = p.outdoorAmbient
	Lighting.ExposureCompensation = p.exposure
	Lighting.ColorShift_Top = p.colorShiftTop
	Lighting.EnvironmentDiffuseScale = p.diffuseScale
	Lighting.EnvironmentSpecularScale = p.specularScale
	atmosphere.Density = p.atmosphere.density
	atmosphere.Offset = p.atmosphere.offset
	atmosphere.Color = p.atmosphere.color
	atmosphere.Decay = p.atmosphere.decay
	atmosphere.Glare = p.atmosphere.glare
	atmosphere.Haze = p.atmosphere.haze
	bloom.Intensity = p.bloom.intensity
	bloom.Size = p.bloom.size
	bloom.Threshold = p.bloom.threshold
	sunRays.Intensity = p.sunRays.intensity
	sunRays.Spread = p.sunRays.spread
end

function LightingController.damageFlash(intensity: number)
	local reduced = SettingsController.get().Video.ReducedFlashes
	flash = math.min(1, flash + intensity * (if reduced then 0.35 else 1))
end

function LightingController.killPop()
	pop = 1
end

function LightingController.setLowHealth(fraction: number)
	local threshold = Theme.feedback.lowHealth
	lowHealth = math.clamp((threshold - fraction) / threshold, 0, 1)
end

function LightingController.setMenuBlur(enabled: boolean)
	menuTarget = if enabled then 1 else 0
end

function LightingController.setScope(enabled: boolean)
	scoped = enabled
end

local function refreshArena()
	local kind = ClientState.arena()
	if kind == "Match" then
		local data = ClientState.matchData()
		if data then
			LightingController.applyMap(data.map)
		end
	else
		LightingController.applyMap("hub")
	end
end

local function applySettings(settings: Types.SettingsData)
	bloom.Enabled = settings.Video.Bloom
	sunRays.Enabled = settings.Video.SunRays
	dof.Enabled = settings.Video.DepthOfField
end

function LightingController.start()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or make("Atmosphere", "AS_Atmosphere")
	grade = make("ColorCorrectionEffect", "AS_Grade")
	damage = make("ColorCorrectionEffect", "AS_Damage")
	bloom = make("BloomEffect", "AS_Bloom")
	sunRays = make("SunRaysEffect", "AS_SunRays")
	dof = make("DepthOfFieldEffect", "AS_DOF")
	blur = make("BlurEffect", "AS_Blur")
	blur.Size = 0
	dof.FarIntensity = 0
	dof.NearIntensity = 0
	dof.FocusDistance = 40
	dof.InFocusRadius = 60

	applySettings(SettingsController.get())
	SettingsController.Changed:Connect(applySettings)
	ClientState.ArenaChanged:Connect(refreshArena)
	ClientState.MatchChanged:Connect(refreshArena)
	refreshArena()

	RunService.RenderStepped:Connect(function(dt: number)
		flash = MathUtil.damp(flash, 0, 6, dt)
		pop = MathUtil.damp(pop, 0, 5, dt)
		menuBlur = MathUtil.damp(menuBlur, menuTarget, 10, dt)
		local p = profile
		local baseContrast = if p then p.colorCorrection.contrast else 0.1
		local baseSaturation = if p then p.colorCorrection.saturation else 0
		local baseBrightness = if p then p.colorCorrection.brightness else 0
		grade.TintColor = if p then p.colorCorrection.tint else Color3.new(1, 1, 1)
		grade.Contrast = baseContrast + flash * 0.15
		grade.Saturation = baseSaturation + pop * 0.35 - lowHealth * 0.55
		grade.Brightness = baseBrightness + pop * 0.06
		-- Teinte rouge combinée : flash de dégâts + bas PV
		local red = math.clamp(flash * 0.6 + lowHealth * 0.35, 0, 0.8)
		damage.TintColor = Color3.new(1, 1 - red * 0.55, 1 - red * 0.6)
		damage.Brightness = -lowHealth * 0.04
		blur.Size = menuBlur * 14
		if dof.Enabled then
			if scoped then
				dof.FarIntensity = 0
				dof.NearIntensity = 0.6
				dof.FocusDistance = 60
				dof.InFocusRadius = 400
			else
				dof.FarIntensity = menuBlur * 0.75
				dof.NearIntensity = 0
				dof.FocusDistance = 10
				dof.InFocusRadius = 12
			end
		end
	end)
end

return LightingController
