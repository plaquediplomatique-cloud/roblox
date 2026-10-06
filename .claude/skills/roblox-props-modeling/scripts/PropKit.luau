--!strict
--[[
	PropKit — parametric furniture and interior props built from Parts.

	Works in Roblox Studio (command bar, plugin, MCP execute_luau, server scripts) and outside
	Roblox with Lune (see export_props.luau), because it only uses Instance.new and datatypes.

	Conventions (shared by every builder):
	  * model origin = bottom-centre of the footprint (y = 0 is the floor), front faces -Z
	    (the pivot's LookVector), so `model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))`
	    places and orients any prop the same way;
	  * visual parts: Anchored, CanCollide = false, CanTouch = false, CastShadow only when the
	    part is larger than 1 stud on its longest side;
	  * collision: invisible parts named "Collider" with simple boxes (cheap physics, no
	    snagging on details);
	  * attributes: PropKit (kind), Footprint (Vector3) for placement tools and audits.

	Dimensions are in studs at the skill's design scale (≈ 3 studs per metre, seat height 1.5);
	see the dimension table in SKILL.md.
]]

export type Style = {
	name: string,
	wood: Color3,
	woodMaterial: Enum.Material,
	fabric: Color3,
	fabricMaterial: Enum.Material,
	metal: Color3,
	metalMaterial: Enum.Material,
	accent: Color3,
}

local PropKit = {}

PropKit.styles = {
	Oak = {
		name = "Oak",
		wood = Color3.fromRGB(176, 132, 88),
		woodMaterial = Enum.Material.Wood,
		fabric = Color3.fromRGB(176, 168, 152),
		fabricMaterial = Enum.Material.Fabric,
		metal = Color3.fromRGB(62, 62, 66),
		metalMaterial = Enum.Material.Metal,
		accent = Color3.fromRGB(124, 146, 120),
	} :: Style,
	Walnut = {
		name = "Walnut",
		wood = Color3.fromRGB(92, 62, 44),
		woodMaterial = Enum.Material.Wood,
		fabric = Color3.fromRGB(122, 54, 46),
		fabricMaterial = Enum.Material.Fabric,
		metal = Color3.fromRGB(150, 122, 72),
		metalMaterial = Enum.Material.Metal,
		accent = Color3.fromRGB(204, 170, 102),
	} :: Style,
	Modern = {
		name = "Modern",
		wood = Color3.fromRGB(226, 222, 214),
		woodMaterial = Enum.Material.Plastic,
		fabric = Color3.fromRGB(62, 66, 76),
		fabricMaterial = Enum.Material.Fabric,
		metal = Color3.fromRGB(30, 30, 34),
		metalMaterial = Enum.Material.Metal,
		accent = Color3.fromRGB(64, 196, 230),
	} :: Style,
}

-- Deterministic pseudo-random generator (identical in Roblox and Lune, unlike Random).
local function rng(seed: number): () -> number
	local state = bit32.bor(math.floor(seed) % 4294967296, 1)
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

local function shade(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

type BlockOptions = {
	shape: Enum.PartType?,
	collide: boolean?,
	transparency: number?,
	rotation: CFrame?,
}

local function block(
	model: Model,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	options: BlockOptions?
): Part
	local opts: BlockOptions = options or {}
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = opts.shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = CFrame.new(position) * (opts.rotation or CFrame.new())
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = opts.collide == true
	part.CanTouch = false
	part.CastShadow = math.max(size.X, size.Y, size.Z) > 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = opts.transparency or 0
	part.Parent = model
	return part
end

local function collider(model: Model, size: Vector3, position: Vector3): Part
	local part = block(model, "Collider", size, position, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		collide = true,
		transparency = 1,
	})
	part.CastShadow = false
	return part
end

-- Vertical cylinder: Roblox cylinders run along X, so rotate 90° about Z.
local function cylinder(
	model: Model,
	name: string,
	diameter: number,
	height: number,
	position: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	return block(model, name, Vector3.new(height, diameter, diameter), position, color, material, {
		shape = Enum.PartType.Cylinder,
		rotation = CFrame.Angles(0, 0, math.rad(90)),
	})
end

local function newModel(kind: string, footprint: Vector3): Model
	local model = Instance.new("Model")
	model.Name = kind
	model.WorldPivot = CFrame.new()
	model:SetAttribute("PropKit", kind)
	model:SetAttribute("Footprint", footprint)
	return model
end

local function styleOf(style: Style?): Style
	return style or PropKit.styles.Oak
end

---------------------------------------------------------------------------------------------
-- Tables and seating
---------------------------------------------------------------------------------------------

export type TableParams = { width: number?, depth: number?, height: number?, style: Style? }

function PropKit.diningTable(params: TableParams?): Model
	local p: TableParams = params or {}
	local s = styleOf(p.style)
	local width, depth, height = p.width or 6, p.depth or 3.6, p.height or 2.5
	local model = newModel("DiningTable", Vector3.new(width, height, depth))
	local top = 0.2
	block(model, "Top", Vector3.new(width, top, depth), Vector3.new(0, height - top / 2, 0), s.wood, s.woodMaterial)
	-- Chamfer illusion: a slightly inset, darker slab under the top edge catches a shadow line.
	block(
		model,
		"TopUnder",
		Vector3.new(width - 0.16, 0.06, depth - 0.16),
		Vector3.new(0, height - top - 0.03, 0),
		shade(s.wood, 0.82),
		s.woodMaterial
	)
	local apronH, inset, leg = 0.35, 0.3, 0.3
	local apronY = height - top - 0.06 - apronH / 2
	for _, z in { -1, 1 } do
		block(
			model,
			"ApronLong",
			Vector3.new(width - 2 * inset, apronH, 0.12),
			Vector3.new(0, apronY, z * (depth / 2 - inset)),
			shade(s.wood, 0.92),
			s.woodMaterial
		)
	end
	for _, x in { -1, 1 } do
		block(
			model,
			"ApronShort",
			Vector3.new(0.12, apronH, depth - 2 * inset),
			Vector3.new(x * (width / 2 - inset), apronY, 0),
			shade(s.wood, 0.92),
			s.woodMaterial
		)
	end
	local legH = height - top - 0.06
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local lx, lz = x * (width / 2 - inset + leg / 2 - 0.06), z * (depth / 2 - inset + leg / 2 - 0.06)
			-- Two-step taper reads as a turned leg without meshes.
			block(
				model,
				"Leg",
				Vector3.new(leg, legH * 0.6, leg),
				Vector3.new(lx, legH * 0.7, lz),
				s.wood,
				s.woodMaterial
			)
			block(
				model,
				"Leg",
				Vector3.new(leg * 0.8, legH * 0.4, leg * 0.8),
				Vector3.new(lx, legH * 0.2, lz),
				s.wood,
				s.woodMaterial
			)
		end
	end
	collider(model, Vector3.new(width, height, depth), Vector3.new(0, height / 2, 0))
	return model
end

export type ChairParams = { seatHeight: number?, width: number?, style: Style?, sittable: boolean? }

function PropKit.chair(params: ChairParams?): Model
	local p: ChairParams = params or {}
	local s = styleOf(p.style)
	local seatH, width = p.seatHeight or 1.5, p.width or 1.6
	local depth, backTop, leg = width, seatH + 1.7, 0.18
	local model = newModel("Chair", Vector3.new(width, backTop, depth))
	local seatT = 0.16
	block(
		model,
		"Seat",
		Vector3.new(width, seatT, depth),
		Vector3.new(0, seatH - 0.12 - seatT / 2, 0),
		s.wood,
		s.woodMaterial
	)
	block(
		model,
		"Cushion",
		Vector3.new(width - 0.12, 0.12, depth - 0.16),
		Vector3.new(0, seatH - 0.06, -0.02),
		s.fabric,
		s.fabricMaterial
	)
	local half = width / 2 - leg / 2 - 0.04
	for _, x in { -1, 1 } do
		-- Front legs stop under the seat, rear legs continue up as back posts.
		local legY = (seatH - 0.12 - seatT) / 2
		block(
			model,
			"LegFront",
			Vector3.new(leg, seatH - 0.12 - seatT, leg),
			Vector3.new(x * half, legY, -half),
			s.wood,
			s.woodMaterial
		)
		block(
			model,
			"BackPost",
			Vector3.new(leg, backTop, leg),
			Vector3.new(x * half, backTop / 2, half),
			s.wood,
			s.woodMaterial
		)
	end
	local recline = CFrame.Angles(math.rad(-8), 0, 0)
	block(
		model,
		"BackRest",
		Vector3.new(width - 2 * leg - 0.08, 0.8, 0.12),
		Vector3.new(0, backTop - 0.55, half + 0.02),
		s.wood,
		s.woodMaterial,
		{ rotation = recline }
	)
	block(
		model,
		"BackRail",
		Vector3.new(width - 2 * leg - 0.08, 0.14, 0.1),
		Vector3.new(0, seatH + 0.35, half),
		shade(s.wood, 0.9),
		s.woodMaterial
	)
	collider(model, Vector3.new(width, seatH, depth), Vector3.new(0, seatH / 2, 0))
	if p.sittable then
		local seat = Instance.new("Seat")
		seat.Name = "SitPoint"
		seat.Size = Vector3.new(width - 0.2, 0.2, depth - 0.2)
		seat.CFrame = CFrame.new(0, seatH - 0.1, 0)
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CastShadow = false
		seat.Parent = model
	end
	return model
end

export type SofaParams = { width: number?, seats: number?, style: Style? }

function PropKit.sofa(params: SofaParams?): Model
	local p: SofaParams = params or {}
	local s = styleOf(p.style)
	local width, seats = p.width or 6.6, math.clamp(p.seats or 3, 1, 4)
	local depth, seatH, backTop, arm = 2.9, 1.4, 2.6, 0.5
	local model = newModel("Sofa", Vector3.new(width, backTop, depth))
	local feet = 0.22
	local baseH = seatH - 0.35 - feet
	local inner = width - 2 * arm
	block(
		model,
		"Base",
		Vector3.new(width, baseH, depth),
		Vector3.new(0, feet + baseH / 2, 0),
		shade(s.fabric, 0.85),
		s.fabricMaterial
	)
	block(
		model,
		"Back",
		Vector3.new(width, backTop - feet - baseH, 0.6),
		Vector3.new(0, feet + baseH + (backTop - feet - baseH) / 2, depth / 2 - 0.3),
		shade(s.fabric, 0.9),
		s.fabricMaterial
	)
	for _, x in { -1, 1 } do
		block(
			model,
			"Arm",
			Vector3.new(arm, 2.0 - feet, depth),
			Vector3.new(x * (width / 2 - arm / 2), feet + (2.0 - feet) / 2, 0),
			s.fabric,
			s.fabricMaterial
		)
	end
	local gap = 0.05
	local cushionW = (inner - gap * (seats - 1)) / seats
	for index = 1, seats do
		local x = -inner / 2 + cushionW / 2 + (index - 1) * (cushionW + gap)
		block(
			model,
			"SeatCushion",
			Vector3.new(cushionW, 0.35, depth - 0.75),
			Vector3.new(x, seatH - 0.175, -0.2),
			s.fabric,
			s.fabricMaterial
		)
		block(
			model,
			"BackCushion",
			Vector3.new(cushionW, 1.0, 0.4),
			Vector3.new(x, seatH + 0.55, depth / 2 - 0.75),
			shade(s.fabric, 1.06),
			s.fabricMaterial,
			{ rotation = CFrame.Angles(math.rad(-10), 0, 0) }
		)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			block(
				model,
				"Foot",
				Vector3.new(0.25, feet, 0.25),
				Vector3.new(x * (width / 2 - 0.3), feet / 2, z * (depth / 2 - 0.3)),
				s.wood,
				s.woodMaterial
			)
		end
	end
	collider(model, Vector3.new(width, seatH, depth), Vector3.new(0, seatH / 2, 0))
	collider(
		model,
		Vector3.new(width, backTop - seatH, 0.6),
		Vector3.new(0, seatH + (backTop - seatH) / 2, depth / 2 - 0.3)
	)
	return model
end

---------------------------------------------------------------------------------------------
-- Bedroom and storage
---------------------------------------------------------------------------------------------

export type BedParams = { width: number?, length: number?, style: Style?, seed: number? }

function PropKit.bed(params: BedParams?): Model
	local p: BedParams = params or {}
	local s = styleOf(p.style)
	local width, length = p.width or 4.8, p.length or 6.6
	local railH, mattress, headTop = 0.9, 0.6, 3.2
	local model = newModel("Bed", Vector3.new(width, headTop, length))
	local legs = 0.3
	block(
		model,
		"Frame",
		Vector3.new(width, railH - legs, length),
		Vector3.new(0, legs + (railH - legs) / 2, 0),
		s.wood,
		s.woodMaterial
	)
	block(
		model,
		"Headboard",
		Vector3.new(width + 0.2, headTop, 0.25),
		Vector3.new(0, headTop / 2, length / 2 + 0.125),
		shade(s.wood, 0.9),
		s.woodMaterial
	)
	block(
		model,
		"Mattress",
		Vector3.new(width - 0.2, mattress, length - 0.2),
		Vector3.new(0, railH + mattress / 2, 0),
		Color3.fromRGB(236, 234, 228),
		Enum.Material.Fabric
	)
	-- Duvet covers the lower two thirds and drapes slightly over the sides.
	local duvetL = (length - 0.2) * 0.68
	block(
		model,
		"Duvet",
		Vector3.new(width - 0.05, 0.18, duvetL),
		Vector3.new(0, railH + mattress + 0.05, -(length - 0.2) / 2 + duvetL / 2 - 0.05),
		s.fabric,
		s.fabricMaterial
	)
	local random = rng(p.seed or 7)
	local pillows = if width >= 4 then 2 else 1
	for index = 1, pillows do
		local x = if pillows == 1 then 0 else (index - 1.5) * (width / 2)
		block(
			model,
			"Pillow",
			Vector3.new(math.min(1.8, width / pillows - 0.3), 0.4, 1.0),
			Vector3.new(x, railH + mattress + 0.2, length / 2 - 0.8),
			Color3.fromRGB(244, 242, 238),
			Enum.Material.Fabric,
			{ rotation = CFrame.Angles(math.rad(-12), math.rad((random() - 0.5) * 8), 0) }
		)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			block(
				model,
				"Leg",
				Vector3.new(0.3, legs, 0.3),
				Vector3.new(x * (width / 2 - 0.2), legs / 2, z * (length / 2 - 0.2)),
				shade(s.wood, 0.8),
				s.woodMaterial
			)
		end
	end
	collider(model, Vector3.new(width, railH + mattress, length), Vector3.new(0, (railH + mattress) / 2, 0))
	collider(model, Vector3.new(width + 0.2, headTop, 0.25), Vector3.new(0, headTop / 2, length / 2 + 0.125))
	return model
end

export type ShelfParams = {
	width: number?,
	height: number?,
	shelves: number?,
	books: boolean?,
	seed: number?,
	style: Style?,
}

function PropKit.bookshelf(params: ShelfParams?): Model
	local p: ShelfParams = params or {}
	local s = styleOf(p.style)
	local width, height, depth = p.width or 3.2, p.height or 6, 1.1
	local count = math.clamp(p.shelves or 5, 2, 8)
	local model = newModel("Bookshelf", Vector3.new(width, height, depth))
	local side, board, kick = 0.15, 0.12, 0.3
	for _, x in { -1, 1 } do
		block(
			model,
			"Side",
			Vector3.new(side, height, depth),
			Vector3.new(x * (width / 2 - side / 2), height / 2, 0),
			s.wood,
			s.woodMaterial
		)
	end
	block(
		model,
		"Back",
		Vector3.new(width - 2 * side, height, 0.06),
		Vector3.new(0, height / 2, depth / 2 - 0.03),
		shade(s.wood, 0.75),
		s.woodMaterial
	)
	block(
		model,
		"Kick",
		Vector3.new(width - 2 * side, kick, 0.1),
		Vector3.new(0, kick / 2, -depth / 2 + 0.2),
		shade(s.wood, 0.85),
		s.woodMaterial
	)
	local inner = width - 2 * side
	local pitch = (height - kick - board) / count
	local random = rng(p.seed or 11)
	local bookColors = {
		Color3.fromRGB(150, 52, 48),
		Color3.fromRGB(46, 74, 120),
		Color3.fromRGB(196, 170, 112),
		Color3.fromRGB(58, 96, 70),
		Color3.fromRGB(220, 214, 200),
		Color3.fromRGB(40, 40, 44),
	}
	for index = 0, count do
		local y = kick + board / 2 + index * pitch
		block(model, "Board", Vector3.new(inner, board, depth - 0.1), Vector3.new(0, y, -0.05), s.wood, s.woodMaterial)
		if p.books ~= false and index < count then
			-- Books in clusters with a gap: reads as a used shelf, not a texture.
			local x = -inner / 2 + 0.05
			local limit = inner / 2 - 0.05 - random() * inner * 0.35
			while x < limit do
				local thick = 0.12 + random() * 0.16
				local tall = math.min(pitch - 0.2, 0.75 + random() * 0.45)
				if x + thick > limit then
					break
				end
				local book = block(
					model,
					"Book",
					Vector3.new(thick, tall, 0.62 + random() * 0.12),
					Vector3.new(x + thick / 2, y + board / 2 + tall / 2, -0.1),
					bookColors[1 + math.floor(random() * #bookColors)],
					Enum.Material.SmoothPlastic
				)
				book.CanQuery = false
				x += thick + (if random() < 0.15 then 0.25 else 0.01)
			end
		end
	end
	collider(model, Vector3.new(width, height, depth), Vector3.new(0, height / 2, 0))
	return model
end

---------------------------------------------------------------------------------------------
-- Kitchen
---------------------------------------------------------------------------------------------

export type CounterParams = { length: number?, upper: boolean?, style: Style? }

function PropKit.kitchenCounter(params: CounterParams?): Model
	local p: CounterParams = params or {}
	local s = styleOf(p.style)
	local length, depth, height = p.length or 8, 2.0, 3.0
	local upperTop = 6.6
	local model = newModel("KitchenCounter", Vector3.new(length, if p.upper then upperTop else height, depth))
	local kick, recess, top = 0.35, 0.15, 0.15
	local carcassH = height - top - kick
	block(
		model,
		"Kick",
		Vector3.new(length, kick, depth - recess - 0.1),
		Vector3.new(0, kick / 2, recess / 2),
		shade(s.metal, 0.9),
		s.metalMaterial
	)
	block(
		model,
		"Carcass",
		Vector3.new(length, carcassH, depth - 0.1),
		Vector3.new(0, kick + carcassH / 2, 0.05),
		shade(s.wood, 0.95),
		s.woodMaterial
	)
	block(
		model,
		"Worktop",
		Vector3.new(length + 0.1, top, depth + 0.1),
		Vector3.new(0, height - top / 2, -0.05),
		Color3.fromRGB(70, 72, 76),
		Enum.Material.Granite
	)
	-- Door fronts with 0.04 gaps and bar handles.
	local doors = math.max(1, math.floor(length / 2))
	local gap = 0.04
	local doorW = (length - gap * (doors + 1)) / doors
	for index = 1, doors do
		local x = -length / 2 + gap + doorW / 2 + (index - 1) * (doorW + gap)
		block(
			model,
			"Door",
			Vector3.new(doorW, carcassH - 2 * gap, 0.08),
			Vector3.new(x, kick + carcassH / 2, -depth / 2 + 0.04),
			s.wood,
			s.woodMaterial
		)
		block(
			model,
			"Handle",
			Vector3.new(0.6, 0.06, 0.08),
			Vector3.new(x, kick + carcassH - 0.35, -depth / 2 - 0.04),
			s.metal,
			s.metalMaterial
		)
	end
	if p.upper then
		local upperDepth, upperH = 1.1, 2.2
		local upperY = upperTop - upperH / 2
		block(
			model,
			"UpperCarcass",
			Vector3.new(length, upperH, upperDepth),
			Vector3.new(0, upperY, depth / 2 - upperDepth / 2),
			shade(s.wood, 0.95),
			s.woodMaterial
		)
		for index = 1, doors do
			local x = -length / 2 + gap + doorW / 2 + (index - 1) * (doorW + gap)
			block(
				model,
				"UpperDoor",
				Vector3.new(doorW, upperH - 2 * gap, 0.08),
				Vector3.new(x, upperY, depth / 2 - upperDepth - 0.04),
				s.wood,
				s.woodMaterial
			)
		end
		block(
			model,
			"Backsplash",
			Vector3.new(length, upperTop - upperH - height, 0.06),
			Vector3.new(0, height + (upperTop - upperH - height) / 2, depth / 2 - 0.03),
			Color3.fromRGB(214, 216, 218),
			Enum.Material.CeramicTiles
		)
	end
	collider(model, Vector3.new(length, height, depth), Vector3.new(0, height / 2, 0))
	return model
end

---------------------------------------------------------------------------------------------
-- Lighting fixtures and doors
---------------------------------------------------------------------------------------------

export type LampParams = { height: number?, brightness: number?, range: number?, shadows: boolean?, style: Style? }

function PropKit.floorLamp(params: LampParams?): Model
	local p: LampParams = params or {}
	local s = styleOf(p.style)
	local height = p.height or 5.4
	local model = newModel("FloorLamp", Vector3.new(1.4, height, 1.4))
	cylinder(model, "Base", 1.2, 0.12, Vector3.new(0, 0.06, 0), s.metal, s.metalMaterial)
	cylinder(model, "Pole", 0.12, height - 1.0, Vector3.new(0, 0.12 + (height - 1.0) / 2, 0), s.metal, s.metalMaterial)
	local shadeY = height - 0.5
	local lampShade = cylinder(
		model,
		"Shade",
		1.4,
		0.9,
		Vector3.new(0, shadeY, 0),
		Color3.fromRGB(236, 226, 206),
		Enum.Material.Fabric
	)
	lampShade.Transparency = 0.15
	local bulb = cylinder(
		model,
		"Bulb",
		0.4,
		0.3,
		Vector3.new(0, shadeY - 0.15, 0),
		Color3.fromRGB(255, 214, 160),
		Enum.Material.Neon
	)
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Brightness = p.brightness or 1.2
	light.Range = p.range or 14
	light.Color = Color3.fromRGB(255, 177, 110) -- 3000 K (see roblox-lighting-art), warm interior practical
	light.Shadows = p.shadows == true -- off by default: shadow-casting lights are the expensive ones
	light.Parent = bulb
	collider(model, Vector3.new(0.6, height, 0.6), Vector3.new(0, height / 2, 0))
	return model
end

export type DoorParams = { width: number?, height: number?, style: Style? }

function PropKit.door(params: DoorParams?): Model
	local p: DoorParams = params or {}
	local s = styleOf(p.style)
	local width, height = p.width or 4, p.height or 7
	local casing, depth = 0.3, 0.6
	local model = newModel("Door", Vector3.new(width + 2 * casing, height + casing, depth))
	for _, x in { -1, 1 } do
		block(
			model,
			"Casing",
			Vector3.new(casing, height + casing, depth),
			Vector3.new(x * (width / 2 + casing / 2), (height + casing) / 2, 0),
			shade(s.wood, 1.1),
			s.woodMaterial
		)
	end
	block(
		model,
		"Head",
		Vector3.new(width, casing, depth),
		Vector3.new(0, height + casing / 2, 0),
		shade(s.wood, 1.1),
		s.woodMaterial
	)
	-- The leaf is a separate part named for scripts: hinge on the -X side.
	local leaf = block(
		model,
		"Leaf",
		Vector3.new(width - 0.08, height - 0.06, 0.18),
		Vector3.new(0, (height - 0.06) / 2 + 0.03, 0),
		s.wood,
		s.woodMaterial,
		{ collide = true }
	)
	leaf:SetAttribute("HingeSide", "Left")
	for _, z in { -1, 1 } do
		block(
			model,
			"Handle",
			Vector3.new(0.5, 0.08, 0.08),
			Vector3.new(width / 2 - 0.55, 3.2, z * 0.16),
			s.metal,
			s.metalMaterial
		)
	end
	return model
end

PropKit.builders = {
	DiningTable = PropKit.diningTable,
	Chair = PropKit.chair,
	Sofa = PropKit.sofa,
	Bed = PropKit.bed,
	Bookshelf = PropKit.bookshelf,
	KitchenCounter = PropKit.kitchenCounter,
	FloorLamp = PropKit.floorLamp,
	Door = PropKit.door,
}

return PropKit
