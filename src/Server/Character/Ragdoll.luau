--!strict
--[[
	Ragdoll — chute physique à la mort (côté serveur, répliquée à tous).

	Chaque Motor6D est remplacé par une BallSocketConstraint bornée (pas de membres
	désarticulés) ; la propriété réseau passe au serveur pour que tous les clients voient
	la même chute. Les pièces ne collisionnent plus avec les joueurs vivants (pas de
	cadavre-obstacle exploitable) mais restent sur le sol.
]]

local Ragdoll = {}

local LIMITS: { [string]: { upper: number, twist: number } } = {
	Neck = { upper = 35, twist = 30 },
	Waist = { upper = 25, twist = 20 },
	LeftShoulder = { upper = 85, twist = 60 },
	RightShoulder = { upper = 85, twist = 60 },
	LeftElbow = { upper = 70, twist = 10 },
	RightElbow = { upper = 70, twist = 10 },
	LeftHip = { upper = 60, twist = 30 },
	RightHip = { upper = 60, twist = 30 },
	LeftKnee = { upper = 70, twist = 5 },
	RightKnee = { upper = 70, twist = 5 },
}

function Ragdoll.apply(character: Model)
	if character:GetAttribute("Ragdolled") then
		return
	end
	character:SetAttribute("Ragdolled", true)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name ~= "Root" then
			local motor = descendant :: Motor6D
			local part0, part1 = motor.Part0, motor.Part1
			if part0 and part1 then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagdollA0"
				a0.CFrame = motor.C0
				a0.Parent = part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagdollA1"
				a1.CFrame = motor.C1
				a1.Parent = part1
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				local limits = LIMITS[motor.Name] or { upper = 45, twist = 20 }
				socket.LimitsEnabled = true
				socket.UpperAngle = limits.upper
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -limits.twist
				socket.TwistUpperAngle = limits.twist
				socket.Parent = part1
				motor.Enabled = false
			end
		end
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.CanQuery = false
			if part.Name == "HumanoidRootPart" then
				part.CanCollide = false
			elseif not string.find(part.Name, "^Gear_") then
				part.CanCollide = true
				part.CollisionGroup = "Ragdoll"
			end
			if not part.Anchored then
				pcall(function()
					part:SetNetworkOwner(nil)
				end)
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
	end
end

return Ragdoll
