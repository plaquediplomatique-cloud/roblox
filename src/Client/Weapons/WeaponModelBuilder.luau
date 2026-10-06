--!strict
--[[
	WeaponModelBuilder — instancie un modèle d'arme procédural (Shared/Config/WeaponModels)
	habillé d'un skin (palette, matériaux, FX).

	Utilisé pour : le viewmodel (1re personne, échelle 0.6), l'arme dans la main des
	autres joueurs (échelle "monde"), les vitrines de l'Armory et l'aperçu 3D du menu.

	* Racine ancrée "Root" (la poignée) ; pièces statiques soudées ; pièces animées
	  (chargeur, culasse, pompe, barillet) reliées par Motor6D : l'animateur procédural
	  modifie leur C0 sans recalculer le modèle.
	* Attachments Muzzle / Ejection / AimPoint / RightHand / LeftHand.
	* FX de skin : pulsation néon (Epic+), dégradé animé cyan↔magenta (Mythic),
	  aura de particules (Legendary+). Les FX sont pilotés par une seule boucle.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)

export type BuiltWeapon = {
	model: Model,
	root: BasePart,
	parts: { [string]: BasePart },
	motors: { [string]: Motor6D },
	baseC0: { [string]: CFrame },
	attachments: { [string]: Attachment },
	neon: { BasePart },
	scale: number,
	skin: Types.ItemDef?,
	destroy: (self: BuiltWeapon) -> (),
}

local WeaponModelBuilder = {}

local animatedNeon: { [BasePart]: { phase: number, fx: Types.SkinFx, base: Color3 } } = {}

local DEFAULT_PALETTE: Types.Palette = {
	Base = Color3.fromRGB(46, 50, 58),
	Secondary = Color3.fromRGB(30, 33, 38),
	Accent = Color3.fromRGB(80, 86, 96),
	Neon = Color3.fromRGB(61, 225, 255),
	Metal = Color3.fromRGB(58, 62, 70),
	Glass = Color3.fromRGB(140, 220, 255),
	Grip = Color3.fromRGB(28, 30, 34),
}

local function roleMaterial(role: Types.ColorRole, skin: Types.ItemDef?): Enum.Material
	if role == "Neon" then
		return Enum.Material.Neon
	elseif role == "Glass" then
		return Enum.Material.Glass
	elseif role == "Metal" then
		return Enum.Material.Metal
	elseif role == "Grip" then
		return Enum.Material.SmoothPlastic
	end
	local materials = skin and skin.materials
	if materials then
		if role == "Base" then
			return materials.Base
		elseif role == "Secondary" then
			return materials.Secondary
		elseif role == "Accent" then
			return materials.Accent
		end
	end
	return if role == "Base" then Enum.Material.Metal else Enum.Material.SmoothPlastic
end

local function createPiece(
	piece: Types.ModelPiece,
	scale: number,
	palette: Types.Palette,
	skin: Types.ItemDef?
): BasePart
	local part: BasePart
	if piece.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if piece.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif piece.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		part = p
	end
	part.Name = piece.name
	part.Size = piece.size * scale
	part.Color = (palette :: any)[piece.role] or DEFAULT_PALETTE.Base
	part.Material = piece.material or roleMaterial(piece.role, skin)
	local transparency = piece.transparency or 0
	if piece.role == "Base" and part.Material == Enum.Material.Glass then
		transparency = math.max(transparency, 0.35)
	end
	part.Transparency = transparency
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function pieceCFrame(piece: Types.ModelPiece, scale: number): CFrame
	local offset = piece.offset
	local scaled = CFrame.new(offset.Position * scale) * offset.Rotation
	if piece.shape == "Cylinder" then
		-- Axe des cylindres Roblox = X ; nos pièces sont orientées selon -Z.
		scaled *= CFrame.Angles(0, math.pi / 2, 0)
	end
	return scaled
end

local function attachAura(root: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Aura"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(0.3, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LockedToPart = false
	emitter.Parent = root
end

--[[
	Construit l'arme. `scale` : 0.6 pour le viewmodel, `spec.worldScale` pour le monde.
	Le modèle n'est PAS parenté : à l'appelant de choisir (caméra, personnage, vitrine).
]]
function WeaponModelBuilder.build(def: Types.WeaponDef, skin: Types.ItemDef?, scale: number): BuiltWeapon
	local spec = def.model
	local palette = (skin and skin.palette) or DEFAULT_PALETTE
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. def.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root

	local built: BuiltWeapon = {
		model = model,
		root = root,
		parts = {},
		motors = {},
		baseC0 = {},
		attachments = {},
		neon = {},
		scale = scale,
		skin = skin,
		destroy = function(self: BuiltWeapon)
			for _, part in self.neon do
				animatedNeon[part] = nil
			end
			self.model:Destroy()
		end,
	}

	for _, piece in spec.pieces do
		local part = createPiece(piece, scale, palette, skin)
		local offset = pieceCFrame(piece, scale)
		part.CFrame = offset
		if piece.animated then
			local motor = Instance.new("Motor6D")
			motor.Name = piece.name
			motor.Part0 = root
			motor.Part1 = part
			motor.C0 = offset
			motor.Parent = root
			built.motors[piece.name] = motor
			built.baseC0[piece.name] = offset
		else
			local weld = Instance.new("Weld")
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = offset
			weld.Parent = part
		end
		part.Parent = model
		built.parts[piece.name] = part
		if piece.role == "Neon" then
			table.insert(built.neon, part)
			local fx = skin and skin.fx
			if fx and (fx.neonPulse or fx.gradientShift) then
				animatedNeon[part] = { phase = math.random() * math.pi * 2, fx = fx, base = part.Color }
			end
		end
	end

	local function attachment(name: string, cframe: CFrame)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = CFrame.new(cframe.Position * scale) * cframe.Rotation
		a.Parent = root
		built.attachments[name] = a
	end
	attachment("Muzzle", spec.muzzle)
	attachment("Ejection", spec.ejection)
	attachment("AimPoint", spec.aimPoint)
	attachment("RightHand", spec.rightHand)
	attachment("LeftHand", spec.leftHand)

	local fx = skin and skin.fx
	if fx and fx.aura then
		attachAura(root, palette.Neon)
	end
	return built
end

--[[
	Repositionne la pièce animée `name` : translation en espace arme (échelle design),
	rotation autour du centre de la pièce (barillet qui pivote, levier qui se relève…).
]]
function WeaponModelBuilder.setPieceOffset(built: BuiltWeapon, name: string, offset: CFrame)
	local motor = built.motors[name]
	local base = built.baseC0[name]
	if motor and base then
		motor.C0 = CFrame.new(offset.Position * built.scale) * base * offset.Rotation
	end
end

function WeaponModelBuilder.setVisible(built: BuiltWeapon, visible: boolean)
	for _, part in built.parts do
		part.LocalTransparencyModifier = if visible then 0 else 1
	end
	local aura = built.root:FindFirstChild("Aura")
	if aura and aura:IsA("ParticleEmitter") then
		aura.Enabled = visible
	end
end

function WeaponModelBuilder.start()
	local cyan = Color3.fromRGB(61, 225, 255)
	local magenta = Color3.fromRGB(220, 80, 255)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for part, info in animatedNeon do
			if part.Parent == nil then
				animatedNeon[part] = nil
				continue
			end
			if info.fx.gradientShift then
				local t = (math.sin(now * 1.6 + info.phase) + 1) / 2
				part.Color = cyan:Lerp(magenta, t)
			elseif info.fx.neonPulse then
				local t = (math.sin(now * info.fx.neonPulse * math.pi * 2 + info.phase) + 1) / 2
				part.Color = info.base:Lerp(Color3.new(1, 1, 1), t * 0.35)
				part.Transparency = 0.15 * (1 - t)
			end
		end
	end)
end

return WeaponModelBuilder
