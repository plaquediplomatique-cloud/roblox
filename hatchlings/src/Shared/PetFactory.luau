--!strict
--[[
	PetFactory — construit le modèle 3D d'un pet à partir de sa description (Config/Pets).

	Tout est fait de formes rondes (aucun asset) : corps + tête ronds façon « mochi »,
	yeux brillants, joues roses. Le pet regarde vers -Z, l'origine est le centre du corps ;
	`groundOffset` donne la hauteur du centre au-dessus du sol (pieds posés).

	Utilisé côté serveur (pets qui suivent) et côté client (aperçus dans les UI).
]]

local Pets = require(script.Parent.Config.Pets)

type PetDef = Pets.PetDef

local PetFactory = {}

local EYE_COLOR = Color3.fromRGB(58, 46, 84)
local CHEEK_COLOR = Color3.fromRGB(255, 160, 184)
local HORN_COLOR = Color3.fromRGB(255, 226, 140)

local function part(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function ball(model: Model, name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?)
	return part(model, name, Enum.PartType.Ball, Vector3.one * diameter, CFrame.new(at), color, material)
end

function PetFactory.groundOffset(def: PetDef): number
	return 1.05 * def.size
end

function PetFactory.build(def: PetDef): Model
	local s = def.size
	local model = Instance.new("Model")
	model.Name = def.name

	local body = ball(model, "Body", 1.8 * s, Vector3.zero, def.body)
	model.PrimaryPart = body
	ball(model, "Belly", 1.1 * s, Vector3.new(0, -0.1 * s, -0.45 * s), def.belly)
	ball(model, "Head", 2.0 * s, Vector3.new(0, 1.5 * s, -0.2 * s), def.body)

	-- visage
	for _, side in { -1, 1 } do
		ball(model, "Eye", 0.34 * s, Vector3.new(0.45 * s * side, 1.65 * s, -1.05 * s), EYE_COLOR)
		ball(model, "EyeShine", 0.12 * s, Vector3.new(0.5 * s * side, 1.76 * s, -1.2 * s), Color3.new(1, 1, 1))
		ball(model, "Cheek", 0.3 * s, Vector3.new(0.7 * s * side, 1.35 * s, -0.92 * s), CHEEK_COLOR)
		ball(model, "Foot", 0.62 * s, Vector3.new(0.5 * s * side, -0.74 * s, -0.3 * s), def.accent)
	end
	ball(model, "Nose", 0.24 * s, Vector3.new(0, 1.45 * s, -1.17 * s), EYE_COLOR)

	-- oreilles
	for _, side in { -1, 1 } do
		if def.ears == "Round" then
			ball(model, "Ear", 0.75 * s, Vector3.new(0.68 * s * side, 2.35 * s, -0.1 * s), def.accent)
		elseif def.ears == "Long" then
			local cf = CFrame.new(0.5 * s * side, 2.85 * s, -0.1 * s) * CFrame.Angles(0, 0, math.rad(90 - 10 * side))
			part(model, "Ear", Enum.PartType.Cylinder, Vector3.new(1.7 * s, 0.55 * s, 0.55 * s), cf, def.accent)
		elseif def.ears == "Pointy" then
			local cf = CFrame.new(0.72 * s * side, 2.4 * s, -0.1 * s) * CFrame.Angles(0, 0, math.rad(45 + 8 * side))
			part(model, "Ear", Enum.PartType.Block, Vector3.new(0.7 * s, 0.7 * s, 0.32 * s), cf, def.accent)
		end
	end

	-- queue
	if def.tail == "Ball" then
		ball(model, "Tail", 0.7 * s, Vector3.new(0, -0.1 * s, 1.0 * s), def.accent)
	elseif def.tail == "Fluffy" then
		ball(model, "Tail", 1.15 * s, Vector3.new(0, 0.15 * s, 1.05 * s), def.accent)
	end

	-- extras
	if def.extra == "Horn" then
		ball(model, "Horn", 0.55 * s, Vector3.new(0, 2.6 * s, -0.65 * s), HORN_COLOR, Enum.Material.Neon)
		ball(model, "Horn", 0.38 * s, Vector3.new(0, 3.0 * s, -0.8 * s), HORN_COLOR, Enum.Material.Neon)
		ball(model, "Horn", 0.22 * s, Vector3.new(0, 3.3 * s, -0.92 * s), HORN_COLOR, Enum.Material.Neon)
	elseif def.extra == "Wings" then
		for _, side in { -1, 1 } do
			local cf = CFrame.new(1.25 * s * side, 0.55 * s, 0.35 * s)
				* CFrame.Angles(0, math.rad(25 * side), math.rad(-22 * side))
			part(model, "Wing", Enum.PartType.Block, Vector3.new(1.5 * s, 0.9 * s, 0.14 * s), cf, def.accent)
		end
	elseif def.extra == "Halo" then
		for i = 1, 10 do
			local angle = i / 10 * math.pi * 2
			ball(
				model,
				"Halo",
				0.22 * s,
				Vector3.new(math.cos(angle) * 0.8 * s, 3.1 * s, -0.2 * s + math.sin(angle) * 0.8 * s),
				HORN_COLOR,
				Enum.Material.Neon
			)
		end
	end

	-- lueur des pets Epic / Legendary
	if def.glow then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(HORN_COLOR, def.accent)
		sparkles.LightEmission = 0.8
		sparkles.Rate = 6
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Parent = body
		local light = Instance.new("PointLight")
		light.Color = def.accent
		light.Range = 8
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = body
	end

	return model
end

return PetFactory
