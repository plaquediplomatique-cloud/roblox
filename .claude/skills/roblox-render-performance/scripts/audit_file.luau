--[[
	Runs SceneAudit on a place (.rbxl) or model (.rbxm) file outside Studio, with Lune.

	  lune run .claude/skills/roblox-render-performance/scripts/audit_file.luau <file> [Mobile|Desktop] [Instance.Path]

	Examples:
	  lune run …/audit_file.luau build/props/PropKit_Showroom.rbxm
	  lune run …/audit_file.luau build/AetherStrike.rbxl Desktop Workspace
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local file = process.args[1]
if not file then
	print("usage: lune run audit_file.luau <file.rbxl|file.rbxm> [Mobile|Desktop] [Path.To.Instance]")
	process.exit(2)
end

local candidates = {
	".claude/skills/roblox-render-performance/scripts/SceneAudit.luau",
	"scripts/SceneAudit.luau",
	"SceneAudit.luau",
}
local auditPath
for _, path in candidates do
	if fs.isFile(path) then
		auditPath = path
		break
	end
end
assert(auditPath, "SceneAudit.luau not found: run from the repository root or the skill directory")

local SceneAudit = luau.load(fs.readFile(auditPath), {
	debugName = auditPath,
	environment = {
		Vector3 = roblox.Vector3,
		NumberRange = roblox.NumberRange,
		Enum = roblox.Enum,
	},
})()

local root
if string.sub(file, -5) == ".rbxl" then
	root = roblox.deserializePlace(fs.readFile(file))
else
	local model = roblox.Instance.new("Folder")
	model.Name = file
	for _, child in roblox.deserializeModel(fs.readFile(file)) do
		child.Parent = model
	end
	root = model
end

local path = process.args[3]
if path then
	for segment in string.gmatch(path, "[^%.]+") do
		local child = root:FindFirstChild(segment)
		assert(child, "no child '" .. segment .. "' under " .. root:GetFullName())
		root = child
	end
end

local budget = SceneAudit.budgets[process.args[2] or "Mobile"]
assert(budget, "budget must be Mobile or Desktop")
print(SceneAudit.format(SceneAudit.run(root, budget)))
