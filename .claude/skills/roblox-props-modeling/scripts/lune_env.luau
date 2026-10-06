--[[
	Loads PropKit.luau outside Roblox (Lune), exposing the same globals Studio provides.
	Usage from another Lune script:
		local PropKit = require("./lune_env").loadPropKit()
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local LuneEnv = {}

local CANDIDATES = {
	".claude/skills/roblox-props-modeling/scripts/PropKit.luau",
	"scripts/PropKit.luau",
	"PropKit.luau",
}

function LuneEnv.findPropKit(): string
	for _, path in CANDIDATES do
		if fs.isFile(path) then
			return path
		end
	end
	error("PropKit.luau not found: run from the repository root or from the skill directory")
end

function LuneEnv.loadPropKit(): any
	local path = LuneEnv.findPropKit()
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
		},
	})
	return chunk()
end

-- Moves every BasePart (and the pivot) of a model by `offset`, like Model:PivotTo would.
function LuneEnv.translate(model: any, offset: any)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = offset * descendant.CFrame
		end
	end
	model.WorldPivot = offset * model.WorldPivot
end

-- Axis-aligned bounds of a model's BaseParts (handles rotated parts via their 8 corners).
function LuneEnv.bounds(model: any): (any, any)
	local Vector3 = roblox.Vector3
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local half = descendant.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = descendant.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						minV = minV:Min(corner)
						maxV = maxV:Max(corner)
					end
				end
			end
		end
	end
	return minV, maxV
end

return LuneEnv
