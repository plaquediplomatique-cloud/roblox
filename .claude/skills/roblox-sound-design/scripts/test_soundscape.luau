--[[
	Lune tests for the pure parts of SoundscapeKit (zone lookup, stem weights).
	  lune run .claude/skills/roblox-sound-design/scripts/test_soundscape.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local path = ".claude/skills/roblox-sound-design/scripts/SoundscapeKit.luau"
if not fs.isFile(path) then
	path = "SoundscapeKit.luau"
end

-- The module only touches services inside start(); a stub `game` is enough to load it.
local stubGame = {
	GetService = function(_self, name)
		return { Name = name }
	end,
}
local SoundscapeKit = luau.load(fs.readFile(path), {
	debugName = path,
	environment = {
		game = stubGame,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		Random = roblox.Random,
	},
})()

local failures, checks = 0, 0
local function check(condition: boolean, label: string)
	checks += 1
	if not condition then
		failures += 1
		print("FAIL " .. label)
	end
end

local folder = roblox.Instance.new("Folder")
local function zone(name: string, center, size, priority: number?)
	local part = roblox.Instance.new("Part")
	part.Name = name
	part.CFrame = roblox.CFrame.new(center)
	part.Size = size
	part:SetAttribute("Ambience", name)
	if priority then
		part:SetAttribute("Priority", priority)
	end
	part.Parent = folder
	return part
end

local street = zone("Street", roblox.Vector3.new(0, 10, 0), roblox.Vector3.new(200, 40, 200))
local room = zone("Interior", roblox.Vector3.new(20, 6, 20), roblox.Vector3.new(16, 12, 16), 5)
local rotated = zone("Tunnel", roblox.Vector3.new(-60, 4, -60), roblox.Vector3.new(40, 8, 6), 2)
rotated.CFrame = roblox.CFrame.new(roblox.Vector3.new(-60, 4, -60)) * roblox.CFrame.Angles(0, math.rad(90), 0)

check(SoundscapeKit.zoneAt(folder, roblox.Vector3.new(0, 5, 0)) == street, "street contains origin")
check(SoundscapeKit.zoneAt(folder, roblox.Vector3.new(20, 5, 20)) == room, "room wins by priority")
check(SoundscapeKit.zoneAt(folder, roblox.Vector3.new(500, 5, 0)) == nil, "outside every zone")
check(SoundscapeKit.zoneAt(folder, roblox.Vector3.new(-60, 4, -45)) == rotated, "rotated box: long axis now along Z")
check(SoundscapeKit.zoneAt(folder, roblox.Vector3.new(-45, 4, -60)) == street, "rotated box: short axis now along X")

check(SoundscapeKit.stemWeight(0, 0) == 1, "base stem audible at rest")
check(SoundscapeKit.stemWeight(0.3, 0.6) == 0, "combat stem silent at low intensity")
check(math.abs(SoundscapeKit.stemWeight(0.5, 0.6) - 0.5) < 1e-6, "combat stem half-way in its fade edge")
check(SoundscapeKit.stemWeight(0.9, 0.6) == 1, "combat stem full above threshold")

print(("SoundscapeKit: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("tests failed")
end
