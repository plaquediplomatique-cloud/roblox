--!strict
--[[
	TransitionController — transitions plein écran (signature visuelle du jeu).

	Un seul overlay, réutilisé partout : match trouvé, entrée/sortie d'arène, retour au
	lobby, téléportation. Séquence "cover" : lamelles cyan qui balaient l'écran, noir,
	logo glitché + statut ; séquence "reveal" : l'inverse. Les appels sont sérialisés
	(jeton) : une transition plus récente annule proprement la précédente.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)

local colors = Theme.colors
local fonts = Theme.fonts

local TransitionController = {}

local gui: ScreenGui
local backdrop: Frame
local slats: { Frame } = {}
local logo: TextLabel
local status: TextLabel
local progressTrack: Frame
local progressFill: Frame
local covered = false
local token = 0

local SLATS = 7

local function tween(instance: Instance, duration: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	local created = TweenService:Create(instance, info, goals)
	created:Play()
	return created
end

--[[ Recouvre l'écran (bloquant ~0.55 s). `text` : statut affiché sous le logo. ]]
function TransitionController.cover(text: string?)
	token += 1
	local current = token
	gui.Enabled = true
	status.Text = text or ""
	progressTrack.Visible = false
	if covered then
		return
	end
	covered = true
	UI.playSound("UI.Whoosh")
	for index, slat in slats do
		slat.Position = UDim2.new(-1.1, 0, (index - 1) / SLATS, 0)
		slat.BackgroundTransparency = 0
		task.delay((index - 1) * 0.035, function()
			if current == token then
				tween(slat, 0.32, { Position = UDim2.new(0, 0, (index - 1) / SLATS, 0) })
			end
		end)
	end
	backdrop.BackgroundTransparency = 1
	tween(backdrop, 0.45, { BackgroundTransparency = 0 })
	logo.TextTransparency = 1
	status.TextTransparency = 1
	task.wait(0.5)
	if current ~= token then
		return
	end
	logo.TextTransparency = 0
	status.TextTransparency = 0
	UI.glitchText(logo, 0.3)
end

--[[ Progression optionnelle (chargement d'arène, téléportation). ]]
function TransitionController.setProgress(fraction: number?, text: string?)
	if text then
		status.Text = text
	end
	progressTrack.Visible = fraction ~= nil
	if fraction then
		progressFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end
end

--[[ Révèle le jeu (non bloquant). ]]
function TransitionController.reveal()
	token += 1
	local current = token
	if not covered then
		gui.Enabled = false
		return
	end
	covered = false
	tween(logo, 0.25, { TextTransparency = 1 })
	tween(status, 0.25, { TextTransparency = 1 })
	tween(backdrop, 0.5, { BackgroundTransparency = 1 })
	for index, slat in slats do
		task.delay((index - 1) * 0.03, function()
			if current == token then
				tween(slat, 0.35, { Position = UDim2.new(1.1, 0, (index - 1) / SLATS, 0) })
			end
		end)
	end
	task.delay(0.7, function()
		if current == token then
			gui.Enabled = false
		end
	end)
end

function TransitionController.isCovered(): boolean
	return covered
end

--[[ Flash bref (apparition, début de manche) : noir -> jeu en 0.35 s. ]]
function TransitionController.blink()
	if covered then
		return
	end
	gui.Enabled = true
	backdrop.BackgroundTransparency = 0
	for _, slat in slats do
		slat.BackgroundTransparency = 1
	end
	logo.TextTransparency = 1
	status.TextTransparency = 1
	progressTrack.Visible = false
	token += 1
	local current = token
	tween(backdrop, 0.35, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(0.4, function()
		if current == token and not covered then
			gui.Enabled = false
		end
	end)
end

function TransitionController.start()
	gui = UI.screen("AS_Transition", 100)
	gui.Enabled = false
	backdrop = UI.frame({
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = gui,
	})
	for index = 1, SLATS do
		local slat = UI.frame({
			BackgroundColor3 = if index % 2 == 0 then colors.panel else colors.background,
			Position = UDim2.new(-1.1, 0, (index - 1) / SLATS, 0),
			Size = UDim2.new(1, 0, 1 / SLATS, 1),
			ZIndex = 2,
			Parent = gui,
		})
		UI.frame({
			BackgroundColor3 = colors.primary,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 3, 1, 0),
			ZIndex = 3,
			Parent = slat,
		})
		table.insert(slats, slat)
	end
	logo = UI.text({
		Text = "AETHER STRIKE",
		FontFace = fonts.display,
		TextSize = 54,
		TextColor3 = colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(900, 64),
		TextTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	UI.gradient(logo, ColorSequence.new(colors.text, colors.primary), 0)
	status = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 18,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 52),
		Size = UDim2.fromOffset(900, 24),
		TextTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	progressTrack = UI.frame({
		BackgroundColor3 = colors.panelLight,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 84),
		Size = UDim2.fromOffset(360, 3),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	progressFill = UI.frame({
		BackgroundColor3 = colors.primary,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 6,
		Parent = progressTrack,
	})
end

return TransitionController
