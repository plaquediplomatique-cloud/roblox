--!strict
--[[
	Écran de chargement : s'affiche dès l'entrée dans le jeu, disparaît quand le serveur a envoyé
	le profil (attribut `Ready` posé par le client une fois le Store prêt) ou après 25 s.
	Aucune dépendance au reste du code : il doit pouvoir apparaître avant tout.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(28, 30, 48)
background.BorderSizePixel = 0
background.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new(Color3.fromRGB(44, 48, 90), Color3.fromRGB(20, 22, 36))
gradient.Rotation = 90
gradient.Parent = background

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.fromOffset(700, 90)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.Text = "SMASH ASCENSION"
title.TextSize = 64
title.TextColor3 = Color3.fromRGB(255, 205, 70)
title.TextStrokeTransparency = 0.2
title.Parent = background

local tip = Instance.new("TextLabel")
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Position = UDim2.fromScale(0.5, 0.56)
tip.Size = UDim2.fromOffset(700, 30)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamMedium
tip.Text = "Hit the dummy. Level up. Unlock the next weapon."
tip.TextSize = 20
tip.TextColor3 = Color3.fromRGB(184, 192, 224)
tip.Parent = background

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.66)
barBack.Size = UDim2.fromOffset(360, 14)
barBack.BackgroundColor3 = Color3.fromRGB(44, 48, 74)
barBack.BorderSizePixel = 0
barBack.Parent = background
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0.05, 1)
fill.BackgroundColor3 = Color3.fromRGB(88, 214, 255)
fill.BorderSizePixel = 0
fill.Parent = barBack
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

TweenService
	:Create(
		fill,
		TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(0.92, 1) }
	)
	:Play()

local function finish()
	TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 1) }):Play()
	task.wait(0.25)
	local fade = TweenInfo.new(0.5)
	TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(tip, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(barBack, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(fill, fade, { BackgroundTransparency = 1 }):Play()
	task.wait(0.55)
	gui:Destroy()
end

-- Le HUD (créé quand le profil est reçu) signale la fin du chargement.
local deadline = os.clock() + 25
while os.clock() < deadline do
	if playerGui:FindFirstChild("Hud") then
		break
	end
	task.wait(0.1)
end
finish()
