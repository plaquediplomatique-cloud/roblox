--!strict
--[[
	CustomGameService — parties personnalisées (Custom Lab du hub).

	Un hôte crée un salon (code à 4 caractères), choisit mode et carte ; les joueurs
	rejoignent par code, choisissent une équipe (A, B, Spectateur) ; l'hôte lance quand
	chaque équipe a au moins un joueur et respecte la taille du mode. Le match est joué
	en local (non classé, aucun gain de RR, XP normale).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Maps = require(Shared.Config.Maps)
local Guard = require(Shared.Util.Guard)
local ServerRole = require(script.Parent.Parent.ServerRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local ReplicaService = require(script.Parent.ReplicaService)
local MatchService = require(script.Parent.MatchService)

type Room = {
	code: string,
	host: Player,
	mode: string,
	map: string,
	teams: { [Player]: string },
	replica: ReplicaService.Replica,
}

local CustomGameService = {}

local rooms: { [string]: Room } = {}
local roomOf: { [Player]: Room } = {}

local CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function newCode(): string
	for _ = 1, 50 do
		local chars = {}
		for index = 1, 4 do
			local position = math.random(1, #CODE_ALPHABET)
			chars[index] = string.sub(CODE_ALPHABET, position, position)
		end
		local code = table.concat(chars)
		if not rooms[code] then
			return code
		end
	end
	return string.upper(string.sub(HttpService:GenerateGUID(false), 1, 6))
end

local function sync(room: Room)
	local members = {}
	local list = {}
	for player, team in room.teams do
		members[tostring(player.UserId)] = { name = player.DisplayName, team = team }
		table.insert(list, player)
	end
	room.replica:SetValues({}, { code = room.code, host = room.host.UserId, mode = room.mode, map = room.map, members = members })
	room.replica:SetReplication(list)
end

local function closeRoom(room: Room)
	for player in room.teams do
		roomOf[player] = nil
	end
	rooms[room.code] = nil
	room.replica:Destroy()
end

local function leaveRoom(player: Player)
	local room = roomOf[player]
	if not room then
		return
	end
	room.teams[player] = nil
	roomOf[player] = nil
	room.replica:RemovePlayer(player)
	if room.host == player then
		closeRoom(room)
	else
		sync(room)
	end
end

local function countTeam(room: Room, team: string): number
	local count = 0
	for _, value in room.teams do
		if value == team then
			count += 1
		end
	end
	return count
end

type CustomAction = { action: string, code: string?, team: string?, mode: string?, map: string? }

local isAction = Guard.shape({
	action = Guard.oneOf({ "Create", "Join", "Leave", "SetTeam", "SetMode", "SetMap", "Start" }),
	code = Guard.optional(Guard.string(8)),
	team = Guard.optional(Guard.oneOf({ "A", "B", "Spectator" })),
	mode = Guard.optional(Guard.string(16)),
	map = Guard.optional(Guard.string(16)),
})

local function handle(player: Player, request: CustomAction): ServerNet.Response
	if MatchService.isInMatch(player) then
		return ServerNet.failure("Déjà en match")
	end
	local room = roomOf[player]
	if request.action == "Create" then
		leaveRoom(player)
		local mode = GameModes.get(request.mode or "Clash3") or GameModes.defs.Clash3
		local map = if request.map and Maps.supports(request.map, mode.id) then request.map else mode.maps[1]
		local code = newCode()
		local created: Room = {
			code = code,
			host = player,
			mode = mode.id,
			map = map,
			teams = { [player] = "A" },
			replica = ReplicaService.new({ token = "CustomRoom", data = {}, replicateTo = { player } }),
		}
		rooms[code] = created
		roomOf[player] = created
		sync(created)
		return ServerNet.success({ code = code })
	elseif request.action == "Join" then
		local target = if request.code then rooms[string.upper(request.code)] else nil
		if not target then
			return ServerNet.failure("Code de salon invalide")
		end
		leaveRoom(player)
		local mode = GameModes.get(target.mode) :: GameModes.ModeDef
		local team = if countTeam(target, "A") < mode.teamSize then "A" elseif countTeam(target, "B") < mode.teamSize then "B" else "Spectator"
		target.teams[player] = team
		roomOf[player] = target
		sync(target)
		return ServerNet.success({ code = target.code })
	elseif request.action == "Leave" then
		leaveRoom(player)
		return ServerNet.success()
	end
	if not room then
		return ServerNet.failure("Aucun salon")
	end
	if request.action == "SetTeam" and request.team then
		local mode = GameModes.get(room.mode) :: GameModes.ModeDef
		if request.team ~= "Spectator" and countTeam(room, request.team) >= mode.teamSize then
			return ServerNet.failure("Équipe complète")
		end
		room.teams[player] = request.team
		sync(room)
		return ServerNet.success()
	end
	if room.host ~= player then
		return ServerNet.failure("Réservé à l'hôte")
	end
	if request.action == "SetMode" and request.mode then
		local mode = GameModes.get(request.mode)
		if not mode then
			return ServerNet.failure("Mode inconnu")
		end
		room.mode = mode.id
		if not Maps.supports(room.map, mode.id) then
			room.map = mode.maps[1]
		end
		sync(room)
		return ServerNet.success()
	elseif request.action == "SetMap" and request.map then
		if not Maps.supports(request.map, room.mode) then
			return ServerNet.failure("Carte incompatible avec ce mode")
		end
		room.map = request.map
		sync(room)
		return ServerNet.success()
	elseif request.action == "Start" then
		local mode = GameModes.get(room.mode) :: GameModes.ModeDef
		local teams: { A: { number }, B: { number } } = { A = {}, B = {} }
		local players: { Player } = {}
		for member, team in room.teams do
			if team == "A" or team == "B" then
				table.insert((teams :: any)[team], member.UserId)
				table.insert(players, member)
			end
		end
		if #teams.A < 1 or #teams.B < 1 or #teams.A > mode.teamSize or #teams.B > mode.teamSize then
			return ServerNet.failure("Chaque équipe doit compter entre 1 et " .. mode.teamSize .. " joueurs")
		end
		local spec: Types.MatchSpec = {
			matchId = HttpService:GenerateGUID(false),
			mode = mode.id,
			map = room.map,
			ranked = false,
			custom = true,
			teams = teams,
			createdAt = os.time(),
		}
		closeRoom(room)
		MatchService.startLocal(spec, players)
		return ServerNet.success()
	end
	return ServerNet.failure("Action inconnue")
end

function CustomGameService.Init() end

function CustomGameService.Start()
	if not ServerRole.isLobby() then
		return
	end
	ServerNet.onInvoke("CustomAction", { capacity = 8, refill = 2 }, function(payload: any): CustomAction?
		return if isAction(payload) then payload :: CustomAction else nil
	end, handle)
	Players.PlayerRemoving:Connect(leaveRoom)
end

return CustomGameService
