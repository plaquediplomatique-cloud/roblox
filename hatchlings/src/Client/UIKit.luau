--!strict
--[[
	UIKit — petits constructeurs d'UI « mochi » partagés (cartes arrondies, contours violets).
	Aucune couleur en dur : tout vient de Config/Theme et Config/Rarities.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)

local UIKit = {}

function UIKit.corner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function UIKit.stroke(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIKit.label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color or Theme.colors.ink
	label.Parent = parent
	return label
end

function UIKit.panel(parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.colors.panel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UIKit.corner(frame, 18)
	UIKit.stroke(frame, Theme.colors.ink, 3)
	return frame
end

return UIKit
