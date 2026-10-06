--!strict
--[[
	AETHER HQ — Hub / quartier général de l'escouade, 88e étage d'une tour, en journée.

	          x=-110        -40          0          40          x=110
	z=90  ┌──────────────┬─────────────────────┬──────────────────┐
	      │ LABORATOIRE  │  SALLE DE BRIEFING  │  SALLE DE JEUX   │  baies vitrées au nord
	      │ (personnal.) │   (classé, scène)   │   (casual)       │
	z=40  ├──────────────┼──────┐ ATRIUM ┌─────┼──────────────────┤
	      │ STAND DE TIR │      verrière      │   ARMURERIE      │
	      │ (entraîn.)  ◄═     ◆ sculpture     ═►  (vitrines)     │
	z=-40 ├──────────────┼────────────────────┼──────────────────┤
	      │ SALON        │  GALERIE DES       │   CAFÉ           │  baies vitrées au sud
	      │ (bibliothèque)│  CHAMPIONS         │   (bar)          │
	z=-90 └──────────────┴────────────────────┴───────────────────┘

	Un vrai bâtiment : murs enduits, bois, béton ciré, marbre, moquette, baies vitrées sur la
	ville, plafonds éclairés, verrière au-dessus de l'atrium (double hauteur). Le néon n'est
	plus qu'un accent (écrans, quelques diodes) : la lumière vient du soleil et des
	luminaires. Chaque pièce garde sa fonction (terminal interactif → panneau d'UI) : le hub
	reste un lieu de vie où l'on croise les autres joueurs, où l'on s'échauffe (stand de tir)
	et où l'on admire les armes (armurerie). Mobilier : Maps/Dressing/Hub + Maps/Furniture.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local dress = require(script.Parent.Parent.Dressing.Hub)

type Kit = MapKit.Kit

local SIGN_INK = Color3.fromRGB(38, 34, 30) -- lettrage mural sombre (sur enduit clair)
local SIGN_BRASS = Color3.fromRGB(196, 158, 92)
local SCREEN_TEXT = Color3.fromRGB(235, 242, 250)

local CEILING = 16 -- pièces latérales
local GALLERY_CEILING = 28
local ATRIUM_CEILING = 30
local SILL, HEAD = 3, 13 -- allège et linteau des baies vitrées

local function styles(kit: Kit)
	kit:defineStyle("HqWall", { material = "Plaster", color = Color3.fromRGB(214, 208, 198) })
	kit:defineStyle("HqWallWarm", { material = "Plaster", color = Color3.fromRGB(196, 186, 170) })
	kit:defineStyle("HqCeiling", { material = "SmoothPlastic", color = Color3.fromRGB(226, 226, 222) })
	kit:defineStyle("HqConcrete", { material = "Concrete", color = Color3.fromRGB(150, 150, 148) })
	kit:defineStyle("HqFloorStone", { material = "Marble", color = Color3.fromRGB(206, 204, 198), reflectance = 0.04 })
	kit:defineStyle("HqFloorWood", { material = "WoodPlanks", color = Color3.fromRGB(126, 92, 62) })
	kit:defineStyle("HqFloorWoodDark", { material = "WoodPlanks", color = Color3.fromRGB(86, 60, 42) })
	kit:defineStyle("HqCarpet", { material = "Carpet", color = Color3.fromRGB(48, 54, 66) })
	kit:defineStyle(
		"HqEpoxy",
		{ material = "SmoothPlastic", color = Color3.fromRGB(168, 172, 174), reflectance = 0.04 }
	)
	kit:defineStyle("HqPolished", { material = "Concrete", color = Color3.fromRGB(124, 126, 128) })
	kit:defineStyle("HqTiles", { material = "CeramicTiles", color = Color3.fromRGB(206, 200, 190) })
	kit:defineStyle("HqDarkStone", { material = "Marble", color = Color3.fromRGB(34, 34, 36), reflectance = 0.06 })
	kit:defineStyle("HqGreyStone", { material = "Marble", color = Color3.fromRGB(92, 92, 94), reflectance = 0.05 })
	kit:defineStyle("HqGlass", {
		material = "Glass",
		color = Color3.fromRGB(196, 214, 228),
		transparency = 0.72,
		reflectance = 0.12,
	})
	kit:defineStyle("HqMullion", { material = "Metal", color = Color3.fromRGB(30, 31, 33) })
	kit:defineStyle("HqSteelWhite", { material = "Metal", color = Color3.fromRGB(214, 216, 218) })
	kit:defineStyle("HqBrick", { material = "Brick", color = Color3.fromRGB(150, 88, 66) })
	kit:defineStyle("HqWoodSlat", { material = "Wood", color = Color3.fromRGB(150, 108, 70) })
	kit:defineStyle("HqWalnut", { material = "Wood", color = Color3.fromRGB(92, 62, 42) })
	kit:defineStyle("HqFabricPanel", { material = "Fabric", color = Color3.fromRGB(62, 70, 84) })
	kit:defineStyle("HqTowerDay", { material = "Concrete", color = Color3.fromRGB(172, 176, 182) })
	kit:defineStyle("HqTowerDark", { material = "Concrete", color = Color3.fromRGB(96, 102, 110) })
	kit:defineStyle("HqTowerGlass", {
		material = "Glass",
		color = Color3.fromRGB(86, 120, 150),
		reflectance = 0.3,
	})
	kit:defineStyle("HqTowerGlassWarm", {
		material = "Glass",
		color = Color3.fromRGB(150, 140, 120),
		reflectance = 0.25,
	})
end

--[[
	Mur extérieur axe-aligné avec baies vitrées : allège pleine, bandeau vitré (vitrage +
	meneaux tous les 5 studs), retombée pleine jusqu'en haut. `bays` : portions vitrées.
]]
local function outerWall(kit: Kit, axis: string, fixed: number, from: number, to: number, bays: { { number } })
	local t = 2
	local function slab(name: string, a: number, b: number, y1: number, y2: number, style: string)
		if axis == "X" then
			kit:box(name, a, y1, fixed - t / 2, b, y2, fixed + t / 2, style)
		else
			kit:box(name, fixed - t / 2, y1, a, fixed + t / 2, y2, b, style)
		end
	end
	local cursor = from
	for _, bay in bays do
		local a, b = bay[1], bay[2]
		if a > cursor then
			slab("OuterWall", cursor, a, 0, ATRIUM_CEILING, "HqWall")
		end
		slab("WindowSill", a, b, 0, SILL, "HqWall")
		slab("WindowHead", a, b, HEAD, ATRIUM_CEILING, "HqWall")
		local panes = math.max(math.floor((b - a) / 5 + 0.5), 1)
		for index = 0, panes do
			local p = a + (b - a) * index / panes
			slab("Mullion", p - 0.25, p + 0.25, SILL, HEAD, "HqMullion")
		end
		slab("WindowGlass", a, b, SILL, HEAD, "HqGlass")
		-- Tablette intérieure et pare-closes (bandeaux fins)
		if axis == "X" then
			local inner = if fixed > 0 then fixed - t / 2 else fixed + t / 2
			local dir = if fixed > 0 then -1 else 1
			kit:decorBox("WindowLedge", a, SILL - 0.15, inner, b, SILL, inner + dir * 0.7, "HqWalnut")
			kit:decorBox("WindowTransom", a, HEAD - 0.1, inner, b, HEAD + 0.25, inner + dir * 0.2, "HqMullion")
		else
			local inner = if fixed > 0 then fixed - t / 2 else fixed + t / 2
			local dir = if fixed > 0 then -1 else 1
			kit:decorBox("WindowLedge", inner, SILL - 0.15, a, inner + dir * 0.7, SILL, b, "HqWalnut")
			kit:decorBox("WindowTransom", inner, HEAD - 0.1, a, inner + dir * 0.2, HEAD + 0.25, b, "HqMullion")
		end
		cursor = b
	end
	if cursor < to then
		slab("OuterWall", cursor, to, 0, ATRIUM_CEILING, "HqWall")
	end
end

--[[ Cloison intérieure axe-alignée, éventuellement percée d'une porte (cadre en noyer). ]]
local function partition(
	kit: Kit,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	height: number,
	door: { number }?,
	style: string?
)
	local wallStyle = style or "HqWall"
	local t = 1.6
	if not door then
		if axis == "X" then
			kit:box("Partition", from, 0, fixed - t / 2, to, height, fixed + t / 2, wallStyle)
		else
			kit:box("Partition", fixed - t / 2, 0, from, fixed + t / 2, height, to, wallStyle)
		end
		return
	end
	local a, b = door[1], door[2]
	local doorHeight = 10
	if axis == "X" then
		kit:wallDoor("Partition", from, fixed, to, fixed, height, a, b, doorHeight, wallStyle, t)
		for _, x in { a, b } do
			kit:decorBox(
				"DoorJamb",
				x - 0.3,
				0,
				fixed - t / 2 - 0.15,
				x + 0.3,
				doorHeight,
				fixed + t / 2 + 0.15,
				"HqWalnut"
			)
		end
		kit:decorBox(
			"DoorHead",
			a - 0.3,
			doorHeight,
			fixed - t / 2 - 0.15,
			b + 0.3,
			doorHeight + 0.6,
			fixed + t / 2 + 0.15,
			"HqWalnut"
		)
	else
		kit:wallDoor("Partition", fixed, from, fixed, to, height, a, b, doorHeight, wallStyle, t)
		for _, z in { a, b } do
			kit:decorBox(
				"DoorJamb",
				fixed - t / 2 - 0.15,
				0,
				z - 0.3,
				fixed + t / 2 + 0.15,
				doorHeight,
				z + 0.3,
				"HqWalnut"
			)
		end
		kit:decorBox(
			"DoorHead",
			fixed - t / 2 - 0.15,
			doorHeight,
			a - 0.3,
			fixed + t / 2 + 0.15,
			doorHeight + 0.6,
			b + 0.3,
			"HqWalnut"
		)
	end
end

--[[ Lettrage mural (sans fond lumineux) : nom de pièce au-dessus d'une porte. ]]
local function lettering(
	kit: Kit,
	text: string,
	x: number,
	y: number,
	z: number,
	width: number,
	height: number,
	facing: string,
	color: Color3
)
	local sign = kit:sign(text, x, y, z, width, height, facing, color)
	local spec = sign.sign
	if spec then
		spec.plain = true
	end
	sign.query = false
end

--[[ Borne interactive : pied en acier sombre, écran blanc sur fond nuit, lumière douce. ]]
local function kiosk(kit: Kit, action: string, label: string, x: number, z: number, facing: string)
	local first = #kit.prims + 1
	kit:terminal(action, label, x, z, facing, SCREEN_TEXT)
	for index = first, #kit.prims do
		local prim = kit.prims[index]
		if prim.name == "Terminal" then
			prim.material = "Metal"
			prim.color = Color3.fromRGB(42, 44, 48)
			-- Socle et chapeau : la borne devient un meuble fini, pas une boîte.
			local p, size = prim.cframe.Position, prim.size
			kit:decorBox(
				"KioskPlinth",
				p.X - size.X / 2 - 0.15,
				0,
				p.Z - size.Z / 2 - 0.15,
				p.X + size.X / 2 + 0.15,
				0.25,
				p.Z + size.Z / 2 + 0.15,
				"HqSteelWhite"
			)
			kit:decorBox(
				"KioskCap",
				p.X - size.X / 2 - 0.05,
				size.Y,
				p.Z - size.Z / 2 - 0.05,
				p.X + size.X / 2 + 0.05,
				size.Y + 0.12,
				p.Z + size.Z / 2 + 0.05,
				"HqSteelWhite"
			)
		elseif prim.light then
			prim.light.color = Color3.fromRGB(220, 232, 255)
			prim.light.brightness = 0.8
			prim.light.range = 10
		elseif prim.sign then
			prim.sign.background = Color3.fromRGB(14, 22, 34)
		end
	end
end

local function build(kit: Kit)
	styles(kit)
	kit:bounds(-110, -90, 110, 90, 60)
	kit:floor("Slab", -110, -90, 110, 90, "HqConcrete", -0.3, 4)

	-- SOLS (finition par pièce, dessus à y = 0) --------------------------------------
	kit:floor("AtriumFloor", -40, -40, 40, 40, "HqFloorStone", 0, 0.3)
	kit:floor("BriefingFloor", -40, 40, 40, 90, "HqCarpet", 0, 0.3)
	kit:floor("LabFloor", -110, 40, -40, 90, "HqEpoxy", 0, 0.3)
	kit:floor("GamesFloor", 40, 40, 110, 90, "HqFloorWood", 0, 0.3)
	kit:floor("ArmoryFloor", 40, -40, 110, 40, "HqPolished", 0, 0.3)
	kit:floor("RangeFloor", -110, -40, -40, 40, "ConcreteDark", 0, 0.3)
	kit:floor("GalleryFloor", -40, -90, 40, -40, "HqGreyStone", 0, 0.3)
	kit:floor("LoungeFloor", -110, -90, -40, -40, "HqFloorWoodDark", 0, 0.3)
	kit:floor("CafeFloor", 40, -90, 110, -40, "HqTiles", 0, 0.3)

	-- ENVELOPPE : baies vitrées au nord, au sud et sur les pignons des pièces de vie -----
	outerWall(kit, "X", 90, -110, 110, { { -104, -46 }, { 46, 104 } })
	outerWall(kit, "X", -90, -110, 110, { { -104, -46 }, { 46, 104 } })
	outerWall(kit, "Z", -110, -90, 90, { { -84, -46 }, { 46, 70 } })
	outerWall(kit, "Z", 110, -90, 90, {})

	-- CLOISONS ----------------------------------------------------------------------------
	-- Atrium (double hauteur jusqu'à la verrière)
	partition(kit, "X", 40, -40, 40, ATRIUM_CEILING, { -14, 14 })
	partition(kit, "X", -40, -40, 40, ATRIUM_CEILING, { -14, 14 })
	partition(kit, "Z", -40, -40, 40, ATRIUM_CEILING, { -12, 12 })
	partition(kit, "Z", 40, -40, 40, ATRIUM_CEILING, { -12, 12 })
	-- Galerie (haute) / salon et café
	partition(kit, "Z", -40, -90, -40, GALLERY_CEILING, { -70, -56 })
	partition(kit, "Z", 40, -90, -40, GALLERY_CEILING, { -70, -56 })
	-- Briefing / laboratoire et salle de jeux
	partition(kit, "Z", -40, 40, 90, CEILING, { 50, 64 })
	partition(kit, "Z", 40, 40, 90, CEILING, { 50, 64 })
	-- Rangée nord et sud des ailes
	partition(kit, "X", 40, -110, -40, CEILING, nil) -- stand de tir | laboratoire (fermé)
	partition(kit, "X", 40, 40, 110, CEILING, { 54, 66 }) -- armurerie | salle de jeux
	partition(kit, "X", -40, -110, -40, CEILING, nil) -- stand de tir | salon (fermé)
	partition(kit, "X", -40, 40, 110, CEILING, { 54, 66 }) -- armurerie | café

	-- PLAFONDS ----------------------------------------------------------------------------
	for _, room in
		{
			{ -40, 40, 40, 90 },
			{ -110, 40, -40, 90 },
			{ 40, 40, 110, 90 },
			{ 40, -40, 110, 40 },
			{ -110, -40, -40, 40 },
			{ -110, -90, -40, -40 },
			{ 40, -90, 110, -40 },
		}
	do
		kit:ceiling(room[1], room[2], room[3], room[4], CEILING, "HqCeiling")
	end
	kit:ceiling(-40, -90, 40, -40, GALLERY_CEILING, "HqCeiling")
	-- Verrière de l'atrium : vitrage collidable (le soleil passe), résille d'acier
	for index = 0, 7 do
		for row = 0, 7 do
			local x1, z1 = -40 + index * 10, -40 + row * 10
			kit:box("Skylight", x1, ATRIUM_CEILING, z1, x1 + 10, ATRIUM_CEILING + 0.3, z1 + 10, "HqGlass", "Ceiling")
		end
	end
	for offset = -40, 40, 10 do
		kit:decorBox(
			"SkylightBeam",
			offset - 0.2,
			ATRIUM_CEILING - 0.8,
			-40,
			offset + 0.2,
			ATRIUM_CEILING,
			40,
			"HqSteelWhite"
		)
		kit:decorBox(
			"SkylightBeam",
			-40,
			ATRIUM_CEILING - 0.8,
			offset - 0.2,
			40,
			ATRIUM_CEILING,
			offset + 0.2,
			"HqSteelWhite"
		)
	end

	-- ATRIUM : sculpture, bassin, apparitions, borne ----------------------------------------
	-- Bassin carré (margelle assise), sculpture torsadée au centre.
	kit:box("PoolFloor", -8, 0, -8, 8, 0.1, 8, "HqDarkStone", "Props")
	for _, spec in
		{
			{ -9, -9, 9, -8 },
			{ -9, 8, 9, 9 },
			{ -9, -8, -8, 8 },
			{ 8, -8, 9, 8 },
		}
	do
		kit:box("PoolRim", spec[1], 0, spec[2], spec[3], 1.5, spec[4], "HqFloorStone", "Props")
	end
	kit:decorBox("PoolWater", -8, 0.9, -8, 8, 1, 8, "Water")
	kit:box("SculptureBase", -2.6, 0, -2.6, 2.6, 2.2, 2.6, "HqConcrete", "Props")
	-- Sculpture « Aether » : tour torsadée acier blanc / laiton (rappel des filets du sol),
	-- silhouette lisible depuis chaque entrée sans boucher la perspective vers la verrière,
	-- couronnée d'un cristal lumineux discret.
	local levels = 7
	for index = 0, levels - 1 do
		local t = index / (levels - 1)
		local width = 3.6 - 1.7 * t
		local height = 1.3
		local y = 2.2 + index * height + height / 2
		-- Pièce solide (pivotée : pas une boîte axe-alignée de kit:box).
		local tier = kit:decor(
			"AetherTier",
			CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(index * 13), 0),
			Vector3.new(width, height - 0.12, width),
			if index % 2 == 0 then "HqSteelWhite" else "Brass",
			{ group = "Props", shadow = true }
		)
		tier.collide = true
		tier.query = true
	end
	local top = 2.2 + levels * 1.3
	kit:decor(
		"AetherCrystal",
		CFrame.new(0, top + 2.3, 0) * CFrame.Angles(math.rad(45), math.rad(20), math.rad(35.26)),
		Vector3.new(1.3, 1.3, 1.3),
		"NeonWhite",
		{ color = Color3.fromRGB(150, 225, 255) }
	)

	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		kit:spawn("Hub", math.cos(angle) * 14, math.sin(angle) * 14, 0, 0)
	end
	-- Deux bornes JOUER encadrent le bassin, tournées vers les apparitions : à un pas du
	-- joueur, sans couper l'axe entrée → sculpture → enseigne.
	kiosk(kit, "Play", "JOUER", -15.5, -15.5, "+X")
	kiosk(kit, "Play", "JOUER", 15.5, -15.5, "-X")
	lettering(kit, "AETHER STRIKE", 0, 23, 39, 34, 4, "-Z", SIGN_BRASS)
	lettering(kit, "SALLE DE BRIEFING · CLASSÉ", 0, 11.6, 39.15, 26, 1.6, "-Z", SIGN_INK)
	lettering(kit, "GALERIE DES CHAMPIONS", 0, 11.6, -39.15, 24, 1.6, "+Z", SIGN_INK)
	lettering(kit, "STAND DE TIR", -39.15, 11.6, 0, 14, 1.6, "+X", SIGN_INK)
	lettering(kit, "ARMURERIE", 39.15, 11.6, 0, 12, 1.6, "-X", SIGN_INK)

	-- SALLE DE BRIEFING (classé) ------------------------------------------------------------
	kit:platform("Stage", -26, 70, 26, 86, 1.6, "HqFloorWood")
	kit:ramp("StageSteps", -8, 66, 8, 70, 0, 1.6, "+Z", "HqFloorWood")
	kiosk(kit, "Ranked", "CLASSÉ", -14, 76, "-Z")
	kiosk(kit, "Ranked", "CLASSÉ", 0, 78, "-Z")
	kiosk(kit, "Ranked", "CLASSÉ", 14, 76, "-Z")
	for _, prim in kit.prims do
		local raised = prim.name == "Terminal" or prim.name == "KioskPlinth" or prim.name == "KioskCap"
		if raised and prim.cframe.Position.Z > 70 then
			prim.cframe += Vector3.new(0, 1.6, 0)
		elseif prim.name == "Sign" and prim.cframe.Position.Z > 70 and prim.cframe.Position.Y < 8 then
			prim.cframe += Vector3.new(0, 1.6, 0)
		end
	end
	local screenSign = kit:sign("CLASSÉ  ·  SAISON 1", 0, 9, 88.7, 40, 9, "-Z", SCREEN_TEXT)
	local screenSpec = screenSign.sign
	if screenSpec then
		screenSpec.background = Color3.fromRGB(16, 30, 52)
	end
	screenSign.query = false

	-- LABORATOIRE (parties personnalisées) ---------------------------------------------------
	kiosk(kit, "Custom", "PERSONNALISÉ", -76, 70, "-Z")
	lettering(kit, "LABORATOIRE", -39.15, 11.6, 57, 12, 1.4, "+X", SIGN_INK)

	-- SALLE DE JEUX (casual) ----------------------------------------------------------------
	kiosk(kit, "Casual", "CASUAL", 76, 70, "-Z")
	lettering(kit, "SALLE DE JEUX", 39.15, 11.6, 57, 12, 1.4, "-X", SIGN_INK)

	-- ARMURERIE : 14 vitrines d'armes (affichage des skins par HubWorld) --------------------
	kiosk(kit, "Armory", "ARMURERIE", 60, 0, "-X")
	for row, x in { 76, 96 } do
		for index = 0, 6 do
			local z = -30 + index * 10
			local pedestal = kit:box("Pedestal", x - 2, 0, z - 2, x + 2, 3, z + 2, "HqDarkStone", "Props")
			table.insert(pedestal.tags, "WeaponPedestal")
			pedestal.attributes.Slot = (row - 1) * 7 + index + 1
		end
	end

	-- STAND DE TIR (entraînement) : le joueur tire vers -X ------------------------------------
	kit:zone("TrainingZone", "TrainingZone", -110, -2, -40, -40.5, 30, 40, nil)
	kiosk(kit, "Training", "ENTRAÎNEMENT", -46, 30, "+X")
	for index, z in { -26, -14, -2, 10 } do
		kit:cover(-50, z - 5, -48, z + 5, 3.2, "HqWalnut")
		local lane =
			kit:zone("BotAnchor", "LaneAnchor", -96, 0, z - 1, -94, 4, z + 1, { Kind = "Static", Lane = index })
		lane.attributes.Distances = "15,30,45"
	end
	for _, z in { -20, -8, 4 } do
		kit:wall("LaneDivider", -94, z, -54, z, 1.2, "HqConcrete", 0.4)
	end
	kit:box("TrackWall", -108, 0, 18, -60, 10, 20, "HqConcrete")
	kit:zone("BotAnchor", "StrafeAnchor", -98, 0, 26, -70, 4, 36, { Kind = "Strafe", Lane = 5 })
	-- Butte de tir (pare-balles incliné) au fond
	kit:box("Backstop", -110, 0, -38, -105, 12, 17, "SteelDark")
	kit:ramp("BackstopSlope", -105, -38, -100, 17, 0, 6, "-X", "Rubber")
	for _, info in { { x = -64, label = "15" }, { x = -79, label = "30" }, { x = -94, label = "45" } } do
		local plate = kit:sign(info.label, info.x, 13.5, -30, 3, 1.6, "+X", Color3.fromRGB(250, 214, 80))
		local spec = plate.sign
		if spec then
			spec.plain = true
		end
	end
	lettering(kit, "ZONE DE TIR — PROTECTION AUDITIVE", -84, 7.5, 17.85, 22, 1.4, "-Z", Color3.fromRGB(250, 214, 80))

	-- GALERIE DES CHAMPIONS (classement, missions, pass, réglages) --------------------------
	local board = kit:box("LeaderboardWall", -36, 2, -88.4, 36, 26, -87.6, "Monolith", "Props")
	table.insert(board.tags, "LeaderboardDisplay")
	kiosk(kit, "Leaderboard", "CLASSEMENT", -18, -70, "+Z")
	kiosk(kit, "Missions", "MISSIONS", 0, -66, "+Z")
	kiosk(kit, "Pass", "AETHER PASS", 18, -70, "+Z")
	kiosk(kit, "Settings", "RÉGLAGES", 30, -50, "-X")

	-- SALON (bibliothèque) et CAFÉ -----------------------------------------------------------
	kiosk(kit, "Play", "JOUER", -75, -46, "-Z")
	kiosk(kit, "Play", "JOUER", 75, -46, "-Z")
	lettering(kit, "SALON", -39.15, 11.6, -63, 8, 1.4, "+X", SIGN_INK)
	lettering(kit, "CAFÉ", 39.15, 11.6, -63, 6, 1.4, "-X", SIGN_INK)

	-- Callouts (nom de la pièce en haut de l'écran) ------------------------------------------
	kit:callout("ATRIUM", -40, -40, 40, 40)
	kit:callout("SALLE DE BRIEFING", -40, 40, 40, 90)
	kit:callout("LABORATOIRE", -110, 40, -40, 90)
	kit:callout("SALLE DE JEUX", 40, 40, 110, 90)
	kit:callout("ARMURERIE", 40, -40, 110, 40)
	kit:callout("STAND DE TIR", -110, -40, -40, 40)
	kit:callout("GALERIE DES CHAMPIONS", -40, -90, 40, -40)
	kit:callout("SALON", -110, -90, -40, -40)
	kit:callout("CAFÉ", 40, -90, 110, -40)

	-- Mobilier, luminaires et ville : Maps/Dressing/Hub
	dress(kit)
end

return {
	id = "hub",
	build = build,
	intro = {
		CFrame.lookAt(Vector3.new(-22, 7, -36), Vector3.new(6, 9, 10)),
		CFrame.lookAt(Vector3.new(58, 7, -44), Vector3.new(96, 4, -72)),
		CFrame.lookAt(Vector3.new(-48, 8, -44), Vector3.new(-92, 4, -76)),
		CFrame.lookAt(Vector3.new(0, 7, 44), Vector3.new(0, 7, 88)),
	},
	overview = CFrame.lookAt(Vector3.new(0, 200, -120), Vector3.new(0, 0, 0)),
}
