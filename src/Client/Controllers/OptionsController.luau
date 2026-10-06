--!strict
--[[
	OptionsController — réglages rapides accessibles partout (hub, entraînement, match).

	* Touche « Options » (P par défaut), bouton engrenage (hub et stand d'entraînement) :
	  fenêtre compacte avec la SENSIBILITÉ en premier (curseur logarithmique, saisie exacte,
	  pas fins − / +), puis visée, champ de vision, volumes et sprint en bascule.
	* « Tous les réglages » ouvre le panneau complet (SettingsPanel) dans la même fenêtre.
	* Ouverte, elle libère la souris et suspend les actions de jeu (ClientState.setOverlay),
	  sans interférer avec les menus du lobby ou du match.
	Chaque valeur passe par SettingsController.update : application immédiate, sauvegarde
	serveur validée (mêmes bornes que Settings.validate).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local SettingsPanel = require(script.Parent.Parent.UI.SettingsPanel)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsController = require(script.Parent.SettingsController)
local InputController = require(script.Parent.InputController)

local colors = Theme.colors
local fonts = Theme.fonts

local OVERLAY = "Options"

local OptionsController = {}

local gui: ScreenGui
local gear: TextButton
local quick: Frame
local quickBody: Frame
local full: Frame
local fullHost: Frame

local function update(mutator: (Types.SettingsData) -> ())
	SettingsController.update(mutator)
end

local function percent(value: number): string
	return string.format("%d %%", math.floor(value * 100 + 0.5))
end

local function keyFor(action: string): string
	return SettingsController.get().Keybinds[action] or "—"
end

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--[[ Contenu reconstruit à chaque ouverture : il reflète toujours les réglages courants. ]]
local function buildQuick()
	clearChildren(quickBody)
	local s = SettingsController.get()
	local order = 0
	local function add(row: Frame)
		order += 1
		row.LayoutOrder = order
		row.Parent = quickBody
	end
	local sensitivity = UI.slider("Sensibilité souris", 0.05, 5, 0.01, s.Controls.Sensitivity, function(v)
		update(function(d)
			d.Controls.Sensitivity = v
		end)
	end, nil, { log = true, editable = true, nudge = 0.01 })
	sensitivity.Size = UDim2.new(1, 0, 0, 46)
	add(sensitivity)
	add(UI.slider("Multiplicateur en visée", 0.2, 2, 0.01, s.Controls.AdsMultiplier, function(v)
		update(function(d)
			d.Controls.AdsMultiplier = v
		end)
	end, nil, { editable = true, nudge = 0.05 }))
	add(UI.slider("Champ de vision", 60, 95, 1, s.Video.Fov, function(v)
		update(function(d)
			d.Video.Fov = v
		end)
	end, function(v: number): string
		return string.format("%d°", v)
	end))
	add(UI.slider("Volume général", 0, 1, 0.05, s.Audio.Master, function(v)
		update(function(d)
			d.Audio.Master = v
		end)
	end, percent))
	add(UI.slider("Volume des effets (tirs)", 0, 1, 0.05, s.Audio.Sfx, function(v)
		update(function(d)
			d.Audio.Sfx = v
		end)
	end, percent))
	add(UI.toggle("Sprint en bascule", s.Controls.ToggleSprint, function(v)
		update(function(d)
			d.Controls.ToggleSprint = v
		end)
	end))
	add(UI.toggle("Inverser l'axe Y", s.Controls.InvertY, function(v)
		update(function(d)
			d.Controls.InvertY = v
		end)
	end))
end

local function setGearVisibility()
	local kind = ClientState.arena()
	gear.Visible = kind ~= "Match" and not quick.Visible and not full.Visible
end

local function isOpen(): boolean
	return quick.Visible or full.Visible
end

function OptionsController.isOpen(): boolean
	return isOpen()
end

function OptionsController.close()
	if not isOpen() then
		return
	end
	quick.Visible = false
	full.Visible = false
	clearChildren(fullHost)
	ClientState.setOverlay(OVERLAY, false)
	UI.playSound("UI.Back")
	setGearVisibility()
end

function OptionsController.open()
	if isOpen() then
		return
	end
	buildQuick()
	quick.Visible = true
	ClientState.setOverlay(OVERLAY, true)
	InputController.releaseAll()
	UI.playSound("UI.Whoosh")
	setGearVisibility()
end

local function openFull()
	quick.Visible = false
	clearChildren(fullHost)
	SettingsPanel.build(fullHost)
	full.Visible = true
	UI.playSound("UI.Click")
end

local function backToQuick()
	full.Visible = false
	clearChildren(fullHost)
	buildQuick()
	quick.Visible = true
end

local function buildGui()
	gui = UI.screen("AS_Options", 70)

	-- Engrenage : toujours au même endroit (coin haut-droit, après les boutons Roblox), cliquable dès que la souris est libre.
	gear = UI.button({
		Name = "Gear",
		Text = "⚙",
		FontFace = fonts.bodyBold,
		TextSize = 24,
		TextColor3 = colors.text,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(40, 40),
		Parent = gui,
	})
	UI.corner(20, gear)
	UI.stroke(gear, colors.strokeBright, 1, 0.3)
	-- Jamais sous les boutons Roblox de droite : on se cale sur la zone libre de la barre.
	UI.onTopbarChanged(gui, function()
		local _, right = UI.topbarClearance(gui)
		gear.Position = UDim2.new(1, -(right + 12), 0, 9)
	end)
	gear.Activated:Connect(function()
		OptionsController.open()
	end)

	quick = UI.panel({
		Name = "Quick",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 470),
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	})
	UI.padding(quick, 26, 26, 20, 18)
	UI.text({
		Text = "OPTIONS",
		FontFace = fonts.headingHeavy,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = quick,
	})
	local hint = UI.text({
		Text = "",
		FontFace = fonts.body,
		TextSize = 14,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = quick,
	})
	quickBody = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -124),
		Parent = quick,
	})
	UI.list(quickBody, Enum.FillDirection.Vertical, 4)
	UI.actionButton("TOUS LES RÉGLAGES", "Secondary", openFull, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(250, 44),
		Parent = quick,
	}).TextSize =
		16
	UI.actionButton("FERMER", "Primary", OptionsController.close, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(170, 44),
		Parent = quick,
	}).TextSize =
		16

	full = UI.panel({
		Name = "Full",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(940, 660),
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	})
	UI.padding(full, 24, 24, 20, 20)
	fullHost = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -56), Parent = full })
	UI.actionButton("RETOUR", "Ghost", backToQuick, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -190, 1, 0),
		Size = UDim2.fromOffset(170, 44),
		Parent = full,
	}).TextSize =
		16
	UI.actionButton("FERMER", "Primary", OptionsController.close, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(170, 44),
		Parent = full,
	}).TextSize =
		16

	local function refreshHint()
		hint.Text = ("[%s] ouvrir / fermer  ·  valeur exacte : cliquer le chiffre, taper, Entrée"):format(
			keyFor("Options")
		)
	end
	refreshHint()
	SettingsController.Changed:Connect(refreshHint)
end

function OptionsController.start()
	buildGui()
	InputController.ActionBegan:Connect(function(action: string)
		if action == "Options" then
			if isOpen() then
				OptionsController.close()
			else
				OptionsController.open()
			end
		elseif action == "Menu" and isOpen() then
			-- Différé : les menus du lobby et du match ignorent « Menu » tant que la fenêtre est ouverte.
			task.defer(OptionsController.close)
		end
	end)
	ClientState.ArenaChanged:Connect(function()
		OptionsController.close()
		setGearVisibility()
	end)
	setGearVisibility()
end

return OptionsController
