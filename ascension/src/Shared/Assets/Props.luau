--!strict
--[[
	Props — bibliothèque modulaire d'assets « jouet / brique » : architecture, mobilier, décor,
	nature. Chaque recette est une fonction (palette, graine) -> { Spec }.

	Conventions (skill roblox-props-modeling) : origine = centre du sol, face avant = -Z ;
	grille de 4 studs pour l'architecture ; détails (liseré clair, plinthes) pour éviter le
	look « blockout » ; collision UNIQUEMENT sur les grosses pièces (murs, arbres, rochers).
]]

local Spec = require(script.Parent.Spec)

export type Recipe = (p: Spec.Palette, seed: number) -> { Spec.Spec }

local V = Vector3.new
local block, cyl, ball = Spec.block, Spec.cyl, Spec.ball
local PLASTIC = Enum.Material.SmoothPlastic
local WOOD = Enum.Material.Wood
local METAL = Enum.Material.Metal
local STONE = Enum.Material.Slate
local NEON = Enum.Material.Neon
local GRASS = Enum.Material.Grass

local function mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function seeded(seed: number): () -> number
	local state = (seed * 2654435761 + 97) % 4294967296
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local function brick(size: Vector3, pos: Vector3, color: Color3, p: Spec.Palette, opts: Spec.Opts?): { Spec.Spec }
	return Spec.brick(size, pos, color, p.Light, opts)
end

local function join(...: { Spec.Spec }): { Spec.Spec }
	local out: { Spec.Spec } = {}
	for _, list in { ... } do
		Spec.append(out, list)
	end
	return out
end

local R: { [string]: Recipe } = {}

---------------------------------------------------------------------------------------------
-- Architecture (modules sur grille de 4)
---------------------------------------------------------------------------------------------

R.Wall = function(p)
	return join(
		brick(V(8, 6, 1), V(0, 3, 0), p.Primary, p, { Material = PLASTIC, Collide = true, Name = "Wall" }),
		{ block(V(8.4, 0.6, 1.4), V(0, 0.3, 0), p.Dark, { Name = "Plinth", Material = PLASTIC }) },
		{ block(V(8.4, 0.5, 1.4), V(0, 6.1, 0), p.Secondary, { Name = "Cornice", Material = PLASTIC }) }
	)
end

R.WindowWall = function(p)
	return join(
		brick(V(8, 1.6, 1), V(0, 0.8, 0), p.Primary, p, { Collide = true, Name = "Sill" }),
		brick(V(8, 1.4, 1), V(0, 5.3, 0), p.Primary, p, { Collide = true, Name = "Lintel" }),
		brick(V(1.6, 3, 1), V(-3.2, 3.1, 0), p.Primary, p, { Collide = true, Name = "PostL" }),
		brick(V(1.6, 3, 1), V(3.2, 3.1, 0), p.Primary, p, { Collide = true, Name = "PostR" }),
		{
			block(
				V(4.8, 3, 0.2),
				V(0, 3.1, 0),
				p.Light,
				{ Name = "Glass", Material = Enum.Material.Glass, Transparency = 0.6, Collide = true }
			),
		},
		{ block(V(0.3, 3, 0.4), V(0, 3.1, 0), p.Dark, { Name = "Mullion", Material = PLASTIC }) }
	)
end

R.Floor = function(p)
	return join(brick(V(8, 0.6, 8), V(0, 0.3, 0), p.Secondary, p, { Collide = true, Name = "Slab" }), {
		block(
			V(3.6, 0.1, 3.6),
			V(-2, 0.62, -2),
			mix(p.Secondary, p.Light, 0.2),
			{ Name = "TileA", Material = PLASTIC, Shadow = false }
		),
	}, {
		block(
			V(3.6, 0.1, 3.6),
			V(2, 0.62, 2),
			mix(p.Secondary, p.Light, 0.2),
			{ Name = "TileB", Material = PLASTIC, Shadow = false }
		),
	})
end

R.Pillar = function(p)
	return join(
		{ block(V(2.6, 0.8, 2.6), V(0, 0.4, 0), p.Dark, { Name = "Base", Material = STONE, Collide = true }) },
		{ cyl(6, 1.8, V(0, 3.8, 0), p.Primary, { Name = "Shaft", Material = STONE, Collide = true }) },
		{ cyl(0.5, 2.3, V(0, 1.05, 0), p.Secondary, { Name = "Ring", Material = STONE }) },
		{ block(V(2.8, 0.8, 2.8), V(0, 7.2, 0), p.Secondary, { Name = "Capital", Material = STONE, Collide = true }) }
	)
end

R.Stairs = function(p)
	local out: { Spec.Spec } = {}
	for i = 1, 5 do
		Spec.append(
			out,
			brick(
				V(6, 0.8 * i, 1.6),
				V(0, 0.4 * i, -3.2 + i * 1.6),
				if i % 2 == 0 then p.Primary else p.Secondary,
				p,
				{ Collide = true, Name = "Step" .. i }
			)
		)
	end
	return out
end

R.Arch = function(p)
	return join(
		brick(V(2, 8, 2), V(-4, 4, 0), p.Primary, p, { Collide = true, Name = "LegL" }),
		brick(V(2, 8, 2), V(4, 4, 0), p.Primary, p, { Collide = true, Name = "LegR" }),
		brick(V(10, 2, 2), V(0, 9, 0), p.Secondary, p, { Collide = true, Name = "Beam" }),
		{ block(V(3, 1.2, 2.2), V(0, 10.6, 0), p.Accent, { Name = "Keystone", Material = PLASTIC }) }
	)
end

R.Door = function(p)
	return join(
		brick(V(1.2, 7.4, 1.2), V(-2.6, 3.7, 0), p.Dark, p, { Collide = true, Name = "FrameL" }),
		brick(V(1.2, 7.4, 1.2), V(2.6, 3.7, 0), p.Dark, p, { Collide = true, Name = "FrameR" }),
		brick(V(6.4, 1.2, 1.2), V(0, 7.8, 0), p.Dark, p, { Collide = true, Name = "FrameTop" }),
		{ block(V(4, 7, 0.4), V(0, 3.5, 0), p.Accent, { Name = "Leaf", Material = WOOD }) },
		{ ball(0.4, V(1.4, 3.4, -0.3), p.Light, { Name = "Handle", Material = METAL, Shadow = false }) }
	)
end

R.Platform = function(p)
	return join(
		{ cyl(1, 12, V(0, 0.5, 0), p.Secondary, { Name = "Base", Material = STONE, Collide = true }) },
		{ cyl(0.4, 10, V(0, 1.2, 0), p.Primary, { Name = "Top", Material = PLASTIC, Collide = true }) },
		{ cyl(0.12, 6, V(0, 1.45, 0), p.Accent, { Name = "Inlay", Material = NEON, Shadow = false }) }
	)
end

R.Podium = function(p)
	return join(
		brick(V(6, 1, 6), V(0, 0.5, 0), p.Primary, p, { Collide = true, Name = "Step1" }),
		brick(V(4.4, 1, 4.4), V(0, 1.5, 0), p.Secondary, p, { Collide = true, Name = "Step2" }),
		brick(V(2.8, 1, 2.8), V(0, 2.5, 0), p.Accent, p, { Collide = true, Name = "Step3" })
	)
end

R.Fence = function(p)
	local out: { Spec.Spec } = {
		block(V(8, 0.4, 0.4), V(0, 2.6, 0), p.Secondary, { Name = "RailTop", Material = WOOD }),
		block(V(8, 0.4, 0.4), V(0, 1.2, 0), p.Secondary, { Name = "RailLow", Material = WOOD }),
	}
	for i = 0, 4 do
		table.insert(
			out,
			block(
				V(0.6, 3.4, 0.6),
				V(-4 + i * 2, 1.7, 0),
				p.Primary,
				{ Name = "Post" .. i, Material = WOOD, Collide = true }
			)
		)
		table.insert(
			out,
			block(
				V(0.7, 0.3, 0.7),
				V(-4 + i * 2, 3.5, 0),
				p.Accent,
				{ Name = "Cap" .. i, Material = PLASTIC, Shadow = false }
			)
		)
	end
	return out
end

R.House = function(p)
	return join(
		brick(V(14, 8, 12), V(0, 4, 0), p.Primary, p, { Collide = true, Name = "Body" }),
		{ block(V(15, 0.8, 13), V(0, 0.4, 0), p.Dark, { Name = "Plinth", Material = STONE }) },
		{ block(V(16, 0.8, 14), V(0, 8.4, 0), p.Secondary, { Name = "Eave", Material = PLASTIC, Collide = true }) },
		{ block(V(12, 2, 10), V(0, 9.8, 0), p.Secondary, { Name = "Roof1", Material = PLASTIC, Collide = true }) },
		{ block(V(8, 2, 8), V(0, 11.8, 0), p.Secondary, { Name = "Roof2", Material = PLASTIC, Collide = true }) },
		{ block(V(4, 2, 6), V(0, 13.8, 0), p.Secondary, { Name = "Roof3", Material = PLASTIC, Collide = true }) },
		{ block(V(3.4, 5.4, 0.3), V(0, 2.7, -6.1), p.Accent, { Name = "Door", Material = WOOD }) },
		{
			block(
				V(3, 3, 0.3),
				V(-4.6, 4.8, -6.1),
				p.Light,
				{ Name = "WindowL", Material = Enum.Material.Glass, Transparency = 0.45 }
			),
		},
		{
			block(
				V(3, 3, 0.3),
				V(4.6, 4.8, -6.1),
				p.Light,
				{ Name = "WindowR", Material = Enum.Material.Glass, Transparency = 0.45 }
			),
		},
		{ block(V(2, 4, 2), V(4, 15.5, 1.5), p.Dark, { Name = "Chimney", Material = STONE }) }
	)
end

R.Tower = function(p)
	return join(
		brick(V(8, 10, 8), V(0, 5, 0), p.Primary, p, { Collide = true, Name = "Lower" }),
		brick(V(7, 8, 7), V(0, 14, 0), p.Secondary, p, { Collide = true, Name = "Upper" }),
		{ block(V(9, 1, 9), V(0, 18.5, 0), p.Dark, { Name = "Crown", Material = STONE, Collide = true }) },
		{ block(V(1.6, 1.4, 1.6), V(-3.7, 19.7, -3.7), p.Dark, { Name = "Merlon1", Material = STONE }) },
		{ block(V(1.6, 1.4, 1.6), V(3.7, 19.7, -3.7), p.Dark, { Name = "Merlon2", Material = STONE }) },
		{ block(V(1.6, 1.4, 1.6), V(-3.7, 19.7, 3.7), p.Dark, { Name = "Merlon3", Material = STONE }) },
		{ block(V(1.6, 1.4, 1.6), V(3.7, 19.7, 3.7), p.Dark, { Name = "Merlon4", Material = STONE }) },
		{ block(V(2, 3, 0.3), V(0, 14, -3.6), p.Light, { Name = "Window", Material = NEON, Shadow = false }) }
	)
end

---------------------------------------------------------------------------------------------
-- Mobilier (échelle : assise 1.5 studs)
---------------------------------------------------------------------------------------------

R.Table = function(p)
	local out = join(
		{ cyl(0.5, 5.2, V(0, 2.55, 0), p.Primary, { Name = "Top", Material = WOOD }) },
		{ cyl(0.15, 5.4, V(0, 2.2, 0), p.Dark, { Name = "Rim", Material = WOOD, Shadow = false }) },
		{ cyl(2.3, 1, V(0, 1.1, 0), p.Secondary, { Name = "Leg", Material = WOOD }) },
		{ cyl(0.4, 2.6, V(0, 0.2, 0), p.Dark, { Name = "Foot", Material = WOOD }) }
	)
	return out
end

R.Chair = function(p)
	local out = join(
		brick(V(1.8, 0.4, 1.8), V(0, 1.5, 0), p.Primary, p, { Name = "Seat", Material = PLASTIC }),
		{ block(V(1.8, 1.8, 0.35), V(0, 2.6, 0.75), p.Primary, { Name = "BackRest", Material = PLASTIC }) }
	)
	for _, x in { -0.7, 0.7 } do
		for _, z in { -0.7, 0.7 } do
			table.insert(
				out,
				block(V(0.3, 1.4, 0.3), V(x, 0.7, z), p.Dark, { Name = "Leg", Material = WOOD, Shadow = false })
			)
		end
	end
	return out
end

R.Bench = function(p)
	return join(
		brick(V(5, 0.5, 1.8), V(0, 1.7, 0), p.Primary, p, { Name = "Seat", Material = WOOD }),
		{ block(V(5, 1.4, 0.3), V(0, 2.8, 0.8), p.Primary, { Name = "BackRest", Material = WOOD }) },
		{ block(V(0.4, 1.5, 1.6), V(-2.2, 0.75, 0), p.Dark, { Name = "LegL", Material = METAL }) },
		{ block(V(0.4, 1.5, 1.6), V(2.2, 0.75, 0), p.Dark, { Name = "LegR", Material = METAL }) }
	)
end

R.Sofa = function(p)
	return join(
		brick(V(6.4, 1.2, 3), V(0, 1.1, 0), p.Primary, p, { Name = "Base", Material = PLASTIC }),
		{ block(V(6.4, 2, 0.9), V(0, 2.7, 1.05), p.Primary, { Name = "BackRest", Material = PLASTIC }) },
		{ block(V(0.9, 1.6, 3), V(-3.15, 2, 0), p.Secondary, { Name = "ArmL", Material = PLASTIC }) },
		{ block(V(0.9, 1.6, 3), V(3.15, 2, 0), p.Secondary, { Name = "ArmR", Material = PLASTIC }) },
		{
			block(
				V(2, 0.5, 2),
				V(-1.5, 1.95, -0.2),
				p.Accent,
				{ Name = "CushionL", Material = PLASTIC, Shadow = false }
			),
		},
		{ block(V(2, 0.5, 2), V(1.5, 1.95, -0.2), p.Accent, { Name = "CushionR", Material = PLASTIC, Shadow = false }) }
	)
end

R.Bed = function(p)
	return join(
		brick(V(4.8, 1, 6.6), V(0, 1, 0), p.Secondary, p, { Name = "Frame", Material = WOOD }),
		{ block(V(4.4, 0.9, 5.4), V(0, 1.9, -0.4), p.Light, { Name = "Mattress", Material = PLASTIC }) },
		{ block(V(4.8, 3.2, 0.5), V(0, 2.4, 3.2), p.Primary, { Name = "Headboard", Material = WOOD }) },
		{ block(V(3.4, 0.5, 1.4), V(0, 2.55, 2.2), p.Accent, { Name = "Pillow", Material = PLASTIC, Shadow = false }) },
		{ block(V(4.6, 0.3, 3), V(0, 2.45, -1.2), p.Accent, { Name = "Blanket", Material = PLASTIC, Shadow = false }) }
	)
end

R.Bookshelf = function(p)
	local out = join(
		{ block(V(0.4, 6, 1.4), V(-1.5, 3, 0), p.Primary, { Name = "SideL", Material = WOOD }) },
		{ block(V(0.4, 6, 1.4), V(1.5, 3, 0), p.Primary, { Name = "SideR", Material = WOOD }) },
		{ block(V(3.4, 6, 0.2), V(0, 3, 0.6), p.Dark, { Name = "Back", Material = WOOD, Shadow = false }) }
	)
	local colors = { p.Accent, p.Light, p.Secondary, p.Dark }
	for i = 0, 3 do
		table.insert(
			out,
			block(V(3, 0.25, 1.3), V(0, 0.5 + i * 1.6, 0), p.Primary, { Name = "Shelf" .. i, Material = WOOD })
		)
		for j = 0, 3 do
			table.insert(
				out,
				block(
					V(0.45, 1.1, 0.9),
					V(-1.05 + j * 0.7, 1.25 + i * 1.6, 0),
					colors[(i + j) % 4 + 1],
					{ Name = "Book", Material = PLASTIC, Shadow = false }
				)
			)
		end
	end
	return out
end

R.ChestProp = function(p)
	return join(
		brick(V(3.4, 1.8, 2.2), V(0, 0.9, 0), p.Primary, p, { Name = "Box", Material = WOOD }),
		{
			cyl(
				2.2,
				3.4,
				V(0, 1.8, 0),
				p.Primary,
				{ Name = "Lid", Material = WOOD, Rot = CFrame.Angles(math.pi / 2, 0, 0) }
			),
		},
		{ block(V(0.5, 2, 2.4), V(-1.3, 1.1, 0), p.Accent, { Name = "StrapL", Material = METAL, Shadow = false }) },
		{ block(V(0.5, 2, 2.4), V(1.3, 1.1, 0), p.Accent, { Name = "StrapR", Material = METAL, Shadow = false }) },
		{ block(V(0.7, 0.8, 0.3), V(0, 1.7, -1.2), p.Light, { Name = "Lock", Material = METAL, Shadow = false }) }
	)
end

---------------------------------------------------------------------------------------------
-- Décor
---------------------------------------------------------------------------------------------

R.Plant = function(p)
	return join(
		{ cyl(1.2, 1.5, V(0, 0.6, 0), p.Accent, { Name = "Pot", Material = PLASTIC }) },
		{ cyl(0.15, 1.3, V(0, 1.2, 0), p.Dark, { Name = "Soil", Material = Enum.Material.Ground, Shadow = false }) },
		{ ball(1.6, V(0, 2.2, 0), Color3.fromRGB(70, 180, 90), { Name = "Leaf1", Material = GRASS }) },
		{
			ball(
				1.1,
				V(-0.7, 2.7, 0.2),
				Color3.fromRGB(96, 206, 110),
				{ Name = "Leaf2", Material = GRASS, Shadow = false }
			),
		},
		{
			ball(
				1,
				V(0.7, 2.6, -0.2),
				Color3.fromRGB(56, 160, 80),
				{ Name = "Leaf3", Material = GRASS, Shadow = false }
			),
		}
	)
end

R.FloorLamp = function(p)
	return join(
		{ cyl(0.3, 1.6, V(0, 0.15, 0), p.Dark, { Name = "Base", Material = METAL }) },
		{ cyl(5, 0.22, V(0, 2.8, 0), p.Dark, { Name = "Pole", Material = METAL }) },
		{
			cyl(
				1.4,
				1.7,
				V(0, 5.8, 0),
				p.Light,
				{ Name = "Shade", Material = Enum.Material.Neon, Transparency = 0.15, Shadow = false }
			),
		},
		{ cyl(0.2, 1.9, V(0, 6.6, 0), p.Accent, { Name = "Cap", Material = METAL, Shadow = false }) }
	)
end

R.Crate = function(p)
	return join(
		brick(V(3, 3, 3), V(0, 1.5, 0), p.Primary, p, { Name = "Box", Material = WOOD, Collide = true }),
		{ block(V(3.1, 0.35, 3.1), V(0, 0.25, 0), p.Dark, { Name = "BandLow", Material = WOOD }) },
		{ block(V(3.1, 0.35, 3.1), V(0, 2.75, 0), p.Dark, { Name = "BandHigh", Material = WOOD }) },
		{ block(V(0.4, 3.1, 3.1), V(0, 1.5, 0), p.Dark, { Name = "BandMid", Material = WOOD, Shadow = false }) }
	)
end

R.Barrel = function(p)
	return join(
		{ cyl(3, 2.4, V(0, 1.5, 0), p.Primary, { Name = "Body", Material = WOOD, Collide = true }) },
		{ cyl(0.3, 2.6, V(0, 0.6, 0), p.Dark, { Name = "HoopLow", Material = METAL }) },
		{ cyl(0.3, 2.6, V(0, 2.4, 0), p.Dark, { Name = "HoopHigh", Material = METAL }) },
		{ cyl(0.1, 2.1, V(0, 3.02, 0), p.Secondary, { Name = "Lid", Material = WOOD, Shadow = false }) }
	)
end

R.Flag = function(p)
	return join(
		{ cyl(9, 0.3, V(0, 4.5, 0), p.Dark, { Name = "Pole", Material = METAL }) },
		{ ball(0.6, V(0, 9.1, 0), p.Light, { Name = "Finial", Material = METAL, Shadow = false }) },
		{ block(V(0.15, 3, 4), V(0, 7.4, -2.2), p.Accent, { Name = "Cloth", Material = Enum.Material.Fabric }) },
		{
			block(
				V(0.18, 0.7, 4),
				V(0, 7.4, -2.2),
				p.Light,
				{ Name = "Stripe", Material = Enum.Material.Fabric, Shadow = false }
			),
		},
		{ cyl(0.5, 1.8, V(0, 0.25, 0), p.Secondary, { Name = "Base", Material = STONE }) }
	)
end

R.Signpost = function(p)
	return join(
		{ cyl(5, 0.5, V(0, 2.5, 0), p.Secondary, { Name = "Post", Material = WOOD }) },
		{ block(V(4, 1.6, 0.4), V(0.8, 4.4, -0.3), p.Primary, { Name = "BoardA", Material = WOOD }) },
		{ block(V(3.4, 1.4, 0.4), V(-0.5, 2.7, -0.3), p.Accent, { Name = "BoardB", Material = WOOD }) },
		{ cyl(0.3, 0.9, V(0, 5.1, 0), p.Dark, { Name = "Top", Material = WOOD, Shadow = false }) }
	)
end

R.Statue = function(p)
	return join(
		brick(V(4, 1.2, 4), V(0, 0.6, 0), p.Dark, p, { Name = "Plinth", Material = STONE, Collide = true }),
		{ block(V(1.6, 2.6, 1.1), V(0, 2.5, 0), p.Primary, { Name = "Body", Material = STONE }) },
		{ ball(1.3, V(0, 4.3, 0), p.Primary, { Name = "Head", Material = STONE }) },
		{ block(V(0.6, 2.2, 0.6), V(-1.15, 2.6, 0), p.Primary, { Name = "ArmL", Material = STONE }) },
		{
			block(
				V(0.6, 3.4, 0.6),
				V(1.15, 3.2, 0),
				p.Primary,
				{ Name = "ArmR", Material = STONE, Rot = CFrame.Angles(0, 0, math.rad(-12)) }
			),
		},
		{ block(V(0.3, 3.6, 0.7), V(1.7, 5.5, 0), p.Accent, { Name = "Sword", Material = METAL }) },
		{ block(V(0.8, 1.6, 0.8), V(-0.4, 1.0, 0), p.Primary, { Name = "LegL", Material = STONE, Shadow = false }) }
	)
end

R.Trophy = function(p)
	return join(
		brick(V(3, 1, 3), V(0, 0.5, 0), p.Dark, p, { Name = "Base", Material = STONE }),
		{ cyl(1.6, 0.7, V(0, 1.8, 0), p.Accent, { Name = "Stem", Material = METAL }) },
		{ cyl(2, 2.4, V(0, 3.6, 0), p.Accent, { Name = "Cup", Material = METAL }) },
		{ ball(0.9, V(-1.5, 3.6, 0), p.Accent, { Name = "HandleL", Material = METAL, Shadow = false }) },
		{ ball(0.9, V(1.5, 3.6, 0), p.Accent, { Name = "HandleR", Material = METAL, Shadow = false }) },
		{ ball(0.7, V(0, 5, 0), p.Light, { Name = "Star", Material = NEON, Shadow = false }) }
	)
end

R.Anvil = function(p)
	return join(
		{ block(V(2.2, 1.2, 2.2), V(0, 0.6, 0), p.Dark, { Name = "Base", Material = METAL }) },
		{ block(V(1.4, 1, 1.4), V(0, 1.7, 0), p.Dark, { Name = "Waist", Material = METAL }) },
		{ block(V(3.6, 1, 1.8), V(0, 2.7, 0), p.Primary, { Name = "Top", Material = METAL }) },
		{ block(V(1.2, 0.6, 1.2), V(2.2, 2.8, 0), p.Primary, { Name = "Horn", Material = METAL, Shadow = false }) }
	)
end

R.Forge = function(p)
	return join(
		brick(V(5, 3.4, 4), V(0, 1.7, 0), p.Dark, p, { Name = "Body", Material = STONE, Collide = true }),
		{
			block(
				V(3.4, 1.6, 0.5),
				V(0, 1.7, -2.05),
				Color3.fromRGB(255, 120, 40),
				{ Name = "Fire", Material = NEON, Shadow = false }
			),
		},
		{ block(V(1.6, 3.4, 1.6), V(0, 5, 0.6), p.Secondary, { Name = "Chimney", Material = STONE }) },
		{ ball(0.8, V(0, 7, 0.6), p.Light, { Name = "Smoke", Material = PLASTIC, Transparency = 0.5, Shadow = false }) }
	)
end

R.Generator = function(p)
	return join(
		brick(V(5, 4, 3.6), V(0, 2, 0), p.Primary, p, { Name = "Body", Material = METAL, Collide = true }),
		{ cyl(1.2, 2.4, V(0, 4.6, 0), p.Dark, { Name = "Turbine", Material = METAL }) },
		{ block(V(3.6, 0.5, 0.2), V(0, 3.2, -1.85), p.Accent, { Name = "Vent", Material = NEON, Shadow = false }) },
		{ block(V(0.6, 0.6, 0.2), V(1.8, 1.2, -1.85), p.Light, { Name = "Light", Material = NEON, Shadow = false }) }
	)
end

R.NeonSign = function(p)
	return join(
		{ block(V(0.6, 6, 0.6), V(0, 3, 0), p.Dark, { Name = "Pole", Material = METAL }) },
		{ block(V(6, 2.4, 0.5), V(0, 6.6, 0), p.Dark, { Name = "Frame", Material = METAL }) },
		{ block(V(5.4, 0.35, 0.3), V(0, 7.2, -0.3), p.Accent, { Name = "TubeA", Material = NEON, Shadow = false }) },
		{ block(V(3.6, 0.35, 0.3), V(0, 6.5, -0.3), p.Light, { Name = "TubeB", Material = NEON, Shadow = false }) },
		{ block(V(4.6, 0.35, 0.3), V(0, 5.9, -0.3), p.Accent, { Name = "TubeC", Material = NEON, Shadow = false }) }
	)
end

R.Terminal = function(p)
	return join(
		brick(V(3, 4.4, 2), V(0, 2.2, 0), p.Dark, p, { Name = "Body", Material = METAL, Collide = true }),
		{ block(V(2.4, 1.6, 0.2), V(0, 3.4, -1.05), p.Accent, { Name = "Screen", Material = NEON, Shadow = false }) },
		{ block(V(2.4, 0.8, 0.2), V(0, 2, -1.05), p.Secondary, { Name = "Keys", Material = PLASTIC, Shadow = false }) }
	)
end

R.Torch = function(p)
	return join(
		{ cyl(3.6, 0.4, V(0, 1.8, 0), p.Secondary, { Name = "Handle", Material = WOOD }) },
		{ cyl(0.6, 0.9, V(0, 3.6, 0), p.Dark, { Name = "Cup", Material = METAL }) },
		{ ball(1, V(0, 4.3, 0), Color3.fromRGB(255, 160, 40), { Name = "Flame", Material = NEON, Shadow = false }) }
	)
end

R.Orb = function(p)
	return join(
		{ cyl(0.6, 2.4, V(0, 0.3, 0), p.Dark, { Name = "Stand", Material = STONE }) },
		{ ball(2.4, V(0, 2.2, 0), p.Accent, { Name = "Sphere", Material = NEON, Transparency = 0.2 }) },
		{ ball(1.2, V(0, 2.2, 0), p.Light, { Name = "Core", Material = NEON, Shadow = false }) }
	)
end

---------------------------------------------------------------------------------------------
-- Nature
---------------------------------------------------------------------------------------------

R.Tree = function(p, seed)
	local rnd = seeded(seed)
	local green = mix(Color3.fromRGB(70, 180, 80), p.Secondary, 0.25)
	local out = join(
		{
			cyl(
				4.5,
				1.4,
				V(0, 2.25, 0),
				Color3.fromRGB(130, 90, 55),
				{ Name = "Trunk", Material = WOOD, Collide = true }
			),
		},
		{ ball(6.4, V(0, 6.6, 0), green, { Name = "Crown", Material = GRASS, Collide = true }) },
		{ ball(4.4, V(2.2 + rnd(), 5.2, 0.8), mix(green, p.Light, 0.12), { Name = "CrownB", Material = GRASS }) },
		{ ball(4, V(-2.4, 5.6 + rnd(), -0.8), mix(green, p.Dark, 0.12), { Name = "CrownC", Material = GRASS }) },
		{
			ball(
				3.2,
				V(0.3, 9.3, rnd() - 0.5),
				mix(green, p.Light, 0.2),
				{ Name = "CrownD", Material = GRASS, Shadow = false }
			),
		}
	)
	return out
end

R.PineTree = function(p)
	local out: { Spec.Spec } = {
		cyl(2.4, 1.1, V(0, 1.2, 0), Color3.fromRGB(110, 78, 50), { Name = "Trunk", Material = WOOD, Collide = true }),
	}
	local green = mix(Color3.fromRGB(40, 120, 80), p.Dark, 0.1)
	for i = 0, 3 do
		table.insert(
			out,
			cyl(
				1.6,
				6 - i * 1.4,
				V(0, 3.2 + i * 1.5, 0),
				mix(green, p.Light, i * 0.08),
				{ Name = "Tier" .. i, Material = GRASS, Collide = i == 0 }
			)
		)
	end
	table.insert(
		out,
		ball(0.8, V(0, 9.4, 0), p.Light, { Name = "Snow", Material = Enum.Material.Snow, Shadow = false })
	)
	return out
end

R.Rock = function(p, seed)
	local rnd = seeded(seed)
	local out: { Spec.Spec } = {}
	for i = 1, 4 do
		local s = 2 + rnd() * 2.4 - i * 0.2
		table.insert(
			out,
			block(
				V(s * 1.3, s, s * 1.1),
				V((rnd() - 0.5) * 2.4, s * 0.45, (rnd() - 0.5) * 2.4),
				mix(p.Primary, p.Dark, rnd() * 0.4),
				{
					Name = "Stone" .. i,
					Material = STONE,
					Collide = true,
					Rot = CFrame.Angles(rnd() * 0.5, rnd() * math.pi, rnd() * 0.5),
				}
			)
		)
	end
	return out
end

R.Flower = function(p, seed)
	local rnd = seeded(seed)
	local petals =
		{ p.Accent, Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 220, 90), Color3.fromRGB(150, 130, 255) }
	local color = petals[math.floor(rnd() * #petals) + 1]
	return join({
		cyl(1.5, 0.15, V(0, 0.75, 0), Color3.fromRGB(70, 160, 80), { Name = "Stem", Material = GRASS, Shadow = false }),
	}, { ball(0.9, V(0, 1.7, 0), color, { Name = "Bloom", Material = PLASTIC, Shadow = false }) }, {
		ball(
			0.4,
			V(0, 1.9, -0.3),
			Color3.fromRGB(255, 240, 150),
			{ Name = "Center", Material = PLASTIC, Shadow = false }
		),
	})
end

R.FlowerBed = function(p, seed)
	local out: { Spec.Spec } = brick(V(5.4, 0.8, 3), V(0, 0.4, 0), p.Dark, p, { Name = "Bed", Material = STONE })
	for i = 0, 5 do
		local flower = R.Flower(p, seed + i)
		for _, spec in flower do
			local shifted = table.clone(spec)
			shifted.CFrame = CFrame.new(-2.2 + (i % 3) * 2.2, 0.8, -0.8 + (i // 3) * 1.6) * spec.CFrame
			table.insert(out, shifted)
		end
	end
	return out
end

R.Mushroom = function(p)
	return join(
		{ cyl(1.6, 0.9, V(0, 0.8, 0), Color3.fromRGB(250, 240, 220), { Name = "Stem", Material = PLASTIC }) },
		{ ball(2.6, V(0, 2.1, 0), p.Accent, { Name = "Cap", Material = PLASTIC }) },
		{ ball(0.5, V(0.7, 3, -0.4), p.Light, { Name = "Dot1", Material = PLASTIC, Shadow = false }) },
		{ ball(0.4, V(-0.6, 2.9, 0.6), p.Light, { Name = "Dot2", Material = PLASTIC, Shadow = false }) }
	)
end

R.Log = function(p)
	return join({
		Spec.cylZ(5, 1.6, V(0, 0.8, 0), Color3.fromRGB(120, 84, 52), { Name = "Log", Material = WOOD, Collide = true }),
	}, {
		Spec.cylZ(
			0.1,
			1.2,
			V(0, 0.8, -2.52),
			Color3.fromRGB(210, 170, 120),
			{ Name = "Rings", Material = WOOD, Shadow = false }
		),
	}, { ball(0.7, V(0.2, 1.7, 1), p.Accent, { Name = "Moss", Material = GRASS, Shadow = false }) })
end

R.Cactus = function(p)
	local green = Color3.fromRGB(60, 160, 100)
	return join(
		{ cyl(5, 1.7, V(0, 2.5, 0), green, { Name = "Trunk", Material = GRASS, Collide = true }) },
		{ ball(1.7, V(0, 5, 0), green, { Name = "Top", Material = GRASS, Shadow = false }) },
		{ cyl(1.8, 0.9, V(1.5, 3, 0), green, { Name = "ArmA", Material = GRASS }) },
		{ block(V(1.6, 0.9, 0.9), V(0.9, 2.2, 0), green, { Name = "ArmJoin", Material = GRASS }) },
		{ ball(0.9, V(1.5, 4, 0), p.Accent, { Name = "Flower", Material = PLASTIC, Shadow = false }) }
	)
end

R.Crystal = function(p, seed)
	local rnd = seeded(seed)
	local out: { Spec.Spec } = {}
	for i = 1, 4 do
		local height = 2.5 + rnd() * 3.5
		table.insert(
			out,
			block(
				V(0.9, height, 0.9),
				V((rnd() - 0.5) * 2, height / 2 - 0.2, (rnd() - 0.5) * 2),
				mix(p.Accent, p.Light, rnd() * 0.4),
				{
					Name = "Shard" .. i,
					Material = NEON,
					Transparency = 0.15,
					Collide = i == 1,
					Rot = CFrame.Angles((rnd() - 0.5) * 0.4, rnd() * math.pi, (rnd() - 0.5) * 0.4),
				}
			)
		)
	end
	return out
end

R.CrystalProp = R.Crystal

R.Cloud = function(p, seed)
	local rnd = seeded(seed)
	local out: { Spec.Spec } = {}
	for i = 1, 5 do
		table.insert(
			out,
			ball(
				4 + rnd() * 3,
				V((i - 3) * 2.6, 2 + rnd() * 1.4, (rnd() - 0.5) * 2),
				mix(Color3.new(1, 1, 1), p.Light, 0.2),
				{ Name = "Puff" .. i, Material = PLASTIC, Shadow = false }
			)
		)
	end
	return out
end

R.Snowman = function(p)
	return join(
		{ ball(4, V(0, 2, 0), Color3.new(1, 1, 1), { Name = "Bottom", Material = Enum.Material.Snow, Collide = true }) },
		{ ball(3, V(0, 5, 0), Color3.new(1, 1, 1), { Name = "Middle", Material = Enum.Material.Snow }) },
		{ ball(2.2, V(0, 7.3, 0), Color3.new(1, 1, 1), { Name = "Head", Material = Enum.Material.Snow }) },
		{
			block(
				V(0.3, 0.3, 1),
				V(0, 7.3, -1.4),
				Color3.fromRGB(255, 140, 40),
				{ Name = "Nose", Material = PLASTIC, Shadow = false }
			),
		},
		{ cyl(0.8, 1.6, V(0, 8.8, 0), p.Dark, { Name = "Hat", Material = PLASTIC, Shadow = false }) }
	)
end

R.LavaPool = function(p)
	return join({ cyl(0.4, 9, V(0, 0.2, 0), Color3.fromRGB(70, 50, 50), { Name = "Rim", Material = STONE }) }, {
		cyl(0.2, 7.6, V(0, 0.45, 0), Color3.fromRGB(255, 100, 30), { Name = "Lava", Material = NEON, Shadow = false }),
	}, {
		ball(1, V(1.2, 0.7, 0.8), Color3.fromRGB(255, 190, 70), { Name = "Bubble", Material = NEON, Shadow = false }),
	})
end

R.Mountain = function(p)
	local out: { Spec.Spec } = {}
	local layers = { { 30, 12 }, { 22, 12 }, { 15, 12 }, { 9, 10 }, { 4, 8 } }
	local y = 0
	for i, layer in layers do
		local size, height = layer[1], layer[2]
		table.insert(
			out,
			block(
				V(size, height, size),
				V(0, y + height / 2, 0),
				mix(p.Primary, if i >= 4 then Color3.new(1, 1, 1) else p.Dark, if i >= 4 then 0.7 else i * 0.1),
				{
					Name = "Tier" .. i,
					Material = STONE,
					Collide = true,
					Shadow = false,
					Rot = CFrame.Angles(0, math.rad(i * 11), 0),
				}
			)
		)
		y += height * 0.82
	end
	return out
end

R.Island = function(p)
	local out: { Spec.Spec } = {
		cyl(3, 22, V(0, 1.5, 0), p.Secondary, { Name = "Top", Material = GRASS, Collide = true }),
		cyl(5, 17, V(0, -2.5, 0), p.Dark, { Name = "Mid", Material = STONE, Collide = true }),
		cyl(5, 11, V(0, -7.5, 0), p.Dark, { Name = "Low", Material = STONE, Shadow = false }),
		cyl(4, 5, V(0, -12, 0), p.Dark, { Name = "Tip", Material = STONE, Shadow = false }),
	}
	return out
end

---------------------------------------------------------------------------------------------
-- Statue/pilier divins, bannière, étagère d'armes (support de la base)
---------------------------------------------------------------------------------------------

R.WeaponRack = function(p)
	local out = join(
		{ block(V(7.6, 0.5, 1.6), V(0, 0.25, 0), p.Dark, { Name = "Foot", Material = WOOD }) },
		{ block(V(0.5, 5.4, 0.5), V(-3.5, 2.7, 0.3), p.Primary, { Name = "PostL", Material = WOOD }) },
		{ block(V(0.5, 5.4, 0.5), V(3.5, 2.7, 0.3), p.Primary, { Name = "PostR", Material = WOOD }) },
		{ block(V(7.5, 0.4, 0.4), V(0, 1.6, 0.3), p.Secondary, { Name = "BarLow", Material = WOOD }) },
		{ block(V(7.5, 0.4, 0.4), V(0, 3.4, 0.3), p.Secondary, { Name = "BarHigh", Material = WOOD }) },
		{
			block(
				V(7.5, 5.2, 0.2),
				V(0, 2.7, 0.7),
				mix(p.Primary, p.Dark, 0.4),
				{ Name = "Back", Material = WOOD, Shadow = false }
			),
		},
		{ block(V(8, 0.5, 0.9), V(0, 5.55, 0.3), p.Accent, { Name = "Sign", Material = PLASTIC }) }
	)
	return out
end

R.Banner = function(p)
	return join(
		{ block(V(0.4, 9, 0.4), V(0, 4.5, 0), p.Dark, { Name = "Pole", Material = METAL }) },
		{ block(V(3.2, 0.3, 0.3), V(0, 8.7, 0), p.Dark, { Name = "Bar", Material = METAL }) },
		{ block(V(2.8, 5.4, 0.15), V(0, 5.8, -0.2), p.Accent, { Name = "Cloth", Material = Enum.Material.Fabric }) },
		{
			block(
				V(2.8, 0.8, 0.17),
				V(0, 6.8, -0.2),
				p.Light,
				{ Name = "Stripe", Material = Enum.Material.Fabric, Shadow = false }
			),
		},
		{
			block(
				V(2.8, 0.8, 0.17),
				V(0, 3.6, -0.2),
				p.Light,
				{ Name = "Fringe", Material = Enum.Material.Fabric, Shadow = false }
			),
		}
	)
end

R.Brazier = function(p)
	return join(
		{ cyl(1.6, 1.2, V(0, 0.8, 0), p.Dark, { Name = "Leg", Material = METAL }) },
		{ cyl(0.8, 2.6, V(0, 2, 0), p.Dark, { Name = "Bowl", Material = METAL }) },
		{ ball(1.6, V(0, 3, 0), Color3.fromRGB(255, 150, 50), { Name = "Fire", Material = NEON, Shadow = false }) },
		{
			ball(
				0.9,
				V(0.3, 3.7, 0),
				Color3.fromRGB(255, 220, 110),
				{ Name = "Flame", Material = NEON, Shadow = false }
			),
		}
	)
end

R.Fountain = function(p)
	return join(
		{ cyl(1.2, 12, V(0, 0.6, 0), p.Primary, { Name = "Basin", Material = STONE, Collide = true }) },
		{
			cyl(
				0.3,
				10.6,
				V(0, 1.3, 0),
				p.Accent,
				{ Name = "Water", Material = Enum.Material.Glass, Transparency = 0.35, Shadow = false }
			),
		},
		{ cyl(3.6, 1.6, V(0, 2.6, 0), p.Secondary, { Name = "Column", Material = STONE }) },
		{ cyl(0.8, 5, V(0, 4.4, 0), p.Primary, { Name = "Bowl", Material = STONE }) },
		{ ball(1.2, V(0, 5.3, 0), p.Light, { Name = "Spout", Material = NEON, Shadow = false }) }
	)
end

R.Gate = function(p)
	return join(
		brick(V(2, 9, 2), V(-5, 4.5, 0), p.Primary, p, { Name = "PostL", Collide = true }),
		brick(V(2, 9, 2), V(5, 4.5, 0), p.Primary, p, { Name = "PostR", Collide = true }),
		{ block(V(12, 1.4, 1.4), V(0, 9.2, 0), p.Secondary, { Name = "Lintel", Material = PLASTIC, Collide = true }) },
		{ block(V(8, 1.8, 0.4), V(0, 9.4, -0.8), p.Accent, { Name = "Sign", Material = NEON, Shadow = false }) },
		{ ball(1.4, V(-5, 9.7, 0), p.Light, { Name = "OrbL", Material = NEON, Shadow = false }) },
		{ ball(1.4, V(5, 9.7, 0), p.Light, { Name = "OrbR", Material = NEON, Shadow = false }) }
	)
end

R.Bridge = function(p)
	local out: { Spec.Spec } = {}
	for i = 0, 3 do
		table.insert(
			out,
			block(
				V(8, 0.5, 2),
				V(0, 0.25, -3 + i * 2.05),
				mix(p.Primary, p.Dark, (i % 2) * 0.2),
				{ Name = "Plank" .. i, Material = WOOD, Collide = true }
			)
		)
	end
	table.insert(out, block(V(0.4, 2.2, 8.4), V(-4, 1.5, 0), p.Secondary, { Name = "RailL", Material = WOOD }))
	table.insert(out, block(V(0.4, 2.2, 8.4), V(4, 1.5, 0), p.Secondary, { Name = "RailR", Material = WOOD }))
	return out
end

local Props = {}

Props.Recipes = R

function Props.names(): { string }
	local names = {}
	for name in R do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Props.build(name: string, palette: Spec.Palette, seed: number?): { Spec.Spec }
	local recipe = R[name]
	assert(recipe, "prop inconnu: " .. name)
	return recipe(palette, seed or 1)
end

-- Palette neutre « jouet » pour la base du joueur et les aperçus.
Props.DefaultPalette = {
	Primary = Color3.fromRGB(226, 182, 118),
	Secondary = Color3.fromRGB(120, 168, 235),
	Accent = Color3.fromRGB(235, 90, 80),
	Dark = Color3.fromRGB(86, 70, 62),
	Light = Color3.fromRGB(255, 244, 214),
} :: Spec.Palette

-- Palette dérivée de la palette d'une zone (Config/Zones).
function Props.zonePalette(
	zonePalette: { Ground: Color3, Accent: Color3, Prop: Color3, Sky: Color3, Glow: Color3 }
): Spec.Palette
	return {
		Primary = zonePalette.Prop,
		Secondary = zonePalette.Ground,
		Accent = zonePalette.Accent,
		Dark = zonePalette.Prop:Lerp(Color3.new(0, 0, 0), 0.45),
		Light = zonePalette.Glow,
	}
end

return Props
