--!strict
--[[
	ServerRole — détermine le rôle de ce serveur.

	Architecture "une seule place, deux rôles" :
	  * Lobby : serveurs publics. Hub, parties, file d'attente, Training Range, parties
	            personnalisées (jouées localement sur une arène du serveur).
	  * Match : serveurs RÉSERVÉS (TeleportService:ReserveServer) créés par le
	            matchmaker. Ils lisent leur MatchSpec dans MemoryStore (source de
	            confiance — jamais les TeleportData, falsifiables par le client).
	Une seule codebase, un seul déploiement, aucun risque de divergence de version
	entre lobby et match.

	En Studio, on est toujours Lobby et le matchmaking lance des matchs LOCAUX
	(même serveur, arène dédiée) : toute la boucle est testable avec "Start Server
	+ 2 joueurs".
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Role = "Lobby" | "Match"

local ServerRole = {}

local cached: Role? = nil

function ServerRole.get(): Role
	if cached then
		return cached
	end
	local forced = Workspace:GetAttribute("ForceRole")
	if forced == "Match" or forced == "Lobby" then
		cached = forced
		return forced
	end
	if RunService:IsStudio() then
		cached = "Lobby"
		return "Lobby"
	end
	local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	local role: Role = if reserved then "Match" else "Lobby"
	cached = role
	return role
end

function ServerRole.isLobby(): boolean
	return ServerRole.get() == "Lobby"
end

function ServerRole.isMatch(): boolean
	return ServerRole.get() == "Match"
end

--[[ Les services cloud (MemoryStore, Teleport) ne sont fiables qu'en live. ]]
function ServerRole.cloudAvailable(): boolean
	return not RunService:IsStudio()
end

return ServerRole
