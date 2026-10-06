--!strict
--[[
	WeaponView — aperçu 3D tournant d'une arme dans un ViewportFrame (popup de déblocage, menu
	d'armes). Une seule boucle RenderStepped partagée, active uniquement tant qu'un aperçu existe.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Builder = require(Shared.Assets.Builder)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)

local WeaponView = {}

type View = { Model: Model, Angle: number, Frame: ViewportFrame, Center: Vector3 }

local views: { [ViewportFrame]: View } = {}
local connection: RBXScriptConnection? = nil

local function stopIfEmpty()
	if next(views) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureLoop()
	if connection then
		return
	end
	connection = RunService.RenderStepped:Connect(function(dt: number)
		for frame, view in views do
			if not frame.Parent then
				views[frame] = nil
			elseif frame.Visible then
				view.Angle += dt * 1.4
				view.Model:PivotTo(CFrame.new(view.Center) * CFrame.Angles(0, view.Angle, math.rad(-18)))
			end
		end
		stopIfEmpty()
	end)
end

-- Crée l'aperçu dans `parent`. Renvoie le ViewportFrame (détruire le frame suffit à tout libérer).
function WeaponView.create(parent: Instance, weapon: WeaponCatalog.Weapon, size: UDim2): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = size
	frame.Ambient = Color3.fromRGB(190, 190, 205)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.LightDirection = Vector3.new(-1, -1.2, -0.8)
	local model = Builder.weapon(weapon, { Fx = false, Anchored = true })
	local extents = model:GetExtentsSize()
	local longest = math.max(extents.X, extents.Y, extents.Z)
	local center = Vector3.new(0, 0, 0)
	model:PivotTo(CFrame.new(center))
	model.Parent = frame
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, longest * 1.55), center)
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent
	views[frame] = { Model = model, Angle = 0, Frame = frame, Center = center }
	ensureLoop()
	return frame
end

return WeaponView
