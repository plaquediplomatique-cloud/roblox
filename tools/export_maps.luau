--[[
	Exporte chaque blueprint de carte en JSON (build/maps/<id>.json) pour la revue de
	level design hors Studio : `lune run tools/export_maps.luau` puis
	`python3 tools/render_maps.py` produit une vue de dessus PNG par carte.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local loader = require("../tests/lib/loader")

local MapKit = loader.require(loader.maps.MapKit)
local blueprints = loader.maps.Blueprints

local function list(v)
	return { v.X, v.Y, v.Z }
end

fs.writeDir("build/maps")
for _, name in { "Hub", "Kestrel", "Helix", "Spire", "Monolith" } do
	local node = blueprints:FindFirstChild(name)
	if node then
		local blueprint = loader.require(node)
		local kit = MapKit.new()
		blueprint.build(kit)
		local prims = {}
		for _, prim in kit.prims do
			local cf = prim.cframe
			local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			table.insert(prims, {
				name = prim.name,
				shape = prim.shape,
				cf = { px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				size = list(prim.size),
				material = prim.material,
				color = { prim.color.R, prim.color.G, prim.color.B },
				transparency = prim.transparency,
				group = prim.group,
				collide = prim.collide,
				tags = prim.tags,
				attributes = prim.attributes,
				sign = if prim.sign then prim.sign.text else nil,
			})
		end
		fs.writeFile(("build/maps/%s.json"):format(blueprint.id), serde.encode("json", { id = blueprint.id, prims = prims }))
		print(("%-10s %4d primitives"):format(blueprint.id, #prims))
	end
end
