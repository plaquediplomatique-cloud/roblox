--!strict
--[[
	Main (client) — point d'entrée unique de StarterPlayerScripts.

	1. Démarre les contrôleurs dans l'ordre de leurs dépendances (état -> entrées ->
	   rendu -> gameplay -> interfaces) ; ReplicaController démarre EN DERNIER : tous les
	   écouteurs existent avant que le serveur n'envoie le premier état.
	2. Câble les signaux transverses (pas, sauts, atterrissages -> audio ; sons d'UI).
	3. Applique le contexte d'arène : Hub = 3e personne / Training & Match = 1re personne.
	4. Désactive l'UI Roblox superflue (barre de vie, sac, liste des joueurs, reset).
	5. Signale "ClientBooted" à l'écran de chargement une fois le profil reçu.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer

local ReplicaController = require(script.Parent.Core.ReplicaController)
local ClientState = require(script.Parent.Core.ClientState)
local UI = require(script.Parent.UI.UI)
local SettingsController = require(script.Parent.Controllers.SettingsController)
local InputController = require(script.Parent.Controllers.InputController)
local AudioController = require(script.Parent.Controllers.AudioController)
local LightingController = require(script.Parent.Controllers.LightingController)
local EffectsController = require(script.Parent.Controllers.EffectsController)
local CameraController = require(script.Parent.Controllers.CameraController)
local MovementController = require(script.Parent.Controllers.MovementController)
local ViewmodelController = require(script.Parent.Controllers.ViewmodelController)
local WeaponController = require(script.Parent.Controllers.WeaponController)
local CharacterAnimator = require(script.Parent.Controllers.CharacterAnimator)
local TransitionController = require(script.Parent.Controllers.TransitionController)
local HUDController = require(script.Parent.Controllers.HUDController)
local MatchController = require(script.Parent.Controllers.MatchController)
local MobileController = require(script.Parent.Controllers.MobileController)
local LobbyController = require(script.Parent.Lobby.LobbyController)
local WeaponModelBuilder = require(script.Parent.Weapons.WeaponModelBuilder)

-- UI Roblox : on garde le chat, tout le reste est remplacé par le jeu.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

-- 1. Démarrage ordonné
ClientState.start()
SettingsController.start()
InputController.start()
AudioController.start()
UI.setSoundPlayer(function(key: string)
	AudioController.play(key)
end)
LightingController.start()
EffectsController.start()
WeaponModelBuilder.start()
CameraController.start()
MovementController.start()
ViewmodelController.start()
WeaponController.start()
CharacterAnimator.start()
TransitionController.start()
HUDController.start()
MatchController.start()
LobbyController.start()
MobileController.start()
ReplicaController.start()

-- 2. Audio des déplacements du joueur local
MovementController.Footstep:Connect(function(material: Enum.Material, volume: number)
	local _, _, root = MovementController.character()
	if root then
		AudioController.footstep(root.Position, material, volume, true)
	end
end)
MovementController.Jumped:Connect(function()
	AudioController.play("Move.Jump", { volume = 0.7 })
end)
MovementController.Landed:Connect(function(fallSpeed: number)
	AudioController.play("Move.Land", { volume = math.clamp(fallSpeed / 40, 0.3, 1) })
	if fallSpeed > 30 then
		CameraController.shake(math.clamp(fallSpeed / 140, 0.05, 0.3))
	end
end)
MovementController.SlideStarted:Connect(function()
	AudioController.play("Move.Slide")
end)

-- 3. Contexte d'arène
local function applyArena(kind: ClientState.ArenaKind)
	if kind == "Hub" then
		CameraController.setMode("ThirdPerson")
		MovementController.setFirstPerson(false)
		ViewmodelController.setVisible(false)
	else
		if CameraController.getMode() ~= "Cinematic" then
			CameraController.setMode("FirstPerson")
		end
		MovementController.setFirstPerson(true)
		ViewmodelController.setVisible(true)
	end
end
ClientState.ArenaChanged:Connect(applyArena)
applyArena((ClientState.arena()))
player.CharacterAdded:Connect(function()
	task.defer(applyArena, (ClientState.arena()))
end)

-- 4. Fin du boot : profil reçu (ou délai dépassé) -> l'écran de chargement s'efface.
task.spawn(function()
	ReplicaController.wait("PlayerProfile", 30)
	player:SetAttribute("ClientBooted", true)
end)
