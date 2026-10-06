--!strict
--[[
	WeaponRecipes — modèles 3D des 17 archétypes d'armes, générés depuis 3 couleurs.

	Repère : poignée centrée à l'origine, lame le long de +Y, largeur le long de X, épaisseur
	le long de Z. Chaque recette renvoie ses pièces + les points d'ancrage utiles aux effets :
	  Tip        bout de l'arme (impact, étincelles)
	  TrailTop   haut de la traînée ; TrailBase = bas de la traînée
	Une même recette donne des dizaines d'armes : seule la palette change (Config/Weapons).
]]

local Spec = require(script.Parent.Spec)

export type Recipe = {
	Parts: { Spec.Spec },
	Tip: Vector3,
	TrailTop: Vector3,
	TrailBase: Vector3,
	Length: number, -- du bas de la poignée au bout
}

type Colors = { Blade: Color3, Handle: Color3, Accent: Color3 }
type Builder = (c: Colors) -> Recipe

local V = Vector3.new
local block, cyl, ball = Spec.block, Spec.cyl, Spec.ball

local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic
local WOOD = Enum.Material.Wood
local NEON = Enum.Material.Neon

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function handle(c: Colors, length: number?, thickness: number?): { Spec.Spec }
	local len = length or 1.4
	local th = thickness or 0.36
	return {
		cyl(len, th, V(0, 0, 0), c.Handle, { Name = "Handle", Material = PLASTIC }),
		ball(th + 0.14, V(0, -len / 2, 0), c.Accent, { Name = "Pommel", Material = METAL, Shadow = false }),
	}
end

-- Lame plate : corps + pointe en biseau + arête centrale plus claire.
local function flatBlade(c: Colors, baseY: number, length: number, width: number, thick: number): { Spec.Spec }
	local bodyLen = length - width * 0.6
	local out = {
		block(V(width, bodyLen, thick), V(0, baseY + bodyLen / 2, 0), c.Blade, { Name = "Blade", Material = METAL }),
		block(
			V(width * 0.28, bodyLen, thick + 0.06),
			V(0, baseY + bodyLen / 2, 0),
			lighten(c.Blade, 0.45),
			{ Name = "Edge", Material = METAL, Shadow = false }
		),
		block(
			V(width * 0.62, width * 0.35, thick * 0.8),
			V(0, baseY + bodyLen + width * 0.17, 0),
			c.Blade,
			{ Name = "TipA", Material = METAL }
		),
		block(
			V(width * 0.3, width * 0.3, thick * 0.6),
			V(0, baseY + bodyLen + width * 0.5, 0),
			c.Blade,
			{ Name = "TipB", Material = METAL }
		),
	}
	return out
end

local function guard(c: Colors, y: number, width: number): { Spec.Spec }
	return {
		block(V(width, 0.3, 0.5), V(0, y, 0), c.Accent, { Name = "Guard", Material = METAL }),
		ball(0.42, V(0, y, 0), lighten(c.Accent, 0.3), { Name = "Gem", Material = NEON, Shadow = false }),
	}
end

local function recipe(parts: { Spec.Spec }, tipY: number, baseY: number, length: number): Recipe
	return {
		Parts = parts,
		Tip = V(0, tipY, 0),
		TrailTop = V(0, tipY, 0),
		TrailBase = V(0, baseY, 0),
		Length = length,
	}
end

local function combine(...: { Spec.Spec }): { Spec.Spec }
	local out: { Spec.Spec } = {}
	for _, list in { ... } do
		Spec.append(out, list)
	end
	return out
end

local builders: { [string]: Builder } = {}

builders.Stick = function(c)
	return recipe(
		combine(
			{ cyl(4.6, 0.5, V(0, 1.7, 0), c.Blade, { Name = "Blade", Material = WOOD }) },
			{ cyl(1.3, 0.62, V(0, 0, 0), c.Handle, { Name = "Handle", Material = PLASTIC }) },
			{ ball(0.72, V(0, 4.1, 0), c.Blade, { Name = "Knob", Material = WOOD }) },
			{ cyl(0.35, 0.66, V(0, 3.2, 0), c.Accent, { Name = "Band", Material = PLASTIC, Shadow = false }) }
		),
		4.45,
		0.9,
		5.1
	)
end

builders.Club = function(c)
	return recipe(
		combine(
			handle(c, 1.5, 0.42),
			{ cyl(2.6, 0.9, V(0, 2, 0), c.Blade, { Name = "Blade", Material = WOOD }) },
			{ cyl(1.8, 1.45, V(0, 3.6, 0), c.Blade, { Name = "Head", Material = WOOD }) },
			{ ball(1.5, V(0, 4.5, 0), c.Blade, { Name = "Top", Material = WOOD }) },
			{ cyl(0.4, 1.6, V(0, 3.1, 0), c.Accent, { Name = "Band", Material = METAL, Shadow = false }) }
		),
		5.2,
		2.8,
		5.9
	)
end

builders.Fork = function(c)
	local prongs = {}
	for i = -1, 1 do
		table.insert(
			prongs,
			block(V(0.22, 1.7, 0.2), V(i * 0.42, 3.55, 0), c.Blade, { Name = "Prong", Material = METAL })
		)
	end
	return recipe(
		combine(
			handle(c, 1.6, 0.36),
			{ block(V(1.2, 0.35, 0.22), V(0, 2.55, 0), c.Blade, { Name = "Bridge", Material = METAL }) },
			{ cyl(1.9, 0.26, V(0, 1.6, 0), c.Blade, { Name = "Shaft", Material = METAL }) },
			prongs
		),
		4.4,
		1.6,
		5.2
	)
end

builders.Knife = function(c)
	return recipe(
		combine(handle(c, 1.3, 0.38), guard(c, 0.7, 1.1), flatBlade(c, 0.85, 2.6, 0.75, 0.16)),
		3.45,
		0.9,
		4.1
	)
end

builders.Dagger = function(c)
	return recipe(combine(handle(c, 1.2, 0.34), guard(c, 0.65, 1.5), flatBlade(c, 0.8, 3, 0.62, 0.15)), 3.8, 0.85, 4.4)
end

builders.Sword = function(c)
	return recipe(combine(handle(c, 1.5, 0.4), guard(c, 0.8, 2.2), flatBlade(c, 0.95, 4.6, 0.95, 0.2)), 5.55, 1, 6.3)
end

builders.Greatsword = function(c)
	return recipe(
		combine(
			handle(c, 2.1, 0.5),
			guard(c, 1.15, 3.1),
			flatBlade(c, 1.3, 7.2, 1.6, 0.28),
			{ block(V(0.9, 0.5, 0.34), V(0, 1.55, 0), c.Accent, { Name = "Ricasso", Material = METAL }) }
		),
		8.5,
		1.4,
		9.5
	)
end

builders.Katana = function(c)
	return recipe(
		combine(
			{ cyl(2.1, 0.38, V(0, 0, 0), c.Handle, { Name = "Handle", Material = PLASTIC }) },
			{ cyl(0.16, 1.2, V(0, 1.15, 0), c.Accent, { Name = "Tsuba", Material = METAL }) },
			{ ball(0.5, V(0, -1.1, 0), c.Accent, { Name = "Pommel", Material = METAL, Shadow = false }) },
			flatBlade(c, 1.25, 5.6, 0.62, 0.14)
		),
		6.85,
		1.3,
		7.9
	)
end

builders.Axe = function(c)
	return recipe(
		combine(
			{ cyl(4.6, 0.42, V(0, 1.2, 0), c.Handle, { Name = "Handle", Material = WOOD }) },
			{ block(V(0.3, 2.2, 2), V(0, 3.1, 0.9), c.Blade, { Name = "Head", Material = METAL }) },
			{
				block(V(0.2, 2.5, 0.5), V(0, 3.1, 2.2), lighten(c.Blade, 0.35), { Name = "Edge", Material = METAL }),
			},
			{ block(V(0.55, 1, 0.6), V(0, 3.1, -0.35), c.Accent, { Name = "Back", Material = METAL }) },
			{ ball(0.5, V(0, -1.2, 0), c.Accent, { Name = "Pommel", Material = METAL, Shadow = false }) }
		),
		4.2,
		2,
		5.8
	)
end

builders.Hammer = function(c)
	return recipe(
		combine(
			{ cyl(4.4, 0.46, V(0, 1.1, 0), c.Handle, { Name = "Handle", Material = WOOD }) },
			{ block(V(1.5, 1.7, 2.6), V(0, 3.9, 0), c.Blade, { Name = "Head", Material = METAL }) },
			{ block(V(1.62, 0.34, 2.72), V(0, 4.55, 0), c.Accent, { Name = "Cap", Material = METAL }) },
			{ block(V(1.62, 0.34, 2.72), V(0, 3.25, 0), c.Accent, { Name = "Cap2", Material = METAL }) },
			{ ball(0.55, V(0, -1.15, 0), c.Accent, { Name = "Pommel", Material = METAL, Shadow = false }) }
		),
		4.9,
		3.2,
		6.1
	)
end

builders.Spear = function(c)
	return recipe(
		combine(
			{ cyl(7, 0.34, V(0, 2, 0), c.Handle, { Name = "Handle", Material = WOOD }) },
			{ block(V(0.75, 1.3, 0.16), V(0, 6, 0), c.Blade, { Name = "Head", Material = METAL }) },
			{
				block(V(0.5, 0.6, 0.14), V(0, 6.95, 0), c.Blade, { Name = "PointA", Material = METAL }),
			},
			{ block(V(0.24, 0.5, 0.12), V(0, 7.45, 0), c.Blade, { Name = "PointB", Material = METAL }) },
			{ cyl(0.35, 0.6, V(0, 5.2, 0), c.Accent, { Name = "Collar", Material = METAL }) },
			{ cyl(0.3, 0.5, V(0, -1.5, 0), c.Accent, { Name = "Butt", Material = METAL, Shadow = false }) }
		),
		7.5,
		5.4,
		9
	)
end

builders.Trident = function(c)
	local out = combine(
		{ cyl(6.6, 0.34, V(0, 1.8, 0), c.Handle, { Name = "Handle", Material = WOOD }) },
		{ block(V(2.1, 0.34, 0.24), V(0, 5.1, 0), c.Blade, { Name = "Crossbar", Material = METAL }) },
		{ cyl(0.35, 0.55, V(0, 4.8, 0), c.Accent, { Name = "Collar", Material = METAL }) }
	)
	for i = -1, 1 do
		local height = if i == 0 then 2.4 else 1.7
		table.insert(
			out,
			block(V(0.28, height, 0.22), V(i * 0.9, 5.3 + height / 2, 0), c.Blade, { Name = "Prong", Material = METAL })
		)
		table.insert(
			out,
			block(
				V(0.14, 0.5, 0.16),
				V(i * 0.9, 5.3 + height + 0.25, 0),
				c.Blade,
				{ Name = "ProngTip", Material = METAL }
			)
		)
	end
	return recipe(out, 8.45, 5, 9.2)
end

builders.DoubleBlade = function(c)
	local top = flatBlade(c, 0.85, 3.6, 0.7, 0.16)
	local bottom: { Spec.Spec } = {}
	for _, spec in flatBlade(c, 0.85, 3.6, 0.7, 0.16) do
		-- lame basse : symétrique (miroir autour de l'origine)
		local mirrored = table.clone(spec)
		mirrored.CFrame = CFrame.Angles(math.pi, 0, 0) * spec.CFrame
		table.insert(bottom, mirrored)
	end
	return recipe(
		combine(
			{ cyl(1.5, 0.4, V(0, 0, 0), c.Handle, { Name = "Handle", Material = PLASTIC }) },
			{ cyl(0.2, 0.8, V(0, 0.8, 0), c.Accent, { Name = "GuardTop", Material = METAL }) },
			{ cyl(0.2, 0.8, V(0, -0.8, 0), c.Accent, { Name = "GuardBottom", Material = METAL }) },
			top,
			bottom
		),
		4.55,
		0.9,
		9.1
	)
end

builders.Scythe = function(c)
	local out = combine(
		{ cyl(7, 0.4, V(0, 1.8, 0), c.Handle, { Name = "Handle", Material = WOOD }) },
		{ cyl(0.4, 0.62, V(0, 5.2, 0), c.Accent, { Name = "Collar", Material = METAL }) },
		{ ball(0.5, V(0, -1.7, 0), c.Accent, { Name = "Pommel", Material = METAL, Shadow = false }) }
	)
	-- Lame courbe : segments inclinés qui s'amincissent vers la pointe.
	local segments = 5
	for i = 1, segments do
		local t = (i - 1) / (segments - 1)
		local angle = math.rad(-20 - 28 * t)
		local length = 1.35 - 0.12 * i
		local x = 0.2 + 1.05 * t * 2.4
		local y = 5.5 + 0.35 * t - 0.9 * t * t
		table.insert(
			out,
			block(
				V(0.2, 1.1 - 0.12 * i, length + 0.7),
				V(0, y - 0.1 * i, 0.6 + x * 0.9),
				c.Blade,
				{ Name = "Blade" .. i, Material = METAL, Rot = CFrame.Angles(angle, 0, 0) }
			)
		)
	end
	return recipe(out, 5.4, 4.7, 8.7)
end

builders.Mace = function(c)
	local out = combine(
		handle(c, 1.9, 0.44),
		{ cyl(2.4, 0.4, V(0, 1.9, 0), c.Handle, { Name = "Shaft", Material = WOOD }) },
		{ ball(1.7, V(0, 3.7, 0), c.Blade, { Name = "Head", Material = METAL }) }
	)
	for _, dir in { V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1), V(0, 1, 0) } do
		table.insert(
			out,
			ball(0.55, V(0, 3.7, 0) + dir * 0.95, c.Accent, { Name = "Spike", Material = METAL, Shadow = false })
		)
	end
	return recipe(out, 4.8, 2.9, 5.6)
end

builders.Staff = function(c)
	return recipe(
		combine(
			{ cyl(7.2, 0.4, V(0, 1.9, 0), c.Handle, { Name = "Handle", Material = WOOD }) },
			{ cyl(0.3, 0.7, V(0, 4.4, 0), c.Accent, { Name = "Ring", Material = METAL }) },
			{ ball(1.4, V(0, 5.6, 0), c.Blade, { Name = "Orb", Material = NEON }) },
			{ ball(0.9, V(0, 5.6, 0), lighten(c.Blade, 0.6), { Name = "Core", Material = NEON, Shadow = false }) },
			{
				block(
					V(0.18, 1.1, 0.18),
					V(0.75, 5.0, 0),
					c.Accent,
					{ Name = "ClawA", Material = METAL, Rot = CFrame.Angles(0, 0, math.rad(-25)) }
				),
			},
			{
				block(
					V(0.18, 1.1, 0.18),
					V(-0.75, 5.0, 0),
					c.Accent,
					{ Name = "ClawB", Material = METAL, Rot = CFrame.Angles(0, 0, math.rad(25)) }
				),
			}
		),
		6.3,
		4.9,
		9.2
	)
end

builders.EnergyBlade = function(c)
	local glow = lighten(c.Blade, 0.25)
	return recipe(
		combine(
			{ cyl(1.8, 0.5, V(0, 0, 0), c.Handle, { Name = "Handle", Material = METAL }) },
			{ cyl(0.3, 0.7, V(0, 0.95, 0), c.Accent, { Name = "Emitter", Material = METAL }) },
			{ cyl(0.2, 0.56, V(0, -0.5, 0), c.Accent, { Name = "Grip1", Material = NEON, Shadow = false }) },
			{ cyl(5.2, 0.36, V(0, 3.7, 0), glow, { Name = "Beam", Material = NEON, Shadow = false }) },
			{
				cyl(
					5.2,
					0.62,
					V(0, 3.7, 0),
					c.Blade,
					{ Name = "Glow", Material = NEON, Transparency = 0.7, Shadow = false }
				),
			},
			{ ball(0.62, V(0, 6.3, 0), glow, { Name = "BeamTip", Material = NEON, Shadow = false }) }
		),
		6.6,
		1.3,
		7.5
	)
end

local Recipes = {}

Recipes.Builders = builders

function Recipes.names(): { string }
	local names = {}
	for name in builders do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Recipes.build(archetype: string, colors: { Color3 }): Recipe
	local builder = builders[archetype]
	assert(builder, "archétype sans recette: " .. archetype)
	return builder({
		Blade = colors[1] or Color3.new(1, 1, 1),
		Handle = colors[2] or Color3.fromRGB(120, 80, 50),
		Accent = colors[3] or Color3.new(1, 1, 1),
	})
end

-- Utilitaires exposés pour les tests et l'affichage.
Recipes.darken = darken
Recipes.lighten = lighten

return Recipes
