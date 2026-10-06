--!strict
--[[
	Habillage de KESTREL YARD — dépôt de fret sur un toit, la nuit, sous la pluie.

	Intentions (roblox-environment-art) :
	  * Le sol raconte l'usage : reprises de béton, flaques qui reflètent les lampes au
	    sodium, voies peintes, bandes de danger devant les quais.
	  * Les murs ont une échelle : pilastres, joints, couronnements, tuyauteries et
	    appliques ; plus aucun aplat de 140 studs.
	  * Les volumes de jeu sont « finis » sans changer leur collision : conteneurs nervurés
	    avec portes et barres de verrouillage, caisses renforcées, tour gainée.
	  * Au-dessus des têtes : guirlandes de câbles, portiques roulants, balises.
	  * L'horizon : une mégapole nocturne (tours éclairées, grues, panneaux) qui situe le
	    toit dans un lieu au lieu d'une boîte flottant dans le vide.
	Tout est décoratif (Decor) : collisions, lignes de vue et métriques du plan inchangées.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local Decor = require(script.Parent.Parent.Decor)

type Kit = MapKit.Kit

local SODIUM = Color3.fromRGB(255, 166, 84)
local COOL = Color3.fromRGB(200, 225, 255)
local ORANGE = Color3.fromRGB(255, 160, 80)
local MAGENTA = Color3.fromRGB(220, 80, 255)
local CYAN = Color3.fromRGB(61, 225, 255)

local RUST = Color3.fromRGB(132, 62, 42)
local TEAL = Color3.fromRGB(38, 104, 116)
local CONTAINER_ORANGE = Color3.fromRGB(190, 100, 40)

local function ground(kit: Kit)
	local rng = Decor.rng(7107)
	Decor.patches(kit, rng, -70, -44, 70, 44, 0, 48, { "ConcreteDark", "Asphalt", "Concrete" }, 3, 10)
	Decor.puddles(kit, rng, -54, -44, 54, 44, 0, 22)
	-- Voies peintes du Yard et du couloir sud
	for _, z in { -13.6, 13.6 } do
		Decor.floorLine(kit, -47, z, 47, z, 0, 0.3, "PaintYellow")
	end
	Decor.floorLine(kit, -54, -33, 54, -33, 0, 0.25, "PaintWhite")
	Decor.floorLine(kit, -54, 33, -10, 33, 0, 0.25, "PaintWhite")
	Decor.floorLine(kit, 10, 33, 54, 33, 0, 0.25, "PaintWhite")
	-- Avaloirs
	for _, x in { -44, -18, 18, 44 } do
		for _, z in { -30, 0, 30 } do
			kit:decorBox("Drain", x - 0.6, 0, z - 0.6, x + 0.6, 0.05, z + 0.6, "SteelDark")
		end
	end
end

local function outerWalls(kit: Kit)
	-- Faces intérieures : nord (z = 45, côté -1), sud (z = -45, côté +1), ouest/est.
	Decor.wall(kit, -72, 46, 72, 46, 20, 2, { seam = "ConcreteDark", spacing = 8, base = "Concrete", sides = { -1 } })
	Decor.wall(kit, -72, -46, 72, -46, 20, 2, { seam = "ConcreteDark", spacing = 8, base = "Concrete", sides = { 1 } })
	Decor.wall(kit, -72, -46, -72, 46, 20, 2, { seam = "ConcreteDark", spacing = 8, base = "Concrete", sides = { 1 } })
	Decor.wall(kit, 72, -46, 72, 46, 20, 2, { seam = "ConcreteDark", spacing = 8, base = "Concrete", sides = { -1 } })
	for _, z in { 46, -46 } do
		kit:decorBox("Parapet", -73, 20, z - 1.2, 73, 20.5, z + 1.2, "Steel")
	end
	for _, x in { 72, -72 } do
		kit:decorBox("Parapet", x - 1.2, 20, -47, x + 1.2, 20.5, 47, "Steel")
	end
	-- Pilastres tous les 12 studs (épaisseur 0.3 : de la profondeur, pas une couverture)
	for x = -60, 60, 12 do
		kit:decorBox("Pilaster", x - 0.45, 0, 44.7, x + 0.45, 20, 45, "Concrete")
		kit:decorBox("Pilaster", x - 0.45, 0, -45, x + 0.45, 20, -44.7, "Concrete")
	end
	-- Tuyauteries du mur nord, chemin de câbles du mur sud
	Decor.pipe(kit, Vector3.new(-70, 10.4, 44.3), Vector3.new(70, 10.4, 44.3), 0.36, "PipeRust", 8)
	Decor.pipe(kit, Vector3.new(-70, 11.4, 44.5), Vector3.new(70, 11.4, 44.5), 0.2, "Pipe", 10)
	kit:decorBox("CableTray", -70, 12, -44.95, 70, 12.25, -44.3, "SteelDark")
	for x = -64, 64, 16 do
		Decor.cable(kit, Vector3.new(x, 12.1, -44.6), Vector3.new(x + 16, 12.1, -44.6), 0.9, 4, 0.05)
	end
	-- Appliques au sodium (sans ombre : budget d'ombres réservé aux lampadaires)
	for _, x in { -48, -24, 0, 24, 48 } do
		Decor.wallLight(kit, Vector3.new(x, 13, 45), Vector3.new(0, 0, -1), SODIUM, 1.1, 18)
		Decor.wallLight(kit, Vector3.new(x, 13, -45), Vector3.new(0, 0, 1), SODIUM, 1.1, 18)
	end
	for _, z in { -36, 36 } do
		Decor.vent(kit, Vector3.new(-71, 5, z), Vector3.new(1, 0, 0), 3, 2)
		Decor.vent(kit, Vector3.new(71, 5, z), Vector3.new(-1, 0, 0), 3, 2)
	end
end

local function docks(kit: Kit)
	for _, sx in { 1, -1 } do
		local function X(x: number): number
			return x * sx
		end
		local dockSide = -sx -- face du mur intérieur tournée vers le quai
		-- Mur du quai (porte z -4..4) : joints et plinthes par segment
		for _, segment in { { -24, -4 }, { 4, 24 } } do
			Decor.wall(kit, X(-56), segment[1], X(-56), segment[2], 14, 1.4, {
				seam = "SteelDark",
				spacing = 4,
				base = "PaintBlack",
			})
		end
		Decor.beams(kit, X(-72), -24, X(-56), 24, 14, true, 4, "SteelDark")
		-- Bandes de danger de part et d'autre des trois portes
		Decor.hazardBand(kit, X(-56) + sx * 1.6, -4, X(-56) + sx * 1.6, 4, 0, 1.1)
		Decor.hazardBand(kit, X(-56) + dockSide * 1.6, -4, X(-56) + dockSide * 1.6, 4, 0.2, 1.1)
		for _, z in { 22.4, -22.4 } do
			Decor.hazardBand(kit, X(-67), z, X(-61), z, 0.2, 1.1)
		end
		-- Marquage des emplacements au sol du quai
		for _, z in { -12, 12 } do
			Decor.floorLine(kit, X(-70), z, X(-58), z, 0.2, 0.25, "PaintWhite")
		end
		Decor.wallLight(kit, Vector3.new(X(-71), 9, -14), Vector3.new(sx, 0, 0), COOL, 0.9, 14)
		Decor.wallLight(kit, Vector3.new(X(-71), 9, 14), Vector3.new(sx, 0, 0), COOL, 0.9, 14)
		Decor.screen(kit, Vector3.new(X(-56) + dockSide * 0.7, 7, -14), Vector3.new(dockSide, 0, 0), 4, 2.2, CYAN)
		-- Pilastres de la face Yard du mur de quai
		for _, z in { -20, -12, 12, 20 } do
			kit:decorBox("Pilaster", X(-56) + sx * 0.7, 0, z - 0.4, X(-56) + sx * 1.0, 14, z + 0.4, "Concrete")
		end
	end
end

local function midWalls(kit: Kit)
	for _, sx in { 1, -1 } do
		local function X(x: number): number
			return x * sx
		end
		-- Mur nord (porte X(-34)..X(-27)) puis segments du mur sud
		Decor.wall(kit, X(-56), 16, X(-34), 16, 14, 1.2, { seam = "ConcreteDark", spacing = 5, base = "Concrete" })
		Decor.wall(kit, X(-27), 16, X(0), 16, 14, 1.2, { seam = "ConcreteDark", spacing = 5, base = "Concrete" })
		Decor.wall(kit, X(-56), -16, X(-26), -16, 14, 1.2, { seam = "ConcreteDark", spacing = 5, base = "Concrete" })
		Decor.wall(kit, X(-19), -16, X(-6), -16, 14, 1.2, { seam = "ConcreteDark", spacing = 5, base = "Concrete" })
		kit:decorBox("WallCap", X(-56), 14, 15.25, X(0), 14.3, 16.75, "Steel")
		kit:decorBox("WallCap", X(-56), 14, -16.75, X(-6), 14.3, -15.25, "Steel")
		-- Encadrements des passages (montants fins)
		for _, z in { 16, -16 } do
			local a, b = if z > 0 then X(-34) else X(-26), if z > 0 then X(-27) else X(-19)
			for _, x in { a, b } do
				kit:decorBox("DoorFrame", x - 0.15, 0, z - 0.75, x + 0.15, 10, z + 0.75, "SteelDark")
			end
			kit:decorBox("DoorHeader", math.min(a, b), 9.7, z - 0.75, math.max(a, b), 10, z + 0.75, "SteelDark")
		end
		Decor.vent(kit, Vector3.new(X(-46), 9, 15.35), Vector3.new(0, 0, -1), 2.4, 1.6)
		Decor.vent(kit, Vector3.new(X(-46), 9, -15.35), Vector3.new(0, 0, 1), 2.4, 1.6)
		Decor.wallLight(kit, Vector3.new(X(-14), 11.5, 15.35), Vector3.new(0, 0, -1), SODIUM, 0.9, 16)
	end
	-- Fenêtre du mur sud : encadrement et appui
	kit:decorBox("WindowFrame", -6, 6.85, -16.75, 6, 7.15, -15.25, "Steel")
	kit:decorBox("WindowFrame", -6, 10.85, -16.75, 6, 11.15, -15.25, "Steel")
	for _, x in { -6, 6 } do
		kit:decorBox("WindowFrame", x - 0.15, 7, -16.75, x + 0.15, 11, -15.25, "Steel")
	end
end

local function containers(kit: Kit)
	for _, sx in { 1, -1 } do
		local function X(x: number): number
			return x * sx
		end
		Decor.container(kit, X(-50), 0, 36, X(-30), 8, 44, RUST, -sx)
		Decor.container(kit, X(-50), 8, 36, X(-40), 16, 44, TEAL, -sx)
		Decor.container(kit, X(-22), 0, 22, X(-6), 8, 30, TEAL, sx)
	end
	Decor.container(kit, -8, 0, 36, 8, 8, 44, CONTAINER_ORANGE, 1)
	Decor.dressCovers(kit, Color3.fromRGB(255, 190, 70))
end

local function tower(kit: Kit)
	-- Gaine nervurée de la tour (dans son emprise + 0.1)
	for i = -6, 6, 2 do
		kit:decorBox("TowerRib", i - 0.15, 0.3, -7.1, i + 0.15, 6.6, -6.95, "Steel")
		kit:decorBox("TowerRib", i - 0.15, 0.3, 6.95, i + 0.15, 6.6, 7.1, "Steel")
		kit:decorBox("TowerRib", -7.1, 0.3, i - 0.15, -6.95, 6.6, i + 0.15, "Steel")
		kit:decorBox("TowerRib", 6.95, 0.3, i - 0.15, 7.1, 6.6, i + 0.15, "Steel")
	end
	kit:decorBox("TowerBand", -7.15, 6.6, -7.15, 7.15, 7, 7.15, "PaintYellow")
	-- Mât d'antenne et balise (fins)
	kit:decorBox("Mast", 6.1, 7, 6.1, 6.5, 19, 6.5, "SteelDark")
	kit:decor("MastBeacon", CFrame.new(6.3, 19.4, 6.3), Vector3.new(0.7, 0.7, 0.7), "Beacon", { shape = "Ball" })
	Decor.cable(kit, Vector3.new(6.3, 18.6, 6.3), Vector3.new(26, 20.4, 45), 2.5, 6, 0.05)
	Decor.cable(kit, Vector3.new(6.3, 18.6, 6.3), Vector3.new(-26, 20.4, -45), 2.5, 6, 0.05)
end

local function overhead(kit: Kit)
	-- Guirlandes lumineuses au-dessus du Yard (ampoules fines, aucune lumière dynamique)
	for _, z in { -9, 9 } do
		local a, b = Vector3.new(-71, 19.4, z), Vector3.new(71, 19.4, z)
		Decor.cable(kit, a, b, 3.2, 12, 0.05)
		for index = 1, 15 do
			local t = index / 16
			local point = a:Lerp(b, t) - Vector3.new(0, 3.2 * 4 * t * (1 - t) + 0.25, 0)
			kit:decor("FestoonBulb", CFrame.new(point), Vector3.new(0.32, 0.32, 0.32), "WindowWarm", { shape = "Ball" })
		end
	end
	-- Portiques roulants au-dessus de la voie des conteneurs (appuyés sur le mur médian)
	for _, sx in { 1, -1 } do
		local x = 20 * sx
		kit:decorBox("GantryBeam", x - 0.9, 21, 15, x + 0.9, 22.4, 47, "PaintYellow")
		kit:decorBox("GantryPost", x - 0.4, 14.3, 15.6, x + 0.4, 21, 16.4, "PaintYellow")
		kit:decorBox("GantryTrolley", x - 1.4, 20.2, 28, x + 1.4, 21, 31, "SteelDark")
		kit:decorBox("GantryCable", x - 0.06, 15.4, 29.44, x + 0.06, 20.2, 29.56, "Cable")
		kit:decorBox("GantryHook", x - 0.45, 14.6, 29, x + 0.45, 15.4, 30, "SteelDark")
	end
end

local function skyline(kit: Kit)
	local rng = Decor.rng(4242)
	Decor.skyline(kit, rng, -72, -46, 72, 46, 34, 560, 48, 170, 340, -230, {
		body = "Tower",
		windows = { "WindowWarm", "WindowCool", "WindowWarm" },
		lit = 0.32,
	})
	Decor.crane(kit, -118, 74, -40, 112, 46, 30)
	Decor.crane(kit, 128, -84, -40, 124, 52, -150)
	Decor.billboard(kit, "KESTREL LOGISTICS", 0, 62, 168, 64, 12, "-Z", ORANGE)
	Decor.billboard(kit, "AETHER", -190, 74, -40, 40, 12, "+X", MAGENTA)
	Decor.billboard(kit, "SECTOR 7", 210, 40, 20, 34, 9, "-X", CYAN)
end

return function(kit: Kit)
	ground(kit)
	outerWalls(kit)
	docks(kit)
	midWalls(kit)
	containers(kit)
	tower(kit)
	overhead(kit)
	skyline(kit)
end
