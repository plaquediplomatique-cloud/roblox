--!strict
--[[
	Aménagement d'AETHER HQ — chaque pièce est meublée comme un vrai lieu.

	  * Atrium : bassin et sculpture, arbres d'intérieur, bancs, suspensions, claustra bois
	    sous la verrière, écrans d'information.
	  * Salle de briefing : gradins de sièges face à un mur d'écrans, scène en bois,
	    panneaux acoustiques, bannières ONYX / HALO.
	  * Laboratoire : îlots de bureaux (écrans, chaises), baies de serveurs, table de
	    réunion et écran de visioconférence, tableaux blancs.
	  * Salle de jeux : billard, bornes d'arcade, coin canapé et télévision, distributeurs,
	    mur de briques et une enseigne lumineuse.
	  * Armurerie : socles de pierre sombre, râteliers muraux, casiers, établi, caisses.
	  * Stand de tir : postes cloisonnés numérotés, baffles acoustiques, cibles, butte.
	  * Galerie des champions : vitrines à trophées, portraits, bancs, cordons, caissons.
	  * Salon : bibliothèques, canapé et fauteuils club, tapis, lampadaires.
	  * Café : bar et arrière-bar (bouteilles, machine à café), tabourets, tables rondes,
	    suspensions, mur de briques, ardoise.
	  * Dehors : la ville en plein jour (tours de verre et de béton) derrière les baies.
	Le néon n'est qu'un accent (écrans, enseigne, diodes) : la lumière vient du soleil (verrière,
	baies) et des luminaires. Le hub n'est pas compétitif : le mobilier est solide.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local Decor = require(script.Parent.Parent.Decor)
local Furniture = require(script.Parent.Parent.Furniture)

type Kit = MapKit.Kit
type Rng = Decor.Rng

local CEILING = 16
local ATRIUM_CEILING = 30
local GALLERY_CEILING = 28

local ONYX = Color3.fromRGB(214, 96, 58)
local HALO = Color3.fromRGB(70, 150, 214)
local SLATE = Color3.fromRGB(70, 78, 92)
local SAND = Color3.fromRGB(176, 160, 136)
local OLIVE = Color3.fromRGB(92, 98, 72)
local RUST = Color3.fromRGB(150, 74, 54)
local CREAM = Color3.fromRGB(214, 204, 186)
local SCREEN_BLUE = Color3.fromRGB(44, 74, 110)
local ART = {
	Color3.fromRGB(196, 92, 60),
	Color3.fromRGB(40, 66, 98),
	Color3.fromRGB(214, 176, 92),
	Color3.fromRGB(60, 96, 80),
}

-- Dalles de plafond : `lit` = vraies lumières, `unlit` = dalles décoratives.
local function ceilingLights(kit: Kit, y: number, lit: { { number } }, unlit: { { number } }, size: Vector2)
	for _, spot in lit do
		Furniture.ceilingPanel(kit, spot[1], spot[2], y, size.X, size.Y, true)
	end
	for _, spot in unlit do
		Furniture.ceilingPanel(kit, spot[1], spot[2], y, size.X, size.Y, false)
	end
end

-- Plinthe le long d'un mur (fine), en évitant les ouvertures.
local function baseboard(
	kit: Kit,
	axis: string,
	face: number,
	from: number,
	to: number,
	gaps: { { number } },
	style: string
)
	local cursor = from
	local pieces: { { number } } = {}
	for _, gap in gaps do
		if gap[1] > cursor then
			table.insert(pieces, { cursor, gap[1] })
		end
		cursor = math.max(cursor, gap[2])
	end
	if cursor < to then
		table.insert(pieces, { cursor, to })
	end
	local dir = if face > 0 then -1 else 1
	for _, piece in pieces do
		if axis == "X" then
			kit:decorBox("Baseboard", piece[1], 0, face, piece[2], 0.7, face + dir * 0.15, style)
		else
			kit:decorBox("Baseboard", face, 0, piece[1], face + dir * 0.15, 0.7, piece[2], style)
		end
	end
end

-- Parement fin (briques, tissu acoustique, bois) sur une face de mur, en évitant les ouvertures.
local function cladding(
	kit: Kit,
	axis: string,
	face: number,
	from: number,
	to: number,
	y1: number,
	y2: number,
	gaps: { { number } },
	style: string
)
	local cursor = from
	local dir = if face > 0 then -1 else 1
	local function piece(a: number, b: number)
		if b - a < 0.5 then
			return
		end
		if axis == "X" then
			kit:decorBox("Cladding", a, y1, face, b, y2, face + dir * 0.2, style)
		else
			kit:decorBox("Cladding", face, y1, a, face + dir * 0.2, y2, b, style)
		end
	end
	for _, gap in gaps do
		piece(cursor, gap[1])
		cursor = math.max(cursor, gap[2])
	end
	piece(cursor, to)
end

---------------------------------------------------------------------------------------------
-- Atrium
---------------------------------------------------------------------------------------------

local function atrium(kit: Kit, rng: Rng)
	-- Calepinage du sol : cadre de pierre sombre et filets de laiton autour du bassin.
	for _, spec in
		{
			{ -19.5, -19.5, 19.5, -18 },
			{ -19.5, 18, 19.5, 19.5 },
			{ -19.5, -18, -18, 18 },
			{ 18, -18, 19.5, 18 },
		}
	do
		kit:decorBox("FloorInlay", spec[1], 0, spec[2], spec[3], 0.03, spec[4], "HqDarkStone")
	end
	for _, r in { 17.6, 19.9 } do
		kit:decorBox("BrassLine", -r, 0, -r, r, 0.04, -r + 0.12, "Brass")
		kit:decorBox("BrassLine", -r, 0, r - 0.12, r, 0.04, r, "Brass")
		kit:decorBox("BrassLine", -r, 0, -r, -r + 0.12, 0.04, r, "Brass")
		kit:decorBox("BrassLine", r - 0.12, 0, -r, r, 0.04, r, "Brass")
	end
	-- Margelle : couvertine de pierre claire
	for _, spec in
		{
			{ -9.2, -9.2, 9.2, -7.8 },
			{ -9.2, 7.8, 9.2, 9.2 },
			{ -9.2, -7.8, -7.8, 7.8 },
			{ 7.8, -7.8, 9.2, 7.8 },
		}
	do
		kit:decorBox("RimCap", spec[1], 1.5, spec[2], spec[3], 1.62, spec[4], "MarbleWhite")
	end
	-- Arbres d'intérieur aux quatre coins, bancs en couronne face au bassin
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		Furniture.tree(kit, rng, corner[1] * 29, corner[2] * 29, 12, "HqConcrete")
	end
	for index = 0, 7 do
		local angle = (index + 0.5) / 8 * math.pi * 2
		local x, z = math.cos(angle) * 23, math.sin(angle) * 23
		Furniture.bench(kit, x, z, math.deg(math.atan2(x, z)), 5.5, false)
	end
	-- Suspensions (tambours de tissu) sous la verrière
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		Furniture.pendant(kit, corner[1] * 20, corner[2] * 20, ATRIUM_CEILING - 1.2, 8, "Plaster")
	end
	-- Bandeau de béton à mi-hauteur et claustra de lattes de bois jusqu'à la verrière
	for _, wall in
		{
			{ axis = "X", face = 39.2 },
			{ axis = "X", face = -39.2 },
			{ axis = "Z", face = 39.2 },
			{ axis = "Z", face = -39.2 },
		}
	do
		local axis, face = wall.axis, wall.face
		local dir = if face > 0 then -1 else 1
		if axis == "X" then
			kit:decorBox("AtriumBand", -39.2, 16, face, 39.2, 16.8, face + dir * 0.6, "HqConcrete")
		else
			kit:decorBox("AtriumBand", face, 16, -39.2, face + dir * 0.6, 16.8, 39.2, "HqConcrete")
		end
		for offset = -38, 38, 1.6 do
			local behindLogo = axis == "X" and face > 0 and math.abs(offset) < 19
			if not behindLogo then
				if axis == "X" then
					kit:decorBox("Slat", offset - 0.18, 17.2, face, offset + 0.18, 28.6, face + dir * 0.3, "HqWoodSlat")
				else
					kit:decorBox("Slat", face, 17.2, offset - 0.18, face + dir * 0.3, 28.6, offset + 0.18, "HqWoodSlat")
				end
			end
		end
	end
	baseboard(kit, "X", 39.2, -39.2, 39.2, { { -14, 14 } }, "HqWalnut")
	baseboard(kit, "X", -39.2, -39.2, 39.2, { { -14, 14 } }, "HqWalnut")
	baseboard(kit, "Z", 39.2, -39.2, 39.2, { { -12, 12 } }, "HqWalnut")
	baseboard(kit, "Z", -39.2, -39.2, 39.2, { { -12, 12 } }, "HqWalnut")
	-- Écrans d'information de part et d'autre de l'entrée de la galerie
	for _, x in { -27, 27 } do
		Furniture.wallScreen(kit, Vector3.new(x, 7.5, -39.2), Vector3.new(0, 0, 1), 10, 5.6, SCREEN_BLUE)
	end
	-- Plantes près des portes
	for _, spot in { { -18, 36 }, { 18, 36 }, { -36, 17 }, { -36, -17 }, { 36, 17 }, { 36, -17 } } do
		Furniture.plant(kit, rng, spot[1], spot[2], 2.4, "HqConcrete")
	end
end

---------------------------------------------------------------------------------------------
-- Salle de briefing (classé)
---------------------------------------------------------------------------------------------

local function briefing(kit: Kit, rng: Rng)
	-- Mur d'écrans : cadre noir autour de l'écran géant
	kit:decorBox("ScreenFrame", -21, 4, 88.9, 21, 4.4, 89, "PaintBlack")
	kit:decorBox("ScreenFrame", -21, 13.6, 88.9, 21, 14, 89, "PaintBlack")
	kit:decorBox("ScreenFrame", -21, 4, 88.9, -20.6, 14, 89, "PaintBlack")
	kit:decorBox("ScreenFrame", 20.6, 4, 88.9, 21, 14, 89, "PaintBlack")
	-- Bannières des factions
	for _, spec in { { x = -27, color = ONYX }, { x = 27, color = HALO } } do
		local x, color = spec.x, spec.color
		kit:decorBox("Banner", x - 2.5, 4.5, 88.6, x + 2.5, 14.5, 88.75, "FabricDark", { color = color })
		kit:decorBox("BannerRod", x - 3, 14.5, 88.5, x + 3, 14.8, 88.8, "Brass")
	end
	-- Gradins : deux blocs de sièges de part et d'autre de l'allée centrale
	for _, z in { 48, 52.4, 56.8, 61.2 } do
		for _, x in { -19, 19 } do
			Furniture.seatRow(kit, x, z, 180, 7, SLATE)
		end
	end
	-- Pupitre sur la scène
	Decor.solid(
		kit,
		"Lectern",
		CFrame.new(-21, 1.6 + 1.8, 80) * CFrame.Angles(0, math.rad(20), 0),
		Vector3.new(1.8, 3.6, 1.4),
		"HqWalnut"
	)
	-- Panneaux acoustiques sur les murs latéraux (hors portes)
	for _, side in { -1, 1 } do
		local face = side * 39.2
		for z = 68, 86, 6 do
			if side < 0 then
				kit:decorBox("AcousticPanel", face, 3, z - 2.2, face + 0.25, 12, z + 2.2, "HqFabricPanel")
			else
				kit:decorBox("AcousticPanel", face - 0.25, 3, z - 2.2, face, 12, z + 2.2, "HqFabricPanel")
			end
		end
	end
	baseboard(kit, "Z", -39.2, 40.8, 89, { { 50, 64 } }, "HqWalnut")
	baseboard(kit, "Z", 39.2, 40.8, 89, { { 50, 64 } }, "HqWalnut")
	ceilingLights(
		kit,
		CEILING,
		{ { 0, 50 }, { 0, 60 }, { 0, 76 } },
		{ { -20, 50 }, { 20, 50 }, { -20, 62 }, { 20, 62 } },
		Vector2.new(6, 3)
	)
	for _, x in { -37, 37 } do
		Furniture.plant(kit, rng, x, 43, 2.4, "HqConcrete")
	end
end

---------------------------------------------------------------------------------------------
-- Laboratoire (parties personnalisées)
---------------------------------------------------------------------------------------------

local function lab(kit: Kit, rng: Rng)
	-- Deux îlots de bureaux dos à dos
	for _, row in { { z = 48, back = 50.8 }, { z = 60, back = 62.8 } } do
		for _, x in { -100, -92.6, -85.2 } do
			Furniture.desk(kit, x, row.z, 0, 7, 2, SCREEN_BLUE)
			Furniture.officeChair(kit, x, row.z - 2.6, 180, Color3.fromRGB(44, 46, 52))
			Furniture.desk(kit, x, row.back, 180, 7, 2, Color3.fromRGB(54, 96, 84))
			Furniture.officeChair(kit, x, row.back + 2.6, 0, Color3.fromRGB(44, 46, 52))
		end
	end
	-- Baies de serveurs le long du mur ouest
	for z = 75, 86, 2.5 do
		Furniture.serverRack(kit, rng, -107.4, z, -90)
	end
	-- Table de réunion, chaises et écran de visioconférence
	Furniture.longTable(kit, -58, 80, 0, 13, 4.6, "HqWalnut")
	for _, x in { -63, -58, -53 } do
		Furniture.chair(kit, x, 76.6, 180, "Leather")
		Furniture.chair(kit, x, 83.4, 0, "Leather")
	end
	Furniture.wallScreen(kit, Vector3.new(-40.8, 7.5, 80), Vector3.new(-1, 0, 0), 12, 6.75, SCREEN_BLUE)
	-- Tableaux blancs (mur sud)
	for _, x in { -96, -84 } do
		Furniture.whiteboard(kit, Vector3.new(x, 7, 40.8), Vector3.new(0, 0, 1), 9, 4.5)
	end
	Furniture.plant(kit, rng, -106.5, 43.5, 2.6, "PaintWhite")
	Furniture.plant(kit, rng, -44, 86.5, 2.6, "PaintWhite")
	ceilingLights(
		kit,
		CEILING,
		{ { -92, 55 }, { -60, 80 } },
		{ { -92, 66 }, { -60, 56 }, { -76, 82 } },
		Vector2.new(5, 5)
	)
end

---------------------------------------------------------------------------------------------
-- Salle de jeux (casual)
---------------------------------------------------------------------------------------------

local function games(kit: Kit, rng: Rng)
	Furniture.poolTable(kit, rng, 94, 56, 90)
	for _, x in { 90, 98 } do
		Furniture.pendant(kit, x, 56, CEILING, 6, "SteelDark")
	end
	for index, z in { 50, 54, 58, 62, 66 } do
		local accent = if index % 2 == 0 then Color3.fromRGB(230, 70, 160) else Color3.fromRGB(70, 200, 240)
		Furniture.arcade(kit, 107.4, z + 4, 90, accent, Color3.fromRGB(60, 90, 160))
	end
	-- Coin télé : canapé dos aux baies, fauteuils, table basse, tapis, meuble télé
	Furniture.rug(kit, 62, 80, 18, 12, Color3.fromRGB(150, 130, 104), Color3.fromRGB(104, 86, 66))
	Furniture.sofa(kit, 62, 85.2, 0, 10, SAND)
	Furniture.armchair(kit, 52.5, 79, -90, "FabricDark", OLIVE)
	Furniture.armchair(kit, 71.5, 79, 90, "FabricDark", OLIVE)
	Furniture.coffeeTable(kit, 62, 79.5, 0, 6, 3.2, "HqWalnut")
	Decor.solid(kit, "MediaConsole", CFrame.new(62, 1, 72.6), Vector3.new(10, 2, 1.8), "HqWalnut")
	Furniture.wallScreen(kit, Vector3.new(62, 5.2, 72.2), Vector3.new(0, 0, 1), 8, 4.5, Color3.fromRGB(60, 110, 150))
	-- Distributeurs
	Furniture.vending(kit, rng, 42.6, 74, -90, Color3.fromRGB(200, 40, 46))
	Furniture.vending(kit, rng, 42.6, 78, -90, Color3.fromRGB(30, 30, 34))
	-- Mur de briques (sud) et enseigne lumineuse
	cladding(kit, "X", 40.8, 40.8, 109, 0, CEILING, { { 54, 66 } }, "HqBrick")
	local neon = kit:sign("GAME ON", 84, 9.5, 41.2, 12, 3, "+Z", Color3.fromRGB(255, 120, 200))
	local spec = neon.sign
	if spec then
		spec.background = Color3.fromRGB(26, 16, 24)
	end
	neon.query = false
	Furniture.plant(kit, rng, 106.5, 86.5, 2.6, "HqConcrete")
	ceilingLights(kit, CEILING, { { 62, 64 } }, { { 94, 76 }, { 80, 50 } }, Vector2.new(5, 5))
end

---------------------------------------------------------------------------------------------
-- Armurerie
---------------------------------------------------------------------------------------------

local function rifleSilhouette(kit: Kit, x: number, y: number, z: number)
	-- Fusil posé sur un râtelier mural (est), canon vers +Z.
	kit:decorBox("RackRifle", x - 0.12, y - 0.25, z - 2, x, y + 0.25, z + 1.4, "SteelDark")
	kit:decorBox("RackRifleStock", x - 0.12, y - 0.55, z - 2.8, x, y + 0.15, z - 2, "PaintBlack")
	kit:decorBox("RackRifleBarrel", x - 0.1, y, z + 1.4, x - 0.02, y + 0.12, z + 3, "SteelDark")
	kit:decorBox("RackRifleMag", x - 0.12, y - 0.9, z - 0.4, x, y - 0.25, z + 0.1, "SteelDark")
end

local function armory(kit: Kit, rng: Rng)
	-- Socles : plateau de laiton et embase sombre
	for _, prim in table.clone(kit.prims) do
		if table.find(prim.tags, "WeaponPedestal") then
			local p = prim.cframe.Position
			kit:decorBox("PedestalTop", p.X - 2.05, 3, p.Z - 2.05, p.X + 2.05, 3.08, p.Z + 2.05, "Brass")
			kit:decorBox("PedestalBase", p.X - 2.2, 0, p.Z - 2.2, p.X + 2.2, 0.3, p.Z + 2.2, "HqMullion")
		end
	end
	for _, x in { 76, 96 } do
		kit:decorBox("FloorMat", x - 4, 0, -35, x + 4, 0.05, 35, "Rubber")
	end
	-- Râteliers muraux (est)
	for _, z in { -24, -8, 8, 24 } do
		kit:decorBox("RackPanel", 108.8, 3, z - 6, 109, 12, z + 6, "HqWalnut")
		for _, y in { 4.5, 7.5, 10.5 } do
			rifleSilhouette(kit, 108.8, y, z)
		end
	end
	-- Casiers (mur sud) et établi (mur nord)
	Furniture.lockers(kit, 80, -38.3, 180, 7, Color3.fromRGB(70, 84, 76))
	Furniture.lockers(kit, 98, -38.3, 180, 6, Color3.fromRGB(70, 84, 76))
	Furniture.counter(kit, 90, 37.6, 0, 14, "Steel", "WoodLight")
	kit:decorBox("Pegboard", 83, 4, 38.9, 97, 9, 39.2, "HqWalnut")
	for x = 84, 96, 2 do
		kit:decorBox("Tool", x - 0.08, 5 + rng(0, 2), 38.75, x + 0.08, 6.6 + rng(0, 1.5), 38.9, "SteelDark")
	end
	-- Caisses de munitions
	for _, spot in { { 104, 34 }, { 104, 30.4 }, { 100.6, 34 } } do
		Decor.solid(kit, "AmmoCrate", CFrame.new(spot[1], 1.2, spot[2]), Vector3.new(3.2, 2.4, 3.2), "CrateWood")
	end
	Decor.solid(kit, "AmmoCrate", CFrame.new(104, 3.6, 34), Vector3.new(3, 2.4, 3), "CrateWood")
	ceilingLights(
		kit,
		CEILING,
		{ { 76, -10 }, { 96, 10 } },
		{ { 76, 10 }, { 96, -10 }, { 76, 28 }, { 96, -28 } },
		Vector2.new(3, 14)
	)
end

---------------------------------------------------------------------------------------------
-- Stand de tir
---------------------------------------------------------------------------------------------

local function range(kit: Kit, rng: Rng)
	local lanes = { -26, -14, -2, 10 }
	for index, z in lanes do
		Furniture.shootingBooth(kit, -49, z, index, 12, if index == #lanes then { -1, 1 } else { -1 })
		Decor.floorLine(kit, -94, z, -52, z, 0, 0.12, "PaintYellow")
		Furniture.rangeTarget(kit, -101, z, CEILING)
	end
	-- Ligne de tir peinte et bande de sécurité derrière les postes
	Decor.floorLine(kit, -51.2, -32, -51.2, 16, 0, 0.35, "PaintYellow")
	Decor.hazardBand(kit, -45, -32, -45, 16, 0, 0.9)
	-- Baffles acoustiques inclinés au-dessus des couloirs
	for x = -100, -58, 7 do
		kit:decor(
			"Baffle",
			CFrame.new(x, 13.6, -8) * CFrame.Angles(0, 0, math.rad(32)),
			Vector3.new(0.3, 3.4, 48),
			"HqFabricPanel"
		)
	end
	-- Panneaux acoustiques sur le mur de tracking et le mur nord
	cladding(kit, "X", 18, -108, -60, 1, 9, {}, "HqFabricPanel")
	cladding(kit, "X", 39.2, -109, -40.8, 2, 12, {}, "HqFabricPanel")
	-- Marquage de l'arène de tracking
	Decor.floorLine(kit, -98, 31, -70, 31, 0, 0.2, "PaintWhite")
	ceilingLights(kit, CEILING, { { -48, -8 }, { -84, -8 } }, { { -84, 30 } }, Vector2.new(4, 40))
	Furniture.plant(kit, rng, -42.5, 37, 2, "HqConcrete")
end

---------------------------------------------------------------------------------------------
-- Galerie des champions
---------------------------------------------------------------------------------------------

local function gallery(kit: Kit, rng: Rng)
	-- Encadrement noyer du tableau de classement
	kit:decorBox("BoardFrame", -37, 1.4, -87.6, 37, 2, -87.2, "HqWalnut")
	kit:decorBox("BoardFrame", -37, 26, -87.6, 37, 26.6, -87.2, "HqWalnut")
	kit:decorBox("BoardFrame", -37, 1.4, -87.6, -36.4, 26.6, -87.2, "HqWalnut")
	kit:decorBox("BoardFrame", 36.4, 1.4, -87.6, 37, 26.6, -87.2, "HqWalnut")
	-- Vitrines à trophées le long des murs latéraux, portraits au-dessus
	for _, side in { -1, 1 } do
		for index, z in { -84, -77.5, -51 } do
			Furniture.displayCase(
				kit,
				side * 37.4,
				z,
				side * 90,
				4.4,
				2.4,
				if index % 2 == 0 then "Medal" else "Trophy"
			)
			Furniture.artwork(
				kit,
				rng,
				Vector3.new(side * 39.2, 11, z),
				Vector3.new(-side, 0, 0),
				4,
				5,
				{ ART[(index + (if side > 0 then 1 else 0)) % #ART + 1], CREAM, SLATE }
			)
		end
	end
	-- Bancs face au classement, cordons
	for _, x in { -11, 11 } do
		Furniture.bench(kit, x, -79, 0, 8, true, "Leather")
	end
	local points = {}
	for x = -30, 30, 10 do
		table.insert(points, Vector3.new(x, 0, -84.6))
	end
	Decor.stanchions(kit, points, Color3.fromRGB(150, 30, 40))
	-- Chemin de laiton depuis l'atrium
	for _, x in { -4, 4 } do
		kit:decorBox("BrassRunner", x - 0.08, 0, -86, x + 0.08, 0.04, -40.8, "Brass")
	end
	-- Plafond à caissons
	for offset = -30, 30, 10 do
		kit:decorBox(
			"Coffer",
			offset - 0.5,
			GALLERY_CEILING - 1.4,
			-89,
			offset + 0.5,
			GALLERY_CEILING,
			-40.8,
			"HqCeiling"
		)
	end
	for z = -80, -50, 10 do
		kit:decorBox("Coffer", -39.2, GALLERY_CEILING - 1.4, z - 0.5, 39.2, GALLERY_CEILING, z + 0.5, "HqCeiling")
	end
	for _, x in { -18, 18 } do
		Furniture.pendant(kit, x, -58, GALLERY_CEILING - 1.4, 10, "Brass")
	end
	ceilingLights(
		kit,
		GALLERY_CEILING,
		{ { -25, -75 }, { 25, -75 }, { 0, -55 } },
		{ { -5, -75 }, { 5, -45 }, { -25, -45 }, { 25, -45 } },
		Vector2.new(6, 6)
	)
	baseboard(kit, "Z", -39.2, -89, -40.8, { { -70, -56 } }, "HqWalnut")
	baseboard(kit, "Z", 39.2, -89, -40.8, { { -70, -56 } }, "HqWalnut")
end

---------------------------------------------------------------------------------------------
-- Salon (bibliothèque) et café
---------------------------------------------------------------------------------------------

local function lounge(kit: Kit, rng: Rng)
	-- Bibliothèques : mur nord (à l'ouest de la borne) et mur est (hors porte)
	for _, x in { -103, -96.6, -90.2 } do
		Furniture.bookshelf(kit, rng, x, -41.6, 0, 6.2, 8)
	end
	for _, z in { -86, -79.6 } do
		Furniture.bookshelf(kit, rng, -41.6, z, 90, 6.2, 8)
	end
	Furniture.bookshelf(kit, rng, -41.6, -47, 90, 6.2, 8)
	-- Grand salon : tapis, canapé, fauteuils club, table basse, lampadaires
	Furniture.rug(kit, -78, -69, 22, 15, RUST, Color3.fromRGB(96, 46, 34))
	Furniture.sofa(kit, -78, -76, 180, 11, Color3.fromRGB(66, 56, 50))
	Furniture.armchair(kit, -88.5, -68, -90, "Leather")
	Furniture.armchair(kit, -67.5, -68, 90, "Leather")
	Furniture.coffeeTable(kit, -78, -69.5, 0, 7, 3.6, "HqWalnut")
	Furniture.floorLamp(kit, -86, -77)
	Furniture.floorLamp(kit, -70, -60, false)
	-- Coin lecture près des baies (sud-ouest)
	Furniture.armchair(kit, -101.5, -81.8, Furniture.facing(-101.5, -81.8, -98.4, -80.6), "Leather")
	Furniture.armchair(kit, -95.2, -84.6, Furniture.facing(-95.2, -84.6, -98.4, -80.6), "Leather")
	Furniture.cafeTable(kit, -98.4, -80.6, 2, "HqWalnut", 1.9)
	Furniture.floorLamp(kit, -104, -86.5)
	-- Table de lecture (bibliothèque) : chaises, lampes de bureau
	Furniture.longTable(kit, -58, -80, 0, 12, 4.4, "HqWalnut")
	for _, x in { -62.5, -58, -53.5 } do
		Furniture.chair(kit, x, -76.8, 180, "Leather")
		Furniture.chair(kit, x, -83.2, 0, "Leather")
	end
	for _, x in { -62, -54 } do
		kit:decorBox("DeskLampBase", x - 0.3, 2.52, -80.3, x + 0.3, 2.62, -79.7, "Brass")
		kit:decorBox("DeskLampStem", x - 0.05, 2.62, -80.05, x + 0.05, 3.6, -79.95, "Brass")
		kit:decorBox("DeskLampShade", x - 0.4, 3.5, -80.4, x + 0.4, 3.9, -79.6, "PaintBlack", {
			color = Color3.fromRGB(30, 70, 50),
		})
	end
	-- Deuxième salon près des baies : banquette, fauteuils, tapis
	Furniture.rug(kit, -94, -60, 14, 11, SLATE, Color3.fromRGB(46, 50, 60))
	Furniture.sofa(kit, -101.5, -60, -90, 9, Color3.fromRGB(150, 140, 124))
	Furniture.armchair(kit, -88, -64, Furniture.facing(-88, -64, -96, -60), "FabricDark", OLIVE)
	Furniture.armchair(kit, -88, -56, Furniture.facing(-88, -56, -96, -60), "FabricDark", OLIVE)
	Furniture.coffeeTable(kit, -95, -60, 90, 5, 3, "HqWalnut")
	Furniture.artwork(kit, rng, Vector3.new(-60, 9, -40.8), Vector3.new(0, 0, -1), 7, 4.5, { RUST, CREAM, SLATE })
	for _, spot in { { -106.5, -50 }, { -45, -86.5 }, { -68, -86.5 }, { -106.5, -70 }, { -45, -52 } } do
		Furniture.plant(kit, rng, spot[1], spot[2], 2.6, "HqConcrete")
	end
	ceilingLights(kit, CEILING, {}, { { -78, -69 }, { -98, -80 }, { -96, -50 } }, Vector2.new(4, 4))
end

local function cafe(kit: Kit, rng: Rng)
	-- Bar : comptoir face à la salle, arrière-bar contre le mur est, tabourets
	Furniture.counter(kit, 96, -71, 90, 26, "HqWalnut", "MarbleWhite")
	Furniture.backBar(kit, rng, 107.6, -71, 90, 26)
	for z = -82, -60, 3.2 do
		Furniture.barStool(kit, 93.2, z)
	end
	for index, z in { -80, -74, -68, -62 } do
		Furniture.pendant(kit, 95.4, z, CEILING, 6.5, "Brass", index % 2 == 1)
	end
	-- Tables rondes et chaises
	for _, x in { 54, 66, 78 } do
		for _, z in { -83, -66 } do
			Furniture.cafeTable(kit, x, z, 3, "MarbleWhite")
			Furniture.chair(kit, x - 2.6, z, -90, "HqWalnut")
			Furniture.chair(kit, x + 2.6, z, 90, "HqWalnut")
			Furniture.chair(kit, x, z + 2.6, 0, "HqWalnut")
		end
	end
	-- Mur de briques (nord), ardoise du menu et enseigne
	cladding(kit, "X", -40.8, 40.8, 109, 0, CEILING, { { 54, 66 } }, "HqBrick")
	kit:decorBox("MenuBoard", 82, 5, -41.2, 92, 11, -41, "PaintBlack", { color = Color3.fromRGB(28, 32, 30) })
	for index = 0, 5 do
		kit:decorBox(
			"MenuLine",
			83,
			10 - index * 0.85,
			-41.25,
			83 + rng(4, 8),
			10.12 - index * 0.85,
			-41.2,
			"PaintWhite"
		)
	end
	local neon = kit:sign("CAFÉ", 70, 10, -41.2, 9, 2.6, "-Z", Color3.fromRGB(255, 214, 160))
	local spec = neon.sign
	if spec then
		spec.background = Color3.fromRGB(30, 22, 16)
	end
	neon.query = false
	-- Mange-debout le long des baies (sud) avec tabourets
	for _, x in { 52, 66, 80 } do
		Furniture.longTable(kit, x, -87.2, 0, 10, 1.8, "HqWalnut")
		for _, dx in { -3, 0, 3 } do
			Furniture.barStool(kit, x + dx, -85.2)
		end
	end
	-- Coin canapé près de l'entrée de la galerie
	Furniture.rug(kit, 50, -48, 12, 9, Color3.fromRGB(120, 110, 96), Color3.fromRGB(84, 76, 66))
	Furniture.sofa(kit, 44.2, -48, -90, 8, Color3.fromRGB(70, 84, 96))
	Furniture.armchair(kit, 54.5, -52, Furniture.facing(54.5, -52, 46, -48), "Leather")
	Furniture.coffeeTable(kit, 50, -48, 90, 4.5, 2.8, "MarbleWhite")
	for _, spot in { { 43.5, -86.5 }, { 88, -60 }, { 108, -46 } } do
		Furniture.plant(kit, rng, spot[1], spot[2], 2.6, "HqConcrete")
	end
	ceilingLights(kit, CEILING, { { 66, -74 } }, { { 54, -60 }, { 78, -60 } }, Vector2.new(4, 4))
end

---------------------------------------------------------------------------------------------
-- Ville en plein jour (hors limites)
---------------------------------------------------------------------------------------------

local function dayTower(
	kit: Kit,
	rng: Rng,
	x: number,
	z: number,
	width: number,
	depth: number,
	height: number,
	baseY: number
)
	local backdrop: MapKit.DecorOptions = { group = "Backdrop" }
	local glassy = rng() < 0.6
	kit:decorBox(
		"Tower",
		x - width / 2,
		baseY,
		z - depth / 2,
		x + width / 2,
		baseY + height,
		z + depth / 2,
		if glassy then "HqTowerGlass" else (if rng() < 0.5 then "HqTowerDay" else "HqTowerDark"),
		backdrop
	)
	if not glassy then
		-- Façade tramée : bandeaux de fenêtres vitrées (seulement côté hub)
		local faceZ = if z > 0 then z - depth / 2 - 0.1 else z + depth / 2 + 0.1
		local faceX = if x > 0 then x - width / 2 - 0.1 else x + width / 2 + 0.1
		for level = 1, 4 do
			local y = baseY + height * level / 5
			kit:decorBox(
				"GlassBand",
				x - width / 2 + 1,
				y,
				faceZ - 0.05,
				x + width / 2 - 1,
				y + height / 9,
				faceZ + 0.05,
				"HqTowerGlass",
				backdrop
			)
			kit:decorBox(
				"GlassBand",
				faceX - 0.05,
				y,
				z - depth / 2 + 1,
				faceX + 0.05,
				y + height / 9,
				z + depth / 2 - 1,
				"HqTowerGlass",
				backdrop
			)
		end
	else
		-- Tour de verre : couronne de béton clair
		kit:decorBox(
			"Crown",
			x - width / 2 - 0.5,
			baseY + height,
			z - depth / 2 - 0.5,
			x + width / 2 + 0.5,
			baseY + height + 3,
			z + depth / 2 + 0.5,
			"HqTowerDay",
			backdrop
		)
	end
	if rng() < 0.3 then
		kit:decorBox(
			"Antenna",
			x - 0.4,
			baseY + height,
			z - 0.4,
			x + 0.4,
			baseY + height + rng(10, 24),
			z + 0.4,
			"Steel",
			backdrop
		)
	end
end

local function city(kit: Kit, rng: Rng)
	local placed = 0
	local attempts = 0
	while placed < 64 and attempts < 2000 do
		attempts += 1
		local x, z = rng(-760, 760), rng(-700, 700)
		local w, d = rng(26, 60), rng(26, 60)
		local clear = x + w / 2 < -180 or x - w / 2 > 180 or z + d / 2 < -160 or z - d / 2 > 160
		if clear then
			placed += 1
			dayTower(kit, rng, x, z, w, d, rng(220, 620), -420)
		end
	end
end

return function(kit: Kit)
	local rng = Decor.rng(8888)
	atrium(kit, rng)
	briefing(kit, rng)
	lab(kit, rng)
	games(kit, rng)
	armory(kit, rng)
	range(kit, rng)
	gallery(kit, rng)
	lounge(kit, rng)
	cafe(kit, rng)
	city(kit, rng)
end
