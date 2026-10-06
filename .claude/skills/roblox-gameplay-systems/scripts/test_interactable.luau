--[[
	Lune tests for InteractableKit's pure logic (use validation, hinge math) and for the
	hinge visual on a PropKit door.
	  lune run .claude/skills/roblox-gameplay-systems/scripts/test_interactable.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local path = ".claude/skills/roblox-gameplay-systems/scripts/InteractableKit.luau"
local stubGame = {
	GetService = function(_self, name)
		if name == "TweenService" then
			return {
				Create = function(_s, object, _info, goals)
					return {
						Play = function()
							for key, value in goals do
								object[key] = value
							end
						end,
					}
				end,
			}
		end
		return { Name = name }
	end,
}
local Kit = luau.load(fs.readFile(path), {
	debugName = path,
	environment = {
		game = stubGame,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		TweenInfo = {
			new = function()
				return {}
			end,
		},
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
local function near(a, b, epsilon)
	return (a - b).Magnitude < (epsilon or 1e-3)
end

local door = {
	tag = "Door",
	states = { "Closed", "Open" },
	initial = "Closed",
	actionText = function(state)
		return if state == "Open" then "Close" else "Open"
	end,
	maxDistance = 8,
	cooldown = 0.6,
	transition = function(context)
		return if context.state == "Open" then "Closed" else "Open"
	end,
}
local function ctx(state, distance)
	return { player = {}, model = {}, state = state, distance = distance }
end

local d = Kit.decide(door, ctx("Closed", 5), 10, nil)
check(d.ok and d.nextState == "Open", "closed door opens")
check(Kit.decide(door, ctx("Open", 5), 10, nil).nextState == "Closed", "open door closes")
check(Kit.decide(door, ctx("Closed", 11.9), 10, nil).ok, "latency margin accepted")
check(Kit.decide(door, ctx("Closed", 12.5), 10, nil).reason == "TooFar", "too far rejected")
check(Kit.decide(door, ctx("Closed", 5), 10.3, 10).reason == "Cooldown", "cooldown enforced")
check(Kit.decide(door, ctx("Closed", 5), 10.7, 10).ok, "cooldown elapsed")

local locked = table.clone(door)
locked.canUse = function()
	return false, "Locked"
end
check(Kit.decide(locked, ctx("Closed", 5), 10, nil).reason == "Locked", "canUse reason surfaced")
local broken = table.clone(door)
broken.transition = function()
	return "Exploded"
end
check(Kit.decide(broken, ctx("Closed", 5), 10, nil).reason == "UnknownState", "unknown state rejected")

-- Hinge math: a point on the free edge rotates a quarter turn about the hinge.
local hinge = roblox.CFrame.new(-2, 3.5, 0)
local closed = roblox.CFrame.new(2, 3.5, 0)
local opened = Kit.hingeCFrame(closed, hinge, math.rad(90))
check(near(opened.Position, roblox.Vector3.new(-2, 3.5, -4)), "free edge swings to -Z")
check(near(Kit.hingeCFrame(closed, hinge, 0).Position, closed.Position), "zero angle is identity")

-- Hinge visual on a PropKit door.
local env = luau.load(fs.readFile(".claude/skills/roblox-props-modeling/scripts/lune_env.luau"))()
local PropKit = env.loadPropKit()
local model = PropKit.door({ width = 4 })
local leaf = model:FindFirstChild("Leaf")
local closedLeaf = leaf.CFrame
local visual = Kit.hingeVisual({ parts = { "Leaf", "Handle" }, openStates = { "Open" }, angle = 90 })
visual(model, "Closed", nil, true)
check(near(leaf.CFrame.Position, closedLeaf.Position), "closed pose untouched")
visual(model, "Open", "Closed", true)
local hingePoint = closedLeaf * roblox.CFrame.new(-leaf.Size.X / 2, 0, 0)
check(
	near((leaf.CFrame * roblox.CFrame.new(-leaf.Size.X / 2, 0, 0)).Position, hingePoint.Position),
	"hinge edge stays put"
)
check(math.abs(leaf.CFrame.Position.X - hingePoint.Position.X) < 0.2, "leaf rotated perpendicular to the frame")
for _, part in model:GetChildren() do
	if part.Name == "Handle" then
		check((part.CFrame.Position - leaf.CFrame.Position).Magnitude < leaf.Size.X / 2 + 0.5, "handle follows leaf")
	end
end
visual(model, "Closed", "Open", true)
check(near(leaf.CFrame.Position, closedLeaf.Position), "closes back exactly")

print(("InteractableKit: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
	error("tests failed")
end
