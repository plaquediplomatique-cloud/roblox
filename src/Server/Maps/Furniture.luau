--!strict
--[[
	Furniture — mobilier réaliste du hub (recettes pures, comme Decor : elles n'enregistrent
	que des primitives MapKit).

	Échelle : un avatar mesure ~5,5 studs (1 stud ≈ 0,33 m) : assise 1,5, table 2,5,
	comptoir 3,4, étagère 6,5, porte 7 à 10. Le volume principal de chaque meuble est
	SOLIDE (Props : on ne traverse pas un canapé) ; les détails (pieds, coussins, écrans,
	livres, câbles) sont décoratifs et respectent les règles du décor (≤ 1 stud d'épaisseur
	ou au-dessus de 12 studs, vérifié par tests/specs/maps.luau).
	Orientation : `yaw` en degrés ; l'avant d'un meuble (côté assise, écran, tiroirs)
	regarde vers -Z local. Base au sol `y` (0 par défaut).
]]

local MapKit = require(script.Parent.MapKit)
local Decor = require(script.Parent.Decor)

type Kit = MapKit.Kit
type Prim = MapKit.Prim
type DecorOptions = MapKit.DecorOptions
type Rng = Decor.Rng

local Furniture = {}

local rad = math.rad
local WARM = Color3.fromRGB(255, 214, 170)

local function frame(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw or 0), 0)
end
Furniture.frame = frame

--[[ Lacet (degrés) qui oriente l'avant d'un meuble placé en (x, z) vers (tx, tz). ]]
function Furniture.facing(x: number, z: number, tx: number, tz: number): number
	return math.deg(math.atan2(-(tx - x), -(tz - z)))
end

local function detail(
	kit: Kit,
	name: string,
	base: CFrame,
	offset: Vector3,
	size: Vector3,
	style: string,
	options: DecorOptions?
): Prim
	return kit:decor(name, base * CFrame.new(offset), size, style, options)
end

local function solid(
	kit: Kit,
	name: string,
	base: CFrame,
	offset: Vector3,
	size: Vector3,
	style: string,
	options: DecorOptions?
): Prim
	return Decor.solid(kit, name, base * CFrame.new(offset), size, style, options)
end

-- Cylindre vertical (l'axe des cylindres Roblox est X local).
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function post(
	kit: Kit,
	name: string,
	base: CFrame,
	offset: Vector3,
	height: number,
	diameter: number,
	style: string,
	options: DecorOptions?
): Prim
	local opts: DecorOptions = if options then table.clone(options) else {}
	opts.shape = "Cylinder"
	return kit:decor(name, base * CFrame.new(offset) * UPRIGHT, Vector3.new(height, diameter, diameter), style, opts)
end

local function disk(
	kit: Kit,
	name: string,
	base: CFrame,
	offset: Vector3,
	thickness: number,
	diameter: number,
	style: string,
	options: DecorOptions?
): Prim
	return post(kit, name, base, offset, thickness, diameter, style, options)
end

---------------------------------------------------------------------------------------------
-- Assises
---------------------------------------------------------------------------------------------

--[[ Canapé moderne : socle, coussins d'assise et de dossier, accoudoirs, pieds laiton. ]]
function Furniture.sofa(kit: Kit, x: number, z: number, yaw: number, width: number, color: Color3, y: number?)
	local base = frame(x, y or 0, z, yaw)
	local dark = Decor.shade(color, 0.82)
	local light = Decor.shade(color, 1.1)
	solid(kit, "Sofa", base, Vector3.new(0, 0.75, 0), Vector3.new(width, 1, 2.9), "FabricDark", { color = dark })
	local seats = math.max(math.floor(width / 2.7), 1)
	local inner = width - 1.2
	for index = 1, seats do
		local cx = -inner / 2 + (index - 0.5) * inner / seats
		detail(
			kit,
			"SeatCushion",
			base,
			Vector3.new(cx, 1.45, -0.25),
			Vector3.new(inner / seats - 0.08, 0.42, 2.2),
			"FabricDark",
			{ color = light }
		)
		kit:decor(
			"BackCushion",
			base * CFrame.new(cx, 2.2, 0.62) * CFrame.Angles(rad(-10), 0, 0),
			Vector3.new(inner / seats - 0.12, 1.25, 0.5),
			"FabricDark",
			{ color = color }
		)
	end
	detail(kit, "SofaBack", base, Vector3.new(0, 2.05, 1.12), Vector3.new(width, 1.6, 0.66), "FabricDark", {
		color = dark,
	})
	for _, side in { -1, 1 } do
		detail(
			kit,
			"SofaArm",
			base,
			Vector3.new(side * (width / 2 - 0.3), 1.62, 0),
			Vector3.new(0.6, 0.75, 2.9),
			"FabricDark",
			{ color = dark }
		)
		for _, depth in { -1.2, 1.2 } do
			detail(
				kit,
				"SofaLeg",
				base,
				Vector3.new(side * (width / 2 - 0.35), 0.12, depth),
				Vector3.new(0.22, 0.24, 0.22),
				"Brass"
			)
		end
	end
end

--[[ Fauteuil club (cuir ou tissu). ]]
function Furniture.armchair(kit: Kit, x: number, z: number, yaw: number, style: string, color: Color3?, y: number?)
	local base = frame(x, y or 0, z, yaw)
	local options: DecorOptions? = if color then { color = color } else nil
	solid(kit, "Armchair", base, Vector3.new(0, 0.72, 0), Vector3.new(3.1, 0.95, 2.9), style, options)
	detail(kit, "SeatCushion", base, Vector3.new(0, 1.4, -0.2), Vector3.new(2.1, 0.4, 2.2), style, options)
	detail(kit, "ChairBack", base, Vector3.new(0, 2.1, 1.12), Vector3.new(3.1, 1.75, 0.66), style, options)
	for _, side in { -1, 1 } do
		detail(kit, "ChairArm", base, Vector3.new(side * 1.25, 1.6, 0), Vector3.new(0.6, 0.8, 2.9), style, options)
		for _, depth in { -1.2, 1.2 } do
			detail(kit, "ChairLeg", base, Vector3.new(side * 1.3, 0.12, depth), Vector3.new(0.2, 0.24, 0.2), "Wood")
		end
	end
end

--[[ Chaise (salle, café) : assise solide, dossier et pieds fins. ]]
function Furniture.chair(kit: Kit, x: number, z: number, yaw: number, seatStyle: string, color: Color3?, y: number?)
	local base = frame(x, y or 0, z, yaw)
	local options: DecorOptions? = if color then { color = color } else nil
	solid(kit, "ChairSeat", base, Vector3.new(0, 1.45, 0), Vector3.new(1.6, 0.18, 1.55), seatStyle, options)
	kit:decor(
		"ChairBack",
		base * CFrame.new(0, 2.45, 0.72) * CFrame.Angles(rad(-6), 0, 0),
		Vector3.new(1.55, 1.5, 0.14),
		seatStyle,
		options
	)
	for _, sx in { -0.68, 0.68 } do
		for _, sz in { -0.65, 0.65 } do
			detail(kit, "ChairLeg", base, Vector3.new(sx, 0.68, sz), Vector3.new(0.12, 1.36, 0.12), "SteelDark")
		end
	end
end

--[[ Chaise de bureau : assise, dossier, vérin, piétement en croix sur roulettes. ]]
function Furniture.officeChair(kit: Kit, x: number, z: number, yaw: number, color: Color3, y: number?)
	local base = frame(x, y or 0, z, yaw)
	solid(kit, "OfficeSeat", base, Vector3.new(0, 1.55, 0), Vector3.new(1.75, 0.3, 1.7), "FabricDark", {
		color = color,
	})
	kit:decor(
		"OfficeBack",
		base * CFrame.new(0, 2.75, 0.8) * CFrame.Angles(rad(-8), 0, 0),
		Vector3.new(1.6, 1.9, 0.26),
		"FabricDark",
		{ color = color }
	)
	post(kit, "GasLift", base, Vector3.new(0, 0.85, 0), 1.2, 0.22, "SteelDark")
	for _, angle in { 0, 72, 144, 216, 288 } do
		kit:decor(
			"ChairSpoke",
			base * CFrame.Angles(0, rad(angle), 0) * CFrame.new(0, 0.28, -0.55),
			Vector3.new(0.16, 0.12, 1.1),
			"SteelDark"
		)
	end
end

--[[ Tabouret de bar : assise ronde, pied central (solide fin), repose-pieds, socle. ]]
function Furniture.barStool(kit: Kit, x: number, z: number, y: number?)
	local base = frame(x, y or 0, z, 0)
	Decor.solid(kit, "StoolPost", base * CFrame.new(0, 1.15, 0) * UPRIGHT, Vector3.new(2.3, 0.3, 0.3), "SteelDark", {
		shape = "Cylinder",
	})
	disk(kit, "StoolSeat", base, Vector3.new(0, 2.42, 0), 0.25, 1.35, "Leather")
	disk(kit, "StoolFoot", base, Vector3.new(0, 0.95, 0), 0.08, 1.05, "Brass")
	disk(kit, "StoolBase", base, Vector3.new(0, 0.04, 0), 0.08, 1.3, "SteelDark")
end

--[[ Banc : assise en lattes de bois sur piétement acier, dossier optionnel. ]]
function Furniture.bench(kit: Kit, x: number, z: number, yaw: number, length: number, back: boolean, seat: string?)
	local base = frame(x, 0, z, yaw)
	local style = seat or "WoodLight"
	solid(kit, "BenchSeat", base, Vector3.new(0, 1.42, 0), Vector3.new(length, 0.16, 1.7), style)
	for index = -1, 1 do
		detail(kit, "BenchSlat", base, Vector3.new(0, 1.52, index * 0.55), Vector3.new(length, 0.06, 0.4), style)
	end
	for _, side in { -1, 1 } do
		detail(
			kit,
			"BenchLeg",
			base,
			Vector3.new(side * (length / 2 - 0.5), 0.68, 0),
			Vector3.new(0.2, 1.36, 1.5),
			"SteelDark"
		)
	end
	if back then
		kit:decor(
			"BenchBack",
			base * CFrame.new(0, 2.5, 0.8) * CFrame.Angles(rad(-10), 0, 0),
			Vector3.new(length, 1.2, 0.14),
			style
		)
	end
end

--[[ Rangée de sièges de salle (briefing) sur poutre commune. ]]
function Furniture.seatRow(kit: Kit, x: number, z: number, yaw: number, count: number, color: Color3)
	local base = frame(x, 0, z, yaw)
	local pitch = 2.1
	local width = count * pitch
	detail(kit, "RowBeam", base, Vector3.new(0, 0.55, 0.2), Vector3.new(width, 0.25, 0.35), "SteelDark")
	for index = 1, count do
		local cx = -width / 2 + (index - 0.5) * pitch
		solid(kit, "Seat", base, Vector3.new(cx, 1.45, -0.1), Vector3.new(1.8, 0.35, 1.6), "FabricDark", {
			color = color,
		})
		kit:decor(
			"SeatBack",
			base * CFrame.new(cx, 2.55, 0.75) * CFrame.Angles(rad(-10), 0, 0),
			Vector3.new(1.75, 1.9, 0.3),
			"FabricDark",
			{ color = Decor.shade(color, 0.85) }
		)
		if index <= count then
			detail(
				kit,
				"SeatArm",
				base,
				Vector3.new(cx - pitch / 2, 1.9, -0.1),
				Vector3.new(0.18, 0.18, 1.5),
				"SteelDark"
			)
			detail(
				kit,
				"SeatLeg",
				base,
				Vector3.new(cx - pitch / 2, 0.9, 0.2),
				Vector3.new(0.16, 1.8, 0.16),
				"SteelDark"
			)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Tables, bureaux, comptoirs
---------------------------------------------------------------------------------------------

--[[ Table basse : plateau solide, cadre et pieds métal. ]]
function Furniture.coffeeTable(kit: Kit, x: number, z: number, yaw: number, width: number, depth: number, top: string)
	local base = frame(x, 0, z, yaw)
	solid(kit, "CoffeeTop", base, Vector3.new(0, 1.3, 0), Vector3.new(width, 0.2, depth), top)
	detail(kit, "CoffeeShelf", base, Vector3.new(0, 0.45, 0), Vector3.new(width - 0.6, 0.08, depth - 0.6), "SteelDark")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			detail(
				kit,
				"CoffeeLeg",
				base,
				Vector3.new(sx * (width / 2 - 0.3), 0.6, sz * (depth / 2 - 0.3)),
				Vector3.new(0.14, 1.2, 0.14),
				"SteelDark"
			)
		end
	end
end

--[[ Table de café ronde (plateau, fût, socle). ]]
function Furniture.cafeTable(kit: Kit, x: number, z: number, diameter: number, top: string, height: number?)
	local h = height or 2.5
	local base = frame(x, 0, z, 0)
	Decor.solid(
		kit,
		"CafeTop",
		base * CFrame.new(0, h - 0.08, 0) * UPRIGHT,
		Vector3.new(0.16, diameter, diameter),
		top,
		{
			shape = "Cylinder",
		}
	)
	post(kit, "CafeStem", base, Vector3.new(0, (h - 0.16) / 2, 0), h - 0.16, 0.3, "SteelDark")
	disk(kit, "CafeFoot", base, Vector3.new(0, 0.05, 0), 0.1, diameter * 0.55, "SteelDark")
end

--[[ Grande table (réunion, salle à manger) : plateau bois, deux piétements en luge. ]]
function Furniture.longTable(kit: Kit, x: number, z: number, yaw: number, width: number, depth: number, top: string)
	local base = frame(x, 0, z, yaw)
	solid(kit, "TableTop", base, Vector3.new(0, 2.42, 0), Vector3.new(width, 0.2, depth), top)
	for _, side in { -1, 1 } do
		local sx = side * (width / 2 - 1)
		detail(kit, "TableLeg", base, Vector3.new(sx, 1.18, 0), Vector3.new(0.25, 2.3, depth - 0.8), "SteelDark")
	end
end

--[[ Bureau : plateau, deux joues, voile de fond, écran(s), clavier, souris. ]]
function Furniture.desk(kit: Kit, x: number, z: number, yaw: number, width: number, screens: number, glow: Color3)
	local base = frame(x, 0, z, yaw)
	solid(kit, "DeskTop", base, Vector3.new(0, 2.4, 0), Vector3.new(width, 0.16, 2.6), "WoodLight")
	for _, side in { -1, 1 } do
		detail(
			kit,
			"DeskSide",
			base,
			Vector3.new(side * (width / 2 - 0.1), 1.16, 0),
			Vector3.new(0.18, 2.32, 2.4),
			"PaintWhite"
		)
	end
	detail(kit, "DeskModesty", base, Vector3.new(0, 1.5, 1.1), Vector3.new(width - 0.4, 1.4, 0.1), "PaintWhite")
	local spacing = 2.5
	for index = 1, screens do
		local sx = (index - (screens + 1) / 2) * spacing
		detail(kit, "MonitorFoot", base, Vector3.new(sx, 2.5, 0.55), Vector3.new(0.8, 0.05, 0.5), "SteelDark")
		detail(kit, "MonitorArm", base, Vector3.new(sx, 2.9, 0.62), Vector3.new(0.12, 0.8, 0.12), "SteelDark")
		local screen = base * CFrame.new(sx, 3.55, 0.55) * CFrame.Angles(0, rad(if screens > 1 then -sx * 6 else 0), 0)
		kit:decor("Monitor", screen, Vector3.new(2.3, 1.35, 0.12), "SteelDark")
		kit:decor("MonitorImage", screen * CFrame.new(0, 0.02, -0.07), Vector3.new(2.14, 1.17, 0.02), "Screen", {
			color = glow,
		})
	end
	detail(kit, "Keyboard", base, Vector3.new(0, 2.5, -0.45), Vector3.new(1.6, 0.06, 0.5), "SteelDark")
	detail(kit, "Mouse", base, Vector3.new(1.25, 2.5, -0.45), Vector3.new(0.22, 0.08, 0.32), "SteelDark")
end

--[[ Comptoir (bar, accueil) le long de son axe X local : caisson, plateau, plinthe, repose-pieds. ]]
function Furniture.counter(kit: Kit, x: number, z: number, yaw: number, length: number, front: string, top: string)
	local base = frame(x, 0, z, yaw)
	solid(kit, "Counter", base, Vector3.new(0, 1.65, 0), Vector3.new(length, 3.3, 2.4), front)
	detail(kit, "CounterTop", base, Vector3.new(0, 3.38, -0.12), Vector3.new(length + 0.3, 0.16, 2.8), top)
	detail(kit, "CounterKick", base, Vector3.new(0, 0.2, -1.21), Vector3.new(length - 0.2, 0.4, 0.04), "SteelDark")
	kit:decor(
		"FootRail",
		base * CFrame.new(0, 0.85, -1.55),
		Vector3.new(length - 0.6, 0.16, 0.16),
		"Brass",
		{ shape = "Cylinder" }
	)
end

---------------------------------------------------------------------------------------------
-- Rangements
---------------------------------------------------------------------------------------------

local BOOK_COLORS = {
	Color3.fromRGB(120, 34, 30),
	Color3.fromRGB(28, 52, 86),
	Color3.fromRGB(46, 74, 52),
	Color3.fromRGB(196, 170, 120),
	Color3.fromRGB(40, 40, 44),
	Color3.fromRGB(150, 96, 52),
	Color3.fromRGB(220, 214, 200),
}

--[[ Bibliothèque : caisson, étagères, livres de hauteurs et couleurs variées, objets. ]]
function Furniture.bookshelf(kit: Kit, rng: Rng, x: number, z: number, yaw: number, width: number, height: number)
	local base = frame(x, 0, z, yaw)
	local depth = 1.4
	solid(kit, "ShelfVolume", base, Vector3.new(0, height / 2, 0.1), Vector3.new(width, height, depth), "Invisible")
	detail(kit, "ShelfBack", base, Vector3.new(0, height / 2, 0.75), Vector3.new(width, height, 0.1), "Wood")
	for _, side in { -1, 1 } do
		detail(
			kit,
			"ShelfSide",
			base,
			Vector3.new(side * (width / 2 - 0.08), height / 2, 0.05),
			Vector3.new(0.16, height, depth),
			"Wood"
		)
	end
	local shelves = math.floor(height / 1.7)
	for level = 0, shelves do
		local y = 0.1 + level * (height - 0.2) / shelves
		detail(kit, "Shelf", base, Vector3.new(0, y, 0.05), Vector3.new(width - 0.2, 0.12, depth), "Wood")
		if level == shelves then
			break
		end
		local cursor = -width / 2 + 0.3
		local limit = width / 2 - 0.3
		while cursor < limit - 0.3 do
			if rng() < 0.12 then
				-- Vide, ou objet décoratif (vase / boîte)
				local gap = rng(0.6, 1.2)
				if rng() < 0.5 and cursor + gap < limit then
					post(kit, "Vase", base, Vector3.new(cursor + gap / 2, y + 0.55, 0), 0.9, 0.5, "PaintWhite")
				end
				cursor += gap
				continue
			end
			local count = math.floor(rng(2, 6))
			local thickness = rng(0.18, 0.3)
			local run = math.min(count * thickness, limit - cursor)
			local h = rng(0.95, 1.4)
			local color = BOOK_COLORS[math.clamp(math.floor(rng() * #BOOK_COLORS) + 1, 1, #BOOK_COLORS)]
			detail(
				kit,
				"Books",
				base,
				Vector3.new(cursor + run / 2, y + 0.06 + h / 2, 0.1),
				Vector3.new(run, h, 1),
				"FabricDark",
				{
					color = color,
				}
			)
			cursor += run + rng(0.02, 0.12)
		end
	end
end

--[[ Rangée de casiers métalliques (portes, aérations, poignées). ]]
function Furniture.lockers(kit: Kit, x: number, z: number, yaw: number, count: number, color: Color3)
	local base = frame(x, 0, z, yaw)
	local pitch = 1.9
	local width = count * pitch
	solid(kit, "Lockers", base, Vector3.new(0, 3.4, 0), Vector3.new(width, 6.8, 1.7), "Steel", { color = color })
	for index = 1, count do
		local cx = -width / 2 + (index - 0.5) * pitch
		detail(
			kit,
			"LockerSeam",
			base,
			Vector3.new(cx + pitch / 2, 3.4, -0.86),
			Vector3.new(0.06, 6.6, 0.04),
			"SteelDark"
		)
		for _, vy in { 5.9, 5.6, 5.3 } do
			detail(kit, "LockerVent", base, Vector3.new(cx, vy, -0.86), Vector3.new(1.1, 0.08, 0.03), "SteelDark")
		end
		detail(kit, "LockerHandle", base, Vector3.new(cx + 0.6, 3.6, -0.9), Vector3.new(0.1, 0.6, 0.08), "Steel")
	end
	detail(kit, "LockerBase", base, Vector3.new(0, 0.2, -0.1), Vector3.new(width, 0.4, 1.5), "SteelDark")
end

--[[ Baie de serveurs : armoire, porte vitrée, diodes. ]]
function Furniture.serverRack(kit: Kit, rng: Rng, x: number, z: number, yaw: number)
	local base = frame(x, 0, z, yaw)
	solid(kit, "ServerRack", base, Vector3.new(0, 3.6, 0), Vector3.new(2.3, 7.2, 3), "Server")
	detail(kit, "RackDoor", base, Vector3.new(0, 3.6, -1.52), Vector3.new(2.1, 7, 0.04), "TowerGlass")
	for row = 0, 5 do
		local y = 1.2 + row * 0.95
		local color = if rng() < 0.7 then Color3.fromRGB(80, 220, 140) else Color3.fromRGB(80, 170, 255)
		detail(kit, "RackLeds", base, Vector3.new(rng(-0.6, 0.2), y, -1.5), Vector3.new(0.5, 0.05, 0.02), "NeonWhite", {
			color = color,
		})
	end
end

--[[ Vitrine : meuble bas en bois, cage de verre, éclairage intégré, objet exposé. ]]
function Furniture.displayCase(kit: Kit, x: number, z: number, yaw: number, width: number, depth: number, item: string?)
	local base = frame(x, 0, z, yaw)
	solid(kit, "CaseCabinet", base, Vector3.new(0, 1.5, 0), Vector3.new(width, 3, depth), "Wood")
	detail(kit, "CasePlinth", base, Vector3.new(0, 3.05, 0), Vector3.new(width - 0.2, 0.1, depth - 0.2), "PaintBlack")
	local glassH = 2.6
	local y = 3.1 + glassH / 2
	for _, side in { -1, 1 } do
		detail(
			kit,
			"CaseGlass",
			base,
			Vector3.new(side * (width / 2 - 0.05), y, 0),
			Vector3.new(0.06, glassH, depth - 0.1),
			"Glass"
		)
		detail(
			kit,
			"CaseGlass",
			base,
			Vector3.new(0, y, side * (depth / 2 - 0.05)),
			Vector3.new(width - 0.1, glassH, 0.06),
			"Glass"
		)
	end
	detail(kit, "CaseLid", base, Vector3.new(0, 3.1 + glassH + 0.05, 0), Vector3.new(width, 0.1, depth), "Wood")
	if item == "Trophy" then
		disk(kit, "TrophyBase", base, Vector3.new(0, 3.4, 0), 0.5, 0.9, "PaintBlack")
		post(kit, "TrophyStem", base, Vector3.new(0, 3.95, 0), 0.6, 0.25, "Gold")
		kit:decor("TrophyCup", base * CFrame.new(0, 4.6, 0), Vector3.new(0.95, 0.95, 0.95), "Gold", { shape = "Ball" })
	elseif item == "Medal" then
		kit:decor(
			"Medal",
			base * CFrame.new(0, 4, 0) * CFrame.Angles(0, math.pi / 2, 0) * UPRIGHT,
			Vector3.new(0.12, 0.9, 0.9),
			"Gold",
			{ shape = "Cylinder" }
		)
		detail(kit, "MedalStand", base, Vector3.new(0, 3.4, 0.2), Vector3.new(0.6, 0.5, 0.1), "PaintBlack")
	end
end

---------------------------------------------------------------------------------------------
-- Luminaires (lumières réelles, sans ombres : budget mobile)
---------------------------------------------------------------------------------------------

local function warmLight(brightness: number, range: number): MapKit.LightSpec
	return {
		kind = "Point",
		color = WARM,
		brightness = brightness,
		range = range,
		face = nil,
		angle = nil,
		shadows = false,
	}
end

--[[ Lampadaire : socle, tige, abat-jour (lumière chaude). ]]
function Furniture.floorLamp(kit: Kit, x: number, z: number, lit: boolean?)
	local base = frame(x, 0, z, 0)
	disk(kit, "LampBase", base, Vector3.new(0, 0.06, 0), 0.12, 1.2, "SteelDark")
	post(kit, "LampPole", base, Vector3.new(0, 2.6, 0), 5.1, 0.14, "Brass")
	post(kit, "LampShade", base, Vector3.new(0, 5.4, 0), 1, 1.6, "Plaster", {
		light = if lit == false then nil else warmLight(0.9, 16),
	})
end

--[[ Suspension : câble, abat-jour métal, ampoule. ]]
function Furniture.pendant(kit: Kit, x: number, z: number, ceilingY: number, drop: number, style: string, lit: boolean?)
	local base = frame(x, 0, z, 0)
	local bottom = ceilingY - drop
	post(kit, "PendantCable", base, Vector3.new(0, ceilingY - (drop - 0.9) / 2, 0), drop - 0.9, 0.06, "Cable")
	post(kit, "PendantShade", base, Vector3.new(0, bottom + 0.45, 0), 0.9, 1.5, style)
	kit:decor("PendantBulb", base * CFrame.new(0, bottom + 0.05, 0), Vector3.new(0.45, 0.45, 0.45), "NeonWhite", {
		shape = "Ball",
		color = WARM,
		light = if lit == false then nil else warmLight(1.1, 18),
	})
end

--[[ Dalle LED encastrée (lumière de plafond) : `light` = vraie SurfaceLight, sinon décor. ]]
function Furniture.ceilingPanel(kit: Kit, x: number, z: number, y: number, width: number, depth: number, light: boolean)
	local panel = kit:decorBox(
		"CeilingLed",
		x - width / 2,
		y - 0.12,
		z - depth / 2,
		x + width / 2,
		y,
		z + depth / 2,
		"NeonWhite",
		{ color = Color3.fromRGB(255, 246, 232) }
	)
	if light then
		panel.light = {
			kind = "Surface",
			color = Color3.fromRGB(255, 240, 222),
			brightness = 1.4,
			range = 24,
			face = "Bottom",
			angle = 120,
			shadows = false,
		}
	end
	kit:decorBox(
		"CeilingTrim",
		x - width / 2 - 0.15,
		y - 0.06,
		z - depth / 2 - 0.15,
		x + width / 2 + 0.15,
		y,
		z + depth / 2 + 0.15,
		"Steel"
	)
end

---------------------------------------------------------------------------------------------
-- Végétal
---------------------------------------------------------------------------------------------

--[[ Plante en pot (pot rond solide, feuillage). `size` ≈ diamètre du pot. ]]
function Furniture.plant(kit: Kit, rng: Rng, x: number, z: number, size: number, potStyle: string)
	local base = frame(x, 0, z, 0)
	local potHeight = size * 0.9
	Decor.solid(
		kit,
		"Pot",
		base * CFrame.new(0, potHeight / 2, 0) * UPRIGHT,
		Vector3.new(potHeight, size, size),
		potStyle,
		{
			shape = "Cylinder",
		}
	)
	disk(kit, "Soil", base, Vector3.new(0, potHeight + 0.01, 0), 0.04, size - 0.2, "Soil")
	local leaves = math.floor(rng(3, 6))
	for _ = 1, leaves do
		local r = rng(0.45, 0.75) * size
		Decor.solid(
			kit,
			"Leaves",
			base * CFrame.new(rng(-0.35, 0.35) * size, potHeight + r * rng(0.7, 1.5), rng(-0.35, 0.35) * size),
			Vector3.new(r * 2, r * 1.6, r * 2),
			if rng() < 0.55 then "Leaf" else "LeafDeep",
			{ shape = "Ball" }
		)
	end
end

--[[ Arbre d'intérieur (ficus) : bac, tronc, branches (cachées dans le houppier), feuillage. ]]
function Furniture.tree(kit: Kit, rng: Rng, x: number, z: number, height: number, planter: string)
	local base = frame(x, 0, z, rng(0, 360))
	solid(kit, "TreePlanter", base, Vector3.new(0, 0.9, 0), Vector3.new(4.2, 1.8, 4.2), planter)
	detail(kit, "TreeSoil", base, Vector3.new(0, 1.82, 0), Vector3.new(3.8, 0.05, 3.8), "Soil")
	post(kit, "Trunk", base, Vector3.new(0, 1.8 + height * 0.35, 0), height * 0.7, 0.4, "Wood")
	for index = 1, 3 do
		local angle = index * 120 + rng(-20, 20)
		kit:decor(
			"Branch",
			base * CFrame.new(0, 1.8 + height * 0.62, 0) * CFrame.Angles(0, rad(angle), rad(40)) * CFrame.new(0.7, 0, 0),
			Vector3.new(1.5, 0.18, 0.18),
			"Wood",
			{ shape = "Cylinder" }
		)
	end
	for _ = 1, 7 do
		local r = rng(1.2, 1.9)
		local angle = rng(0, math.pi * 2)
		local spread = rng(0.3, 1.6)
		Decor.solid(
			kit,
			"Canopy",
			base * CFrame.new(math.cos(angle) * spread, 1.8 + height * rng(0.7, 0.98), math.sin(angle) * spread),
			Vector3.new(r * 2, r * 1.5, r * 2),
			if rng() < 0.5 then "Leaf" else "LeafDeep",
			{ shape = "Ball" }
		)
	end
end

---------------------------------------------------------------------------------------------
-- Murs : écrans, cadres, tableaux blancs
---------------------------------------------------------------------------------------------

--[[ Repère d'un objet plaqué contre un mur : `normal` sort du mur (vers la pièce). ]]
local function wallFrame(position: Vector3, normal: Vector3): CFrame
	return CFrame.lookAt(position, position + normal)
end

--[[ Téléviseur / écran mural : cadre fin, dalle (allumée ou non). ]]
function Furniture.wallScreen(
	kit: Kit,
	position: Vector3,
	normal: Vector3,
	width: number,
	height: number,
	glow: Color3?
)
	local base = wallFrame(position, normal)
	kit:decor("TvFrame", base * CFrame.new(0, 0, -0.08), Vector3.new(width + 0.2, height + 0.2, 0.16), "PaintBlack")
	if glow then
		kit:decor(
			"TvImage",
			base * CFrame.new(0, 0, -0.17),
			Vector3.new(width, height, 0.02),
			"Screen",
			{ color = glow }
		)
	else
		kit:decor("TvGlass", base * CFrame.new(0, 0, -0.17), Vector3.new(width, height, 0.02), "ScreenDim")
	end
end

--[[ Tableau : cadre, toile, composition abstraite en aplats. ]]
function Furniture.artwork(
	kit: Kit,
	rng: Rng,
	position: Vector3,
	normal: Vector3,
	width: number,
	height: number,
	palette: { Color3 }
)
	local base = wallFrame(position, normal)
	kit:decor("ArtFrame", base * CFrame.new(0, 0, -0.06), Vector3.new(width + 0.3, height + 0.3, 0.12), "Wood")
	kit:decor("ArtCanvas", base * CFrame.new(0, 0, -0.13), Vector3.new(width, height, 0.02), "Plaster", {
		color = Color3.fromRGB(232, 228, 220),
	})
	for index = 1, 3 do
		local w = rng(0.25, 0.6) * width
		local h = rng(0.2, 0.6) * height
		local cx = rng(-0.5, 0.5) * (width - w)
		local cy = rng(-0.5, 0.5) * (height - h)
		kit:decor(
			"ArtShape",
			base * CFrame.new(cx, cy, -0.15 - index * 0.005),
			Vector3.new(w, h, 0.01),
			"Plaster",
			{ color = palette[(index - 1) % #palette + 1] }
		)
	end
end

function Furniture.whiteboard(kit: Kit, position: Vector3, normal: Vector3, width: number, height: number)
	local base = wallFrame(position, normal)
	kit:decor("BoardFrame", base * CFrame.new(0, 0, -0.05), Vector3.new(width + 0.2, height + 0.2, 0.1), "Steel")
	kit:decor("Board", base * CFrame.new(0, 0, -0.11), Vector3.new(width, height, 0.02), "PaintWhite", {
		color = Color3.fromRGB(240, 242, 244),
	})
	kit:decor("BoardTray", base * CFrame.new(0, -height / 2 - 0.15, -0.2), Vector3.new(width * 0.8, 0.1, 0.3), "Steel")
	for index, color in { Color3.fromRGB(40, 90, 200), Color3.fromRGB(200, 50, 50), Color3.fromRGB(30, 30, 30) } do
		kit:decor(
			"BoardSketch",
			base * CFrame.new(-width * 0.25 + index * width * 0.12, height * 0.15 - index * 0.35, -0.125),
			Vector3.new(width * 0.3, 0.06, 0.01),
			"PaintWhite",
			{ color = color }
		)
	end
end

--[[ Tapis : aplat + liseré. ]]
function Furniture.rug(
	kit: Kit,
	x: number,
	z: number,
	width: number,
	depth: number,
	color: Color3,
	border: Color3,
	y: number?
)
	local base = y or 0
	kit:decorBox(
		"Rug",
		x - width / 2,
		base + 0.1,
		z - depth / 2,
		x + width / 2,
		base + 0.16,
		z + depth / 2,
		"FabricDark",
		{
			color = color,
		}
	)
	local b = 0.45
	for _, spec in
		{
			{ x - width / 2, z - depth / 2, x + width / 2, z - depth / 2 + b },
			{ x - width / 2, z + depth / 2 - b, x + width / 2, z + depth / 2 },
			{ x - width / 2, z - depth / 2 + b, x - width / 2 + b, z + depth / 2 - b },
			{ x + width / 2 - b, z - depth / 2 + b, x + width / 2, z + depth / 2 - b },
		}
	do
		kit:decorBox("RugBorder", spec[1], base + 0.16, spec[2], spec[3], base + 0.18, spec[4], "FabricDark", {
			color = border,
		})
	end
end

---------------------------------------------------------------------------------------------
-- Loisirs
---------------------------------------------------------------------------------------------

local BALL_COLORS = {
	Color3.fromRGB(240, 240, 235),
	Color3.fromRGB(230, 190, 40),
	Color3.fromRGB(40, 70, 170),
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(90, 40, 120),
	Color3.fromRGB(230, 110, 30),
	Color3.fromRGB(30, 110, 60),
	Color3.fromRGB(20, 20, 20),
}

--[[ Billard : caisse bois, tapis vert, bandes, poches, billes, queue posée. ]]
function Furniture.poolTable(kit: Kit, rng: Rng, x: number, z: number, yaw: number)
	local base = frame(x, 0, z, yaw)
	local w, l = 4.6, 8.2
	solid(kit, "PoolBody", base, Vector3.new(0, 1.65, 0), Vector3.new(w, 1.1, l), "Wood")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			detail(
				kit,
				"PoolLeg",
				base,
				Vector3.new(sx * (w / 2 - 0.5), 0.55, sz * (l / 2 - 0.6)),
				Vector3.new(0.7, 1.1, 0.7),
				"Wood"
			)
		end
	end
	detail(kit, "PoolFelt", base, Vector3.new(0, 2.22, 0), Vector3.new(w - 0.6, 0.04, l - 0.6), "FabricDark", {
		color = Color3.fromRGB(32, 104, 74),
	})
	for _, side in { -1, 1 } do
		detail(kit, "PoolRail", base, Vector3.new(side * (w / 2 - 0.15), 2.32, 0), Vector3.new(0.3, 0.24, l), "Wood")
		detail(
			kit,
			"PoolRail",
			base,
			Vector3.new(0, 2.32, side * (l / 2 - 0.15)),
			Vector3.new(w - 0.6, 0.24, 0.3),
			"Wood"
		)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 0, 1 } do
			disk(
				kit,
				"Pocket",
				base,
				Vector3.new(sx * (w / 2 - 0.32), 2.25, sz * (l / 2 - 0.32)),
				0.06,
				0.42,
				"PaintBlack"
			)
		end
	end
	for index = 1, 8 do
		kit:decor(
			"PoolBall",
			base * CFrame.new(rng(-1.3, 1.3), 2.38, rng(-3, 3)),
			Vector3.new(0.28, 0.28, 0.28),
			"PaintWhite",
			{ shape = "Ball", color = BALL_COLORS[index] }
		)
	end
	kit:decor(
		"Cue",
		base * CFrame.new(0.6, 2.42, 0.6) * CFrame.Angles(0, rad(rng(-25, 25)), 0) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(4.8, 0.1, 0.1),
		"WoodLight",
		{ shape = "Cylinder" }
	)
end

--[[ Borne d'arcade : caisson, écran incliné, pupitre, fronton lumineux. ]]
function Furniture.arcade(kit: Kit, x: number, z: number, yaw: number, accent: Color3, screen: Color3)
	local base = frame(x, 0, z, yaw)
	solid(kit, "ArcadeBody", base, Vector3.new(0, 2.9, 0.2), Vector3.new(2.6, 5.8, 2.2), "PaintBlack")
	kit:decor(
		"ArcadeScreen",
		base * CFrame.new(0, 3.9, -0.95) * CFrame.Angles(rad(-12), 0, 0),
		Vector3.new(2.1, 1.6, 0.04),
		"Screen",
		{ color = screen }
	)
	kit:decor(
		"ArcadePanel",
		base * CFrame.new(0, 2.85, -1.2) * CFrame.Angles(rad(-20), 0, 0),
		Vector3.new(2.5, 0.12, 1),
		"PaintBlack",
		{ color = Decor.shade(accent, 0.5) }
	)
	for index, color in { Color3.fromRGB(230, 60, 60), Color3.fromRGB(60, 160, 230), Color3.fromRGB(240, 200, 40) } do
		kit:decor(
			"ArcadeButton",
			base * CFrame.new(-0.2 + index * 0.35, 2.95, -1.25),
			Vector3.new(0.18, 0.08, 0.18),
			"PaintWhite",
			{
				shape = "Ball",
				color = color,
			}
		)
	end
	detail(kit, "ArcadeMarquee", base, Vector3.new(0, 5.45, -0.92), Vector3.new(2.4, 0.6, 0.06), "NeonWhite", {
		color = accent,
	})
	for _, side in { -1, 1 } do
		detail(
			kit,
			"ArcadeSideArt",
			base,
			Vector3.new(side * 1.31, 2.9, 0.2),
			Vector3.new(0.02, 5.4, 2),
			"PaintBlack",
			{
				color = Decor.shade(accent, 0.35),
			}
		)
	end
end

--[[ Distributeur : caisson, vitrine éclairée, rangées de produits. ]]
function Furniture.vending(kit: Kit, rng: Rng, x: number, z: number, yaw: number, color: Color3)
	local base = frame(x, 0, z, yaw)
	solid(kit, "Vending", base, Vector3.new(0, 3.1, 0), Vector3.new(3, 6.2, 2.6), "PaintWhite", { color = color })
	detail(kit, "VendingWindow", base, Vector3.new(-0.3, 3.6, -1.31), Vector3.new(2, 4.2, 0.02), "ScreenDim")
	for row = 0, 4 do
		local y = 2 + row * 0.8
		detail(kit, "VendingRow", base, Vector3.new(-0.3, y, -1.29), Vector3.new(1.8, 0.45, 0.02), "PaintWhite", {
			color = BALL_COLORS[math.clamp(math.floor(rng() * #BALL_COLORS) + 1, 1, #BALL_COLORS)],
		})
	end
	detail(kit, "VendingKeypad", base, Vector3.new(1.05, 3.6, -1.31), Vector3.new(0.5, 1.2, 0.03), "SteelDark")
	detail(kit, "VendingSlot", base, Vector3.new(-0.3, 0.9, -1.31), Vector3.new(1.6, 0.5, 0.03), "SteelDark")
end

--[[ Machine à café et comptoir arrière (bouteilles, verres). ]]
function Furniture.backBar(kit: Kit, rng: Rng, x: number, z: number, yaw: number, length: number)
	local base = frame(x, 0, z, yaw)
	solid(kit, "BackCounter", base, Vector3.new(0, 1.5, 0), Vector3.new(length, 3, 1.8), "Wood")
	detail(kit, "BackTop", base, Vector3.new(0, 3.06, 0), Vector3.new(length + 0.2, 0.12, 2), "MarbleWhite")
	detail(kit, "BackPanel", base, Vector3.new(0, 6.5, 0.85), Vector3.new(length, 6.8, 0.1), "WoodLight")
	for _, level in { 5, 7, 9 } do
		detail(kit, "BottleShelf", base, Vector3.new(0, level, 0.45), Vector3.new(length - 0.4, 0.1, 0.8), "Glass")
		local cursor = -length / 2 + 0.5
		while cursor < length / 2 - 0.5 do
			local h = rng(0.8, 1.3)
			local tint = if rng() < 0.4
				then Color3.fromRGB(120, 70, 30)
				elseif rng() < 0.5 then Color3.fromRGB(40, 90, 50)
				else Color3.fromRGB(200, 210, 210)
			post(kit, "Bottle", base, Vector3.new(cursor, level + 0.05 + h / 2, 0.45), h, 0.32, "Glass", {
				color = tint,
				transparency = 0.25,
			})
			cursor += rng(0.4, 0.9)
		end
	end
	-- Machine à café (sur le comptoir)
	detail(kit, "CoffeeMachine", base, Vector3.new(length / 2 - 1.6, 3.9, 0.2), Vector3.new(1.8, 1.6, 1), "Steel")
	detail(kit, "CoffeeFace", base, Vector3.new(length / 2 - 1.6, 4.2, -0.31), Vector3.new(1.2, 0.5, 0.02), "SteelDark")
end

---------------------------------------------------------------------------------------------
-- Stand de tir
---------------------------------------------------------------------------------------------

--[[
	Poste de tir : tablette, cloisons acoustiques (`sides` : -1 et/ou 1, une cloison
	partagée n'est posée qu'une fois), numéro. `x` = ligne de tir, couloir vers -X.
]]
function Furniture.shootingBooth(kit: Kit, x: number, z: number, number: number, width: number, sides: { number })
	-- Cloison légère : bas acoustique clair (protection), vitre dépolie au-dessus (on voit
	-- le poste voisin, la pièce reste ouverte), chant d'acier. Plus de mur sombre de 7 m.
	for _, side in sides do
		local wz = z + side * (width / 2)
		Decor.solid(
			kit,
			"BoothWall",
			CFrame.new(x - 0.5, 1.8, wz),
			Vector3.new(4.5, 3.6, 0.35),
			"FabricDark",
			{ color = Color3.fromRGB(112, 118, 126) }
		)
		Decor.solid(kit, "BoothGlass", CFrame.new(x - 0.5, 4.9, wz), Vector3.new(4.3, 2.6, 0.12), "HqGlass")
		kit:decorBox("BoothRail", x - 2.75, 6.2, wz - 0.12, x + 1.75, 6.32, wz + 0.12, "Steel")
		kit:decorBox("BoothEdge", x - 2.8, 0, wz - 0.2, x - 2.7, 6.32, wz + 0.2, "Steel")
	end
	local plate = kit:sign(tostring(number), x + 1.6, 8, z, 1.6, 1.2, "+X", Color3.fromRGB(245, 245, 240))
	local spec = plate.sign
	if spec then
		spec.plain = true
	end
	kit:decorBox("BoothTop", x - 1.1, 3.2, z - width / 2 + 0.6, x + 1.1, 3.34, z + width / 2 - 0.6, "WoodLight")
end

--[[ Cible de tir suspendue (cadre, carton, rail). ]]
function Furniture.rangeTarget(kit: Kit, x: number, z: number, ceilingY: number)
	kit:decorBox("TargetRail", x - 0.3, ceilingY - 0.3, z - 0.15, x + 0.3, ceilingY, z + 0.15, "SteelDark")
	kit:decorBox("TargetHanger", x - 0.05, 7.5, z - 0.05, x + 0.05, ceilingY - 0.3, z + 0.05, "Cable")
	kit:decorBox("TargetCard", x - 0.04, 3.5, z - 1.1, x + 0.04, 7.5, z + 1.1, "PaintWhite", {
		color = Color3.fromRGB(226, 220, 204),
	})
	kit:decorBox("TargetRing", x + 0.05, 5.2, z - 0.45, x + 0.07, 6.1, z + 0.45, "PaintBlack")
end

return Furniture
