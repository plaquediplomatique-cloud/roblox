--!strict
--[[
	Boot — premier script exécuté par le client (ReplicatedFirst).

	Remplace l'écran de chargement Roblox par celui du jeu dès la première frame, ou
	reprend celui de la téléportation (match <-> lobby), puis attend que le client soit
	réellement prêt : jeu chargé, contrôleurs démarrés, profil reçu (attribut
	"ClientBooted" posé par StarterPlayerScripts/Client/Main). Délai de sécurité : 45 s.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

local LoadingScreen = require(script.Parent.LoadingScreen)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local arriving = TeleportService:GetArrivingTeleportGui()
local gui: ScreenGui = if arriving and arriving:IsA("ScreenGui") then arriving else LoadingScreen.create()
gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local screen = LoadingScreen.animate(gui)
screen.setStatus("CHARGEMENT DU MONDE")
screen.setProgress(0.15)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
screen.setStatus("SYNCHRONISATION AVEC LE SERVEUR")
screen.setProgress(0.55)

local deadline = os.clock() + 45
while player:GetAttribute("ClientBooted") ~= true and os.clock() < deadline do
	task.wait(0.1)
end
local profileStatus = player:GetAttribute("ClientBooted") == true
screen.setStatus(if profileStatus then "PRÊT" else "CONNEXION LENTE — POURSUITE DU CHARGEMENT")
screen.setProgress(1)
task.wait(0.4)
screen.finish()
