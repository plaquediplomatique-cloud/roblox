--[[
	Construit chaque carte (plans MapKit + habillage) en Instances, hors Studio, puis :
	  * mesure son coût avec SceneAudit (skill roblox-render-performance) ;
	  * écrit build/maps/<id>.rbxm (modèle à glisser dans Studio pour inspection).

	  lune run tools/audit_maps.luau [Mobile|Desktop]
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local loader = require("../tests/lib/loader")

local MapKit = loader.require(loader.maps.MapKit)
local blueprints = loader.maps.Blueprints

local auditPath = ".claude/skills/roblox-render-performance/scripts/SceneAudit.luau"
local SceneAudit = luau.load(fs.readFile(auditPath), {
	debugName = auditPath,
	environment = { Vector3 = roblox.Vector3, NumberRange = roblox.NumberRange, Enum = roblox.Enum },
})()
local budget = SceneAudit.budgets[process.args[1] or "Mobile"]
assert(budget, "budget : Mobile ou Desktop")

local Instance, Enum = roblox.Instance, roblox.Enum

local function createPart(prim)
	local part
	if prim.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		if prim.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif prim.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		end
	end
	part.Name = prim.name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = prim.collide
	part.CanQuery = prim.query
	part.CastShadow = prim.shadow
	part.Material = Enum.Material[prim.material]
	part.Color = prim.color
	part.Transparency = prim.transparency
	part.Reflectance = prim.reflectance
	part.Size = prim.size
	part.CFrame = prim.cframe
	local light = prim.light
	if light then
		local className = if light.kind == "Point"
			then "PointLight"
			elseif light.kind == "Spot" then "SpotLight"
			else "SurfaceLight"
		local instance = Instance.new(className)
		instance.Color = light.color
		instance.Brightness = light.brightness
		instance.Range = light.range
		instance.Shadows = light.shadows
		instance.Parent = part
	end
	if prim.sign then
		local gui = Instance.new("SurfaceGui")
		gui.Parent = part
	end
	return part
end

fs.writeDir("build/maps")
for _, name in { "Hub", "Kestrel", "Helix", "Spire", "Monolith" } do
	local blueprint = loader.require(blueprints[name])
	local kit = MapKit.new()
	blueprint.build(kit)
	local model = Instance.new("Model")
	model.Name = "Map_" .. blueprint.id
	local folders = {}
	for _, prim in kit.prims do
		local folder = folders[prim.group]
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = prim.group
			folder.Parent = model
			folders[prim.group] = folder
		end
		createPart(prim).Parent = folder
	end
	fs.writeFile(("build/maps/%s.rbxm"):format(blueprint.id), roblox.serializeModel({ model }))
	print(SceneAudit.format(SceneAudit.run(model, budget)))
	print()
end
