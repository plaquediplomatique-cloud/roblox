--!strict
--[[
	SceneAudit — counts the render, physics and memory cost drivers under a container and flags
	what exceeds a budget. Read-only: it never modifies the scene.

	Studio (command bar / MCP execute_luau / plugin):
		local SceneAudit = require(path.to.SceneAudit)
		print(SceneAudit.format(SceneAudit.run(workspace, SceneAudit.budgets.Mobile)))

	Outside Studio (Lune, on a place or model file):
		lune run .claude/skills/roblox-render-performance/scripts/audit_file.luau build/AetherStrike.rbxl

	Budgets are starting points for a streamed area on target hardware, not engine limits:
	measure on real devices (see roblox-performance) and tune them per project.
]]

export type Budget = {
	name: string,
	baseParts: number,
	uniqueMeshes: number,
	uniqueTextures: number,
	transparentParts: number,
	shadowLights: number,
	lights: number,
	particleBudget: number,
	smallShadowCasters: number,
	unanchoredParts: number,
	touchParts: number,
	preciseCollisions: number,
	unions: number,
	guis3D: number,
}

export type Report = {
	root: string,
	instances: number,
	baseParts: number,
	meshParts: number,
	unions: number,
	uniqueMeshes: number,
	decals: number,
	textures: number,
	surfaceAppearances: number,
	uniqueTextures: number,
	transparentParts: number,
	glassParts: number,
	neonParts: number,
	unanchoredParts: number,
	touchParts: number,
	smallShadowCasters: number,
	preciseCollisions: number,
	lights: number,
	shadowLights: number,
	emitters: number,
	particleBudget: number,
	beamsAndTrails: number,
	guis3D: number,
	humanoids: number,
	sounds: number,
	loopedSounds: number,
	scripts: number,
	materials: { [string]: number },
	findings: { string },
}

local SceneAudit = {}

SceneAudit.budgets = {
	Mobile = {
		name = "Mobile (per streamed area)",
		baseParts = 8000,
		uniqueMeshes = 250,
		uniqueTextures = 60,
		transparentParts = 250,
		shadowLights = 6,
		lights = 60,
		particleBudget = 600,
		smallShadowCasters = 400,
		unanchoredParts = 50,
		touchParts = 200,
		preciseCollisions = 20,
		unions = 150,
		guis3D = 40,
	} :: Budget,
	Desktop = {
		name = "Desktop (per streamed area)",
		baseParts = 20000,
		uniqueMeshes = 600,
		uniqueTextures = 150,
		transparentParts = 600,
		shadowLights = 12,
		lights = 150,
		particleBudget = 2000,
		smallShadowCasters = 1500,
		unanchoredParts = 150,
		touchParts = 500,
		preciseCollisions = 60,
		unions = 400,
		guis3D = 120,
	} :: Budget,
}

-- Property read that tolerates runtimes where a property has no value (e.g. Lune files).
local function get(instance: Instance, property: string, fallback: any): any
	local ok, value = pcall(function()
		return (instance :: any)[property]
	end)
	if ok and value ~= nil then
		return value
	end
	return fallback
end

local function idOf(value: any): string
	if typeof(value) == "string" then
		return value
	end
	if value == nil then
		return ""
	end
	local text = tostring(value)
	return if text == "nil" then "" else text
end

function SceneAudit.run(root: Instance, budget: Budget?): Report
	local report: Report = {
		root = if root:GetFullName() == "" then root.ClassName else root:GetFullName(),
		instances = 0,
		baseParts = 0,
		meshParts = 0,
		unions = 0,
		uniqueMeshes = 0,
		decals = 0,
		textures = 0,
		surfaceAppearances = 0,
		uniqueTextures = 0,
		transparentParts = 0,
		glassParts = 0,
		neonParts = 0,
		unanchoredParts = 0,
		touchParts = 0,
		smallShadowCasters = 0,
		preciseCollisions = 0,
		lights = 0,
		shadowLights = 0,
		emitters = 0,
		particleBudget = 0,
		beamsAndTrails = 0,
		guis3D = 0,
		humanoids = 0,
		sounds = 0,
		loopedSounds = 0,
		scripts = 0,
		materials = {},
		findings = {},
	}
	local meshes: { [string]: boolean } = {}
	local images: { [string]: boolean } = {}

	local function addImage(value: any)
		local id = idOf(value)
		if id ~= "" then
			images[id] = true
		end
	end

	for _, item in root:GetDescendants() do
		report.instances += 1
		if item:IsA("BasePart") then
			report.baseParts += 1
			local size: Vector3 = get(item, "Size", Vector3.new(1, 1, 1))
			local transparency: number = get(item, "Transparency", 0)
			local material: Enum.Material? = get(item, "Material", nil)
			local materialName = if material then material.Name else "Unknown"
			report.materials[materialName] = (report.materials[materialName] or 0) + 1
			if transparency > 0 and transparency < 1 then
				report.transparentParts += 1
			end
			if materialName == "Glass" then
				report.glassParts += 1
			elseif materialName == "Neon" then
				report.neonParts += 1
			end
			if get(item, "Anchored", true) == false then
				report.unanchoredParts += 1
			end
			if get(item, "CanTouch", false) == true then
				report.touchParts += 1
			end
			if
				get(item, "CastShadow", false) == true
				and transparency < 1
				and math.max(size.X, size.Y, size.Z) <= 1
			then
				report.smallShadowCasters += 1
			end
			if item:IsA("TriangleMeshPart") then
				local fidelity: Enum.CollisionFidelity? = get(item, "CollisionFidelity", nil)
				if fidelity and fidelity.Name == "PreciseConvexDecomposition" then
					report.preciseCollisions += 1
				end
			end
			if item:IsA("MeshPart") then
				report.meshParts += 1
				local mesh = idOf(get(item, "MeshId", ""))
				if mesh ~= "" then
					meshes[mesh] = true
				end
				addImage(get(item, "TextureID", ""))
			elseif item:IsA("PartOperation") then
				report.unions += 1
			end
		elseif item:IsA("Texture") then
			report.textures += 1
			addImage(get(item, "Texture", ""))
		elseif item:IsA("Decal") then
			report.decals += 1
			addImage(get(item, "Texture", ""))
		elseif item:IsA("SurfaceAppearance") then
			report.surfaceAppearances += 1
			addImage(get(item, "ColorMap", ""))
			addImage(get(item, "NormalMap", ""))
			addImage(get(item, "RoughnessMap", ""))
			addImage(get(item, "MetalnessMap", ""))
		elseif item:IsA("Light") then
			report.lights += 1
			if get(item, "Shadows", false) == true and get(item, "Enabled", true) == true then
				report.shadowLights += 1
			end
		elseif item:IsA("ParticleEmitter") then
			report.emitters += 1
			local rate: number = get(item, "Rate", 0)
			local lifetime: NumberRange = get(item, "Lifetime", NumberRange.new(0))
			if get(item, "Enabled", true) == true then
				report.particleBudget += rate * lifetime.Max
			end
		elseif item:IsA("Beam") or item:IsA("Trail") then
			report.beamsAndTrails += 1
		elseif item:IsA("SurfaceGui") or item:IsA("BillboardGui") then
			report.guis3D += 1
		elseif item:IsA("Humanoid") then
			report.humanoids += 1
		elseif item:IsA("Sound") then
			report.sounds += 1
			if get(item, "Looped", false) == true then
				report.loopedSounds += 1
			end
		elseif item:IsA("LuaSourceContainer") then
			report.scripts += 1
		end
	end
	for _ in meshes do
		report.uniqueMeshes += 1
	end
	for _ in images do
		report.uniqueTextures += 1
	end

	local limits = budget
	if limits then
		local function over(label: string, value: number, limit: number, advice: string)
			if value > limit then
				table.insert(report.findings, ("%s: %d > %d — %s"):format(label, math.floor(value), limit, advice))
			end
		end
		over("BaseParts", report.baseParts, limits.baseParts, "merge repeated detail into meshes, stream by zone")
		over(
			"Unique meshes",
			report.uniqueMeshes,
			limits.uniqueMeshes,
			"reuse a modular kit; identical meshes are cheaper"
		)
		over(
			"Unique textures",
			report.uniqueTextures,
			limits.uniqueTextures,
			"share texture sets; tint with SurfaceAppearance.Color"
		)
		over(
			"Transparent parts",
			report.transparentParts,
			limits.transparentParts,
			"overdraw: use opaque or Neon where possible"
		)
		over("Shadow-casting lights", report.shadowLights, limits.shadowLights, "Shadows = false on fill/bounce lights")
		over("Lights", report.lights, limits.lights, "Neon emitters for distant glow, smaller ranges")
		over(
			"Particle budget (Rate×Lifetime)",
			report.particleBudget,
			limits.particleBudget,
			"lower Rate/Lifetime, use Emit bursts"
		)
		over(
			"Small shadow casters",
			report.smallShadowCasters,
			limits.smallShadowCasters,
			"CastShadow = false on parts ≤ 1 stud"
		)
		over("Unanchored parts", report.unanchoredParts, limits.unanchoredParts, "anchor static scenery")
		over("CanTouch parts", report.touchParts, limits.touchParts, "CanTouch = false unless Touched is used")
		over(
			"Precise collisions",
			report.preciseCollisions,
			limits.preciseCollisions,
			"Box/Hull collision or simple colliders"
		)
		over("Unions", report.unions, limits.unions, "unions are unique geometry; prefer reused MeshParts")
		over("SurfaceGui/BillboardGui", report.guis3D, limits.guis3D, "MaxDistance, fewer always-on world GUIs")
	end
	return report
end

function SceneAudit.format(report: Report): string
	local lines = {
		("SceneAudit — %s"):format(report.root),
		("instances %d | BaseParts %d (MeshParts %d, unions %d) | unique meshes %d"):format(
			report.instances,
			report.baseParts,
			report.meshParts,
			report.unions,
			report.uniqueMeshes
		),
		("textures %d, decals %d, SurfaceAppearances %d | unique images %d"):format(
			report.textures,
			report.decals,
			report.surfaceAppearances,
			report.uniqueTextures
		),
		("transparent %d (glass %d) | neon %d | unanchored %d | CanTouch %d | small shadow casters %d | precise collisions %d"):format(
			report.transparentParts,
			report.glassParts,
			report.neonParts,
			report.unanchoredParts,
			report.touchParts,
			report.smallShadowCasters,
			report.preciseCollisions
		),
		("lights %d (shadowed %d) | emitters %d, particle budget %d | beams/trails %d | world GUIs %d"):format(
			report.lights,
			report.shadowLights,
			report.emitters,
			math.floor(report.particleBudget),
			report.beamsAndTrails,
			report.guis3D
		),
		("humanoids %d | sounds %d (looped %d) | scripts %d"):format(
			report.humanoids,
			report.sounds,
			report.loopedSounds,
			report.scripts
		),
	}
	local materials = {}
	for name, count in report.materials do
		table.insert(materials, { name = name, count = count })
	end
	table.sort(materials, function(a, b)
		return a.count > b.count
	end)
	local top = {}
	for index = 1, math.min(8, #materials) do
		table.insert(top, ("%s %d"):format(materials[index].name, materials[index].count))
	end
	if #top > 0 then
		table.insert(lines, "materials: " .. table.concat(top, ", "))
	end
	if #report.findings == 0 then
		table.insert(lines, "within budget")
	else
		for _, finding in report.findings do
			table.insert(lines, "! " .. finding)
		end
	end
	return table.concat(lines, "\n")
end

return SceneAudit
