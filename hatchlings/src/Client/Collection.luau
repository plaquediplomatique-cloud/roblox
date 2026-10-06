--!strict
--[[
	Collection — barre d'index en bas de l'écran : une case par pet du catalogue. Les pets
	découverts s'affichent en 3D avec le contour de leur rareté, les autres restent « ? ».
	Source de vérité : l'attribut `Discovered` du joueur (écrit par le serveur).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Rarities = require(Shared.Config.Rarities)
local Theme = require(Shared.Config.Theme)
local PetPreview = require(script.Parent.PetPreview)
local UIKit = require(script.Parent.UIKit)

local localPlayer = Players.LocalPlayer

local Collection = {}

function Collection.start(gui: ScreenGui)
	local bar = UIKit.panel(gui)
	bar.Name = "Collection"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(#Pets.list * 62 + 28, 98)

	local counter = UIKit.label(bar, "", 18, Theme.colors.inkSoft)
	counter.Size = UDim2.new(1, 0, 0, 20)
	counter.Position = UDim2.fromOffset(0, 5)

	local layout = Instance.new("Frame")
	layout.BackgroundTransparency = 1
	layout.Size = UDim2.new(1, -20, 0, 60)
	layout.Position = UDim2.fromOffset(10, 30)
	layout.Parent = bar
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 4)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = layout

	local cells: { [string]: { frame: Frame, shown: boolean } } = {}
	for index, def in Pets.list do
		local cell = Instance.new("Frame")
		cell.LayoutOrder = index
		cell.Size = UDim2.fromOffset(58, 58)
		cell.BackgroundColor3 = Theme.colors.cream
		cell.BorderSizePixel = 0
		cell.Parent = layout
		UIKit.corner(cell, 12)
		UIKit.stroke(cell, Theme.colors.inkSoft, 2)
		local unknown = UIKit.label(cell, "?", 28, Theme.colors.inkSoft)
		unknown.Name = "Unknown"
		unknown.Size = UDim2.fromScale(1, 1)
		cells[def.id] = { frame = cell, shown = false }
	end

	local function refresh()
		local raw = localPlayer:GetAttribute(Net.discoveredAttribute)
		local found: { [string]: boolean } = {}
		local count = 0
		if type(raw) == "string" then
			for id in string.gmatch(raw, "[^,]+") do
				found[id] = true
				count += 1
			end
		end
		for id, cell in cells do
			if found[id] and not cell.shown then
				cell.shown = true
				local def = Pets.byId[id]
				local unknown = cell.frame:FindFirstChild("Unknown")
				if unknown then
					unknown:Destroy()
				end
				local stroke = cell.frame:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = Rarities.info[def.rarity].color
					stroke.Thickness = 4
				end
				PetPreview.create(cell.frame, def)
			end
		end
		counter.Text = string.format("Pets  %d / %d", count, #Pets.list)
	end

	localPlayer:GetAttributeChangedSignal(Net.discoveredAttribute):Connect(refresh)
	refresh()
end

return Collection
