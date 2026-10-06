--!strict
--[[
	Habillage de MONOLITH — relais orbital autour d'un monolithe noir, dans le vide étoilé.

	Intentions :
	  * Le monolithe est un artefact : glyphes magenta gravés, éclats en lévitation au-dessus.
	  * La station est fabriquée : tôles et joints de coque, nervures des pylônes, rails de
	    guidage lumineux au sol, hublots sur l'espace, bandes de danger des sas.
	  * Le dehors existe : bras de structure, panneaux solaires, anneau d'habitat, une
	    planète immense sous la station — la sensation d'être en orbite.
	Tout est décoratif (Decor) : la carte polyvalente garde ses métriques et ses modes.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local Decor = require(script.Parent.Parent.Decor)

type Kit = MapKit.Kit

local MAGENTA = Color3.fromRGB(220, 80, 255)
local CYAN = Color3.fromRGB(61, 225, 255)
local VIOLET = Color3.fromRGB(150, 110, 255)
local AMBER = Color3.fromRGB(255, 190, 70)

local function monolith(kit: Kit, rng: Decor.Rng)
	-- Glyphes : segments fins sur les quatre faces (circuits gravés)
	local faces = {
		{ normal = Vector3.new(0, 0, -1), right = Vector3.new(1, 0, 0) },
		{ normal = Vector3.new(0, 0, 1), right = Vector3.new(-1, 0, 0) },
		{ normal = Vector3.new(-1, 0, 0), right = Vector3.new(0, 0, -1) },
		{ normal = Vector3.new(1, 0, 0), right = Vector3.new(0, 0, 1) },
	}
	for _, face in faces do
		local origin = face.normal * 8.04
		for _ = 1, 9 do
			local u = rng(-6.5, 6.5)
			local y = rng(3, 40)
			local vertical = rng() < 0.5
			local length = rng(2, 9)
			local center = origin + face.right * u + Vector3.new(0, y, 0)
			local size = if vertical
				then Vector3.new(0.18, length, 0.18)
				else (if math.abs(face.right.X) > 0
					then Vector3.new(length, 0.18, 0.08)
					else Vector3.new(0.08, 0.18, length))
			kit:decor("Glyph", CFrame.new(center), size, "NeonMagenta")
		end
	end
	-- Éclats en lévitation au-dessus du monolithe (au-delà de 12 studs)
	for index = 1, 7 do
		local angle = index / 7 * math.pi * 2
		local radius = rng(9, 14)
		local s = rng(1.2, 2.6)
		kit:decor(
			"Shard",
			CFrame.new(math.cos(angle) * radius, rng(46, 58), math.sin(angle) * radius)
				* CFrame.Angles(rng(0, 3), rng(0, 3), rng(0, 3)),
			Vector3.new(s, s * 1.6, s),
			"Monolith"
		)
	end
end

local function deck(kit: Kit)
	-- Rails de guidage lumineux dans l'anneau et les couloirs
	for _, z in { -30, 30 } do
		Decor.floorLine(kit, -38, z, 38, z, 0.1, 0.2, "NeonWhite", { color = VIOLET })
	end
	for _, x in { -36, 36 } do
		Decor.floorLine(kit, x, -24, x, 24, 0.1, 0.2, "NeonWhite", { color = VIOLET })
	end
	for _, sz in { 1, -1 } do
		Decor.floorLine(kit, -84, 45 * sz, 84, 45 * sz, 0.1, 0.18, "NeonWhite", { color = CYAN })
		-- Bandes de danger des sas (portes de l'anneau et des sites)
		Decor.hazardBand(kit, -8, 35.6 * sz, 8, 35.6 * sz, 0.1, 1)
		Decor.hazardBand(kit, -78, 35.6 * sz, -66, 35.6 * sz, 0.1, 1)
		Decor.hazardBand(kit, 66, 35.6 * sz, 78, 35.6 * sz, 0.1, 1)
	end
	-- Joints de tôle du pont (grille fine)
	for x = -32, 32, 8 do
		Decor.floorLine(kit, x, -34, x, 34, 0.1, 0.08, "SteelDark")
	end
	for z = -24, 24, 8 do
		Decor.floorLine(kit, -40, z, 40, z, 0.1, 0.08, "SteelDark")
	end
end

local function hull(kit: Kit)
	local panel = { seam = "SteelDark", spacing = 4, base = "PaintBlack", cap = "Steel" }
	-- Murs de l'anneau (portes au centre de chaque côté)
	for _, s in { 1, -1 } do
		Decor.wall(kit, 40 * s, -34, 40 * s, -6, 16, 1.4, panel)
		Decor.wall(kit, 40 * s, 6, 40 * s, 34, 16, 1.4, panel)
		Decor.wall(kit, -40, 34 * s, -8, 34 * s, 16, 1.4, panel)
		Decor.wall(kit, 8, 34 * s, 40, 34 * s, 16, 1.4, panel)
	end
	-- Pylônes : nervures verticales sur leurs faces visibles (couloirs de connexion z = ±6,
	-- concourses z = ±34), saillie 0.2 vers l'espace de circulation.
	for _, sx in { 1, -1 } do
		for x = 42, 52.5, 2.5 do
			local px = x * sx
			for _, face in
				{
					{ z = 6, out = -0.2, top = 11.5 },
					{ z = -6, out = 0.2, top = 11.5 },
					{ z = 34, out = 0.2, top = 15 },
					{ z = -34, out = -0.2, top = 15 },
				}
			do
				kit:decorBox("PylonRib", px - 0.15, 0.5, face.z, px + 0.15, face.top, face.z + face.out, "Steel")
			end
		end
	end
	-- Hublots sur l'espace (murs extérieurs des sites) + appliques
	for _, sx in { 1, -1 } do
		for _, z in { -24, -12, 12, 24 } do
			local x = 85 * sx
			kit:decorBox("Viewport", x - 0.1 * sx, 5, z - 2.5, x, 10, z + 2.5, "TowerGlass")
			kit:decorBox("ViewportFrame", x - 0.25 * sx, 4.7, z - 2.8, x, 5, z + 2.8, "Steel")
			kit:decorBox("ViewportFrame", x - 0.25 * sx, 10, z - 2.8, x, 10.3, z + 2.8, "Steel")
		end
		Decor.wallLight(kit, Vector3.new(85 * sx, 12, 0), Vector3.new(-sx, 0, 0), CYAN, 0.9, 16)
	end
	-- Concourses : poutres et écrans d'information
	for _, sz in { 1, -1 } do
		Decor.beams(kit, -86, 34 * sz, 86, 56 * sz, 16, false, 8, "SteelDark")
		Decor.screen(
			kit,
			Vector3.new(0, 9, 55.4 * sz),
			Vector3.new(0, 0, -sz),
			8,
			2.4,
			if sz > 0 then CYAN else MAGENTA
		)
	end
end

local function sites(kit: Kit)
	-- A — antenne : anneaux de l'antenne et parabole
	for _, y in { 8, 12, 16 } do
		kit:decorBox("ArrayRing", -72, y, -2, -68, y + 0.3, 2, "NeonWhite", { color = CYAN })
	end
	kit:decor(
		"ArrayDishFace",
		CFrame.new(-70, 6.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(0.3, 11, 11),
		"Steel",
		{
			shape = "Cylinder",
		}
	)
	-- B — relais : glyphes du cœur
	for _, y in { 2, 4.5, 7 } do
		kit:decorBox("RelayGlyph", 65.85, y, -4, 65.95, y + 0.2, 4, "NeonMagenta")
	end
	-- Sas des spawns : contours de grandes portes de hangar et marquages
	for _, sz in { 1, -1 } do
		kit:decorBox("HangarDoor", -14, 0.3, 75.3 * sz, 14, 13, 75 * sz, "HullPlate")
		Decor.hazardBand(kit, -14, 74.4 * sz, 14, 74.4 * sz, 0.15, 0.9)
		Decor.beams(kit, -24, 56 * sz, 24, 76 * sz, 16, false, 6, "SteelDark")
	end
	Decor.dressCovers(kit, AMBER)
end

local function space(kit: Kit, rng: Decor.Rng)
	-- Dessous de la station : structure de coque
	kit:decorBox("HullBelly", -90, -14, -80, 90, -4.5, 80, "Hull", { group = "Backdrop" })
	for x = -80, 80, 20 do
		kit:decorBox("BellyRib", x - 1, -18, -80, x + 1, -14, 80, "SteelDark", { group = "Backdrop" })
	end
	-- Bras de structure et panneaux solaires (hors limites)
	for _, arm in
		{
			{ from = Vector3.new(-86, 4, 0), to = Vector3.new(-300, 4, 0) },
			{ from = Vector3.new(86, 4, 0), to = Vector3.new(300, 4, 0) },
			{ from = Vector3.new(0, 4, 76), to = Vector3.new(0, 4, 260) },
			{ from = Vector3.new(0, 4, -76), to = Vector3.new(0, 4, -260) },
		}
	do
		local outer = arm.from + (arm.to - arm.from).Unit * 2
		Decor.truss(kit, outer, arm.to, 5, "SteelDark")
		for index = 1, 3 do
			local base = arm.from:Lerp(arm.to, 0.35 + index * 0.18)
			local side = if math.abs(arm.to.X) > 0 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
			for _, s in { -1, 1 } do
				local center = base + side * s * 22
				local size = if math.abs(side.Z) > 0 then Vector3.new(26, 0.4, 34) else Vector3.new(34, 0.4, 26)
				kit:decor(
					"SolarPanel",
					CFrame.new(center) * CFrame.Angles(0.25, 0, 0),
					size,
					"Solar",
					{ group = "Backdrop" }
				)
			end
		end
	end
	-- Fermes de structure le long des bras (marquées pour le groupe Backdrop)
	for _, prim in kit.prims do
		if prim.name == "TrussChord" or prim.name == "TrussPost" or prim.name == "TrussBrace" then
			prim.group = "Backdrop"
		end
	end
	-- Anneau d'habitat lointain
	for index = 0, 23 do
		local angle = index / 24 * math.pi * 2
		local radius = 620
		local center =
			Vector3.new(math.cos(angle) * radius, 140 + math.sin(angle) * 40, 900 + math.sin(angle) * radius * 0.35)
		kit:decor("HabitatRing", CFrame.lookAt(center, Vector3.new(0, 140, 900)), Vector3.new(150, 26, 30), "Hull", {
			group = "Backdrop",
		})
		if index % 3 == 0 then
			kit:decor(
				"HabitatLights",
				CFrame.lookAt(center, Vector3.new(0, 140, 900)) * CFrame.new(0, 0, -15.2),
				Vector3.new(120, 3, 0.5),
				"WindowCool",
				{
					group = "Backdrop",
				}
			)
		end
	end
	-- Planète sous la station, liseré d'atmosphère
	kit:decor("Planet", CFrame.new(400, -1900, -1400), Vector3.new(2048, 2048, 2048), "Planet", {
		group = "Backdrop",
		shape = "Ball",
	})
	kit:decor("PlanetAtmosphere", CFrame.new(400, -1900, -1400), Vector3.new(2048, 2048, 2048), "NeonWhite", {
		group = "Backdrop",
		shape = "Ball",
		color = Color3.fromRGB(90, 160, 255),
		transparency = 0.86,
	})
	for _ = 1, 5 do
		kit:decor(
			"Debris",
			CFrame.new(rng(-400, 400), rng(-60, 80), rng(180, 420)) * CFrame.Angles(rng(0, 3), rng(0, 3), 0),
			Vector3.new(rng(4, 12), rng(2, 6), rng(4, 14)),
			"Hull",
			{
				group = "Backdrop",
			}
		)
	end
end

return function(kit: Kit)
	local rng = Decor.rng(8008)
	monolith(kit, rng)
	deck(kit)
	hull(kit)
	sites(kit)
	space(kit, rng)
end
