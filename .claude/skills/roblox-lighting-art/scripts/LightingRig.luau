--!strict
--[[
	LightingRig — apply and blend art-directed "looks" (Lighting + Atmosphere + post effects),
	convert colour temperatures, and place practical lights with sane defaults.

	Run on the client (LocalScript/controller) for per-zone moods: Lighting changes made by a
	client are local to that client. Run on the server only for global, replicated changes.

		local LightingRig = require(path.to.LightingRig)
		LightingRig.apply(LightingRig.looks.GoldenHour, 2) -- blend over 2 seconds
		LightingRig.practical(lampBulb, 2700, 1.2, 14)    -- warm lamp, no shadows
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

export type AtmosphereLook = {
	density: number?,
	offset: number?,
	color: Color3?,
	decay: Color3?,
	glare: number?,
	haze: number?,
}

export type GradeLook = { brightness: number?, contrast: number?, saturation: number?, tint: Color3? }
export type BloomLook = { intensity: number?, size: number?, threshold: number? }
export type SunRaysLook = { intensity: number?, spread: number? }

export type Look = {
	clockTime: number?,
	geographicLatitude: number?,
	brightness: number?,
	exposure: number?,
	ambient: Color3?,
	outdoorAmbient: Color3?,
	diffuse: number?,
	specular: number?,
	shadowSoftness: number?,
	atmosphere: AtmosphereLook?,
	grade: GradeLook?,
	bloom: BloomLook?,
	sunRays: SunRaysLook?,
}

local LightingRig = {}

--[[ Colour temperature (Kelvin) to Color3 — Tanner Helland's approximation, 1000–40000 K. ]]
function LightingRig.kelvin(kelvin: number): Color3
	local t = math.clamp(kelvin, 1000, 40000) / 100
	local r, g, b
	if t <= 66 then
		r = 255
		g = 99.4708025861 * math.log(t) - 161.1195681661
	else
		r = 329.698727446 * (t - 60) ^ -0.1332047592
		g = 288.1221695283 * (t - 60) ^ -0.0755148492
	end
	if t >= 66 then
		b = 255
	elseif t <= 19 then
		b = 0
	else
		b = 138.5177312231 * math.log(t - 10) - 305.0447927307
	end
	return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

local function effect<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return (existing :: any) :: T
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return (created :: any) :: T
end

--[[ The rig's own effect instances (created once, reused by every look). ]]
function LightingRig.effects(): (Atmosphere, ColorCorrectionEffect, BloomEffect, SunRaysEffect)
	return effect("Atmosphere", "Atmosphere"),
		effect("ColorCorrectionEffect", "Rig_Grade"),
		effect("BloomEffect", "Rig_Bloom"),
		effect("SunRaysEffect", "Rig_SunRays")
end

local function blend(instance: Instance, goals: { [string]: any }, duration: number)
	if next(goals) == nil then
		return
	end
	if duration <= 0 then
		for property, value in goals do
			(instance :: any)[property] = value
		end
		return
	end
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(instance, info, goals):Play()
end

--[[ Applies a look, blending every numeric/colour property over `duration` seconds. ]]
function LightingRig.apply(look: Look, duration: number?)
	local time = duration or 0
	local atmosphere, grade, bloom, sunRays = LightingRig.effects()

	local lightingGoals: { [string]: any } = {}
	lightingGoals.ClockTime = look.clockTime
	lightingGoals.GeographicLatitude = look.geographicLatitude
	lightingGoals.Brightness = look.brightness
	lightingGoals.ExposureCompensation = look.exposure
	lightingGoals.Ambient = look.ambient
	lightingGoals.OutdoorAmbient = look.outdoorAmbient
	lightingGoals.EnvironmentDiffuseScale = look.diffuse
	lightingGoals.EnvironmentSpecularScale = look.specular
	lightingGoals.ShadowSoftness = look.shadowSoftness
	blend(Lighting, lightingGoals, time)

	local a = look.atmosphere
	if a then
		blend(atmosphere, {
			Density = a.density,
			Offset = a.offset,
			Color = a.color,
			Decay = a.decay,
			Glare = a.glare,
			Haze = a.haze,
		}, time)
	end
	local g = look.grade
	if g then
		blend(
			grade,
			{ Brightness = g.brightness, Contrast = g.contrast, Saturation = g.saturation, TintColor = g.tint },
			time
		)
	end
	local b = look.bloom
	if b then
		blend(bloom, { Intensity = b.intensity, Size = b.size, Threshold = b.threshold }, time)
	end
	local s = look.sunRays
	if s then
		blend(sunRays, { Intensity = s.intensity, Spread = s.spread }, time)
	end
end

--[[
	Practical light: a light source players can see (lamp, sconce, screen, window glow).
	Shadows are OFF by default — enable them only on the few key lights of a space.
]]
function LightingRig.practical(
	host: BasePart,
	kelvin: number,
	brightness: number,
	range: number,
	shadows: boolean?,
	kind: ("Point" | "Spot" | "Surface")?
): Light
	local light: Light
	if kind == "Spot" then
		local spot = Instance.new("SpotLight")
		spot.Range = range
		spot.Angle = 70
		spot.Face = Enum.NormalId.Bottom
		light = spot
	elseif kind == "Surface" then
		local surface = Instance.new("SurfaceLight")
		surface.Range = range
		surface.Angle = 80
		surface.Face = Enum.NormalId.Front
		light = surface
	else
		local point = Instance.new("PointLight")
		point.Range = range
		light = point
	end
	light.Color = LightingRig.kelvin(kelvin)
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = host
	return light
end

--[[
	Starting looks for exteriors. They are recipes, not final answers: tune per map with the
	review loop in SKILL.md. Values assume the default sky.
]]
LightingRig.looks = {
	NoonClear = {
		clockTime = 13,
		brightness = 3,
		exposure = 0,
		ambient = Color3.fromRGB(70, 74, 82),
		outdoorAmbient = Color3.fromRGB(128, 132, 140),
		diffuse = 1,
		specular = 1,
		shadowSoftness = 0.15,
		atmosphere = {
			density = 0.25,
			offset = 0.2,
			color = Color3.fromRGB(199, 212, 230),
			decay = Color3.fromRGB(106, 120, 140),
			glare = 0.2,
			haze = 0.6,
		},
		grade = { brightness = 0, contrast = 0.08, saturation = 0.05, tint = Color3.fromRGB(255, 255, 255) },
		bloom = { intensity = 0.4, size = 24, threshold = 1.6 },
		sunRays = { intensity = 0.02, spread = 0.4 },
	} :: Look,
	GoldenHour = {
		clockTime = 17.6,
		brightness = 2.4,
		exposure = 0.1,
		ambient = Color3.fromRGB(64, 54, 58),
		outdoorAmbient = Color3.fromRGB(150, 122, 104),
		diffuse = 1,
		specular = 1,
		shadowSoftness = 0.2,
		atmosphere = {
			density = 0.32,
			offset = 0.25,
			color = Color3.fromRGB(255, 196, 150),
			decay = Color3.fromRGB(132, 92, 110),
			glare = 1.2,
			haze = 1.4,
		},
		grade = { brightness = 0, contrast = 0.12, saturation = 0.08, tint = Color3.fromRGB(255, 240, 225) },
		bloom = { intensity = 0.6, size = 28, threshold = 1.4 },
		sunRays = { intensity = 0.1, spread = 0.6 },
	} :: Look,
	Overcast = {
		clockTime = 11,
		brightness = 1.4,
		exposure = 0.15,
		ambient = Color3.fromRGB(86, 90, 96),
		outdoorAmbient = Color3.fromRGB(140, 144, 150),
		diffuse = 1,
		specular = 0.6,
		shadowSoftness = 0.6,
		atmosphere = {
			density = 0.42,
			offset = 0.1,
			color = Color3.fromRGB(176, 182, 190),
			decay = Color3.fromRGB(120, 126, 134),
			glare = 0,
			haze = 2,
		},
		grade = { brightness = 0, contrast = 0.04, saturation = -0.15, tint = Color3.fromRGB(240, 245, 255) },
		bloom = { intensity = 0.2, size = 20, threshold = 2 },
		sunRays = { intensity = 0, spread = 0.2 },
	} :: Look,
	NightCity = {
		clockTime = 0.5,
		brightness = 1.2,
		exposure = 0.2,
		ambient = Color3.fromRGB(26, 30, 42),
		outdoorAmbient = Color3.fromRGB(44, 50, 70),
		diffuse = 0.8,
		specular = 1,
		shadowSoftness = 0.25,
		atmosphere = {
			density = 0.36,
			offset = 0.15,
			color = Color3.fromRGB(60, 72, 104),
			decay = Color3.fromRGB(34, 30, 56),
			glare = 0,
			haze = 1.8,
		},
		grade = { brightness = 0, contrast = 0.16, saturation = -0.05, tint = Color3.fromRGB(222, 232, 255) },
		bloom = { intensity = 0.8, size = 26, threshold = 1.2 },
		sunRays = { intensity = 0, spread = 0.2 },
	} :: Look,
}

return LightingRig
