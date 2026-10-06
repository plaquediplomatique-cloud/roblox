--!strict
--[[
	PetPreview — ViewportFrame montrant un pet (modèle construit par PetFactory).
	`spin = true` renvoie un `step(dt)` à appeler à chaque frame pour le faire tourner.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PetFactory = require(Shared.PetFactory)
local Pets = require(Shared.Config.Pets)

local PetPreview = {}

function PetPreview.create(parent: Instance, def: Pets.PetDef): (ViewportFrame, (dt: number) -> ())
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(190, 180, 200)
	viewport.LightColor = Color3.fromRGB(255, 240, 225)
	viewport.Parent = parent

	local model = PetFactory.build(def)
	model:PivotTo(CFrame.new(0, 0, 0))
	model.Parent = viewport

	local s = def.size
	local center = Vector3.new(0, 0.9 * s, 0)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(center + Vector3.new(3.2, 1.6, -9) * s, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local angle = math.rad(-25)
	local function step(dt: number)
		angle += dt * 1.1
		model:PivotTo(CFrame.Angles(0, angle, 0))
	end
	model:PivotTo(CFrame.Angles(0, angle, 0))
	return viewport, step
end

return PetPreview
