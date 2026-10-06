--!strict
--[[
	Builder — réalise des `Spec` (Assets/Spec) en instances Roblox, et assemble armes et props.

	Règles de performance (cf. skill roblox-render-performance) :
	  * toutes les pièces sont ancrées (props) ou non-massives (armes) et sans collision/touch/query ;
	  * ombres coupées pour les petites pièces ;
	  * les armes n'ont AUCUN script : effets = quelques émetteurs bornés par la rareté.
]]

local Spec = require(script.Parent.Spec)
local WeaponRecipes = require(script.Parent.WeaponRecipes)
local SwingPose = require(script.Parent.Parent.Rules.SwingPose)
local WeaponCatalog = require(script.Parent.Parent.Rules.WeaponCatalog)

local Builder = {}

local SHADOW_MIN_SIZE = 1.2 -- en dessous (plus grande dimension), la pièce ne projette pas d'ombre

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

function Builder.part(spec: Spec.Spec): BasePart
	local part: BasePart
	if spec.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = SHAPES[spec.Shape]
		part = p
	end
	part.Name = spec.Name or "Part"
	part.Size = spec.Size
	part.CFrame = spec.CFrame
	part.Color = spec.Color
	part.Material = if spec.Neon then Enum.Material.Neon else (spec.Material or Enum.Material.SmoothPlastic)
	part.Transparency = spec.Transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = spec.Collide == true
	part.CanTouch = false
	part.CanQuery = spec.Collide == true
	local largest = math.max(spec.Size.X, spec.Size.Y, spec.Size.Z)
	part.CastShadow = if spec.Shadow ~= nil then spec.Shadow else largest >= SHADOW_MIN_SIZE
	return part
end

-- Props : modèle ancré, pivot = origine de la recette (centre du sol), noms sémantiques.
function Builder.model(name: string, specs: { Spec.Spec }): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, spec in specs do
		local part = Builder.part(spec)
		part.Parent = model
	end
	model.WorldPivot = CFrame.identity
	return model
end

---------------------------------------------------------------------------------------------
-- Armes
---------------------------------------------------------------------------------------------

local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function addAttachment(parent: BasePart, name: string, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = parent.CFrame:PointToObjectSpace(position)
	attachment.Parent = parent
	return attachment
end

local function addFx(handle: BasePart, weapon: WeaponCatalog.Weapon, recipe: WeaponRecipes.Recipe)
	local fx = weapon.Rarity.Fx
	local color = weapon.Rarity.Color
	local accent = weapon.Rarity.Accent
	local tip = addAttachment(handle, "Tip", recipe.Tip)
	local top = addAttachment(handle, "TrailTop", recipe.TrailTop)
	local base = addAttachment(handle, "TrailBase", recipe.TrailBase)

	if fx.Trail then
		local trail = Instance.new("Trail")
		trail.Name = "SwingTrail"
		trail.Attachment0 = top
		trail.Attachment1 = base
		trail.Lifetime = 0.22
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.LightEmission = 0.6
		trail.Color = ColorSequence.new(color, accent)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Enabled = false -- activée par le client pendant la frappe
		trail.Parent = handle
	end

	if fx.Aura then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Texture = TEX_SPARK
		emitter.Color = ColorSequence.new(color, accent)
		emitter.LightEmission = 0.8
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Rate = 3 + weapon.Rarity.Order -- budget : 12 à 13 particules/s au maximum
		emitter.Speed = NumberRange.new(0.3, 1.2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-60, 60)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = tip
		if weapon.Rarity.Order >= 8 then
			local haze = Instance.new("ParticleEmitter")
			haze.Name = "Haze"
			haze.Texture = TEX_SMOKE
			haze.Color = ColorSequence.new(color)
			haze.LightEmission = 0.4
			haze.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1.6) })
			haze.Lifetime = NumberRange.new(0.6, 1)
			haze.Rate = 4
			haze.Speed = NumberRange.new(0.2, 0.6)
			haze.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			haze.Parent = tip
		end
	end

	if fx.Light then
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Range = 7 + weapon.Rarity.Order * 0.4
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = handle
	end
end

export type WeaponOptions = {
	Fx: boolean?, -- false : aperçu d'interface (pas d'émetteurs)
	Anchored: boolean?, -- true : modèle posé en décor / vitrine
}

-- Construit le modèle 3D d'une arme du catalogue. PrimaryPart = Handle ; l'arme est tenue par
-- soudure (Attach) ou posée ancrée (vitrine, aperçu).
function Builder.weapon(weapon: WeaponCatalog.Weapon, options: WeaponOptions?): Model
	local opts: WeaponOptions = options or {}
	local recipe = WeaponRecipes.build(weapon.Archetype, weapon.Colors)
	local model = Instance.new("Model")
	model.Name = weapon.Id
	model:SetAttribute("WeaponId", weapon.Id)

	local handle: BasePart? = nil
	local parts: { BasePart } = {}
	for _, spec in recipe.Parts do
		local part = Builder.part(spec)
		part.Parent = model
		table.insert(parts, part)
		if spec.Name == "Handle" then
			handle = part
		end
	end
	assert(handle, "recette sans Handle: " .. weapon.Archetype)
	model.PrimaryPart = handle

	local anchored = opts.Anchored == true
	for _, part in parts do
		if part ~= handle and not anchored then
			local weld = Instance.new("Weld")
			weld.Name = "PartWeld"
			weld.Part0 = handle
			weld.Part1 = part
			weld.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
			weld.Parent = part
		end
		part.Anchored = anchored
		part.Massless = true
	end

	if opts.Fx ~= false then
		addFx(handle, weapon, recipe)
	end
	return model
end

-- Soude une arme à la main droite d'un personnage R15 (blade vers l'avant/haut en pose « prêt »).
function Builder.attach(model: Model, hand: BasePart): Weld
	local handle = model.PrimaryPart :: BasePart
	local weld = Instance.new("Weld")
	weld.Name = "WeaponGrip"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = CFrame.new(0, -0.25, 0) * CFrame.Angles(SwingPose.GripAngle, 0, 0)
	weld.Parent = handle
	return weld
end

return Builder
