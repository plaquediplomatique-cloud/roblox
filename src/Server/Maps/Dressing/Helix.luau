--!strict
--[[
	Habillage de HELIX VAULT — banque corporatiste, étage 140, lumière de jour.

	Intentions :
	  * Le luxe se lit au sol et aux murs : soubassements de marbre noir, filets de laiton,
	    calepinage du marbre, colonnes avec base et chapiteau.
	  * Chaque pièce a sa fonction : hall d'accueil (files à cordons, canapés, plantes),
	    guichets automatiques, mur d'écrans de la sécurité, coffre tapissé de casiers.
	  * Plafonds à caissons et verrière à meneaux : l'atrium se lit comme un puits de lumière.
	  * Par la verrière, les gratte-ciel voisins rappellent qu'on est au 140e étage.
	Le mobilier solide (canapés, plantes) n'existe que dans les zones de spawn ; ailleurs
	tout est décoratif et sans collision (métriques du plan inchangées).
]]

local MapKit = require(script.Parent.Parent.MapKit)
local Decor = require(script.Parent.Parent.Decor)

type Kit = MapKit.Kit

local H = 16
local WHITE = Color3.fromRGB(235, 242, 255)
local GOLD = Color3.fromRGB(255, 200, 90)
local CYAN = Color3.fromRGB(61, 225, 255)
local VELVET = Color3.fromRGB(140, 30, 40)
local SOFA = Color3.fromRGB(46, 50, 60)

local function wainscot(kit: Kit, x1: number, z1: number, x2: number, z2: number, thickness: number, sides: { number })
	Decor.wall(kit, x1, z1, x2, z2, H, thickness, {
		base = "Marble",
		baseHeight = 1.4,
		band = "Brass",
		bandY = 1.4,
		seam = "WallDark",
		spacing = 6,
		sides = sides,
	})
end

local function floors(kit: Kit)
	-- Calepinage : filets de laiton tous les 8 studs dans l'atrium et le hall d'accueil
	for x = -32, 16, 8 do
		Decor.floorLine(kit, x, -20, x, 16, 0.1, 0.12, "Brass")
	end
	for z = -12, 12, 8 do
		Decor.floorLine(kit, -40, z, 24, z, 0.1, 0.12, "Brass")
	end
	for x = -26, 38, 8 do
		Decor.floorLine(kit, x, -62, x, -44, 0.15, 0.12, "Brass")
	end
	-- Bordures sombres des circulations
	Decor.floorLine(kit, 24, -43.5, 46, -43.5, 0.1, 0.5, "Marble")
	Decor.floorLine(kit, 24, 15.5, 46, 15.5, 0.1, 0.5, "Marble")
	-- Tapis du hall d'accueil
	kit:decorBox("Rug", 30, 0.15, -60, 44, 0.2, -52, "FabricDark", { color = VELVET })
end

local function walls(kit: Kit)
	-- Enveloppe : soubassement marbre noir + filet laiton sur les faces intérieures
	-- (seulement là où la face intérieure est visible : hors des volumes pleins)
	wainscot(kit, -34, -62, 46, -62, 2, { 1 })
	wainscot(kit, -42, 62, -8, 62, 2, { -1 })
	wainscot(kit, -42, -44, -42, 62, 2, { 1 })
	wainscot(kit, 52, 16, 52, 46, 2, { -1 })
	-- Murs du hall principal et de l'atrium
	wainscot(kit, 46, -44, 46, 16, 1.4, { -1 })
	wainscot(kit, -16, -20, 24, -20, 1.2, { 1 })
	wainscot(kit, 4, 16, 24, 16, 1.2, { -1 })
	wainscot(kit, -28, 16, -4, 16, 1.2, { -1 })
	-- Plafonds à caissons
	Decor.beams(kit, 24, -44, 46, 16, H, false, 5.5, "WallPanel")
	Decor.beams(kit, -34, -62, 46, -44, H, true, 6, "WallPanel")
	Decor.beams(kit, -40, 16, -20, 46, H, true, 6, "WallPanel")
	Decor.beams(kit, -8, 46, 30, 54, H, false, 6, "WallPanel")
end

local function lobby(kit: Kit, rng: Decor.Rng)
	-- Comptoir d'accueil (la couverture existante) : plateau laiton et façade éclairée
	kit:decorBox("DeskTop", -4.1, 4, -50.1, 12.1, 4.15, -47.9, "Brass")
	kit:decorBox("DeskGlow", -3.8, 0.4, -50.06, 11.8, 0.55, -50.0, "NeonWhite", { color = GOLD })
	-- Files à cordons vers les guichets (fines)
	Decor.stanchions(kit, {
		Vector3.new(26, 0.15, -52),
		Vector3.new(26, 0.15, -47),
		Vector3.new(34, 0.15, -47),
		Vector3.new(34, 0.15, -52),
	}, VELVET)
	-- Coin salon (zone de spawn : mobilier solide autorisé)
	Decor.sofa(kit, 38, 0.15, -59.6, 180, 7, SOFA)
	Decor.table(kit, 38, 0.15, -55.8, 4, 2.2, 1.4, "Marble")
	Decor.planter(kit, rng, -31, 0.15, -59.5, 2.6, "MarbleWhite")
	Decor.planter(kit, rng, 43.5, 0.15, -46.5, 2.2, "MarbleWhite")
	-- Écrans d'information au-dessus du comptoir
	Decor.screen(kit, Vector3.new(4, 8.5, -61), Vector3.new(0, 0, 1), 10, 2.6, CYAN)
end

local function mainHall(kit: Kit)
	-- Colonnes : base et chapiteau (anneaux fins), bague dorée
	for _, p in { Vector2.new(30, -32), Vector2.new(40, -26), Vector2.new(30, 2) } do
		kit:decorBox("ColumnBase", p.X - 1.55, 0.1, p.Y - 1.55, p.X + 1.55, 0.9, p.Y + 1.55, "Marble")
		kit:decorBox("ColumnRing", p.X - 1.35, 6, p.Y - 1.35, p.X + 1.35, 6.25, p.Y + 1.35, "Brass")
		kit:decorBox("ColumnCapital", p.X - 1.6, H - 1, p.Y - 1.6, p.X + 1.6, H - 0.2, p.Y + 1.6, "MarbleWhite")
	end
	-- Guichets automatiques encastrés dans le mur est
	for _, z in { -36, -28, -6, 4 } do
		Decor.screen(kit, Vector3.new(45.3, 4.5, z), Vector3.new(-1, 0, 0), 2.2, 1.4, CYAN)
		kit:decorBox("AtmFrame", 45.05, 2, z - 1.6, 45.3, 7, z + 1.6, "SteelDark")
	end
	-- Portiques de sécurité : bandeaux lumineux et écrans
	for _, x in { 26, 44 } do
		kit:decorBox("GateStrip", x - 0.1, 7.6, -17.1, x + 0.1, 7.8, -14.9, "NeonWhite", { color = CYAN })
	end
	Decor.screen(kit, Vector3.new(35, 9.5, -16.9), Vector3.new(0, 0, -1), 5, 1.2, Color3.fromRGB(255, 90, 70))
	-- Grande porte de coffre (décor existant) : couronne de boulons et volant
	local door = Vector3.new(43.35, 6, 13)
	for index = 0, 9 do
		local angle = index / 10 * math.pi * 2
		local bolt = door + Vector3.new(0, math.cos(angle) * 4.6, math.sin(angle) * 4.6)
		kit:decor("VaultBolt", CFrame.new(bolt), Vector3.new(0.3, 0.6, 0.6), "Steel", { shape = "Cylinder" })
	end
	kit:decor("VaultRing", CFrame.new(door), Vector3.new(0.2, 10.4, 10.4), "Brass", { shape = "Cylinder" })
	kit:decor(
		"VaultHub",
		CFrame.new(door - Vector3.new(0.15, 0, 0)),
		Vector3.new(0.3, 2.4, 2.4),
		"Steel",
		{ shape = "Cylinder" }
	)
	for _, angle in { 0, math.pi / 3, 2 * math.pi / 3 } do
		kit:decor(
			"VaultSpoke",
			CFrame.new(door - Vector3.new(0.3, 0, 0)) * CFrame.Angles(angle, 0, 0),
			Vector3.new(0.15, 6, 0.3),
			"Steel"
		)
	end
end

local function atrium(kit: Kit)
	-- Meneaux de la verrière (sous le verre, au-dessus des têtes)
	for x = -32, 16, 8 do
		kit:decorBox("Mullion", x - 0.13, H - 0.4, -20, x + 0.13, H, 16, "SteelDark")
	end
	for z = -12, 12, 8 do
		kit:decorBox("Mullion", -40, H - 0.4, z - 0.13, 24, H, z + 0.13, "SteelDark")
	end
	-- Fontaine : margelle laiton et plan d'eau
	kit:decorBox("FountainRim", -12.1, 3.6, -6.1, -3.9, 3.75, 2.1, "Brass")
	kit:decorBox("FountainWater", -11.6, 3.6, -5.6, -4.4, 3.68, 1.6, "Water")
	-- Colonnes de l'atrium
	for _, z in { 8, -12 } do
		kit:decorBox("ColumnBase", -21.55, 0.1, z - 1.55, -18.45, 0.9, z + 1.55, "Marble")
		kit:decorBox("ColumnCapital", -21.6, H - 1, z - 1.6, -18.4, H - 0.2, z + 1.6, "MarbleWhite")
	end
	-- Vitrine : socle lumineux du lingot exposé
	kit:decorBox("ShowroomGlow", 6, 0.1, -10, 10, 0.18, -6, "NeonWhite", { color = GOLD })
	Decor.screen(kit, Vector3.new(-16, 8, 15.4), Vector3.new(0, 0, -1), 11, 2, CYAN)
	-- Rampes d'escalator (mains courantes laiton)
	for _, x in { -24, -16 } do
		Decor.pipe(kit, Vector3.new(x, 3.4, -20), Vector3.new(x, 7.4, -26), 0.09, "Brass", 0)
	end
	for _, z in { -40, -34 } do
		Decor.pipe(kit, Vector3.new(-34, 3.4, z), Vector3.new(-24, 7.4, z), 0.09, "Brass", 0)
	end
end

local function vault(kit: Kit)
	-- Murs de casiers (coffres individuels) sur les faces intérieures du coffre
	local function lockers(x1: number, z1: number, x2: number, z2: number, normal: Vector3)
		local alongX = math.abs(x2 - x1) > math.abs(z2 - z1)
		local length = if alongX then math.abs(x2 - x1) else math.abs(z2 - z1)
		local columns = math.floor(length / 1.8)
		for column = 0, columns - 1 do
			for row = 0, 5 do
				local t = (column + 0.5) / columns
				local y = 1.2 + row * 1.25
				local center = Vector3.new(x1 + (x2 - x1) * t, y, z1 + (z2 - z1) * t) + normal * 0.08
				local size = if alongX then Vector3.new(1.6, 1.05, 0.16) else Vector3.new(0.16, 1.05, 1.6)
				kit:decor("Locker", CFrame.new(center), size, "Steel")
				kit:decor("LockerDial", CFrame.new(center + normal * 0.12), Vector3.new(0.12, 0.18, 0.18), "Brass")
			end
		end
	end
	-- (portes du coffre laissées libres : nord x 16..24, ouest z 28..36)
	lockers(10.8, 45.2, 15.4, 45.2, Vector3.new(0, 0, -1))
	lockers(24.6, 45.2, 50, 45.2, Vector3.new(0, 0, -1))
	lockers(10.8, 17, 10.8, 27.4, Vector3.new(1, 0, 0))
	lockers(10.8, 36.6, 10.8, 45, Vector3.new(1, 0, 0))
	Decor.dressCovers(kit, GOLD)
	-- Baies de serveurs : rangées de diodes
	for _, z in { 20, 34 } do
		for row = 0, 5 do
			kit:decorBox("RackLeds", 46.85, 1.2 + row * 1.4, z + 0.6, 46.95, 1.3 + row * 1.4, z + 7.4, "NeonWhite", {
				color = if row % 2 == 0 then CYAN else WHITE,
			})
		end
	end
	Decor.beams(kit, 10, 16, 52, 46, H, true, 5, "MetalDark")
end

local function security(kit: Kit)
	-- Mur d'écrans de surveillance (zone de spawn défense)
	for column = 0, 3 do
		for row = 0, 1 do
			Decor.screen(
				kit,
				Vector3.new(-33 + column * 6, 6.5 + row * 3, 61),
				Vector3.new(0, 0, -1),
				5,
				2.4,
				if (column + row) % 3 == 0 then Color3.fromRGB(255, 90, 70) else CYAN
			)
		end
	end
	for _, x in { -38, -24 } do
		Decor.wallLight(kit, Vector3.new(x, 12, 46.6), Vector3.new(0, 0, 1), WHITE, 0.8, 14)
		Decor.wallLight(kit, Vector3.new(x, 12, 45.4), Vector3.new(0, 0, -1), WHITE, 0.7, 12)
	end
	-- Appliques des couloirs
	for z = 20, 44, 8 do
		Decor.wallLight(kit, Vector3.new(-41, 10, z), Vector3.new(1, 0, 0), WHITE, 0.7, 12)
	end
	for x = 0, 24, 8 do
		Decor.wallLight(kit, Vector3.new(x, 10, 54), Vector3.new(0, 0, -1), WHITE, 0.7, 12)
	end
end

local function skyline(kit: Kit)
	-- Gratte-ciel voisins, vus par la verrière (au-dessus du 140e étage)
	local rng = Decor.rng(1403)
	Decor.skyline(kit, rng, -42, -62, 52, 62, 40, 260, 14, 420, 700, -500, {
		body = "TowerGlass",
		windows = { "WindowCool", "PaintWhite" },
		lit = 0.18,
	})
end

return function(kit: Kit)
	local rng = Decor.rng(2140)
	floors(kit)
	walls(kit)
	lobby(kit, rng)
	mainHall(kit)
	atrium(kit)
	vault(kit)
	security(kit)
	skyline(kit)
end
