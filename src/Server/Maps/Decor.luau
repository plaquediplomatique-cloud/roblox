--!strict
--[[
	Decor — recettes d'habillage pour MapKit (pures : elles n'enregistrent que des
	primitives, comme les plans de cartes).

	Règles (vérifiées par tests/specs/maps.luau) :
	  * tout est décoratif : ni collision ni requête (`kit:decor`) — tirs, raycasts et
	    déplacements traversent le décor exactement comme avant l'habillage ;
	  * dans l'espace de jeu, un élément est FIN (≤ 1 stud : plinthes, joints, nervures,
	    câbles, tuyaux, marquages) ou en HAUTEUR (base ≥ 12 studs) : aucune fausse
	    couverture, aucune cachette visuelle ;
	  * les volumes massifs (immeubles, grues, roches, coque de station) sont HORS des
	    limites de la carte, dans le groupe "Backdrop".
	Les recettes aléatoires prennent un générateur à graine : une carte se reconstruit à
	l'identique, partout (serveur, tests, outils de rendu).
]]

local MapKit = require(script.Parent.MapKit)

type Kit = MapKit.Kit
type Prim = MapKit.Prim
type DecorOptions = MapKit.DecorOptions

export type Rng = (min: number?, max: number?) -> number

local Decor = {}

local BACKDROP: DecorOptions = { group = "Backdrop" }

-- Générateur de Lehmer (exact en double) : déterministe, indépendant du moteur.
function Decor.rng(seed: number): Rng
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(min: number?, max: number?): number
		state = (state * 16807) % 2147483647
		local value = (state - 1) / 2147483646
		if min and max then
			return min + (max - min) * value
		end
		return value
	end
end

function Decor.shade(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

-- CFrame d'un cylindre (axe X local) de `a` vers `b`.
local function axisCFrame(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	local direction = (b - a).Unit
	if math.abs(direction.Y) > 0.999 then
		return CFrame.new(mid) * CFrame.Angles(0, 0, math.pi / 2)
	end
	return CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
end

---------------------------------------------------------------------------------------------
-- Éléments linéaires
---------------------------------------------------------------------------------------------

--[[ Tuyau (cylindre) de `a` à `b`, colliers réguliers. ]]
function Decor.pipe(kit: Kit, a: Vector3, b: Vector3, radius: number, style: string, bracketEvery: number?)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	kit:decor("Pipe", axisCFrame(a, b), Vector3.new(length, radius * 2, radius * 2), style, { shape = "Cylinder" })
	local every = bracketEvery or 0
	if every > 0 then
		local count = math.floor(length / every)
		for index = 1, count do
			local point = a + (b - a) * (index / (count + 1))
			kit:decor(
				"PipeBracket",
				axisCFrame(a, b).Rotation + point,
				Vector3.new(0.18, radius * 2 + 0.16, radius * 2 + 0.16),
				"SteelDark",
				{ shape = "Cylinder" }
			)
		end
	end
end

--[[ Câble suspendu (parabole) de `a` à `b`. ]]
function Decor.cable(kit: Kit, a: Vector3, b: Vector3, sag: number, segments: number?, radius: number?)
	local count = segments or 6
	local r = radius or 0.06
	local previous = a
	for index = 1, count do
		local t = index / count
		local point = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		local length = (point - previous).Magnitude
		kit:decor("Cable", axisCFrame(previous, point), Vector3.new(length + r, r * 2, r * 2), "Cable", {
			shape = "Cylinder",
		})
		previous = point
	end
end

--[[ Ligne peinte / bande au sol (épaisseur 0.04). ]]
function Decor.floorLine(
	kit: Kit,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y: number,
	width: number,
	style: string,
	options: DecorOptions?
)
	if math.abs(x2 - x1) >= math.abs(z2 - z1) then
		local cz = (z1 + z2) / 2
		kit:decorBox("FloorLine", x1, y, cz - width / 2, x2, y + 0.04, cz + width / 2, style, options)
	else
		local cx = (x1 + x2) / 2
		kit:decorBox("FloorLine", cx - width / 2, y, z1, cx + width / 2, y + 0.04, z2, style, options)
	end
end

--[[ Bande de danger jaune/noire le long d'un segment axe-aligné, au sol. ]]
function Decor.hazardBand(kit: Kit, x1: number, z1: number, x2: number, z2: number, y: number, width: number)
	local alongX = math.abs(x2 - x1) >= math.abs(z2 - z1)
	local from, to =
		if alongX then math.min(x1, x2) else math.min(z1, z2), if alongX then math.max(x1, x2) else math.max(z1, z2)
	local fixed = if alongX then (z1 + z2) / 2 else (x1 + x2) / 2
	local step = 1.2
	local index = 0
	local position = from
	while position < to - 0.01 do
		local stop = math.min(position + step, to)
		local style = if index % 2 == 0 then "PaintYellow" else "PaintBlack"
		if alongX then
			kit:decorBox("Hazard", position, y, fixed - width / 2, stop, y + 0.045, fixed + width / 2, style)
		else
			kit:decorBox("Hazard", fixed - width / 2, y, position, fixed + width / 2, y + 0.045, stop, style)
		end
		position = stop
		index += 1
	end
end

---------------------------------------------------------------------------------------------
-- Murs, sols, plafonds
---------------------------------------------------------------------------------------------

export type WallDetail = {
	seam: string?, -- style des joints verticaux (nil = aucun)
	spacing: number?,
	base: string?, -- plinthe
	baseHeight: number?,
	cap: string?, -- couronnement en tête de mur
	band: string?, -- bandeau horizontal
	bandY: number?,
	sides: { number }?, -- faces habillées : -1 et/ou 1 (normale -axe / +axe)
}

--[[
	Habille un mur AXE-ALIGNÉ (de (x1,z1) à (x2,z2), épaisseur t, hauteur h, base y0) :
	joints verticaux, plinthe, bandeau, couronnement. Tout dépasse de ≤ 0.25 stud.
]]
function Decor.wall(
	kit: Kit,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number,
	thickness: number,
	detail: WallDetail,
	baseY: number?
)
	local y0 = baseY or 0
	local alongX = math.abs(x2 - x1) >= math.abs(z2 - z1)
	local from = if alongX then math.min(x1, x2) else math.min(z1, z2)
	local to = if alongX then math.max(x1, x2) else math.max(z1, z2)
	local center = if alongX then (z1 + z2) / 2 else (x1 + x2) / 2
	local half = thickness / 2
	local function slab(
		name: string,
		a: number,
		b: number,
		ya: number,
		yb: number,
		depth: number,
		side: number,
		style: string
	)
		local inner = center + side * half
		local outer = inner + side * depth
		if alongX then
			kit:decorBox(name, a, ya, inner, b, yb, outer, style)
		else
			kit:decorBox(name, inner, ya, a, outer, yb, b, style)
		end
	end
	local sides: { number } = detail.sides or { -1, 1 }
	for _, side in sides do
		local baseHeight = detail.baseHeight or 0.6
		if detail.base then
			slab("Baseboard", from, to, y0, y0 + baseHeight, 0.18, side, detail.base)
		end
		if detail.band then
			local by = y0 + (detail.bandY or 3)
			slab("WallBand", from, to, by, by + 0.3, 0.1, side, detail.band)
		end
		if detail.seam then
			local spacing = detail.spacing or 4
			local count = math.floor((to - from) / spacing)
			for index = 1, count - 1 do
				local position = from + (to - from) * index / count
				slab(
					"Seam",
					position - 0.06,
					position + 0.06,
					y0 + baseHeight,
					y0 + height - 0.3,
					0.05,
					side,
					detail.seam
				)
			end
		end
	end
	if detail.cap then
		if alongX then
			kit:decorBox(
				"WallCap",
				from,
				y0 + height,
				center - half - 0.15,
				to,
				y0 + height + 0.3,
				center + half + 0.15,
				detail.cap
			)
		else
			kit:decorBox(
				"WallCap",
				center - half - 0.15,
				y0 + height,
				from,
				center + half + 0.15,
				y0 + height + 0.3,
				to,
				detail.cap
			)
		end
	end
end

--[[ Taches de variation sur un grand sol (réparations, salissures, zones peintes). ]]
function Decor.patches(
	kit: Kit,
	rng: Rng,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y: number,
	count: number,
	styles: { string },
	minSize: number,
	maxSize: number
)
	for _ = 1, count do
		local w, d = rng(minSize, maxSize), rng(minSize, maxSize)
		local x, z = rng(x1 + w / 2, x2 - w / 2), rng(z1 + d / 2, z2 - d / 2)
		local style = styles[math.clamp(math.floor(rng() * #styles) + 1, 1, #styles)]
		kit:decor(
			"FloorPatch",
			CFrame.new(x, y + 0.012, z) * CFrame.Angles(0, rng(-0.4, 0.4), 0),
			Vector3.new(w, 0.024, d),
			style
		)
	end
end

--[[ Flaques (pluie) : disques sombres réfléchissants, groupés par deux pour une forme organique. ]]
function Decor.puddles(kit: Kit, rng: Rng, x1: number, z1: number, x2: number, z2: number, y: number, count: number)
	for _ = 1, count do
		local x, z = rng(x1 + 2, x2 - 2), rng(z1 + 2, z2 - 2)
		for _ = 1, 2 do
			local radius = rng(0.9, 2.4)
			kit:decor(
				"Puddle",
				CFrame.new(x + rng(-1.2, 1.2), y + 0.02, z + rng(-1.2, 1.2)) * CFrame.Angles(0, 0, math.pi / 2),
				Vector3.new(0.03, radius * 2, radius * 2),
				"Wet",
				{ shape = "Cylinder" }
			)
		end
	end
end

--[[ Poutres de plafond parallèles (sous un plafond à `y`). ]]
function Decor.beams(
	kit: Kit,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y: number,
	alongX: boolean,
	spacing: number,
	style: string
)
	local from, to =
		if alongX then math.min(z1, z2) else math.min(x1, x2), if alongX then math.max(z1, z2) else math.max(x1, x2)
	local count = math.max(math.floor((to - from) / spacing), 1)
	for index = 1, count - 1 do
		local position = from + (to - from) * index / count
		if alongX then
			kit:decorBox("CeilingBeam", x1, y - 0.7, position - 0.35, x2, y, position + 0.35, style)
		else
			kit:decorBox("CeilingBeam", position - 0.35, y - 0.7, z1, position + 0.35, y, z2, style)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Objets fixés aux murs
---------------------------------------------------------------------------------------------

local function faceFrame(position: Vector3, normal: Vector3): CFrame
	-- -Z local = normale sortante du mur (la façade de l'objet regarde la salle).
	return CFrame.lookAt(position, position + normal)
end

--[[ Applique murale : boîtier, diffuseur néon, lumière ponctuelle sans ombre. ]]
function Decor.wallLight(
	kit: Kit,
	position: Vector3,
	normal: Vector3,
	color: Color3,
	brightness: number?,
	range: number?
)
	local frame = faceFrame(position, normal)
	kit:decor("LightHousing", frame * CFrame.new(0, 0, -0.18), Vector3.new(1.4, 0.45, 0.36), "SteelDark")
	kit:decor("LightLens", frame * CFrame.new(0, -0.08, -0.38), Vector3.new(1.2, 0.18, 0.08), "NeonWhite", {
		color = color,
		light = {
			kind = "Point",
			color = color,
			brightness = brightness or 1.2,
			range = range or 16,
			face = nil,
			angle = nil,
			shadows = false,
		},
	})
end

--[[ Grille d'aération : cadre + lamelles, épaisseur 0.25. ]]
function Decor.vent(kit: Kit, position: Vector3, normal: Vector3, width: number, height: number)
	local frame = faceFrame(position, normal)
	kit:decor("VentBack", frame * CFrame.new(0, 0, -0.04), Vector3.new(width, height, 0.08), "PaintBlack")
	for _, offset in { -1, 1 } do
		kit:decor(
			"VentFrame",
			frame * CFrame.new(offset * (width / 2 - 0.08), 0, -0.12),
			Vector3.new(0.16, height, 0.16),
			"Steel"
		)
		kit:decor(
			"VentFrame",
			frame * CFrame.new(0, offset * (height / 2 - 0.08), -0.12),
			Vector3.new(width, 0.16, 0.16),
			"Steel"
		)
	end
	local slats = math.max(math.floor(height / 0.45), 2)
	for index = 1, slats - 1 do
		local y = -height / 2 + height * index / slats
		kit:decor(
			"VentSlat",
			frame * CFrame.new(0, y, -0.12) * CFrame.Angles(math.rad(-35), 0, 0),
			Vector3.new(width - 0.3, 0.06, 0.24),
			"Steel"
		)
	end
end

--[[ Écran / panneau d'information plat (néon tamisé + cadre). ]]
function Decor.screen(kit: Kit, position: Vector3, normal: Vector3, width: number, height: number, color: Color3)
	local frame = faceFrame(position, normal)
	kit:decor(
		"ScreenBezel",
		frame * CFrame.new(0, 0, -0.06),
		Vector3.new(width + 0.24, height + 0.24, 0.12),
		"SteelDark"
	)
	kit:decor(
		"ScreenGlow",
		frame * CFrame.new(0, 0, -0.14),
		Vector3.new(width, height, 0.04),
		"Screen",
		{ color = color }
	)
end

---------------------------------------------------------------------------------------------
-- Détail des volumes de couverture (dans leur emprise, ≤ 0.12 stud de débord)
---------------------------------------------------------------------------------------------

--[[ Caisse : arêtes renforcées (12), bandeau et plaque de marquage. `prim` = caisse MapKit. ]]
function Decor.crate(kit: Kit, prim: Prim, edgeStyle: string, plateColor: Color3?)
	local size = prim.size
	local e = 0.22
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			kit:decor(
				"CrateEdge",
				prim.cframe * CFrame.new(0, sy * (hy - e / 2 + 0.03), sz * (hz - e / 2 + 0.03)),
				Vector3.new(size.X + 0.06, e, e),
				edgeStyle
			)
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			kit:decor(
				"CrateEdge",
				prim.cframe * CFrame.new(sx * (hx - e / 2 + 0.03), 0, sz * (hz - e / 2 + 0.03)),
				Vector3.new(e, size.Y + 0.06, e),
				edgeStyle
			)
		end
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			kit:decor(
				"CrateEdge",
				prim.cframe * CFrame.new(sx * (hx - e / 2 + 0.03), sy * (hy - e / 2 + 0.03), 0),
				Vector3.new(e, e, size.Z + 0.06),
				edgeStyle
			)
		end
	end
	if plateColor then
		for _, sz in { -1, 1 } do
			kit:decor(
				"CratePlate",
				prim.cframe * CFrame.new(0, hy * 0.25, sz * (hz + 0.02)),
				Vector3.new(size.X * 0.42, size.Y * 0.22, 0.05),
				"PaintWhite",
				{
					color = plateColor,
				}
			)
		end
	end
end

--[[
	Conteneur maritime sur une boîte axe-alignée : nervures sur les grandes faces,
	montants d'angle, rails haut/bas, porte à barres de verrouillage côté `doorEnd`.
]]
function Decor.container(
	kit: Kit,
	x1: number,
	y1: number,
	z1: number,
	x2: number,
	y2: number,
	z2: number,
	color: Color3,
	doorEnd: number? -- +1 / -1 : extrémité (le long du grand axe) portant les portes
)
	local alongX = math.abs(x2 - x1) >= math.abs(z2 - z1)
	local ax, bx = math.min(x1, x2), math.max(x1, x2)
	local az, bz = math.min(z1, z2), math.max(z1, z2)
	local dark, light = Decor.shade(color, 0.62), Decor.shade(color, 1.12)
	local height = y2 - y1
	local length = if alongX then bx - ax else bz - az
	local ribs = math.floor(length / 1.6)
	for index = 1, ribs - 1 do
		local t = index / ribs
		for _, side in { -1, 1 } do
			if alongX then
				local x = ax + (bx - ax) * t
				local z = if side < 0 then az else bz
				kit:decorBox(
					"Rib",
					x - 0.14,
					y1 + 0.45,
					z,
					x + 0.14,
					y2 - 0.45,
					z + side * 0.1,
					"Metal",
					{ color = light }
				)
			else
				local z = az + (bz - az) * t
				local x = if side < 0 then ax else bx
				kit:decorBox(
					"Rib",
					x,
					y1 + 0.45,
					z - 0.14,
					x + side * 0.1,
					y2 - 0.45,
					z + 0.14,
					"Metal",
					{ color = light }
				)
			end
		end
	end
	for _, cx in { ax, bx } do
		for _, cz in { az, bz } do
			local ox = if cx == ax then 0.35 else -0.35
			local oz = if cz == az then 0.35 else -0.35
			kit:decorBox("CornerPost", cx - 0.05, y1, cz - 0.05, cx + ox, y2 + 0.05, cz + oz, "Metal", { color = dark })
		end
	end
	for _, y in { y1, y2 - 0.4 } do
		if alongX then
			kit:decorBox("Rail", ax, y, az - 0.08, bx, y + 0.4, az + 0.1, "Metal", { color = dark })
			kit:decorBox("Rail", ax, y, bz - 0.1, bx, y + 0.4, bz + 0.08, "Metal", { color = dark })
		else
			kit:decorBox("Rail", ax - 0.08, y, az, ax + 0.1, y + 0.4, bz, "Metal", { color = dark })
			kit:decorBox("Rail", bx - 0.1, y, az, bx + 0.08, y + 0.4, bz, "Metal", { color = dark })
		end
	end
	if doorEnd then
		local width = if alongX then bz - az else bx - ax
		local from = if alongX then az else ax
		local face = if alongX then (if doorEnd > 0 then bx else ax) else (if doorEnd > 0 then bz else az)
		local out = doorEnd * 0.12
		for _, t in { 0.2, 0.4, 0.6, 0.8 } do
			local p = from + width * t
			if alongX then
				kit:decor(
					"LockBar",
					CFrame.new(face + out, (y1 + y2) / 2, p) * CFrame.Angles(0, 0, math.pi / 2),
					Vector3.new(height - 0.8, 0.16, 0.16),
					"Steel",
					{ shape = "Cylinder" }
				)
			else
				kit:decor(
					"LockBar",
					CFrame.new(p, (y1 + y2) / 2, face + out) * CFrame.Angles(0, 0, math.pi / 2),
					Vector3.new(height - 0.8, 0.16, 0.16),
					"Steel",
					{ shape = "Cylinder" }
				)
			end
		end
		local mid = from + width / 2
		if alongX then
			kit:decorBox("DoorSeam", face, y1 + 0.4, mid - 0.05, face + out * 0.6, y2 - 0.4, mid + 0.05, "PaintBlack")
		else
			kit:decorBox("DoorSeam", mid - 0.05, y1 + 0.4, face, mid + 0.05, y2 - 0.4, face + out * 0.6, "PaintBlack")
		end
	end
end

--[[
	Habille toutes les couvertures déjà posées par le plan : caisses (arêtes renforcées,
	plaque de marquage selon le matériau) et murets (couronnement + bandeau bas).
]]
function Decor.dressCovers(kit: Kit, plateColor: Color3?)
	local snapshot = table.clone(kit.prims)
	for _, prim in snapshot do
		if prim.group ~= "Cover" then
			continue
		end
		if prim.name == "Crate" then
			if prim.material == "WoodPlanks" then
				Decor.crate(kit, prim, "Wood", nil)
			elseif prim.material == "Metal" and prim.reflectance > 0.1 then
				Decor.crate(kit, prim, "Brass", nil)
			else
				Decor.crate(kit, prim, "SteelDark", plateColor)
			end
		elseif prim.name == "Cover" then
			local size = prim.size
			local top = prim.cframe * CFrame.new(0, size.Y / 2 + 0.06, 0)
			kit:decor("CoverCap", top, Vector3.new(size.X + 0.12, 0.12, size.Z + 0.12), "SteelDark")
			kit:decor(
				"CoverKick",
				prim.cframe * CFrame.new(0, -size.Y / 2 + 0.2, 0),
				Vector3.new(size.X + 0.1, 0.4, size.Z + 0.1),
				"PaintBlack"
			)
		end
	end
end

--[[ Panneau (SurfaceGui) placé dans l'horizon : non collidable, groupe Backdrop. ]]
function Decor.billboard(
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
	sign.group = "Backdrop"
	sign.query = false
	-- Cadre néon DERRIÈRE la face affichée (il déborde de 0.5 stud tout autour).
	local direction = if facing == "+X"
		then Vector3.xAxis
		elseif facing == "-X" then -Vector3.xAxis
		elseif facing == "+Z" then Vector3.zAxis
		else -Vector3.zAxis
	local frameSize = if facing == "+X" or facing == "-X"
		then Vector3.new(0.3, height + 1, width + 1)
		else Vector3.new(width + 1, height + 1, 0.3)
	kit:decor("BillboardFrame", CFrame.new(Vector3.new(x, y, z) - direction * 0.25), frameSize, "NeonWhite", {
		group = "Backdrop",
		color = color,
	})
end

---------------------------------------------------------------------------------------------
-- Mobilier (VRAIE géométrie : collision et requête, groupe Props) — zones de spawn et hub
---------------------------------------------------------------------------------------------

--[[ Volume solide orienté (participe aux collisions et aux lignes de vue). ]]
function Decor.solid(kit: Kit, name: string, cframe: CFrame, size: Vector3, style: string, options: DecorOptions?): Prim
	local opts: DecorOptions = if options then table.clone(options) else {}
	opts.group = "Props"
	opts.shadow = if opts.shadow == nil then true else opts.shadow
	local prim = kit:decor(name, cframe, size, style, opts)
	prim.collide = true
	prim.query = true
	return prim
end

--[[ Canapé (largeur `width`, dossier côté +Z local), base au sol `y`. ]]
function Decor.sofa(kit: Kit, x: number, y: number, z: number, yaw: number, width: number, color: Color3)
	local frame = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
	Decor.solid(
		kit,
		"Sofa",
		frame * CFrame.new(0, 0.9, 0.15),
		Vector3.new(width, 1.8, 2.7),
		"FabricDark",
		{ color = color }
	)
	kit:decor(
		"SofaBack",
		frame * CFrame.new(0, 2.25, 1.15),
		Vector3.new(width, 1.6, 0.7),
		"FabricDark",
		{ color = color }
	)
	for _, side in { -1, 1 } do
		kit:decor(
			"SofaArm",
			frame * CFrame.new(side * (width / 2 + 0.25), 1.45, 0.15),
			Vector3.new(0.5, 1.3, 2.7),
			"FabricDark",
			{
				color = Decor.shade(color, 0.85),
			}
		)
	end
	local cushions = math.max(math.floor(width / 2.2), 1)
	for index = 1, cushions do
		local cx = -width / 2 + (index - 0.5) * width / cushions
		kit:decor(
			"Cushion",
			frame * CFrame.new(cx, 1.88, -0.05),
			Vector3.new(width / cushions - 0.15, 0.22, 2.1),
			"FabricDark",
			{
				color = Decor.shade(color, 1.12),
			}
		)
	end
end

--[[ Table basse / comptoir : plateau + pied central. ]]
function Decor.table(
	kit: Kit,
	x: number,
	y: number,
	z: number,
	width: number,
	depth: number,
	height: number,
	top: string
)
	Decor.solid(
		kit,
		"TableBase",
		CFrame.new(x, y + (height - 0.2) / 2, z),
		Vector3.new(width * 0.4, height - 0.2, depth * 0.4),
		"SteelDark"
	)
	kit:decor("TableTop", CFrame.new(x, y + height - 0.1, z), Vector3.new(width, 0.2, depth), top)
end

--[[ Jardinière : bac solide + feuillage (boules) au-dessus. ]]
function Decor.planter(kit: Kit, rng: Rng, x: number, y: number, z: number, size: number, potStyle: string)
	Decor.solid(kit, "Planter", CFrame.new(x, y + 0.7, z), Vector3.new(size, 1.4, size), potStyle)
	kit:decor("Soil", CFrame.new(x, y + 1.41, z), Vector3.new(size - 0.3, 0.04, size - 0.3), "Soil")
	for _ = 1, 4 do
		local r = rng(0.7, 1.2) * size * 0.5
		Decor.solid(
			kit,
			"Foliage",
			CFrame.new(x + rng(-0.3, 0.3) * size, y + 1.6 + r * rng(0.6, 1.4), z + rng(-0.3, 0.3) * size),
			Vector3.new(r * 2, r * 2, r * 2),
			if rng() < 0.5 then "Foliage" else "FoliageDark",
			{
				shape = "Ball",
			}
		)
	end
end

--[[ Poteaux et cordons (file d'attente) : fins, purement décoratifs. ]]
function Decor.stanchions(kit: Kit, points: { Vector3 }, color: Color3)
	for index, point in points do
		kit:decorBox(
			"Stanchion",
			point.X - 0.12,
			point.Y,
			point.Z - 0.12,
			point.X + 0.12,
			point.Y + 2.8,
			point.Z + 0.12,
			"Brass"
		)
		kit:decor(
			"StanchionBase",
			CFrame.new(point.X, point.Y + 0.05, point.Z) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(0.1, 0.9, 0.9),
			"Brass",
			{
				shape = "Cylinder",
			}
		)
		local nextPoint = points[index + 1]
		if nextPoint then
			Decor.cable(kit, point + Vector3.new(0, 2.6, 0), nextPoint + Vector3.new(0, 2.6, 0), 0.35, 4, 0.07)
			local last = kit.prims
			for offset = 0, 3 do
				last[#last - offset].color = color
			end
		end
	end
end

--[[ Ferme métallique en hauteur (membrures + diagonales), de `a` à `b` (horizontale). ]]
function Decor.truss(kit: Kit, a: Vector3, b: Vector3, depth: number, style: string)
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt(a, b)
	local panels = math.max(math.floor(length / 6), 1)
	for _, y in { 0, -depth } do
		kit:decor("TrussChord", frame * CFrame.new(0, y, -length / 2), Vector3.new(0.5, 0.5, length), style)
	end
	for index = 0, panels do
		local z = -length * index / panels
		kit:decor("TrussPost", frame * CFrame.new(0, -depth / 2, z), Vector3.new(0.35, depth, 0.35), style)
		if index < panels then
			local span = length / panels
			local diagonal = math.sqrt(span * span + depth * depth)
			local angle = math.atan2(depth, span) * (if index % 2 == 0 then 1 else -1)
			kit:decor(
				"TrussBrace",
				frame * CFrame.new(0, -depth / 2, z - span / 2) * CFrame.Angles(angle, 0, 0),
				Vector3.new(0.25, 0.25, diagonal),
				style
			)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Horizon (hors limites, groupe Backdrop)
---------------------------------------------------------------------------------------------

export type TowerPalette = { body: string, windows: { string }, lit: number }

--[[ Tour lointaine : volume + bandes de fenêtres éclairées + antenne et balise. ]]
function Decor.tower(
	kit: Kit,
	rng: Rng,
	x: number,
	z: number,
	width: number,
	depth: number,
	height: number,
	baseY: number,
	palette: TowerPalette
)
	kit:decorBox(
		"Tower",
		x - width / 2,
		baseY,
		z - depth / 2,
		x + width / 2,
		baseY + height,
		z + depth / 2,
		palette.body,
		BACKDROP
	)
	local floors = math.floor(height / 5)
	local faces = {
		{ axis = "X", fixed = z - depth / 2 - 0.1, span = width, sign = -1 },
		{ axis = "X", fixed = z + depth / 2 + 0.1, span = width, sign = 1 },
		{ axis = "Z", fixed = x - width / 2 - 0.1, span = depth, sign = -1 },
		{ axis = "Z", fixed = x + width / 2 + 0.1, span = depth, sign = 1 },
	}
	for _, face in faces do
		-- Seules les façades tournées vers la carte (centre à l'origine) sont vues.
		local toward = if face.axis == "X" then -z * face.sign else -x * face.sign
		if toward <= 0 then
			continue
		end
		local strips = 0
		for floor = 1, floors - 1 do
			if rng() < palette.lit and strips < 5 then
				strips += 1
				local y = baseY + floor * 5 - 2
				local a = rng(0.05, 0.55) * face.span - face.span / 2
				local b = math.min(a + rng(0.2, 0.6) * face.span, face.span / 2 - 0.5)
				local style = palette.windows[math.clamp(math.floor(rng() * #palette.windows) + 1, 1, #palette.windows)]
				if face.axis == "X" then
					kit:decorBox(
						"Windows",
						x + a,
						y,
						face.fixed,
						x + b,
						y + 1.6,
						face.fixed + face.sign * 0.1,
						style,
						BACKDROP
					)
				else
					kit:decorBox(
						"Windows",
						face.fixed,
						y,
						z + a,
						face.fixed + face.sign * 0.1,
						y + 1.6,
						z + b,
						style,
						BACKDROP
					)
				end
			end
		end
	end
	local top = baseY + height
	if rng() < 0.6 then
		local mast = rng(6, 16)
		kit:decorBox("Antenna", x - 0.3, top, z - 0.3, x + 0.3, top + mast, z + 0.3, "SteelDark", BACKDROP)
		kit:decor("Beacon", CFrame.new(x, top + mast + 0.5, z), Vector3.new(1, 1, 1), "Beacon", {
			group = "Backdrop",
			shape = "Ball",
		})
	else
		kit:decorBox(
			"RoofUnit",
			x - width * 0.3,
			top,
			z - depth * 0.25,
			x + width * 0.1,
			top + 3,
			z + depth * 0.25,
			palette.body,
			BACKDROP
		)
	end
end

--[[ Ceinture de tours autour d'un rectangle (anneau entre `inner` et `outer` de marge). ]]
function Decor.skyline(
	kit: Kit,
	rng: Rng,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	inner: number,
	outer: number,
	count: number,
	minHeight: number,
	maxHeight: number,
	baseY: number,
	palette: TowerPalette
)
	local placed = 0
	local attempts = 0
	while placed < count and attempts < count * 20 do
		attempts += 1
		local x = rng(x1 - outer, x2 + outer)
		local z = rng(z1 - outer, z2 + outer)
		local w, d = rng(14, 40), rng(14, 40)
		local outside = x + w / 2 < x1 - inner
			or x - w / 2 > x2 + inner
			or z + d / 2 < z1 - inner
			or z - d / 2 > z2 + inner
		if outside then
			placed += 1
			Decor.tower(kit, rng, x, z, w, d, rng(minHeight, maxHeight), baseY, palette)
		end
	end
end

--[[ Grue à tour (silhouette) : mât en treillis, flèche, contre-flèche, cabine, balises. ]]
function Decor.crane(kit: Kit, x: number, z: number, baseY: number, height: number, jib: number, yaw: number)
	local frame = CFrame.new(x, baseY, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local half = 1.4
	local function part(name: string, cf: CFrame, size: Vector3, style: string, shape: MapKit.Shape?)
		kit:decor(name, frame * cf, size, style, { group = "Backdrop", shape = shape })
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				"CraneMast",
				CFrame.new(sx * half, height / 2, sz * half),
				Vector3.new(0.35, height, 0.35),
				"PaintYellow"
			)
		end
	end
	local segment = 4
	for index = 0, math.floor(height / segment) - 1 do
		local y = index * segment + segment / 2
		local diagonal = math.sqrt(segment * segment + (half * 2) ^ 2)
		local angle = math.atan2(segment, half * 2) * (if index % 2 == 0 then 1 else -1)
		part(
			"CraneBrace",
			CFrame.new(0, y, -half) * CFrame.Angles(0, 0, angle),
			Vector3.new(diagonal, 0.2, 0.2),
			"PaintYellow"
		)
		part(
			"CraneBrace",
			CFrame.new(half, y, 0) * CFrame.Angles(angle, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Vector3.new(diagonal, 0.2, 0.2),
			"PaintYellow"
		)
	end
	part("CraneJib", CFrame.new(0, height + 0.8, -jib / 2), Vector3.new(2.2, 1.6, jib), "PaintYellow")
	part("CraneCounterJib", CFrame.new(0, height + 0.8, jib * 0.16), Vector3.new(2.2, 1.6, jib * 0.32), "PaintYellow")
	part("CraneWeight", CFrame.new(0, height - 0.6, jib * 0.28), Vector3.new(3, 2.4, 3.6), "Concrete")
	part("CraneCab", CFrame.new(1.8, height - 1.2, -0.5), Vector3.new(2, 2.4, 2.4), "SteelDark")
	part("CraneTop", CFrame.new(0, height + 4.5, 0), Vector3.new(0.8, 7.5, 0.8), "PaintYellow")
	part("CraneCable", CFrame.new(0, height - 10, -jib * 0.7), Vector3.new(0.12, 21, 0.12), "Cable")
	part("CraneHook", CFrame.new(0, height - 21, -jib * 0.7), Vector3.new(1, 1.4, 1), "SteelDark")
	part("CraneBeacon", CFrame.new(0, height + 8.6, 0), Vector3.new(0.8, 0.8, 0.8), "Beacon", "Ball")
	part("CraneBeacon", CFrame.new(0, height + 1.9, -jib + 0.6), Vector3.new(0.7, 0.7, 0.7), "Beacon", "Ball")
end

--[[
	Massif rocheux lointain : crêtes en prisme triangulaire (deux coins adossés), arêtes
	orientées au hasard, calottes de neige au-dessus de `snowLine` (groupe Backdrop).
]]
function Decor.ridge(
	kit: Kit,
	rng: Rng,
	x: number,
	z: number,
	width: number,
	height: number,
	baseY: number,
	snowLine: number?
)
	local pieces = math.max(math.floor(width / 70), 3)
	local function prism(name: string, frame: CFrame, w: number, h: number, d: number, style: string)
		kit:decor(name, frame * CFrame.new(0, 0, -d / 4), Vector3.new(w, h, d / 2), style, {
			group = "Backdrop",
			shape = "Wedge",
		})
		kit:decor(
			name,
			frame * CFrame.new(0, 0, d / 4) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(w, h, d / 2),
			style,
			{
				group = "Backdrop",
				shape = "Wedge",
			}
		)
	end
	for index = 1, pieces do
		local px = x + (index - (pieces + 1) / 2) * (width / pieces) + rng(-10, 10)
		local pz = z + rng(-20, 20)
		local h = height * rng(0.55, 1)
		local w = width / pieces * rng(1.1, 1.6)
		local d = h * rng(1.4, 2.2)
		local frame = CFrame.new(px, baseY + h / 2, pz) * CFrame.Angles(0, rng(-0.6, 0.6), 0)
		prism("Ridge", frame, w, h, d, if index % 2 == 0 then "RockDark" else "Basalt")
		if snowLine and baseY + h > snowLine then
			local capH = math.min(h * 0.28, baseY + h - snowLine)
			local capFrame = frame * CFrame.new(0, h / 2 - capH / 2 + 0.5, 0)
			prism("SnowCap", capFrame, w * 0.9, capH, d * capH / h, "SnowPack")
		end
	end
end

return Decor
