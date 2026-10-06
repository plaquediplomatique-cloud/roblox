--!strict
--[[
	Habillage du hub AETHER SPIRE — hangar suspendu au 88e niveau d'une mégapole, la nuit.

	Intentions :
	  * Situer le lieu : une mégapole verticale tout autour (tours éclairées, couloirs de
	    trafic aérien, panneaux holographiques de la saison) ; une charpente de hangar
	    au-dessus de la place, avec bannières des deux factions.
	  * Rendre le hub habitable : salons (canapés, tables, bar, plantes), bancs habillés,
	    trophées du Hall of Fame, écrans de la salle personnalisée.
	  * Guider : anneaux lumineux autour du cœur, chemins lumineux vers chaque zone,
	    bandes de danger aux portiques, couleur de zone répétée au sol.
	Le hub n'est pas compétitif : le mobilier y est solide (collisions) ; il ne gêne ni les
	terminaux, ni les couloirs, ni le stand de tir.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local Decor = require(script.Parent.Parent.Decor)

type Kit = MapKit.Kit

local CYAN = Color3.fromRGB(61, 225, 255)
local MAGENTA = Color3.fromRGB(220, 80, 255)
local AMBER = Color3.fromRGB(255, 190, 70)
local GREEN = Color3.fromRGB(61, 255, 162)
local ONYX = Color3.fromRGB(255, 90, 54)
local HALO = Color3.fromRGB(61, 200, 255)
local WHITE = Color3.fromRGB(230, 240, 255)

local function plaza(kit: Kit)
	-- Anneaux lumineux autour du cœur
	for _, radius in { 9, 18 } do
		local segments = if radius < 10 then 16 else 28
		for index = 0, segments - 1 do
			local angle = (index + 0.5) / segments * math.pi * 2
			local length = 2 * math.pi * radius / segments * 0.82
			kit:decor(
				"CoreRing",
				CFrame.new(math.cos(angle) * radius, 0.13, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
				Vector3.new(0.25, 0.04, length),
				"NeonWhite",
				{ color = CYAN }
			)
		end
	end
	-- Chemins lumineux vers les portiques (couleur de la zone de destination)
	for _, path in
		{
			{ from = Vector2.new(0, 20), to = Vector2.new(0, 40), color = AMBER },
			{ from = Vector2.new(0, -20), to = Vector2.new(0, -40), color = AMBER },
			{ from = Vector2.new(-20, 0), to = Vector2.new(-40, 0), color = GREEN },
			{ from = Vector2.new(20, 0), to = Vector2.new(40, 0), color = CYAN },
		}
	do
		Decor.floorLine(kit, path.from.X, path.from.Y, path.to.X, path.to.Y, 0.13, 0.35, "NeonWhite", {
			color = path.color,
		})
	end
	-- Bancs de la place : coussins et dossiers (sur les volumes existants)
	for _, sx in { 1, -1 } do
		for _, z in { 23, -23 } do
			kit:decorBox("BenchCushion", sx * 22 - 3.9, 1.6, z - 0.9, sx * 22 + 3.9, 1.85, z + 0.9, "FabricDark", {
				color = Color3.fromRGB(40, 46, 62),
			})
			local back = if z > 0 then z + 1 else z - 1
			kit:decorBox("BenchBack", sx * 22 - 3.9, 1.6, back - 0.2, sx * 22 + 3.9, 3, back + 0.2, "HullLight")
		end
	end
	-- Portiques : bandes de danger
	for _, gate in { { 0, 40 }, { 0, -40 } } do
		Decor.hazardBand(
			kit,
			-14,
			gate[2] + (if gate[2] > 0 then -1.2 else 1.2),
			14,
			gate[2] + (if gate[2] > 0 then -1.2 else 1.2),
			0.1,
			0.9
		)
	end
	for _, gate in { { -40, 0 }, { 40, 0 } } do
		local x = gate[1] + (if gate[1] > 0 then -1.2 else 1.2)
		Decor.hazardBand(kit, x, -12, x, 12, 0.1, 0.9)
	end
end

local function walls(kit: Kit)
	local panel = { seam = "SteelDark", spacing = 6, base = "PaintBlack", cap = "Steel" }
	Decor.wall(kit, -110, 90, 110, 90, 30, 2, { seam = panel.seam, spacing = 6, base = panel.base, sides = { -1 } })
	Decor.wall(kit, -110, -90, 110, -90, 30, 2, { seam = panel.seam, spacing = 6, base = panel.base, sides = { 1 } })
	Decor.wall(kit, -110, -90, -110, 90, 30, 2, { seam = panel.seam, spacing = 6, base = panel.base, sides = { 1 } })
	Decor.wall(kit, 110, -90, 110, 90, 30, 2, { seam = panel.seam, spacing = 6, base = panel.base, sides = { -1 } })
	-- Bandeaux lumineux verticaux sur les grands murs (rythme de 20 studs)
	for x = -100, 100, 20 do
		kit:decorBox("WallLightStrip", x - 0.15, 2, 88.75, x + 0.15, 28, 89, "NeonWhite", { color = CYAN })
		kit:decorBox("WallLightStrip", x - 0.15, 2, -89, x + 0.15, 28, -88.75, "NeonWhite", { color = CYAN })
	end
	-- Écran géant au-dessus du terminal classé
	Decor.screen(kit, Vector3.new(0, 24, 89), Vector3.new(0, 0, -1), 36, 8, Color3.fromRGB(40, 70, 120))
end

local function overhead(kit: Kit)
	-- Charpente du hangar : fermes transversales posées sur les murs (y ≥ 30)
	for _, z in { -60, -20, 20, 60 } do
		Decor.truss(kit, Vector3.new(-110, 44, z), Vector3.new(110, 44, z), 5, "SteelDark")
		for _, x in { -110, 110 } do
			kit:decorBox("TrussShoe", x - 1, 30, z - 1, x + 1, 39, z + 1, "Steel")
		end
	end
	Decor.truss(kit, Vector3.new(0, 44, -90), Vector3.new(0, 44, 90), 5, "SteelDark")
	-- Bannières des factions et barres lumineuses suspendues
	for index, x in { -60, -30, 30, 60 } do
		local color = if index <= 2 then ONYX else HALO
		kit:decorBox("Banner", x - 3, 26, -0.15, x + 3, 38.6, 0.15, "FabricDark", { color = Decor.shade(color, 0.55) })
		kit:decorBox("BannerStripe", x - 3, 30, -0.2, x + 3, 30.6, 0.2, "NeonWhite", { color = color })
		Decor.cable(kit, Vector3.new(x, 38.6, 0), Vector3.new(x, 39, 0) + Vector3.new(0, 0, 0.01), 0, 1, 0.05)
	end
	for _, z in { -40, 40 } do
		for _, x in { -80, -40, 40, 80 } do
			kit:decorBox("HangingLight", x - 4, 34, z - 0.3, x + 4, 34.4, z + 0.3, "NeonWhite", { color = WHITE })
			Decor.cable(kit, Vector3.new(x - 3.5, 34.4, z), Vector3.new(x - 3.5, 39, z), 0, 1, 0.04)
			Decor.cable(kit, Vector3.new(x + 3.5, 34.4, z), Vector3.new(x + 3.5, 39, z), 0, 1, 0.04)
		end
	end
end

local function lounges(kit: Kit, rng: Decor.Rng)
	for _, sx in { 1, -1 } do
		local tint = if sx > 0 then Color3.fromRGB(28, 60, 80) else Color3.fromRGB(70, 30, 80)
		-- Banquettes existantes (volumes de 30 × 4) : coussins et dossiers
		for _, z in { -74, -56 } do
			kit:decorBox("BenchCushion", sx * 60, 1.6, z - 1.8, sx * 90, 1.9, z + 1.8, "FabricDark", { color = tint })
		end
		kit:decorBox(
			"BenchBack",
			sx * 60,
			1.6,
			-76.4,
			sx * 90,
			3.4,
			-75.8,
			"FabricDark",
			{ color = Decor.shade(tint, 0.8) }
		)
		kit:decorBox(
			"BenchBack",
			sx * 60,
			1.6,
			-54.2,
			sx * 90,
			3.4,
			-53.6,
			"FabricDark",
			{ color = Decor.shade(tint, 0.8) }
		)
		-- Tables basses entre les banquettes
		for _, x in { 66, 75, 84 } do
			Decor.table(kit, sx * x, 0.3, -65, 3.2, 2.2, 1.3, "Marble")
		end
		-- Canapés le long du mur du fond et plantes
		Decor.sofa(kit, sx * 75, 0.3, -87.6, 180, 9, Decor.shade(tint, 1.3))
		Decor.planter(kit, rng, sx * 104, 0.3, -84, 3, "HullLight")
		Decor.planter(kit, rng, sx * 104, 0.3, -46, 3, "HullLight")
		-- Bar (salon est) / écrans (salon ouest)
		if sx > 0 then
			Decor.solid(kit, "BarCounter", CFrame.new(100, 2, -65), Vector3.new(3, 4, 18), "Marble")
			kit:decorBox("BarTop", 98.3, 4, -74.2, 101.7, 4.2, -55.8, "Brass")
			kit:decorBox("BarGlow", 98.45, 0.5, -74, 98.5, 0.7, -56, "NeonWhite", { color = CYAN })
			for z = -72, -58, 4.5 do
				Decor.solid(
					kit,
					"BarStool",
					CFrame.new(96.4, 1.3, z),
					Vector3.new(1.2, 2.6, 1.2),
					"SteelDark",
					{ shape = "Cylinder" }
				)
			end
		else
			for index, z in { -80, -68, -56 } do
				Decor.screen(
					kit,
					Vector3.new(-109, 9, z),
					Vector3.new(1, 0, 0),
					9,
					5,
					if index == 2 then MAGENTA else CYAN
				)
			end
		end
	end
end

local function zones(kit: Kit, rng: Decor.Rng)
	-- ARMURERIE : socles (plinthes et chapeaux), râteliers muraux
	for _, prim in table.clone(kit.prims) do
		if table.find(prim.tags, "WeaponPedestal") then
			local p = prim.cframe.Position
			kit:decorBox("PedestalPlinth", p.X - 2.3, 0.3, p.Z - 2.3, p.X + 2.3, 0.6, p.Z + 2.3, "SteelDark")
			kit:decorBox(
				"PedestalCap",
				p.X - 2.1,
				3,
				p.Z - 2.1,
				p.X + 2.1,
				3.12,
				p.Z + 2.1,
				"NeonWhite",
				{ color = CYAN }
			)
		end
	end
	for z = -32, 32, 16 do
		Decor.screen(kit, Vector3.new(109, 8, z), Vector3.new(-1, 0, 0), 10, 3, Color3.fromRGB(40, 90, 120))
	end
	-- STAND DE TIR : lignes de couloir, butte de tir, portique lumineux
	for _, z in { -20, -8, 4 } do
		Decor.floorLine(kit, -94, z, -50, z, 0.3, 0.15, "PaintYellow")
	end
	Decor.hazardBand(kit, -108.6, -38, -108.6, 16, 0.3, 1.2)
	for _, x in { -60, -80 } do
		kit:decorBox("RangeGantry", x - 0.5, 14, -36, x + 0.5, 15, 16, "SteelDark")
		kit:decorBox("RangeGantryLight", x - 0.3, 13.6, -36, x + 0.3, 14, 16, "NeonWhite", { color = WHITE })
	end
	-- HALL OF FAME : trophées (solides) le long des côtés
	for _, x in { -34, -22, 22, 34 } do
		Decor.solid(kit, "TrophyPlinth", CFrame.new(x, 1.3, -82), Vector3.new(3, 2.6, 3), "Marble")
		Decor.solid(
			kit,
			"Trophy",
			CFrame.new(x, 3.6, -82) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(2, 1.2, 1.2),
			"Brass",
			{
				shape = "Cylinder",
			}
		)
		Decor.solid(kit, "TrophyCup", CFrame.new(x, 5.2, -82), Vector3.new(1.8, 1.8, 1.8), "Gold", { shape = "Ball" })
	end
	-- SALLE PERSONNALISÉE : écrans autour de la table holographique, câbles au sol
	for index, x in { -92, -76, -60 } do
		Decor.screen(kit, Vector3.new(x, 7, 89), Vector3.new(0, 0, -1), 8, 3.5, if index == 2 then MAGENTA else CYAN)
	end
	kit:decorBox("FloorCable", -84, 0.3, 61, -68, 0.42, 61.3, "Cable")
	-- BAIE CASUAL : bornes d'arcade (solides) contre le mur nord
	for index, x in { 56, 64, 88, 96 } do
		Decor.solid(kit, "Arcade", CFrame.new(x, 2.6, 86.5), Vector3.new(3, 5.2, 2.4), "SteelDark")
		kit:decorBox("ArcadeScreen", x - 1.2, 3, 85.25, x + 1.2, 4.8, 85.3, "NeonWhite", {
			color = if index % 2 == 0 then GREEN else MAGENTA,
		})
	end
	Decor.planter(kit, rng, 46, 0.3, 86, 2.6, "HullLight")
	-- TERMINAL CLASSÉ : marches éclairées du podium
	kit:decorBox("DaisGlow", -24, 1.8, 61.75, 24, 2, 62, "NeonWhite", { color = AMBER })
end

local function city(kit: Kit, rng: Decor.Rng)
	Decor.skyline(kit, rng, -110, -90, 110, 90, 50, 700, 60, 260, 640, -420, {
		body = "Tower",
		windows = { "WindowCool", "WindowCool", "WindowWarm", "NeonMagenta" },
		lit = 0.42,
	})
	Decor.billboard(kit, "AETHER STRIKE", 0, 120, 260, 120, 22, "-Z", CYAN)
	Decor.billboard(kit, "ONYX  VS  HALO", -280, 90, -60, 90, 18, "+X", ONYX)
	Decor.billboard(kit, "SAISON 1 — CLASSÉ", 300, 110, 80, 100, 18, "-X", AMBER)
	-- Couloirs de trafic aérien : files de feux (blancs à l'aller, rouges au retour)
	for lane = 0, 3 do
		local y = 70 + lane * 26
		local radius = 300 + lane * 60
		for index = 0, 35 do
			local angle = index / 36 * math.pi * 2 + lane * 0.4
			local color = if index % 2 == 0 then WHITE else Color3.fromRGB(255, 70, 70)
			kit:decor(
				"AirTraffic",
				CFrame.new(math.cos(angle) * radius, y + math.sin(angle * 3) * 4, math.sin(angle) * radius),
				Vector3.new(1.2, 0.6, 1.2),
				"NeonWhite",
				{
					group = "Backdrop",
					shape = "Ball",
					color = color,
				}
			)
		end
	end
end

return function(kit: Kit)
	local rng = Decor.rng(8888)
	plaza(kit)
	walls(kit)
	overhead(kit)
	lounges(kit, rng)
	zones(kit, rng)
	city(kit, rng)
end
