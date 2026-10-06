--!strict
--[[
	LoadingScreen — écran de chargement AUTONOME (aucun require : il s'affiche avant que
	ReplicatedStorage ne soit disponible).

	Utilisé à trois moments :
	  * démarrage du client (ReplicatedFirst/Boot) ;
	  * téléportation lobby -> serveur de match et retour : la même interface est
	    passée à TeleportService:SetTeleportGui, puis récupérée à l'arrivée par
	    GetArrivingTeleportGui -> transition sans couture entre deux serveurs.
	Identité "dark cyber" : grille, logo à dégradé, barre de progression, astuces.
]]

local TweenService = game:GetService("TweenService")

local LoadingScreen = {}

local VOID = Color3.fromRGB(5, 7, 10)
local CYAN = Color3.fromRGB(61, 225, 255)
local TEXT = Color3.fromRGB(230, 237, 243)
local DIM = Color3.fromRGB(125, 139, 153)
local STROKE = Color3.fromRGB(36, 48, 62)

local TIPS = {
	"Contre-strafe : appuyez sur la direction opposée pour retrouver la précision en 70 ms.",
	"Une caisse standard de 4 studs cache entièrement un joueur accroupi.",
	"La marche (Maj) est silencieuse : vos pas trahissent votre position.",
	"Rechargement tactique : recharger avant d'être à sec garde une cartouche chambrée (+1).",
	"Le VK-12 tue en une balle dans la tête, à toute distance, même à travers un bouclier.",
	"Glissade + saut conserve 85 % de votre élan : idéal pour traverser une ligne de tir.",
	"Les murs fins (verre, bois, tôle) se traversent : les dégâts diminuent selon le matériau.",
	"Le réticule dynamique montre la dispersion RÉELLE : quand il s'ouvre, vos balles aussi.",
	"En défense, la moitié d'un désamorçage est conservée si vous êtes interrompu.",
	"Les tirs lointains ont une sonorité distincte : écoutez où se battent les autres.",
}

export type Controller = {
	gui: ScreenGui,
	setStatus: (text: string) -> (),
	setProgress: (fraction: number) -> (),
	finish: (done: (() -> ())?) -> (),
}

local function label(
	parent: Instance,
	text: string,
	font: Enum.Font,
	size: number,
	color: Color3,
	position: UDim2
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = position
	item.Size = UDim2.new(1, 0, 0, size + 10)
	item.FontFace = Font.fromEnum(font)
	item.TextSize = size
	item.TextColor3 = color
	item.Text = text
	item.Parent = parent
	return item
end

--[[ Construit l'interface (non parentée). `status` : texte initial. ]]
function LoadingScreen.create(status: string?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "AS_Loading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.BorderSizePixel = 0
	background.BackgroundColor3 = VOID
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = gui

	-- Grille discrète (lignes horizontales + verticales)
	for index = 1, 11 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = STROKE
		line.BackgroundTransparency = 0.55
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.fromScale(0, index / 12)
		line.Parent = background
	end
	for index = 1, 19 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = STROKE
		line.BackgroundTransparency = 0.7
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.fromScale(index / 20, 0)
		line.Parent = background
	end
	local vignette = Instance.new("Frame")
	vignette.BorderSizePixel = 0
	vignette.BackgroundColor3 = VOID
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.Parent = background
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	fade.Rotation = 90
	fade.Parent = vignette

	local logo = label(background, "AETHER STRIKE", Enum.Font.Michroma, 64, TEXT, UDim2.fromScale(0.5, 0.42))
	logo.Name = "Logo"
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(TEXT, CYAN)
	gradient.Parent = logo
	local tagline = label(
		background,
		"TACTIQUE  ·  COMPÉTITIF  ·  1v1  2v2  3v3",
		Enum.Font.Sarpanch,
		18,
		DIM,
		UDim2.new(0.5, 0, 0.42, 50)
	)
	tagline.Name = "Tagline"

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BorderSizePixel = 0
	track.BackgroundColor3 = STROKE
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.new(0.5, 0, 0.42, 96)
	track.Size = UDim2.fromOffset(420, 3)
	track.Parent = background
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = CYAN
	fill.Size = UDim2.fromScale(0.04, 1)
	fill.Parent = track

	local statusLabel =
		label(background, status or "INITIALISATION", Enum.Font.RobotoMono, 16, CYAN, UDim2.new(0.5, 0, 0.42, 120))
	statusLabel.Name = "Status"
	local tip =
		label(background, TIPS[math.random(1, #TIPS)], Enum.Font.TitilliumWeb, 18, DIM, UDim2.new(0.5, 0, 1, -60))
	tip.Name = "Tip"
	tip.TextWrapped = true
	tip.Size = UDim2.new(0.8, 0, 0, 50)
	return gui
end

--[[ Anime une interface créée par `create` (ou récupérée après téléportation). ]]
function LoadingScreen.animate(gui: ScreenGui): Controller
	local background = gui:FindFirstChild("Background") :: Frame
	local logo = background:FindFirstChild("Logo") :: TextLabel
	local status = background:FindFirstChild("Status") :: TextLabel
	local tip = background:FindFirstChild("Tip") :: TextLabel
	local track = background:FindFirstChild("Track") :: Frame
	local fill = track:FindFirstChild("Fill") :: Frame
	local alive = true
	local base = logo.Position

	task.spawn(function()
		local tipIndex = math.random(1, #TIPS)
		local lastTip = os.clock()
		while alive and gui.Parent do
			-- Glitch du logo, rare et bref.
			if math.random() < 0.06 then
				for _ = 1, 4 do
					logo.Position = base + UDim2.fromOffset(math.random(-5, 5), math.random(-2, 2))
					logo.TextTransparency = if math.random() < 0.3 then 0.5 else 0
					task.wait(0.03)
				end
				logo.Position = base
				logo.TextTransparency = 0
			end
			if os.clock() - lastTip > 5 then
				lastTip = os.clock()
				tipIndex = tipIndex % #TIPS + 1
				tip.Text = TIPS[tipIndex]
			end
			task.wait(0.08)
		end
	end)

	local controller: Controller = {
		gui = gui,
		setStatus = function(text: string)
			status.Text = text
		end,
		setProgress = function(fraction: number)
			TweenService:Create(
				fill,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad),
				{ Size = UDim2.fromScale(math.clamp(fraction, 0.04, 1), 1) }
			):Play()
		end,
		finish = function(done: (() -> ())?)
			alive = false
			local info = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			for _, descendant in gui:GetDescendants() do
				if descendant:IsA("TextLabel") then
					TweenService:Create(descendant, info, { TextTransparency = 1 }):Play()
				elseif descendant:IsA("Frame") then
					TweenService:Create(descendant, info, { BackgroundTransparency = 1 }):Play()
				end
			end
			task.delay(0.65, function()
				gui:Destroy()
				if done then
					done()
				end
			end)
		end,
	}
	return controller
end

return LoadingScreen
