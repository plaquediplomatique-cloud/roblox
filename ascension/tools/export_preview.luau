--[[
	Exporte des scènes d'aperçu (armes, personnages en pose, props, mannequins) au format JSON du
	rasteriseur hors-Studio du dépôt (tools/render_view.py), pour juger les modèles SANS Roblox :

	  lune run ascension/tools/export_preview.luau
	  python3 tools/render_view.py asc_weapons --eye 0,9,70 --target 0,5,0 --name front
	  -> build/renders/asc_weapons_front.png
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
local loader = require("../tests/loader")

local Shared = loader.shared
local req = loader.require
local Spec = req(Shared.Assets.Spec)
local WeaponRecipes = req(Shared.Assets.WeaponRecipes)
local WeaponCatalog = req(Shared.Rules.WeaponCatalog)
local Props = req(Shared.Assets.Props)
local Dummies = req(Shared.Assets.Dummies)
local Zones = req(Shared.Config.Zones)
local SwingPose = req(Shared.Rules.SwingPose)

local function rgb(c)
	return { c.R, c.G, c.B }
end

local function cframe(cf)
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function prim(spec, transform)
	local cf = if transform then transform * spec.CFrame else spec.CFrame
	return {
		name = spec.Name or "Part",
		shape = spec.Shape,
		cf = cframe(cf),
		size = { spec.Size.X, spec.Size.Y, spec.Size.Z },
		material = if spec.Neon then "Neon" else (if spec.Material then spec.Material.Name else "SmoothPlastic"),
		color = rgb(spec.Color),
		transparency = spec.Transparency or 0,
		reflectance = 0,
		group = "Scene",
		collide = false,
		query = false,
		shadow = spec.Shadow ~= false,
	}
end

local function floor(width, depth, centerZ)
	return prim(
		Spec.block(
			Vector3.new(width, 1, depth),
			Vector3.new(0, -0.5, centerZ or 0),
			Color3.fromRGB(150, 205, 120),
			{ Material = Enum.Material.Grass }
		)
	)
end

local LIGHTING = {
	clockTime = 14,
	brightness = 2.4,
	ambient = { 0.5, 0.52, 0.6 },
	outdoorAmbient = { 0.6, 0.62, 0.7 },
	exposure = 0,
	colorShiftTop = { 1, 0.98, 0.94 },
	atmosphere = {
		density = 0.2,
		offset = 0.2,
		color = { 0.78, 0.88, 1 },
		decay = { 0.8, 0.85, 0.95 },
		glare = 0,
		haze = 1,
	},
	colorCorrection = { brightness = 0, contrast = 0.05, saturation = 0.1, tint = { 1, 1, 1 } },
	bloom = { intensity = 0.35, size = 24, threshold = 1.1 },
}

local function write(id, prims)
	fs.writeDir("build/maps")
	local identity = { 0, 10, 40, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	fs.writeFile(
		("build/maps/%s.json"):format(id),
		serde.encode("json", { id = id, prims = prims, intro = { identity }, overview = identity, lighting = LIGHTING })
	)
	print(("%-14s %5d primitives"):format(id, #prims))
end

---------------------------------------------------------------------------------------------
-- 1. Armes : un exemplaire de chaque archétype (palette de la première arme qui l'utilise)
---------------------------------------------------------------------------------------------

do
	local prims = { floor(120, 30, 0) }
	local names = WeaponRecipes.names()
	for i, name in names do
		local colors
		for _, weapon in WeaponCatalog.List do
			if weapon.Archetype == name then
				colors = weapon.Colors
			end
		end
		local recipe = WeaponRecipes.build(name, colors)
		local column = (i - 1) % 9
		local row = (i - 1) // 9
		local x = (column - 4) * 9
		local z = -row * 14
		for _, spec in recipe.Parts do
			table.insert(prims, prim(spec, CFrame.new(x, 2.2, z)))
		end
	end
	write("asc_weapons", prims)
end

---------------------------------------------------------------------------------------------
-- 2. Personnage (silhouette R15 simplifiée) en pose « prêt » ou à l'impact, arme en main
---------------------------------------------------------------------------------------------

local function figure(weaponId, pose, origin)
	local out = {}
	local skin = Color3.fromRGB(245, 205, 140)
	local shirt = Color3.fromRGB(80, 140, 230)
	local pants = Color3.fromRGB(60, 70, 110)
	local function box(size, position, color)
		table.insert(out, prim(Spec.block(size, position, color, { Material = Enum.Material.SmoothPlastic }), origin))
	end
	box(Vector3.new(2, 0.4, 1), Vector3.new(0, 0.9, 0), pants) -- bassin
	box(Vector3.new(1.4, 2, 1), Vector3.new(-0.5, 0.0 - 0.1, 0), pants)
	box(Vector3.new(1.4, 2, 1), Vector3.new(0.5, -0.1, 0), pants)
	box(Vector3.new(2, 2, 1), Vector3.new(0, 2.4, 0), shirt)
	table.insert(out, prim(Spec.ball(1.7, Vector3.new(0, 4.2, 0), skin), origin))
	box(Vector3.new(1, 2, 1), Vector3.new(-1.5, 2.4, 0), skin) -- bras gauche
	-- Bras droit : épaule (1.5, 3.2, 0) ; rotation yaw puis élévation ; bras de 2.6 studs vers le bas.
	local torsoTwist = CFrame.Angles(0, pose.Torso, 0)
	local shoulderWorld = origin * CFrame.new(0, 2.4, 0) * torsoTwist * CFrame.new(1.5, 0.8, 0)
	local arm = shoulderWorld * CFrame.Angles(0, pose.Yaw, 0) * CFrame.Angles(pose.Shoulder, 0, 0)
	table.insert(out, prim(Spec.block(Vector3.new(1, 2.6, 1), Vector3.new(0, -1.3, 0), skin), arm))
	-- Main : au bout du bras ; l'arme s'y soude comme Builder.attach (C0 = 0,-0.25,0 * Rx(GripAngle)).
	local hand = arm * CFrame.new(0, -2.6, 0)
	local grip = hand * CFrame.new(0, -0.25, 0) * CFrame.Angles(SwingPose.GripAngle, 0, 0)
	local weapon = WeaponCatalog.ById[weaponId]
	local recipe = WeaponRecipes.build(weapon.Archetype, weapon.Colors)
	for _, spec in recipe.Parts do
		table.insert(out, prim(spec, grip))
	end
	return out
end

do
	local prims = { floor(80, 40, 0) }
	local entries = {
		{ "IronSword", "ready", -18 },
		{ "InfernoHammer", "ready", -6 },
		{ "StormSpear", "ready", 6 },
		{ "AuroraStaff", "ready", 18 },
	}
	for _, entry in entries do
		local origin = CFrame.new(entry[3], 3.9, 0) * CFrame.Angles(0, math.rad(35), 0)
		for _, p in figure(entry[1], SwingPose.ready(), origin) do
			table.insert(prims, p)
		end
	end
	-- Rangée arrière : à l'instant de l'impact.
	for _, entry in
		{
			{ "IronSword", "Slash", -18 },
			{ "InfernoHammer", "Slam", -6 },
			{ "StormSpear", "Stab", 6 },
			{ "WindTwins", "Spin", 18 },
		}
	do
		local origin = CFrame.new(entry[3], 3.9, -22) * CFrame.Angles(0, math.rad(35), 0)
		for _, p in figure(entry[1], SwingPose.sample(entry[2], SwingPose.ImpactTime), origin) do
			table.insert(prims, p)
		end
	end
	write("asc_heroes", prims)
end

---------------------------------------------------------------------------------------------
-- 3. Props
---------------------------------------------------------------------------------------------

do
	local prims = { floor(260, 140, -20) }
	local names = Props.names()
	local perRow = 10
	for i, name in names do
		local column = (i - 1) % perRow
		local row = (i - 1) // perRow
		local x = (column - perRow / 2) * 22
		local z = -row * 28
		local palette = Props.zonePalette(Zones.List[((i - 1) % 9) + 2].Palette)
		for _, spec in Props.build(name, if i % 3 == 0 then palette else Props.DefaultPalette, i) do
			table.insert(prims, prim(spec, CFrame.new(x, 0, z)))
		end
	end
	write("asc_props", prims)
end

---------------------------------------------------------------------------------------------
-- 4. Mannequins des 10 zones
---------------------------------------------------------------------------------------------

do
	local prims = { floor(130, 40, 0) }
	for i, zone in Zones.List do
		local x = (i - 5.5) * 12
		for _, spec in Dummies.build(zone) do
			table.insert(prims, prim(spec, CFrame.new(x, 0, 0)))
		end
	end
	write("asc_dummies", prims)
end

---------------------------------------------------------------------------------------------
-- 5. Poses isolées (une scène par pose, vue de côté depuis +X ; le personnage regarde -Z)
---------------------------------------------------------------------------------------------

do
	local poses = {
		{ "ready", "IronSword", SwingPose.ready() },
		{ "overhead_windup", "IronSword", SwingPose.sample("Overhead", 0.2) },
		{ "overhead_impact", "IronSword", SwingPose.sample("Overhead", SwingPose.ImpactTime) },
		{ "slash_windup", "SnowflakeKatana", SwingPose.sample("Slash", 0.2) },
		{ "slash_impact", "SnowflakeKatana", SwingPose.sample("Slash", SwingPose.ImpactTime) },
		{ "stab_impact", "StormSpear", SwingPose.sample("Stab", SwingPose.ImpactTime) },
		{ "slam_impact", "InfernoHammer", SwingPose.sample("Slam", SwingPose.ImpactTime) },
		{ "spin_mid", "WindTwins", SwingPose.sample("Spin", 0.55) },
	}
	for _, entry in poses do
		local prims = { floor(60, 60, 0) }
		for _, p in figure(entry[2], entry[3], CFrame.new(0, 3.9, 0)) do
			table.insert(prims, p)
		end
		write("asc_pose_" .. entry[1], prims)
	end
end
