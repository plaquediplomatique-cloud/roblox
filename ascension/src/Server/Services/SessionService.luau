--!strict
--[[
	SessionService — cycle de vie d'un joueur : chargement du profil (verrou de session),
	création de l'état, attribution de la base, synchronisation initiale, apparition.
	Un échec de chargement n'autorise JAMAIS à jouer sur un profil vide (risque d'écraser
	des données) : le joueur est expulsé avec un message clair.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Util.Logger)
local GameEvents = require(script.Parent.Parent.GameEvents)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local BaseService = require(script.Parent.BaseService)
local CharacterService = require(script.Parent.CharacterService)

local log = Logger.new("Session")

local SessionService = {}

local function onJoin(player: Player)
	local profile, reason = DataService.load(player)
	if not profile then
		log:warn("chargement impossible", player.Name, reason)
		player:Kick(
			if reason == "locked"
				then "Your data is still saving on another server. Please rejoin in a minute."
				else "We couldn't load your data. Please rejoin."
		)
		return
	end
	if player.Parent == nil then
		DataService.release(player)
		return
	end
	local state = PlayerService.create(player, profile)
	if not BaseService.assign(state) then
		player:Kick("Server is full.")
		return
	end
	PlayerService.fullSync(state)
	GameEvents.ProfileLoaded:Fire(state)
	CharacterService.spawn(state)
end

function SessionService.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onJoin, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return SessionService
