--[[
	Exporte chaque blueprint de carte en JSON (build/maps/<id>.json) pour la revue de
	level design hors Studio :
	  lune run tools/export_maps.luau
	  python3 tools/render_maps.py     -> vue de dessus PNG par carte
	  python3 tools/render_view.py     -> rendus 3D de prévisualisation (caméras d'intro)
	Le JSON contient les primitives (géométrie, matériau, lumières, panneaux), les caméras
	d'intro/overview du blueprint et le profil d'éclairage de la carte (Shared/Config/Maps).
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local loader = require("../tests/lib/loader")

local MapKit = loader.require(loader.maps.MapKit)
local Maps = loader.require(loader.shared.Config.Maps)
local blueprints = loader.maps.Blueprints

local function list(v)
	return { v.X, v.Y, v.Z }
end

local function rgb(c)
	return { c.R, c.G, c.B }
end

local function cframe(cf)
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function lighting(profile)
	if not profile then
		return nil
	end
	return {
		clockTime = profile.clockTime,
		brightness = profile.brightness,
		ambient = rgb(profile.ambient),
		outdoorAmbient = rgb(profile.outdoorAmbient),
		exposure = profile.exposure,
		colorShiftTop = rgb(profile.colorShiftTop),
		atmosphere = {
			density = profile.atmosphere.density,
			offset = profile.atmosphere.offset,
			color = rgb(profile.atmosphere.color),
			decay = rgb(profile.atmosphere.decay),
			glare = profile.atmosphere.glare,
			haze = profile.atmosphere.haze,
		},
		colorCorrection = {
			brightness = profile.colorCorrection.brightness,
			contrast = profile.colorCorrection.contrast,
			saturation = profile.colorCorrection.saturation,
			tint = rgb(profile.colorCorrection.tint),
		},
		bloom = {
			intensity = profile.bloom.intensity,
			size = profile.bloom.size,
			threshold = profile.bloom.threshold,
		},
	}
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
			local light = prim.light
			local sign = prim.sign
			table.insert(prims, {
				name = prim.name,
				shape = prim.shape,
				cf = cframe(prim.cframe),
				size = list(prim.size),
				material = prim.material,
				color = rgb(prim.color),
				transparency = prim.transparency,
				reflectance = prim.reflectance,
				group = prim.group,
				collide = prim.collide,
				query = prim.query,
				shadow = prim.shadow,
				tags = prim.tags,
				attributes = prim.attributes,
				sign = if sign then sign.text else nil,
				signColor = if sign then rgb(sign.color) else nil,
				signBackground = if sign then rgb(sign.background) else nil,
				signFace = if sign then sign.face else nil,
				signPlain = if sign then sign.plain == true else nil,
				light = if light
					then {
						kind = light.kind,
						color = rgb(light.color),
						brightness = light.brightness,
						range = light.range,
						face = light.face,
						angle = light.angle,
						shadows = light.shadows,
					}
					else nil,
			})
		end
		local intro = {}
		for _, keyframe in blueprint.intro do
			table.insert(intro, cframe(keyframe))
		end
		local info = Maps.get(blueprint.id)
		fs.writeFile(
			("build/maps/%s.json"):format(blueprint.id),
			serde.encode("json", {
				id = blueprint.id,
				prims = prims,
				intro = intro,
				overview = cframe(blueprint.overview),
				lighting = lighting(info and info.lighting),
				weather = info and (info :: any).weather,
			})
		)
		print(("%-10s %4d primitives"):format(blueprint.id, #prims))
	end
end
