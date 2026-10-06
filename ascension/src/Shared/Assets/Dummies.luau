--!strict
--[[
	Dummies — mannequins d'entraînement et boss, un par zone (même squelette, accessoires
	propres à chaque royaume). Repère des props : origine = sol, face avant = -Z.
	`HitHeight` donne la hauteur du point d'impact (centre du torse) pour les effets.
]]

local Spec = require(script.Parent.Spec)
local Zones = require(script.Parent.Parent.Config.Zones)

local V = Vector3.new
local block, cyl, ball = Spec.block, Spec.cyl, Spec.ball

local Dummies = {}

local function scaleSpecs(specs: { Spec.Spec }, scale: number): { Spec.Spec }
	if scale == 1 then
		return specs
	end
	local out: { Spec.Spec } = {}
	for _, spec in specs do
		local copy = table.clone(spec)
		copy.Size = spec.Size * scale
		copy.CFrame = CFrame.new(spec.CFrame.Position * scale) * (spec.CFrame - spec.CFrame.Position)
		table.insert(out, copy)
	end
	return out
end

-- Accessoires par zone (reconnaissables d'un coup d'œil).
local ACCESSORIES: { [string]: (zone: Zones.Zone, color: Color3) -> { Spec.Spec } } = {
	Village = function(zone)
		return {
			cyl(
				0.5,
				3.6,
				V(0, 7.6, 0),
				Color3.fromRGB(230, 190, 90),
				{ Name = "StrawHatBrim", Material = Enum.Material.Fabric }
			),
			cyl(
				1,
				2.1,
				V(0, 8.2, 0),
				Color3.fromRGB(230, 190, 90),
				{ Name = "StrawHatTop", Material = Enum.Material.Fabric }
			),
			block(
				V(0.3, 0.3, 1.4),
				V(-1.3, 3.6, 0),
				zone.Palette.Accent,
				{ Name = "Patch", Material = Enum.Material.Fabric, Shadow = false }
			),
		}
	end,
	Forest = function()
		return {
			ball(1.8, V(-1.2, 7.8, 0), Color3.fromRGB(70, 170, 80), { Name = "LeafA", Material = Enum.Material.Grass }),
			ball(
				1.5,
				V(1.2, 7.9, 0.2),
				Color3.fromRGB(96, 200, 100),
				{ Name = "LeafB", Material = Enum.Material.Grass }
			),
		}
	end,
	Desert = function(zone)
		return {
			block(
				V(0.5, 3, 0.5),
				V(-1.8, 5.2, 0),
				Color3.fromRGB(70, 170, 100),
				{ Name = "SpikeL", Material = Enum.Material.Grass }
			),
			ball(
				1,
				V(1.6, 7.2, 0),
				zone.Palette.Accent,
				{ Name = "Bloom", Material = Enum.Material.SmoothPlastic, Shadow = false }
			),
			cyl(
				0.5,
				3.4,
				V(0, 7.5, 0),
				Color3.fromRGB(235, 220, 190),
				{ Name = "Turban", Material = Enum.Material.Fabric }
			),
		}
	end,
	Ice = function()
		return {
			cyl(
				1,
				2.2,
				V(0, 8.2, 0),
				Color3.fromRGB(40, 60, 100),
				{ Name = "Hat", Material = Enum.Material.SmoothPlastic }
			),
			block(
				V(0.3, 0.3, 1.6),
				V(0, 6.2, -1.4),
				Color3.fromRGB(255, 140, 40),
				{ Name = "Nose", Material = Enum.Material.SmoothPlastic, Shadow = false }
			),
		}
	end,
	Volcano = function(zone)
		return {
			block(V(0.5, 1.6, 0.5), V(-0.8, 8.2, 0), zone.Palette.Accent, {
				Name = "HornL",
				Material = Enum.Material.Neon,
				Shadow = false,
				Rot = CFrame.Angles(0, 0, math.rad(15)),
			}),
			block(V(0.5, 1.6, 0.5), V(0.8, 8.2, 0), zone.Palette.Accent, {
				Name = "HornR",
				Material = Enum.Material.Neon,
				Shadow = false,
				Rot = CFrame.Angles(0, 0, math.rad(-15)),
			}),
			block(
				V(2, 0.4, 0.3),
				V(0, 4.2, -1.1),
				zone.Palette.Accent,
				{ Name = "Crack", Material = Enum.Material.Neon, Shadow = false }
			),
		}
	end,
	Sky = function()
		return {
			ball(
				2.6,
				V(-2.4, 3.8, 0),
				Color3.new(1, 1, 1),
				{ Name = "WingL", Material = Enum.Material.SmoothPlastic, Shadow = false }
			),
			ball(
				2.6,
				V(2.4, 3.8, 0),
				Color3.new(1, 1, 1),
				{ Name = "WingR", Material = Enum.Material.SmoothPlastic, Shadow = false }
			),
		}
	end,
	Cyber = function(zone)
		return {
			block(
				V(2.2, 0.35, 0.3),
				V(0, 6.4, -1.1),
				zone.Palette.Accent,
				{ Name = "Visor", Material = Enum.Material.Neon, Shadow = false }
			),
			cyl(
				1.4,
				0.2,
				V(0, 8.6, 0),
				Color3.fromRGB(80, 90, 130),
				{ Name = "Antenna", Material = Enum.Material.Metal, Shadow = false }
			),
			ball(
				0.5,
				V(0, 9.4, 0),
				zone.Palette.Glow,
				{ Name = "AntennaLight", Material = Enum.Material.Neon, Shadow = false }
			),
		}
	end,
	Void = function(zone)
		return {
			ball(
				1,
				V(-0.5, 6.4, -1.3),
				zone.Palette.Accent,
				{ Name = "EyeL", Material = Enum.Material.Neon, Shadow = false }
			),
			ball(
				1,
				V(0.5, 6.4, -1.3),
				zone.Palette.Accent,
				{ Name = "EyeR", Material = Enum.Material.Neon, Shadow = false }
			),
			block(
				V(0.5, 3, 0.5),
				V(-2.6, 3.4, 0),
				zone.Palette.Accent,
				{ Name = "WispL", Material = Enum.Material.Neon, Transparency = 0.4, Shadow = false }
			),
		}
	end,
	Divine = function(zone)
		return {
			cyl(
				0.25,
				3.2,
				V(0, 9.1, 0),
				zone.Palette.Accent,
				{ Name = "Halo", Material = Enum.Material.Neon, Shadow = false, Rot = CFrame.Angles(0, 0, math.rad(8)) }
			),
			ball(
				2.2,
				V(-2.6, 4, 0.6),
				Color3.new(1, 1, 1),
				{ Name = "WingL", Material = Enum.Material.SmoothPlastic, Shadow = false }
			),
			ball(
				2.2,
				V(2.6, 4, 0.6),
				Color3.new(1, 1, 1),
				{ Name = "WingR", Material = Enum.Material.SmoothPlastic, Shadow = false }
			),
		}
	end,
	Secret = function(zone)
		return {
			block(V(1.8, 1.8, 1.8), V(0, 8.4, 0), zone.Palette.Accent, {
				Name = "Cube",
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				Shadow = false,
				Rot = CFrame.Angles(0.6, 0.8, 0),
			}),
			ball(
				0.8,
				V(0, 6.5, -1.3),
				Color3.new(1, 1, 1),
				{ Name = "Eye", Material = Enum.Material.Neon, Shadow = false }
			),
		}
	end,
}

-- Hauteur du point d'impact (centre du torse).
Dummies.HitHeight = 3.8
-- Rayon de touche approximatif (pour la portée serveur).
Dummies.Radius = 2.2

function Dummies.build(zone: Zones.Zone, scale: number?): { Spec.Spec }
	local color = zone.DummyColor
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.4)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.35)
	local specs: { Spec.Spec } = {
		cyl(
			0.8,
			5.4,
			V(0, 0.4, 0),
			zone.Palette.Prop,
			{ Name = "Base", Material = Enum.Material.Slate, Collide = true }
		),
		cyl(
			0.2,
			4.2,
			V(0, 0.9, 0),
			zone.Palette.Accent,
			{ Name = "BaseRing", Material = Enum.Material.Neon, Shadow = false }
		),
		cyl(1.6, 0.9, V(0, 1.6, 0), dark, { Name = "Post", Material = Enum.Material.Wood }),
		block(
			V(2.6, 2.6, 1.5),
			V(0, 3.8, 0),
			color,
			{ Name = "Torso", Material = Enum.Material.SmoothPlastic, Collide = true }
		),
		block(
			V(2.4, 0.5, 1.3),
			V(0, 4.8, -0.01),
			light,
			{ Name = "Chest", Material = Enum.Material.SmoothPlastic, Shadow = false }
		),
		block(V(4.6, 0.7, 0.8), V(0, 4.4, 0), dark, { Name = "Arms", Material = Enum.Material.Wood }),
		ball(0.9, V(-2.4, 4.4, 0), color, { Name = "HandL", Material = Enum.Material.SmoothPlastic, Shadow = false }),
		ball(0.9, V(2.4, 4.4, 0), color, { Name = "HandR", Material = Enum.Material.SmoothPlastic, Shadow = false }),
		ball(2.3, V(0, 6.5, 0), color, { Name = "Head", Material = Enum.Material.SmoothPlastic, Collide = true }),
		ball(
			0.34,
			V(-0.55, 6.7, -1.05),
			Color3.fromRGB(30, 30, 40),
			{ Name = "EyeL", Material = Enum.Material.SmoothPlastic, Shadow = false }
		),
		ball(
			0.34,
			V(0.55, 6.7, -1.05),
			Color3.fromRGB(30, 30, 40),
			{ Name = "EyeR", Material = Enum.Material.SmoothPlastic, Shadow = false }
		),
		block(
			V(1, 0.18, 0.2),
			V(0, 6, -1.1),
			Color3.fromRGB(30, 30, 40),
			{ Name = "Mouth", Material = Enum.Material.SmoothPlastic, Shadow = false }
		),
		block(
			V(2.7, 0.35, 1.6),
			V(0, 2.6, 0),
			zone.Palette.Accent,
			{ Name = "Belt", Material = Enum.Material.SmoothPlastic, Shadow = false }
		),
	}
	local accessory = ACCESSORIES[zone.Id]
	if accessory then
		Spec.append(specs, accessory(zone, color))
	end
	return scaleSpecs(specs, scale or 1)
end

return Dummies
