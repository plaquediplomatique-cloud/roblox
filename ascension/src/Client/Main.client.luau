--!strict
--[[
	Main (client) — démarrage des contrôleurs de Smash Ascension.
	Ordre : réplication des données -> audio/VFX/animation -> interface -> entrées -> ambiance.
]]

local StarterGui = game:GetService("StarterGui")

local Core = script.Parent.Core
local Controllers = script.Parent.Controllers

local Store = require(Core.Store)
local Sfx = require(Core.Sfx)
local Vfx = require(Core.Vfx)
local DummyView = require(Controllers.DummyView)
local SwingAnimator = require(Controllers.SwingAnimator)
local Hud = require(Controllers.Hud)
local HitFeedback = require(Controllers.HitFeedback)
local InputController = require(Controllers.InputController)
local Popups = require(Controllers.Popups)
local ZoneController = require(Controllers.ZoneController)
local MenuController = require(Controllers.MenuController)

-- Pas d'inventaire Roblox : les armes se gèrent dans notre menu ; la vie n'est pas un enjeu.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

Store.start()
Sfx.start()
Vfx.start()
DummyView.start()
SwingAnimator.start()

Popups.start() -- branché avant l'attente du profil : aucune notification de connexion perdue

Store.waitReady()
Hud.start()
DummyView.BossSeen:Connect(Hud.setBoss)
HitFeedback.start()
InputController.start()
ZoneController.start()
MenuController.start()
