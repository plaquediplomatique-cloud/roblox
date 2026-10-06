--!strict
--[[
	MapKit — langage de description de cartes (blockout jouable), PUREMENT DÉCLARATIF.

	Un blueprint appelle des primitives de level design (sol, mur avec porte, caisse,
	rampe, plateforme, néon, lampe, spawn, barrière, site, callout, panneau…) et MapKit
	ENREGISTRE des descripteurs. Il ne crée aucune Instance : MapBuilder s'en charge.

	Conséquences :
	  * les cartes sont du code versionné, diffable, revu comme le reste ;
	  * elles s'exécutent hors moteur (Lune) : tools/render_maps produit une vue de dessus
	    PNG de chaque carte pour la revue de level design ;
	  * les métriques de gameplay sont garanties par construction : caisse = 4 studs
	    (cache un joueur accroupi, pas debout), porte ≥ 6 studs, murs 14+ studs, etc.

	Repère : sol à y = 0, carte centrée sur l'origine, +Y vers le haut.
]]

export type SignSpec = {
	text: string,
	color: Color3,
	face: string,
	background: Color3,
}

export type LightSpec = {
	kind: "Point" | "Spot" | "Surface",
	color: Color3,
	brightness: number,
	range: number,
	face: string?,
	angle: number?,
	shadows: boolean,
}

export type Prim = {
	name: string,
	shape: "Block" | "Wedge" | "Cylinder" | "Ball",
	cframe: CFrame,
	size: Vector3,
	material: string,
	color: Color3,
	transparency: number,
	reflectance: number,
	collide: boolean,
	query: boolean,
	shadow: boolean,
	group: string,
	tags: { string },
	attributes: { [string]: any },
	sign: SignSpec?,
	light: LightSpec?,
}

export type Style = {
	material: string,
	color: Color3,
	transparency: number?,
	reflectance: number?,
}

export type Kit = {
	prims: { Prim },
	style: (self: Kit, name: string) -> Style,
	defineStyle: (self: Kit, name: string, style: Style) -> (),
	block: (self: Kit, name: string, center: Vector3, size: Vector3, style: string, group: string?) -> Prim,
	box: (
		self: Kit,
		name: string,
		x1: number,
		y1: number,
		z1: number,
		x2: number,
		y2: number,
		z2: number,
		style: string,
		group: string?
	) -> Prim,
	floor: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		style: string,
		top: number?,
		thickness: number?
	) -> Prim,
	ceiling: (self: Kit, x1: number, z1: number, x2: number, z2: number, y: number, style: string) -> Prim,
	wall: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		height: number,
		style: string,
		thickness: number?,
		baseY: number?
	) -> Prim,
	wallDoor: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		height: number,
		doorFrom: number,
		doorTo: number,
		doorHeight: number,
		style: string,
		thickness: number?
	) -> (),
	window: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		height: number,
		openFrom: number,
		openTo: number,
		sillY: number,
		topY: number,
		style: string,
		thickness: number?
	) -> (),
	crate: (self: Kit, x: number, z: number, y: number?, size: number?, style: string?, yaw: number?) -> Prim,
	cover: (
		self: Kit,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		height: number,
		style: string?,
		baseY: number?
	) -> Prim,
	platform: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		top: number,
		style: string,
		thickness: number?
	) -> Prim,
	ramp: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		y1: number,
		y2: number,
		direction: string,
		style: string
	) -> Prim,
	pillar: (self: Kit, x: number, z: number, width: number, height: number, style: string, baseY: number?) -> Prim,
	trim: (
		self: Kit,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		y: number,
		color: Color3,
		thickness: number?
	) -> Prim,
	light: (
		self: Kit,
		x: number,
		y: number,
		z: number,
		color: Color3,
		brightness: number,
		range: number,
		shadows: boolean?
	) -> Prim,
	lamp: (self: Kit, x: number, z: number, height: number, color: Color3, baseY: number?) -> (),
	panelLight: (
		self: Kit,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		y: number,
		color: Color3,
		brightness: number
	) -> Prim,
	spawn: (self: Kit, side: string, x: number, z: number, lookX: number, lookZ: number, y: number?) -> Prim,
	barrier: (
		self: Kit,
		side: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		height: number,
		baseY: number?
	) -> Prim,
	modeBarrier: (self: Kit, modes: { string }, x1: number, z1: number, x2: number, z2: number, height: number) -> Prim,
	site: (self: Kit, id: string, x1: number, z1: number, x2: number, z2: number, y: number?) -> (),
	callout: (
		self: Kit,
		name: string,
		x1: number,
		z1: number,
		x2: number,
		z2: number,
		y1: number?,
		y2: number?
	) -> Prim,
	zone: (
		self: Kit,
		tag: string,
		name: string,
		x1: number,
		y1: number,
		z1: number,
		x2: number,
		y2: number,
		z2: number,
		attributes: { [string]: any }?
	) -> Prim,
	sign: (
		self: Kit,
		text: string,
		x: number,
		y: number,
		z: number,
		width: number,
		height: number,
		facing: string,
		color: Color3
	) -> Prim,
	terminal: (self: Kit, action: string, label: string, x: number, z: number, facing: string, color: Color3) -> (),
	bounds: (self: Kit, x1: number, z1: number, x2: number, z2: number, height: number) -> (),
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BASE_STYLES: { [string]: Style } = {
	Floor = { material = "Concrete", color = rgb(46, 49, 56) },
	FloorDark = { material = "Slate", color = rgb(28, 30, 35) },
	FloorMetal = { material = "DiamondPlate", color = rgb(58, 62, 69) },
	FloorTile = { material = "SmoothPlastic", color = rgb(34, 37, 43), reflectance = 0.05 },
	Wall = { material = "Concrete", color = rgb(56, 60, 68) },
	WallDark = { material = "Concrete", color = rgb(32, 35, 40) },
	WallPanel = { material = "SmoothPlastic", color = rgb(70, 76, 86) },
	Metal = { material = "Metal", color = rgb(84, 88, 96) },
	MetalDark = { material = "Metal", color = rgb(38, 41, 46) },
	Grate = { material = "DiamondPlate", color = rgb(72, 76, 82) },
	Glass = { material = "Glass", color = rgb(150, 205, 230), transparency = 0.65 },
	Marble = { material = "Marble", color = rgb(20, 22, 26), reflectance = 0.08 },
	MarbleWhite = { material = "Marble", color = rgb(214, 218, 224), reflectance = 0.05 },
	ContainerRust = { material = "CorrodedMetal", color = rgb(132, 62, 42) },
	ContainerTeal = { material = "Metal", color = rgb(38, 104, 116) },
	ContainerGray = { material = "Metal", color = rgb(92, 96, 104) },
	ContainerOrange = { material = "Metal", color = rgb(190, 100, 40) },
	Crate = { material = "Metal", color = rgb(62, 66, 74) },
	CrateWood = { material = "WoodPlanks", color = rgb(112, 82, 56) },
	Gold = { material = "Metal", color = rgb(205, 160, 60), reflectance = 0.15 },
	Server = { material = "SmoothPlastic", color = rgb(18, 20, 24) },
	Rock = { material = "Rock", color = rgb(78, 82, 92) },
	Snow = { material = "Snow", color = rgb(228, 234, 240) },
	Ice = { material = "Ice", color = rgb(170, 210, 230) },
	Monolith = { material = "SmoothPlastic", color = rgb(6, 6, 8), reflectance = 0.2 },
	Hull = { material = "Metal", color = rgb(48, 44, 58) },
	HullLight = { material = "SmoothPlastic", color = rgb(96, 90, 110) },
	NeonCyan = { material = "Neon", color = rgb(61, 225, 255) },
	NeonOrange = { material = "Neon", color = rgb(255, 140, 50) },
	NeonMagenta = { material = "Neon", color = rgb(220, 80, 255) },
	NeonWhite = { material = "Neon", color = rgb(235, 240, 255) },
	NeonRed = { material = "Neon", color = rgb(255, 70, 85) },
	Invisible = { material = "SmoothPlastic", color = rgb(255, 255, 255), transparency = 1 },
	BarrierAttack = { material = "ForceField", color = rgb(255, 90, 54), transparency = 0.2 },
	BarrierDefense = { material = "ForceField", color = rgb(61, 200, 255), transparency = 0.2 },
	BarrierMode = { material = "ForceField", color = rgb(150, 120, 255), transparency = 0.25 },
}

local SIDE_COLOR: { [string]: Color3 } = {
	Attack = rgb(255, 90, 54),
	Defense = rgb(61, 200, 255),
}

local MapKit = {}

local KitClass = {}
KitClass.__index = KitClass

local function sorted(a: number, b: number): (number, number)
	if a <= b then
		return a, b
	end
	return b, a
end

local function record(self: Kit, prim: Prim): Prim
	table.insert(self.prims, prim)
	return prim
end

function KitClass.style(self: any, name: string): Style
	local style = self._styles[name]
	assert(style, "unknown map style " .. name)
	return style
end

function KitClass.defineStyle(self: any, name: string, style: Style)
	self._styles[name] = style
end

local function makePrim(
	self: Kit,
	name: string,
	shape: "Block" | "Wedge" | "Cylinder" | "Ball",
	cframe: CFrame,
	size: Vector3,
	styleName: string,
	group: string?
): Prim
	local style = self:style(styleName)
	local transparency = style.transparency or 0
	return {
		name = name,
		shape = shape,
		cframe = cframe,
		size = size,
		material = style.material,
		color = style.color,
		transparency = transparency,
		reflectance = style.reflectance or 0,
		collide = true,
		query = true,
		shadow = transparency < 0.5 and style.material ~= "Neon",
		group = group or "Geometry",
		tags = {},
		attributes = {},
		sign = nil,
		light = nil,
	}
end

function KitClass.block(self: Kit, name: string, center: Vector3, size: Vector3, style: string, group: string?): Prim
	return record(self, makePrim(self, name, "Block", CFrame.new(center), size, style, group))
end

function KitClass.box(
	self: Kit,
	name: string,
	x1: number,
	y1: number,
	z1: number,
	x2: number,
	y2: number,
	z2: number,
	style: string,
	group: string?
): Prim
	local ax, bx = sorted(x1, x2)
	local ay, by = sorted(y1, y2)
	local az, bz = sorted(z1, z2)
	local size = Vector3.new(math.max(bx - ax, 0.05), math.max(by - ay, 0.05), math.max(bz - az, 0.05))
	local center = Vector3.new((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2)
	return self:block(name, center, size, style, group)
end

function KitClass.floor(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	style: string,
	top: number?,
	thickness: number?
): Prim
	local y = top or 0
	local t = thickness or 2
	return self:box(name, x1, y - t, z1, x2, y, z2, style, "Floor")
end

function KitClass.ceiling(self: Kit, x1: number, z1: number, x2: number, z2: number, y: number, style: string): Prim
	local prim = self:box("Ceiling", x1, y, z1, x2, y + 1, z2, style, "Ceiling")
	prim.shadow = true
	return prim
end

function KitClass.wall(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number,
	style: string,
	thickness: number?,
	baseY: number?
): Prim
	local t = thickness or 1.2
	local y0 = baseY or 0
	if x1 == x2 then
		return self:box(name, x1 - t / 2, y0, z1, x1 + t / 2, y0 + height, z2, style)
	elseif z1 == z2 then
		return self:box(name, x1, y0, z1 - t / 2, x2, y0 + height, z1 + t / 2, style)
	end
	local a = Vector3.new(x1, y0 + height / 2, z1)
	local b = Vector3.new(x2, y0 + height / 2, z2)
	local length = (b - a).Magnitude
	local cframe = CFrame.lookAt((a + b) / 2, b)
	return record(self, makePrim(self, name, "Block", cframe, Vector3.new(t, height, length), style, nil))
end

--[[ Mur axe-aligné percé d'une porte (coordonnées absolues le long de l'axe du mur). ]]
function KitClass.wallDoor(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number,
	doorFrom: number,
	doorTo: number,
	doorHeight: number,
	style: string,
	thickness: number?
)
	local t = thickness or 1.2
	local dFrom, dTo = sorted(doorFrom, doorTo)
	if x1 == x2 then
		local a, b = sorted(z1, z2)
		if dFrom > a then
			self:box(name, x1 - t / 2, 0, a, x1 + t / 2, height, dFrom, style)
		end
		if dTo < b then
			self:box(name, x1 - t / 2, 0, dTo, x1 + t / 2, height, b, style)
		end
		self:box(name .. "Lintel", x1 - t / 2, doorHeight, dFrom, x1 + t / 2, height, dTo, style)
	else
		local a, b = sorted(x1, x2)
		if dFrom > a then
			self:box(name, a, 0, z1 - t / 2, dFrom, height, z1 + t / 2, style)
		end
		if dTo < b then
			self:box(name, dTo, 0, z1 - t / 2, b, height, z1 + t / 2, style)
		end
		self:box(name .. "Lintel", dFrom, doorHeight, z1 - t / 2, dTo, height, z1 + t / 2, style)
	end
end

--[[ Mur avec une ouverture (fenêtre) entre sillY et topY. ]]
function KitClass.window(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number,
	openFrom: number,
	openTo: number,
	sillY: number,
	topY: number,
	style: string,
	thickness: number?
)
	local t = thickness or 1.2
	local oFrom, oTo = sorted(openFrom, openTo)
	if x1 == x2 then
		local a, b = sorted(z1, z2)
		self:box(name, x1 - t / 2, 0, a, x1 + t / 2, height, oFrom, style)
		self:box(name, x1 - t / 2, 0, oTo, x1 + t / 2, height, b, style)
		self:box(name .. "Sill", x1 - t / 2, 0, oFrom, x1 + t / 2, sillY, oTo, style)
		self:box(name .. "Top", x1 - t / 2, topY, oFrom, x1 + t / 2, height, oTo, style)
	else
		local a, b = sorted(x1, x2)
		self:box(name, a, 0, z1 - t / 2, oFrom, height, z1 + t / 2, style)
		self:box(name, oTo, 0, z1 - t / 2, b, height, z1 + t / 2, style)
		self:box(name .. "Sill", oFrom, 0, z1 - t / 2, oTo, sillY, z1 + t / 2, style)
		self:box(name .. "Top", oFrom, topY, z1 - t / 2, oTo, height, z1 + t / 2, style)
	end
end

--[[ Caisse de couverture standard : 4 studs = cache un joueur accroupi, pas debout. ]]
function KitClass.crate(self: Kit, x: number, z: number, y: number?, size: number?, style: string?, yaw: number?): Prim
	local s = size or 4
	local base = y or 0
	local cframe = CFrame.new(x, base + s / 2, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	local prim = record(self, makePrim(self, "Crate", "Block", cframe, Vector3.new(s, s, s), style or "Crate", "Cover"))
	prim.attributes.CoverHeight = s
	return prim
end

function KitClass.cover(
	self: Kit,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number,
	style: string?,
	baseY: number?
): Prim
	local base = baseY or 0
	local prim = self:box("Cover", x1, base, z1, x2, base + height, z2, style or "WallPanel", "Cover")
	prim.attributes.CoverHeight = height
	return prim
end

function KitClass.platform(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	top: number,
	style: string,
	thickness: number?
): Prim
	local t = thickness or top
	return self:box(name, x1, top - t, z1, x2, top, z2, style)
end

--[[
	Rampe (WedgePart) sur l'emprise (x1,z1)-(x2,z2), montant de y1 à y2 dans `direction`
	("+X", "-X", "+Z", "-Z"). Pente max conseillée : 35° (montée sans saut).
]]
function KitClass.ramp(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y1: number,
	y2: number,
	direction: string,
	style: string
): Prim
	local ax, bx = sorted(x1, x2)
	local az, bz = sorted(z1, z2)
	local rise = math.max(y2 - y1, 0.1)
	local center = Vector3.new((ax + bx) / 2, y1 + rise / 2, (az + bz) / 2)
	local dir: Vector3
	local width, length
	if direction == "+X" then
		dir, width, length = Vector3.new(1, 0, 0), bz - az, bx - ax
	elseif direction == "-X" then
		dir, width, length = Vector3.new(-1, 0, 0), bz - az, bx - ax
	elseif direction == "+Z" then
		dir, width, length = Vector3.new(0, 0, 1), bx - ax, bz - az
	else
		dir, width, length = Vector3.new(0, 0, -1), bx - ax, bz - az
	end
	-- Le WedgePart monte vers son +Z local : on oriente +Z selon `dir`.
	local cframe = CFrame.lookAt(center, center - dir)
	local prim =
		record(self, makePrim(self, name, "Wedge", cframe, Vector3.new(width, rise, length), style, "Geometry"))
	prim.attributes.RampDirection = direction
	return prim
end

function KitClass.pillar(
	self: Kit,
	x: number,
	z: number,
	width: number,
	height: number,
	style: string,
	baseY: number?
): Prim
	local base = baseY or 0
	return self:box("Pillar", x - width / 2, base, z - width / 2, x + width / 2, base + height, z + width / 2, style)
end

function KitClass.trim(
	self: Kit,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y: number,
	color: Color3,
	thickness: number?
): Prim
	local t = thickness or 0.3
	local prim = self:box("Trim", x1, y - t / 2, z1, x2, y + t / 2, z2, "NeonCyan", "Trim")
	prim.color = color
	prim.collide = false
	prim.query = false
	prim.shadow = false
	return prim
end

function KitClass.light(
	self: Kit,
	x: number,
	y: number,
	z: number,
	color: Color3,
	brightness: number,
	range: number,
	shadows: boolean?
): Prim
	local prim = self:block("LightSource", Vector3.new(x, y, z), Vector3.new(0.4, 0.4, 0.4), "Invisible", "Lights")
	prim.collide = false
	prim.query = false
	prim.shadow = false
	prim.light = {
		kind = "Point",
		color = color,
		brightness = brightness,
		range = range,
		face = nil,
		angle = nil,
		shadows = shadows or false,
	}
	return prim
end

function KitClass.lamp(self: Kit, x: number, z: number, height: number, color: Color3, baseY: number?)
	local base = baseY or 0
	self:box("LampPole", x - 0.3, base, z - 0.3, x + 0.3, base + height, z + 0.3, "MetalDark", "Props")
	local head =
		self:box("LampHead", x - 1, base + height, z - 0.6, x + 1, base + height + 0.5, z + 0.6, "NeonWhite", "Props")
	head.color = color
	head.collide = false
	local light = self:light(x, base + height - 0.6, z, color, 2.2, 38, true)
	light.light =
		{ kind = "Spot", color = color, brightness = 3, range = 40, face = "Bottom", angle = 110, shadows = true }
end

function KitClass.panelLight(
	self: Kit,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y: number,
	color: Color3,
	brightness: number
): Prim
	local prim = self:box("PanelLight", x1, y - 0.2, z1, x2, y, z2, "NeonWhite", "Lights")
	prim.color = color
	prim.collide = false
	prim.query = false
	prim.light = {
		kind = "Surface",
		color = color,
		brightness = brightness,
		range = 22,
		face = "Bottom",
		angle = 120,
		shadows = false,
	}
	return prim
end

function KitClass.spawn(self: Kit, side: string, x: number, z: number, lookX: number, lookZ: number, y: number?): Prim
	local base = y or 0
	local position = Vector3.new(x, base + 3, z)
	local look = Vector3.new(lookX, base + 3, lookZ)
	local marker = record(
		self,
		makePrim(
			self,
			"SpawnPoint",
			"Block",
			CFrame.lookAt(position, look),
			Vector3.new(2, 1, 2),
			"Invisible",
			"Markers"
		)
	)
	marker.collide = false
	marker.query = false
	marker.shadow = false
	table.insert(marker.tags, "SpawnPoint")
	marker.attributes.Side = side
	local pad = self:box("SpawnPad", x - 1.6, base, z - 1.6, x + 1.6, base + 0.12, z + 1.6, "NeonCyan", "Trim")
	pad.color = SIDE_COLOR[side] or rgb(255, 255, 255)
	pad.collide = false
	pad.query = false
	pad.transparency = 0.35
	return marker
end

function KitClass.barrier(
	self: Kit,
	side: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number,
	baseY: number?
): Prim
	local base = baseY or 0
	local prim = self:box(
		"SpawnBarrier",
		x1,
		base,
		z1,
		x2,
		base + height,
		z2,
		if side == "Attack" then "BarrierAttack" else "BarrierDefense",
		"Markers"
	)
	table.insert(prim.tags, "SpawnBarrier")
	prim.attributes.Side = side
	prim.attributes.Impenetrable = true
	prim.shadow = false
	return prim
end

function KitClass.modeBarrier(
	self: Kit,
	modes: { string },
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	height: number
): Prim
	local prim = self:box("ModeBarrier", x1, 0, z1, x2, height, z2, "BarrierMode", "Markers")
	table.insert(prim.tags, "ModeBarrier")
	prim.attributes.Modes = table.concat(modes, ",")
	prim.attributes.Impenetrable = true
	prim.shadow = false
	return prim
end

function KitClass.zone(
	self: Kit,
	tag: string,
	name: string,
	x1: number,
	y1: number,
	z1: number,
	x2: number,
	y2: number,
	z2: number,
	attributes: { [string]: any }?
): Prim
	local prim = self:box(name, x1, y1, z1, x2, y2, z2, "Invisible", "Markers")
	prim.collide = false
	prim.query = false
	prim.shadow = false
	table.insert(prim.tags, tag)
	if attributes then
		for key, value in attributes do
			prim.attributes[key] = value
		end
	end
	return prim
end

function KitClass.callout(
	self: Kit,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y1: number?,
	y2: number?
): Prim
	return self:zone("CalloutZone", "Callout_" .. name, x1, y1 or -4, z1, x2, y2 or 40, z2, { Callout = name })
end

--[[ Site d'objectif : zone de pose + contour néon au sol + grande lettre lumineuse. ]]
function KitClass.site(self: Kit, id: string, x1: number, z1: number, x2: number, z2: number, y: number?)
	local base = y or 0
	self:zone("SiteZone", "Site_" .. id, x1, base - 1, z1, x2, base + 12, z2, { Site = id })
	local ax, bx = sorted(x1, x2)
	local az, bz = sorted(z1, z2)
	local color = rgb(255, 190, 70)
	self:trim(ax, az, bx, az + 0.4, base + 0.1, color, 0.2)
	self:trim(ax, bz - 0.4, bx, bz, base + 0.1, color, 0.2)
	self:trim(ax, az, ax + 0.4, bz, base + 0.1, color, 0.2)
	self:trim(bx - 0.4, az, bx, bz, base + 0.1, color, 0.2)
end

function KitClass.sign(
	self: Kit,
	text: string,
	x: number,
	y: number,
	z: number,
	width: number,
	height: number,
	facing: string,
	color: Color3
): Prim
	local size: Vector3
	if facing == "+X" or facing == "-X" then
		size = Vector3.new(0.3, height, width)
	else
		size = Vector3.new(width, height, 0.3)
	end
	local prim = self:block("Sign", Vector3.new(x, y, z), size, "MetalDark", "Props")
	prim.collide = false
	local face = if facing == "+X"
		then "Right"
		elseif facing == "-X" then "Left"
		elseif facing == "+Z" then "Back"
		else "Front"
	prim.sign = { text = text, color = color, face = face, background = rgb(8, 10, 14) }
	return prim
end

--[[ Terminal interactif du hub (ProximityPrompt créé par MapBuilder). ]]
function KitClass.terminal(
	self: Kit,
	action: string,
	label: string,
	x: number,
	z: number,
	facing: string,
	color: Color3
)
	local base = self:box("Terminal", x - 1.5, 0, z - 1, x + 1.5, 3.4, z + 1, "MetalDark", "Props")
	table.insert(base.tags, "HubTerminal")
	base.attributes.Action = action
	base.attributes.Label = label
	local screenY = 4.4
	local offset = if facing == "+X"
		then Vector3.new(0.6, 0, 0)
		elseif facing == "-X" then Vector3.new(-0.6, 0, 0)
		elseif facing == "+Z" then Vector3.new(0, 0, 0.6)
		else Vector3.new(0, 0, -0.6)
	self:sign(label, x + offset.X, screenY, z + offset.Z, 3, 2, facing, color)
	self:light(x, 5.5, z, color, 1.6, 14, false)
end

--[[ Murs invisibles de limite + plafond de jeu + volume de mort sous la carte. ]]
function KitClass.bounds(self: Kit, x1: number, z1: number, x2: number, z2: number, height: number)
	local ax, bx = sorted(x1, x2)
	local az, bz = sorted(z1, z2)
	local t = 4
	for _, coords in
		{
			{ ax - t, az - t, bx + t, az },
			{ ax - t, bz, bx + t, bz + t },
			{ ax - t, az, ax, bz },
			{ bx, az, bx + t, bz },
		}
	do
		local wall =
			self:box("Boundary", coords[1], -20, coords[2], coords[3], height, coords[4], "Invisible", "Markers")
		wall.attributes.Impenetrable = true
		wall.shadow = false
	end
	local roof = self:box("BoundaryRoof", ax, height, az, bx, height + t, bz, "Invisible", "Markers")
	roof.attributes.Impenetrable = true
	roof.shadow = false
	self:zone("KillVolume", "KillVolume", ax - 50, -400, az - 50, bx + 50, -30, bz + 50, nil)
end

function MapKit.new(): Kit
	local self = setmetatable({ prims = {}, _styles = table.clone(BASE_STYLES) }, KitClass)
	return (self :: any) :: Kit
end

MapKit.SIDE_COLOR = SIDE_COLOR

return MapKit
