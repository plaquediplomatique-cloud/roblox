--!strict
--[[
	Habillage de SPIRE-9 — station scientifique sur une falaise gelée, au crépuscule.

	Intentions :
	  * Le froid se voit : congères le long des murs, plaques de glace, neige sur la falaise.
	  * Les volumes pleins deviennent des bâtiments : bandeaux vitrés, enseignes, toits
	    équipés (groupes froids, antennes, balises).
	  * Chaque site a sa signature : réacteur cerclé de tuyauteries et de bandes de danger
	    (A), datacenter aux baies scintillantes et chemins de câbles (B).
	  * L'horizon : chaînes de montagnes enneigées, vallée dans la brume, téléphérique qui
	    plonge depuis la gare d'arrivée — on comprend d'où viennent les attaquants.
	Tout est décoratif (Decor) sauf le mobilier des spawns.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local Decor = require(script.Parent.Parent.Decor)

type Kit = MapKit.Kit

local REACTOR = Color3.fromRGB(120, 255, 210)
local CYAN = Color3.fromRGB(61, 225, 255)
local DUSK = Color3.fromRGB(255, 190, 150)
local AMBER = Color3.fromRGB(255, 190, 70)

local function ground(kit: Kit, rng: Decor.Rng)
	Decor.patches(kit, rng, -100, -86, -64, 4, 0.05, 26, { "SnowPack", "Ice" }, 3, 9)
	Decor.patches(kit, rng, -64, -86, 76, 4, 0, 30, { "RockDark", "SnowPack", "Basalt" }, 2, 7)
	-- Congères le long de la falaise et des murs exposés au vent (basses, fines)
	for z = -82, 0, 9 do
		kit:decor(
			"SnowDrift",
			CFrame.new(-98.4, 0.25, z) * CFrame.Angles(0, rng(-0.2, 0.2), 0),
			Vector3.new(2.6, 0.5, rng(5, 8)),
			"SnowPack"
		)
	end
	for x = -60, 56, 14 do
		kit:decor(
			"SnowDrift",
			CFrame.new(x, 0.2, -84.6) * CFrame.Angles(0, rng(-0.1, 0.1), 0),
			Vector3.new(rng(6, 10), 0.4, 2),
			"SnowPack"
		)
	end
	-- Plaza : calepinage, anneau d'incrustation autour de la flèche
	for x = -24, 24, 8 do
		Decor.floorLine(kit, x, -24, x, 24, 0.1, 0.12, "SteelDark")
	end
	for z = -16, 16, 8 do
		Decor.floorLine(kit, -30, z, 30, z, 0.1, 0.12, "SteelDark")
	end
	for _, d in { 8, 9 } do
		kit:decorBox("Inlay", -d, 0.1, -d, d, 0.15, -d + 0.2, "NeonWhite", { color = REACTOR })
		kit:decorBox("Inlay", -d, 0.1, d - 0.2, d, 0.15, d, "NeonWhite", { color = REACTOR })
		kit:decorBox("Inlay", -d, 0.1, -d, -d + 0.2, 0.15, d, "NeonWhite", { color = REACTOR })
		kit:decorBox("Inlay", d - 0.2, 0.1, -d, d, 0.15, d, "NeonWhite", { color = REACTOR })
	end
	-- Cour : marquages
	Decor.floorLine(kit, -28, -47, 28, -47, 0.1, 0.25, "PaintYellow")
	Decor.floorLine(kit, 0, -70, 0, -24, 0.1, 0.25, "PaintWhite")
end

local function building(kit: Kit, x1: number, z1: number, x2: number, z2: number, label: string?, labelFace: string?)
	local top = 14
	-- Bandeaux vitrés (fins) sur les quatre faces
	kit:decorBox("Glazing", x1 + 1, 9, z1 - 0.12, x2 - 1, 11, z1, "TowerGlass")
	kit:decorBox("Glazing", x1 + 1, 9, z2, x2 - 1, 11, z2 + 0.12, "TowerGlass")
	kit:decorBox("Glazing", x1 - 0.12, 9, z1 + 1, x1, 11, z2 - 1, "TowerGlass")
	kit:decorBox("Glazing", x2, 9, z1 + 1, x2 + 0.12, 11, z2 - 1, "TowerGlass")
	kit:decorBox("Sill", x1 + 1, 8.85, z1 - 0.2, x2 - 1, 9, z1, "WindowCool")
	kit:decorBox("Sill", x1 + 1, 8.85, z2, x2 - 1, 9, z2 + 0.2, "WindowCool")
	-- Couronnement et équipements de toiture (au-dessus de 14 studs)
	kit:decorBox("Coping", x1 - 0.2, top, z1 - 0.2, x2 + 0.2, top + 0.4, z2 + 0.2, "SteelDark")
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	kit:decorBox("RoofUnit", cx - 3, top + 0.4, cz - 2, cx + 3, top + 2.6, cz + 2, "Steel")
	kit:decorBox("RoofFan", cx - 2.2, top + 2.6, cz - 1.4, cx - 0.4, top + 2.8, cz + 1.4, "SteelDark")
	kit:decorBox("RoofMast", x2 - 2, top + 0.4, z2 - 2, x2 - 1.6, top + 9, z2 - 1.6, "SteelDark")
	kit:decor(
		"RoofBeacon",
		CFrame.new(x2 - 1.8, top + 9.3, z2 - 1.8),
		Vector3.new(0.6, 0.6, 0.6),
		"Beacon",
		{ shape = "Ball" }
	)
	if label and labelFace then
		local x, z = cx, cz
		if labelFace == "-Z" then
			z = z1 - 0.2
		elseif labelFace == "+Z" then
			z = z2 + 0.2
		elseif labelFace == "-X" then
			x = x1 - 0.2
		else
			x = x2 + 0.2
		end
		local width = if labelFace == "-Z" or labelFace == "+Z" then (x2 - x1) * 0.5 else (z2 - z1) * 0.5
		kit:sign(label, x, 12.4, z, math.min(width, 16), 1.6, labelFace, DUSK)
	end
end

local function buildings(kit: Kit)
	building(kit, -64, -72, -30, -50, "HYDRO-2", "+Z")
	building(kit, -64, -40, -30, 4, "HYDRO-1", "+X")
	building(kit, -46, 18, -30, 56, nil, nil)
	building(kit, 30, -72, 60, -50, "LAB C", "+Z")
	building(kit, 30, -40, 60, 4, "LAB B", "-X")
	building(kit, 30, 18, 46, 56, nil, nil)
end

local function walls(kit: Kit)
	local concrete = { seam = "ConcreteDark", spacing = 6, base = "Concrete", cap = "Steel" }
	for _, w in
		{
			{ -64, -72, -22, -72 },
			{ -64, -50, -30, -50 },
			{ -64, -40, -30, -40 },
			{ 22, -72, 60, -72 },
			{ 30, -50, 60, -50 },
			{ 30, -40, 60, -40 },
			{ -96, 64, -16, 64 },
			{ 16, 64, 96, 64 },
		}
	do
		Decor.wall(kit, w[1], w[2], w[3], w[4], if w[2] == 64 then 16 else 14, 1.2, concrete)
	end
	-- Murs percés : habillés par segments, hors des portes
	for _, sx in { 1, -1 } do
		Decor.wall(kit, 30 * sx, -70, 30 * sx, -50, 14, 1.2, concrete)
		Decor.wall(kit, 30 * sx, -40, 30 * sx, -24, 14, 1.2, concrete)
		Decor.wall(kit, 30 * sx, -24, 30 * sx, 6, 14, 1.2, concrete)
		Decor.wall(kit, 30 * sx, 16, 30 * sx, 24, 14, 1.2, concrete)
	end
	-- Mur extérieur sud et est : contreforts
	for x = -56, 56, 16 do
		kit:decorBox("Buttress", x - 0.5, 0, -85, x + 0.5, 17, -84.7, "Concrete")
	end
	-- Garde-corps de falaise : poteaux et balises ambre
	for z = -82, 82, 8 do
		kit:decorBox("RailPost", -99.75, 3.2, z - 0.15, -99.45, 4.4, z + 0.15, "SteelDark")
		kit:decor("RailBeacon", CFrame.new(-99.6, 4.6, z), Vector3.new(0.35, 0.35, 0.35), "NeonWhite", {
			shape = "Ball",
			color = AMBER,
		})
	end
end

local function plaza(kit: Kit)
	-- Anneaux lumineux de la flèche (fins)
	for _, y in { 8, 16, 26 } do
		kit:decorBox("SpireRing", -3.35, y, -3.35, 3.35, y + 0.3, 3.35, "NeonWhite", { color = REACTOR })
	end
	kit:decorBox("SpireRingDark", -3.3, 30, -3.3, 3.3, 30.8, 3.3, "SteelDark")
	-- Bandeaux et poteaux des garde-corps de la terrasse
	for x = -28, 28, 4 do
		if math.abs(x) < 18 or math.abs(x) > 26 then
			kit:decorBox("RailPost", x - 0.12, 8.4, 23.9, x + 0.12, 8.6, 24.7, "SteelDark")
		end
	end
	Decor.floorLine(kit, -30, 30, 30, 30, 5, 0.25, "PaintYellow")
	Decor.floorLine(kit, -56, 60, 56, 60, 5, 0.2, "PaintWhite")
end

local function reactor(kit: Kit)
	-- Bandes de danger autour du cœur, coins lumineux, tuyauteries vers les murs (hautes)
	Decor.hazardBand(kit, -78, 22, -62, 22, 0.1, 1)
	Decor.hazardBand(kit, -78, 38, -62, 38, 0.1, 1)
	Decor.hazardBand(kit, -78, 22, -78, 38, 0.1, 1)
	Decor.hazardBand(kit, -62, 22, -62, 38, 0.1, 1)
	for _, p in { Vector2.new(-76, 24), Vector2.new(-64, 24), Vector2.new(-76, 36), Vector2.new(-64, 36) } do
		kit:decorBox(
			"CoreEdge",
			p.X - 0.15,
			0,
			p.Y - 0.15,
			p.X + 0.15,
			10,
			p.Y + 0.15,
			"NeonWhite",
			{ color = REACTOR }
		)
	end
	Decor.pipe(kit, Vector3.new(-64, 12.5, 30), Vector3.new(-46.6, 12.5, 30), 0.45, "PipeCopper", 4)
	Decor.pipe(kit, Vector3.new(-70, 13, 36), Vector3.new(-70, 13, 55.4), 0.4, "PipeCopper", 4)
	Decor.pipe(kit, Vector3.new(-76, 12, 26), Vector3.new(-95.4, 12, 26), 0.35, "Pipe", 5)
	Decor.screen(kit, Vector3.new(-46.6, 7, 40), Vector3.new(-1, 0, 0), 4, 2, REACTOR)
	Decor.wallLight(kit, Vector3.new(-46.6, 11, 30), Vector3.new(-1, 0, 0), DUSK, 0.9, 16)
end

local function datacore(kit: Kit)
	for _, z in { 16, 28, 40 } do
		for _, face in { -1, 1 } do
			local zf = z + face * 1.06
			for row = 0, 4 do
				kit:decorBox(
					"RackLeds",
					58.6,
					1.4 + row * 1.5,
					zf - 0.04,
					69.4,
					1.5 + row * 1.5,
					zf + 0.04,
					"NeonWhite",
					{
						color = if (row + face) % 3 == 0 then AMBER else CYAN,
					}
				)
			end
		end
		-- Chemins de câbles au-dessus des baies
		kit:decorBox("CableTray", 56, 12.2, z - 0.8, 72, 12.45, z + 0.8, "SteelDark")
	end
	Decor.floorLine(kit, 58, 22, 70, 22, 0.1, 1.2, "NeonWhite", { color = Color3.fromRGB(30, 80, 120) })
	Decor.floorLine(kit, 58, 34, 70, 34, 0.1, 1.2, "NeonWhite", { color = Color3.fromRGB(30, 80, 120) })
	Decor.beams(kit, 46, 4, 100, 52, 14, false, 6, "MetalDark")
	Decor.screen(kit, Vector3.new(79.9, 6, 28), Vector3.new(-1, 0, 0), 6, 2.4, CYAN)
end

local function tunnel(kit: Kit)
	Decor.pipe(kit, Vector3.new(75.4, 9, -84), Vector3.new(75.4, 9, 2), 0.45, "PipeRust", 8)
	Decor.pipe(kit, Vector3.new(75.5, 10.2, -84), Vector3.new(75.5, 10.2, 2), 0.25, "Pipe", 10)
	for _, z in { -16, -32 } do
		kit:decor(
			"PipeFlange",
			CFrame.new(62, 6.2, z) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(0.3, 4.6, 4.6),
			"SteelDark",
			{
				shape = "Cylinder",
			}
		)
	end
	Decor.hazardBand(kit, 60.5, -84, 75.5, -84, 0.1, 1)
	Decor.hazardBand(kit, 60.5, 2.6, 75.5, 2.6, 0.1, 1)
	Decor.beams(kit, 60, -86, 76, 4, 12, true, 8, "SteelDark")
end

local function station(kit: Kit)
	Decor.beams(kit, -22, -86, 22, -70, 14, false, 5, "SteelDark")
	Decor.hazardBand(kit, -8, -68.4, 8, -68.4, 0.1, 1.1)
	Decor.screen(kit, Vector3.new(-14, 8, -85), Vector3.new(0, 0, 1), 6, 2.2, CYAN)
	Decor.screen(kit, Vector3.new(14, 8, -85), Vector3.new(0, 0, 1), 6, 2.2, DUSK)
	-- Câbles du téléphérique : de la gare vers la vallée (hors limites au sud)
	for _, x in { -6, 6 } do
		Decor.cable(kit, Vector3.new(x, 14.5, -86), Vector3.new(x * 1.4, -70, -420), 14, 10, 0.12)
	end
	kit:decorBox("CableCar", -5, -8, -168, 5, -2, -158, "PaintYellow", { group = "Backdrop" })
	kit:decorBox("CableCarGlass", -4.6, -6, -168.1, 4.6, -3.4, -157.9, "TowerGlass", { group = "Backdrop" })
	kit:decorBox("CableCarHanger", -0.3, -2, -163.3, 0.3, 4, -162.7, "SteelDark", { group = "Backdrop" })
	-- Pylône intermédiaire, accroché à la paroi
	kit:decorBox("Pylon", -3, -220, -262, 3, -20, -256, "SteelDark", { group = "Backdrop" })
	kit:decorBox("PylonArm", -12, -22, -261, 12, -19, -257, "SteelDark", { group = "Backdrop" })
end

local function command(kit: Kit)
	Decor.beams(kit, -16, 64, 16, 86, 19, false, 5, "SteelDark")
	for index, x in { -10, -3.5, 3.5, 10 } do
		Decor.screen(
			kit,
			Vector3.new(x, 11, 85),
			Vector3.new(0, 0, -1),
			5.4,
			2.6,
			if index % 2 == 0 then CYAN else DUSK
		)
	end
end

local function horizon(kit: Kit, rng: Decor.Rng)
	-- Vallée dans la brume, très bas à l'ouest et au sud
	kit:decorBox("ValleyFloor", -2600, -420, -2600, -100.5, -400, 2600, "RockDark", { group = "Backdrop" })
	kit:decorBox("ValleyFloor", -100.5, -420, -2600, 2600, -400, -86.5, "RockDark", { group = "Backdrop" })
	-- Chaînes de montagnes
	for _, ridge in
		{
			{ x = -520, z = -200, width = 620, height = 260 },
			{ x = -760, z = 260, width = 700, height = 360 },
			{ x = -400, z = 620, width = 520, height = 300 },
			{ x = 300, z = 520, width = 700, height = 320 },
			{ x = 640, z = -120, width = 520, height = 280 },
			{ x = 120, z = -620, width = 800, height = 240 },
		}
	do
		Decor.ridge(kit, rng, ridge.x, ridge.z, ridge.width, ridge.height, -300, 120)
	end
	-- Falaise sous la station (paroi rocheuse visible depuis le bord)
	for z = -80, 80, 20 do
		kit:decor(
			"CliffFace",
			CFrame.new(-114, -60, z) * CFrame.Angles(0, rng(-0.1, 0.1), 0),
			Vector3.new(22, 120, 24),
			if rng() < 0.5 then "RockDark" else "Basalt",
			{
				group = "Backdrop",
			}
		)
	end
end

return function(kit: Kit)
	local rng = Decor.rng(9017)
	ground(kit, rng)
	buildings(kit)
	walls(kit)
	plaza(kit)
	reactor(kit)
	datacore(kit)
	tunnel(kit)
	station(kit)
	command(kit)
	Decor.dressCovers(kit, AMBER)
	horizon(kit, rng)
end
