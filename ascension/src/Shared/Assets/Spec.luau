--!strict
--[[
	Spec — description DONNÉE d'une pièce 3D, indépendante du moteur.

	Les recettes (armes, props, mannequins) renvoient des listes de `Spec` : testables avec Lune
	(budgets, bornes, couleurs) et réalisées en instances par un seul module, Assets/Builder.
	Convention de repère des props : origine au CENTRE DU SOL de l'objet, face avant = -Z.
	Armes : origine au centre de la poignée, lame le long de +Y, largeur le long de X.
]]

export type Shape = "Block" | "Ball" | "Cylinder" | "Wedge"

export type Spec = {
	Name: string?,
	Shape: Shape,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	Neon: boolean?,
	Collide: boolean?,
	Shadow: boolean?, -- false : pas d'ombre (petites pièces)
}

export type Opts = {
	Name: string?,
	Material: Enum.Material?,
	Transparency: number?,
	Neon: boolean?,
	Collide: boolean?,
	Shadow: boolean?,
	Rot: CFrame?, -- rotation appliquée AVANT le décalage (autour du centre de la pièce)
}

export type Palette = {
	Primary: Color3,
	Secondary: Color3,
	Accent: Color3,
	Dark: Color3,
	Light: Color3,
}

local Spec = {}

local function make(shape: Shape, size: Vector3, position: Vector3, color: Color3, opts: Opts?): Spec
	local o: Opts = opts or {}
	local rot = o.Rot or CFrame.identity
	return {
		Name = o.Name,
		Shape = shape,
		Size = size,
		CFrame = CFrame.new(position) * rot,
		Color = color,
		Material = o.Material,
		Transparency = o.Transparency,
		Neon = o.Neon,
		Collide = o.Collide,
		Shadow = o.Shadow,
	}
end

function Spec.block(size: Vector3, position: Vector3, color: Color3, opts: Opts?): Spec
	return make("Block", size, position, color, opts)
end

function Spec.ball(diameter: number, position: Vector3, color: Color3, opts: Opts?): Spec
	return make("Ball", Vector3.new(diameter, diameter, diameter), position, color, opts)
end

-- Cylindre VERTICAL (axe Y) : hauteur `height`, diamètre `diameter`.
function Spec.cyl(height: number, diameter: number, position: Vector3, color: Color3, opts: Opts?): Spec
	local o: Opts = table.clone(opts or {})
	o.Rot = (o.Rot or CFrame.identity) * CFrame.Angles(0, 0, math.pi / 2)
	return make("Cylinder", Vector3.new(height, diameter, diameter), position, color, o)
end

-- Cylindre dont l'axe est la direction Z (poutre, tronc couché).
function Spec.cylZ(length: number, diameter: number, position: Vector3, color: Color3, opts: Opts?): Spec
	local o: Opts = table.clone(opts or {})
	o.Rot = (o.Rot or CFrame.identity) * CFrame.Angles(0, math.pi / 2, 0)
	return make("Cylinder", Vector3.new(length, diameter, diameter), position, color, o)
end

function Spec.wedge(size: Vector3, position: Vector3, color: Color3, opts: Opts?): Spec
	return make("Wedge", size, position, color, opts)
end

-- Boîte de côtés arrondis « jouet » : un bloc + deux bandeaux plus clairs (chanfrein visuel).
function Spec.brick(size: Vector3, position: Vector3, color: Color3, light: Color3, opts: Opts?): { Spec }
	local out = { make("Block", size, position, color, opts) }
	local bevel = math.min(0.25, size.Y * 0.2)
	table.insert(
		out,
		make(
			"Block",
			Vector3.new(size.X - 0.2, bevel, size.Z - 0.2),
			position + Vector3.new(0, size.Y / 2 - bevel / 2 + 0.01, 0),
			light,
			{ Shadow = false }
		)
	)
	return out
end

function Spec.append(into: { Spec }, items: { Spec })
	for _, item in items do
		table.insert(into, item)
	end
end

-- Étendue (boîte englobante alignée aux axes, approximée par les 8 coins de chaque pièce).
function Spec.bounds(specs: { Spec }): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, spec in specs do
		local half = spec.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = spec.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					min = Vector3.new(math.min(min.X, corner.X), math.min(min.Y, corner.Y), math.min(min.Z, corner.Z))
					max = Vector3.new(math.max(max.X, corner.X), math.max(max.Y, corner.Y), math.max(max.Z, corner.Z))
				end
			end
		end
	end
	return min, max
end

return Spec
