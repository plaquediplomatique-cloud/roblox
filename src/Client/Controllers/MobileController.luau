--!strict
--[[
	MobileController — contrôles tactiles (téléphones, tablettes).

	Le gameplay n'a AUCUN code spécifique au mobile : ces contrôles alimentent
	InputController (actions virtuelles, déplacement analogique, visée) exactement comme
	un clavier ou une manette.
	  * Joystick flottant (moitié gauche) : apparaît là où le pouce se pose.
	  * Visée : glisser sur la moitié droite ; le bouton TIR est aussi une zone de visée
	    (on peut tirer ET corriger sans lever le pouce).
	  * Boutons : tir, visée, recharger, sauter, accroupir/glisser, arme suivante,
	    interagir, tableau des scores, menu ; disposés dans la zone du pouce droit.
	  * Ralentissement de visée sur cible (friction légère, jamais de verrouillage) :
	    compense l'imprécision du tactile sans jouer à la place du joueur.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Hitbox = require(Shared.Combat.Hitbox)
local MathUtil = require(Shared.Util.MathUtil)
local UI = require(script.Parent.Parent.UI.UI)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)
local WeaponController = require(script.Parent.WeaponController)

local colors = Theme.colors
local fonts = Theme.fonts

local MobileController = {}

local LOOK_SCALE = 1.35 -- pixels tactiles -> pixels "souris" équivalents
local STICK_RADIUS = 70

local gui: ScreenGui
local stickBase: Frame
local stickKnob: Frame
local combatButtons: { GuiButton } = {}
local moveTouch: InputObject? = nil
local moveOrigin = Vector2.zero
local lookTouches: { [InputObject]: Vector2 } = {}

local function aimFriction(): number
	if not WeaponController.isArmed() then
		return 1
	end
	local origin, aim = CameraController.getAim()
	local mine = Players.LocalPlayer.Character
	local myTeam = if mine then mine:GetAttribute("Team") else nil
	local best = math.huge
	for _, tag in { "Combatant", "TrainingBot" } do
		for _, model in CollectionService:GetTagged(tag) do
			if not model:IsA("Model") or model == mine or model:GetAttribute("Alive") ~= true then
				continue
			end
			if tag == "Combatant" and myTeam ~= nil and myTeam ~= "" and model:GetAttribute("Team") == myTeam then
				continue
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local center = Hitbox.centerOf(root.CFrame, "Stand")
				local angle = math.deg(MathUtil.angleBetween(aim, center - origin))
				best = math.min(best, angle)
			end
		end
	end
	-- Friction maximale au centre de la cible, nulle au-delà de 4.5°.
	return if best < 4.5 then MathUtil.lerp(0.5, 1, best / 4.5) else 1
end

local function makeButton(text: string, position: UDim2, size: number, action: string, lookArea: boolean?): TextButton
	local button = UI.button({
		Text = text,
		FontFace = fonts.heading,
		TextSize = math.floor(size * 0.22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.35,
		TextColor3 = colors.text,
		Parent = gui,
	})
	UI.corner(math.floor(size / 2), button)
	UI.stroke(button, colors.primary, 1.5, 0.4)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			InputController.setVirtual(action, true)
			button.BackgroundTransparency = 0.05
			if lookArea then
				lookTouches[input] = Vector2.new(input.Position.X, input.Position.Y)
			end
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			InputController.setVirtual(action, false)
			button.BackgroundTransparency = 0.35
			lookTouches[input] = nil
		end
	end)
	return button
end

local function refreshVisibility()
	local kind = ClientState.arena()
	local combat = kind ~= "Hub"
	for _, button in combatButtons do
		button.Visible = combat and not ClientState.menuOpen
	end
end

function MobileController.start()
	if not UI.isMobile() then
		return
	end
	gui = UI.screen("AS_Mobile", 12)
	stickBase = UI.frame({
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.6,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(STICK_RADIUS * 2, STICK_RADIUS * 2),
		Visible = false,
		Parent = gui,
	})
	UI.corner(STICK_RADIUS, stickBase)
	UI.stroke(stickBase, colors.primary, 1.5, 0.5)
	stickKnob = UI.frame({
		BackgroundColor3 = colors.primary,
		BackgroundTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(56, 56),
		Parent = stickBase,
	})
	UI.corner(28, stickKnob)

	-- Boutons (zone du pouce droit)
	table.insert(combatButtons, makeButton("TIR", UDim2.new(1, -150, 1, -170), 112, "Fire", true))
	table.insert(combatButtons, makeButton("TIR", UDim2.new(0, 120, 0.42, 0), 84, "Fire", true))
	table.insert(combatButtons, makeButton("VISER", UDim2.new(1, -280, 1, -110), 76, "Aim"))
	table.insert(combatButtons, makeButton("RECH.", UDim2.new(1, -270, 1, -230), 64, "Reload"))
	table.insert(combatButtons, makeButton("ARME", UDim2.new(1, -150, 1, -300), 64, "Cycle"))
	table.insert(combatButtons, makeButton("F", UDim2.new(1, -60, 0.45, 0), 60, "Interact"))
	table.insert(combatButtons, makeButton("TAB", UDim2.new(1, -60, 0, 120), 52, "Scoreboard"))
	makeButton("SAUT", UDim2.new(1, -60, 1, -90), 76, "Jump")
	makeButton("ACCR.", UDim2.new(1, -60, 1, -190), 66, "Crouch")
	makeButton("MENU", UDim2.new(0, 60, 0, 110), 52, "Menu")

	UserInputService.TouchStarted:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		local camera = Workspace.CurrentCamera
		local width = if camera then camera.ViewportSize.X else 1000
		if position.X < width * 0.4 and moveTouch == nil then
			moveTouch = input
			moveOrigin = position
			-- Positions tactiles hors inset : on repasse en coordonnées écran (échelle relative).
			local inset = UI.insets()
			local viewport = if camera then camera.ViewportSize else Vector2.new(1000, 600)
			local screen = position + inset
			stickBase.Position = UDim2.fromScale(screen.X / viewport.X, screen.Y / viewport.Y)
			stickBase.Visible = true
		else
			lookTouches[input] = position
		end
	end)
	UserInputService.TouchMoved:Connect(function(input: InputObject)
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if input == moveTouch then
			local offset = position - moveOrigin
			if offset.Magnitude > STICK_RADIUS then
				offset = offset.Unit * STICK_RADIUS
			end
			local scale = gui:FindFirstChildOfClass("UIScale")
			local factor = if scale and scale.Scale > 0 then 1 / scale.Scale else 1
			stickKnob.Position = UDim2.new(0.5, offset.X * factor, 0.5, offset.Y * factor)
			local vector = offset / STICK_RADIUS
			-- y écran vers le bas = reculer ; dead-zone de 12 %.
			local magnitude = vector.Magnitude
			InputController.setVirtualMove(if magnitude < 0.12 then Vector2.zero else Vector2.new(vector.X, -vector.Y))
			-- Sprint automatique : stick poussé à fond vers l'avant.
			InputController.setVirtual("Sprint", magnitude >= 0.92 and -vector.Y >= 0.7)
		else
			local previous = lookTouches[input]
			if previous then
				lookTouches[input] = position
				InputController.addVirtualLook((position - previous) * LOOK_SCALE * aimFriction())
			end
		end
	end)
	UserInputService.TouchEnded:Connect(function(input: InputObject)
		if input == moveTouch then
			moveTouch = nil
			stickBase.Visible = false
			stickKnob.Position = UDim2.fromScale(0.5, 0.5)
			InputController.setVirtualMove(Vector2.zero)
			InputController.setVirtual("Sprint", false)
		end
		lookTouches[input] = nil
	end)
	ClientState.ArenaChanged:Connect(refreshVisibility)
	ClientState.MenuChanged:Connect(refreshVisibility)
	refreshVisibility()
end

return MobileController
