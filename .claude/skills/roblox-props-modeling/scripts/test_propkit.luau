--[[
	Checks every PropKit builder in every style:
	  * grounded at y = 0, footprint attribute matches the real bounds (±10 %),
	  * all parts anchored, positive sizes, CanTouch off,
	  * visual parts never collide; collision only through "Collider" parts (or a door Leaf),
	  * no shadows from tiny parts, deterministic output for the same parameters.

	  lune run .claude/skills/roblox-props-modeling/scripts/test_propkit.luau
]]

local process = require("@lune/process")
local LuneEnv = require("./lune_env")

local PropKit = LuneEnv.loadPropKit()
local failures = {}
local checks = 0

local function check(condition: boolean, message: string)
	checks += 1
	if not condition then
		table.insert(failures, message)
	end
end

local function signature(model: any): string
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local p = descendant.CFrame.Position
			table.insert(parts, ("%s:%.3f,%.3f,%.3f"):format(descendant.Name, p.X, p.Y, p.Z))
		end
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

for kind, build in PropKit.builders do
	for styleName, style in PropKit.styles do
		local label = kind .. "/" .. styleName
		local model = build({ style = style, upper = true, sittable = true })
		check(model:GetAttribute("PropKit") == kind, label .. ": PropKit attribute")
		local footprint = model:GetAttribute("Footprint")
		check(footprint ~= nil, label .. ": Footprint attribute")
		local minV, maxV = LuneEnv.bounds(model)
		local size = maxV - minV
		check(math.abs(minV.Y) < 0.02, ("%s: grounded (min y = %.3f)"):format(label, minV.Y))
		if footprint then
			for _, axis in { "X", "Y", "Z" } do
				local expected, actual = footprint[axis], size[axis]
				check(
					actual <= expected * 1.1 + 0.25 and actual >= expected * 0.85,
					("%s: footprint %s expected %.2f, bounds %.2f"):format(label, axis, expected, actual)
				)
			end
		end
		local colliders = 0
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				local name = descendant.Name
				check(descendant.Anchored == true, label .. ": " .. name .. " anchored")
				check(
					descendant.Size.X > 0 and descendant.Size.Y > 0 and descendant.Size.Z > 0,
					label .. ": " .. name .. " size"
				)
				if descendant.ClassName ~= "Seat" then
					check(descendant.CanTouch == false, label .. ": " .. name .. " CanTouch off")
				end
				local isCollider = name == "Collider" or name == "Leaf"
				if isCollider then
					colliders += 1
				else
					check(descendant.CanCollide == false, label .. ": visual part " .. name .. " must not collide")
				end
				local longest = math.max(descendant.Size.X, descendant.Size.Y, descendant.Size.Z)
				if longest <= 1 then
					check(descendant.CastShadow == false, label .. ": tiny part " .. name .. " casts no shadow")
				end
			end
		end
		check(colliders >= 1, label .. ": has a collider")
		local again = build({ style = style, upper = true, sittable = true })
		check(signature(model) == signature(again), label .. ": deterministic")
	end
end

if #failures > 0 then
	for _, failure in failures do
		print("FAIL " .. failure)
	end
	print(("%d/%d checks failed"):format(#failures, checks))
	process.exit(1)
end
print(("PropKit: %d checks passed"):format(checks))
