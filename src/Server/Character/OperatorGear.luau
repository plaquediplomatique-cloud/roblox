--!strict
--[[
	OperatorGear — équipement procédural de l'opérateur (casque, visière, gilet, épaulières,
	module dorsal), coloré par la tenue cosmétique équipée.

	Contraintes compétitives : les pièces sont Massless, non collidables, non
	"queryables" (les raycasts les ignorent) et ne débordent quasiment pas de la
	silhouette R15 — un cosmétique ne doit JAMAIS cacher ou grossir une hitbox perçue.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)

local OperatorGear = {}

local function weldPiece(
	character: Model,
	bodyPartName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
): BasePart?
	local body = character:FindFirstChild(bodyPartName)
	if not (body and body:IsA("BasePart")) then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "Gear_" .. name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.CFrame = body.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character
	return part
end

function OperatorGear.bodyColors(description: HumanoidDescription, palette: Types.Palette)
	description.HeadColor = palette.Grip
	description.TorsoColor = palette.Base
	description.LeftArmColor = palette.Base
	description.RightArmColor = palette.Base
	description.LeftLegColor = palette.Secondary
	description.RightLegColor = palette.Secondary
end

function OperatorGear.attach(character: Model, item: Types.ItemDef?)
	local palette = item and item.palette
	if not palette then
		return
	end
	-- Casque + visière néon
	weldPiece(
		character,
		"Head",
		"Helmet",
		Vector3.new(1.32, 0.55, 1.32),
		CFrame.new(0, 0.42, 0.04),
		palette.Base,
		Enum.Material.Metal
	)
	local visor = weldPiece(
		character,
		"Head",
		"Visor",
		Vector3.new(1.12, 0.22, 0.12),
		CFrame.new(0, 0.08, -0.6),
		palette.Neon,
		Enum.Material.Neon
	)
	if visor then
		visor:SetAttribute("NeonRole", true)
	end
	-- Gilet + bande néon
	weldPiece(
		character,
		"UpperTorso",
		"Vest",
		Vector3.new(2.1, 1.25, 1.18),
		CFrame.new(0, 0.05, 0),
		palette.Secondary,
		Enum.Material.SmoothPlastic
	)
	local stripe = weldPiece(
		character,
		"UpperTorso",
		"VestStripe",
		Vector3.new(2.12, 0.1, 1.2),
		CFrame.new(0, -0.32, 0),
		palette.Neon,
		Enum.Material.Neon
	)
	if stripe then
		stripe:SetAttribute("NeonRole", true)
	end
	-- Épaulières
	weldPiece(
		character,
		"LeftUpperArm",
		"PadL",
		Vector3.new(1.05, 0.38, 1.05),
		CFrame.new(0, 0.42, 0),
		palette.Accent,
		Enum.Material.Metal
	)
	weldPiece(
		character,
		"RightUpperArm",
		"PadR",
		Vector3.new(1.05, 0.38, 1.05),
		CFrame.new(0, 0.42, 0),
		palette.Accent,
		Enum.Material.Metal
	)
	-- Module dorsal (accueille la charge Uplink pour le porteur)
	weldPiece(
		character,
		"UpperTorso",
		"Pack",
		Vector3.new(1.3, 1.0, 0.45),
		CFrame.new(0, 0.05, 0.78),
		palette.Metal,
		Enum.Material.Metal
	)
	-- Genouillères
	weldPiece(
		character,
		"LeftLowerLeg",
		"KneeL",
		Vector3.new(0.62, 0.5, 0.4),
		CFrame.new(0, 0.25, -0.32),
		palette.Accent,
		Enum.Material.Metal
	)
	weldPiece(
		character,
		"RightLowerLeg",
		"KneeR",
		Vector3.new(0.62, 0.5, 0.4),
		CFrame.new(0, 0.25, -0.32),
		palette.Accent,
		Enum.Material.Metal
	)
end

return OperatorGear
