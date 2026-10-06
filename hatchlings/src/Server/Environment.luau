--!strict
--[[
	Environment — ambiance « heure dorée pastel » : lumière chaude et douce, brume rose,
	post-traitement léger (bloom, saturation) pour rester fluide sur mobile.
]]

local Lighting = game:GetService("Lighting")

local Environment = {}

local function ensure<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing :: any
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance :: any
end

function Environment.apply()
	Lighting.ClockTime = 16.6
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(150, 140, 175)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 190)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 232, 205)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35

	local atmosphere = ensure("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(255, 214, 224)
	atmosphere.Decay = Color3.fromRGB(255, 190, 200)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.2

	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 28
	bloom.Threshold = 1.6

	local color = ensure("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	color.Saturation = 0.18
	color.Contrast = 0.04
	color.TintColor = Color3.fromRGB(255, 244, 236)

	local rays = ensure("SunRaysEffect", "Rays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6
end

return Environment
