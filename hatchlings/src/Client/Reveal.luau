--!strict
--[[
	Reveal — écran de révélation d'un pet qui vient d'éclore (carte qui rebondit, aperçu 3D
	qui tourne, bandeau de rareté), plus une bannière discrète quand un autre joueur sort un
	pet Epic ou Legendary (la rareté `announce` de Config/Rarities).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Pets = require(Shared.Config.Pets)
local Rarities = require(Shared.Config.Rarities)
local Theme = require(Shared.Config.Theme)
local PetPreview = require(script.Parent.PetPreview)
local UIKit = require(script.Parent.UIKit)

local localPlayer = Players.LocalPlayer
local MIN_SHOW_SECONDS = 0.7

local Reveal = {}

local current: TextButton? = nil

local function showCard(gui: ScreenGui, def: Pets.PetDef, isNew: boolean)
	if current then
		current:Destroy()
	end
	local rarity = Rarities.info[def.rarity]

	local dim = Instance.new("TextButton")
	dim.Name = "Reveal"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.BackgroundColor3 = Theme.colors.ink
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = gui
	current = dim
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()

	local card = UIKit.panel(dim)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(0, 0)
	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	if cardStroke then
		cardStroke.Color = rarity.color
		cardStroke.Thickness = 6
	end
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(340, 420),
	}):Play()

	local banner = UIKit.label(card, string.upper(rarity.name), 30, Theme.colors.white)
	banner.BackgroundTransparency = 0
	banner.BackgroundColor3 = rarity.color
	banner.Size = UDim2.new(1, -24, 0, 46)
	banner.Position = UDim2.fromOffset(12, 12)
	UIKit.corner(banner, 14)

	local stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.new(1, -24, 0, 230)
	stage.Position = UDim2.fromOffset(12, 66)
	stage.Parent = card
	local _, step = PetPreview.create(stage, def)

	local name = UIKit.label(card, def.name, 34)
	name.Size = UDim2.new(1, 0, 0, 40)
	name.Position = UDim2.fromOffset(0, 302)

	local note = UIKit.label(
		card,
		if isNew then "NEW! Added to your collection" else "Already in your collection",
		18,
		if isNew then Theme.colors.berry else Theme.colors.inkSoft
	)
	note.Size = UDim2.new(1, 0, 0, 24)
	note.Position = UDim2.fromOffset(0, 346)

	local hint = UIKit.label(card, "Tap to continue", 16, Theme.colors.inkSoft)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.Position = UDim2.fromOffset(0, 380)

	local opened = os.clock()
	local connection = RunService.RenderStepped:Connect(step)
	dim.Activated:Connect(function()
		if os.clock() - opened < MIN_SHOW_SECONDS then
			return
		end
		connection:Disconnect()
		TweenService:Create(card, TweenInfo.new(0.2), { Size = UDim2.fromOffset(0, 0) }):Play()
		TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.delay(0.22, function()
			dim:Destroy()
		end)
		if current == dim then
			current = nil
		end
	end)
end

local function showToast(gui: ScreenGui, ownerName: string, def: Pets.PetDef)
	local rarity = Rarities.info[def.rarity]
	local toast = UIKit.panel(gui)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, -80)
	toast.Size = UDim2.fromOffset(420, 52)
	local toastStroke = toast:FindFirstChildOfClass("UIStroke")
	if toastStroke then
		toastStroke.Color = rarity.color
	end
	local text = UIKit.label(toast, string.format("%s hatched a %s %s!", ownerName, rarity.name, def.name), 20)
	text.Size = UDim2.fromScale(1, 1)
	TweenService:Create(toast, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 18) })
		:Play()
	task.delay(3.5, function()
		TweenService:Create(toast, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -80) }):Play()
		task.delay(0.35, function()
			toast:Destroy()
		end)
	end)
end

function Reveal.start(gui: ScreenGui)
	local folder = Shared.Parent:WaitForChild(Net.folderName)
	local remote = folder:WaitForChild(Net.petHatched) :: RemoteEvent
	remote.OnClientEvent:Connect(function(ownerName: string, ownerUserId: number, petId: string, isNew: boolean)
		local def = Pets.byId[petId]
		if not def then
			return
		end
		if ownerUserId == localPlayer.UserId then
			showCard(gui, def, isNew)
		elseif Rarities.info[def.rarity].announce then
			showToast(gui, ownerName, def)
		end
	end)
end

return Reveal
