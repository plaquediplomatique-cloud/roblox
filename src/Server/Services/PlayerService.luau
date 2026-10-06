--!strict
--[[
	PlayerService — orchestration du cycle de vie d'un joueur.

	Profil chargé (DataService)
	  -> replica "PlayerProfile" (données du profil, propriétaire seul, sections privées
	     filtrées) : toute mutation de progression passe par ce replica = répliquée ET
	     sauvegardée ;
	  -> attributs publics (niveau, rang, bannière…) visibles par tous (scoreboard, cartes
	     de joueurs du hub, party) ;
	  -> rôle Lobby : contexte Hub + apparition sur la plaza.
	Profil libéré -> replica détruit.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Logger = require(Shared.Util.Logger)
local Net = require(Shared.Net.Net)
local ReplicaPath = require(Shared.Replica.ReplicaPath)
local ServerRole = require(script.Parent.Parent.ServerRole)
local DataService = require(script.Parent.DataService)
local ReplicaService = require(script.Parent.ReplicaService)
local ArenaService = require(script.Parent.ArenaService)
local CharacterService = require(script.Parent.CharacterService)
local MapService = require(script.Parent.MapService)

local log = Logger.new("Player")

local PlayerService = {
	Ready = Signal.new() :: Signal.Signal<Player, Types.ProfileData>,
}

local replicas: { [Player]: ReplicaService.Replica } = {}

function PlayerService.getReplica(player: Player): ReplicaService.Replica?
	return replicas[player]
end

--[[ Écrit une valeur du profil (répliquée + persistée). ]]
function PlayerService.set(player: Player, path: ReplicaPath.Path, value: any)
	local replica = replicas[player]
	if replica then
		replica:Set(path, value)
	end
end

function PlayerService.increment(player: Player, path: ReplicaPath.Path, delta: number): number
	local replica = replicas[player]
	if replica then
		return replica:Increment(path, delta)
	end
	return 0
end

--[[ Rafraîchit les attributs publics (après un changement de niveau / rang / cosmétique). ]]
function PlayerService.refreshPublic(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("RankIndex", data.Rank.RankIndex)
	player:SetAttribute("Placed", data.Rank.Placements >= 5)
	player:SetAttribute("Banner", data.Cosmetics.Banner)
	player:SetAttribute("Title", data.Cosmetics.Title)
	player:SetAttribute("Operator", data.Cosmetics.Operator)
end

--[[ Envoie un toast au joueur (notifications génériques : récompense, invitation…). ]]
function PlayerService.notify(player: Player, kind: string, text: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { kind = kind, text = text }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	Net.event("Notify"):FireClient(player, payload)
end

--[[ Ramène un joueur au hub (fin de match local, sortie du Training). ]]
function PlayerService.returnToHub(player: Player)
	if not ServerRole.isLobby() or player.Parent ~= Players then
		return
	end
	ArenaService.set(player, "Hub")
	local hub = MapService.hub()
	local spawns: { CFrame } = if hub then hub.spawns.Hub or {} else {}
	local spawnCFrame = if #spawns > 0 then spawns[math.random(1, #spawns)] else CFrame.new(0, 5, 0)
	local options: CharacterService.SpawnOptions = { arenaKind = "Hub", arenaId = "Hub", shields = 0 }
	task.spawn(CharacterService.spawn, player, spawnCFrame, options)
end

function PlayerService.Init() end

function PlayerService.Start()
	DataService.ProfileLoaded:Connect(function(player: Player, profile: DataService.Profile)
		local replica = ReplicaService.new({
			token = "PlayerProfile",
			data = profile.data,
			tags = { UserId = player.UserId },
			replicateTo = { player },
			private = { Moderation = true, Purchases = true },
		})
		replicas[player] = replica
		PlayerService.refreshPublic(player)
		PlayerService.Ready:Fire(player, profile.data)
		if ServerRole.isLobby() then
			PlayerService.returnToHub(player)
		end
		log:debug("ready", player.Name)
	end)

	DataService.ProfileReleasing:Connect(function(player: Player)
		local replica = replicas[player]
		if replica then
			replica:Destroy()
			replicas[player] = nil
		end
	end)

	-- Mort dans le hub (chute) : réapparition immédiate.
	CharacterService.Died:Connect(function(player: Player)
		local kind = ArenaService.get(player)
		if kind == "Hub" then
			task.delay(1.5, PlayerService.returnToHub, player)
		end
	end)
end

return PlayerService
