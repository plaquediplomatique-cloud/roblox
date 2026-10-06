--!strict
--[[
	PartyService — groupes de 1 à 3 joueurs.

	Chaque joueur du lobby est TOUJOURS dans une party (solo par défaut) : la file
	d'attente, l'affichage et le matchmaking manipulent une seule notion.
	Actions : inviter (60 s), accepter/refuser, quitter, exclure, verrouiller (plus
	d'invitations acceptées), changer le mode visé, promouvoir un nouveau leader.
	L'état est répliqué aux membres (replica "Party") ; toute modification de la
	composition annule la recherche en cours (signal Changed -> MatchmakingService).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Guard = require(Shared.Util.Guard)
local Signal = require(Shared.Util.Signal)
local ServerRole = require(script.Parent.Parent.ServerRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local ReplicaService = require(script.Parent.ReplicaService)
local PlayerService = require(script.Parent.PlayerService)

local MAX_SIZE = 3
local INVITE_TTL = 60

export type Party = {
	id: string,
	leader: Player,
	members: { Player },
	locked: boolean,
	mode: string,
	ranked: boolean,
	invites: { [Player]: number },
	replica: ReplicaService.Replica,
	queue: Types.QueueStatus,
}

local PartyService = {
	Changed = Signal.new() :: Signal.Signal<Party>,
}

local parties: { [string]: Party } = {}
local partyOf: { [Player]: Party } = {}

local function idleQueue(): Types.QueueStatus
	return { state = "Idle", key = "", mode = "", ranked = false, since = 0, estimate = 0, inQueue = 0, searchWidth = 0 }
end

local function snapshot(party: Party): Types.PartyData
	local members, names, ranks = {}, {}, {}
	for _, member in party.members do
		table.insert(members, member.UserId)
		names[tostring(member.UserId)] = member.DisplayName
		local data = DataService.getData(member)
		ranks[tostring(member.UserId)] = if data then data.Rank.RankIndex else 0
	end
	local invites = {}
	for invited, expires in party.invites do
		invites[tostring(invited.UserId)] = expires
	end
	return {
		id = party.id,
		leader = party.leader.UserId,
		members = members,
		names = names,
		ranks = ranks,
		locked = party.locked,
		mode = party.mode,
		ranked = party.ranked,
		queue = party.queue,
		invites = invites,
	}
end

local function sync(party: Party)
	local data = snapshot(party)
	party.replica:SetValues({}, data :: any)
	party.replica:SetReplication(party.members)
	PartyService.Changed:Fire(party)
end

local function create(player: Player): Party
	local id = HttpService:GenerateGUID(false)
	local party: Party = {
		id = id,
		leader = player,
		members = { player },
		locked = false,
		mode = "Squad",
		ranked = false,
		invites = {},
		replica = ReplicaService.new({ token = "Party", data = {}, replicateTo = { player } }),
		queue = idleQueue(),
	}
	parties[id] = party
	partyOf[player] = party
	sync(party)
	return party
end

local function removeMember(party: Party, player: Player)
	local index = table.find(party.members, player)
	if index then
		table.remove(party.members, index)
	end
	partyOf[player] = nil
	party.replica:RemovePlayer(player)
	if #party.members == 0 then
		party.replica:Destroy()
		parties[party.id] = nil
		return
	end
	if party.leader == player then
		party.leader = party.members[1]
	end
	sync(party)
end

function PartyService.get(player: Player): Party?
	return partyOf[player]
end

function PartyService.ensure(player: Player): Party
	return partyOf[player] or create(player)
end

function PartyService.setQueue(party: Party, status: Types.QueueStatus)
	party.queue = status
	if parties[party.id] then
		party.replica:Set({ "queue" }, status)
	end
end

function PartyService.byId(id: string): Party?
	return parties[id]
end

type PartyAction = { action: string, target: number?, partyId: string?, value: boolean?, mode: string? }

local isAction = Guard.shape({
	action = Guard.oneOf({ "Invite", "Accept", "Decline", "Leave", "Kick", "Lock", "SetMode", "Promote" }),
	target = Guard.optional(Guard.integer(1, 2 ^ 53)),
	partyId = Guard.optional(Guard.string(64)),
	value = Guard.optional(Guard.boolean),
	mode = Guard.optional(Guard.string(16)),
})

local function handle(player: Player, request: PartyAction): ServerNet.Response
	local party = PartyService.ensure(player)
	local isLeader = party.leader == player
	local blocked = party.queue.state ~= "Idle" and request.action ~= "Decline"
	if blocked then
		return ServerNet.failure("Annulez la recherche avant de modifier la party")
	end
	if request.action == "Invite" then
		local target = if request.target then Players:GetPlayerByUserId(request.target) else nil
		if not target or target == player then
			return ServerNet.failure("Joueur introuvable")
		end
		if not isLeader then
			return ServerNet.failure("Seul le leader peut inviter")
		end
		if #party.members >= MAX_SIZE then
			return ServerNet.failure("Party complète")
		end
		party.invites[target] = os.time() + INVITE_TTL
		PlayerService.notify(target, "PartyInvite", player.DisplayName .. " vous invite dans sa party", {
			partyId = party.id,
			from = player.UserId,
		})
		sync(party)
		return ServerNet.success()
	elseif request.action == "Accept" or request.action == "Decline" then
		local target = if request.partyId then parties[request.partyId] else nil
		if not target then
			return ServerNet.failure("Party introuvable")
		end
		local expires = target.invites[player]
		target.invites[player] = nil
		if request.action == "Decline" then
			sync(target)
			return ServerNet.success()
		end
		if not expires or expires < os.time() then
			return ServerNet.failure("Invitation expirée")
		end
		if target.locked or #target.members >= MAX_SIZE or target.queue.state ~= "Idle" then
			sync(target)
			return ServerNet.failure("Impossible de rejoindre cette party")
		end
		removeMember(party, player)
		table.insert(target.members, player)
		partyOf[player] = target
		sync(target)
		return ServerNet.success()
	elseif request.action == "Leave" then
		if #party.members <= 1 then
			return ServerNet.success()
		end
		removeMember(party, player)
		create(player)
		return ServerNet.success()
	elseif request.action == "Kick" then
		local target = if request.target then Players:GetPlayerByUserId(request.target) else nil
		if not isLeader or not target or target == player or partyOf[target] ~= party then
			return ServerNet.failure("Exclusion impossible")
		end
		removeMember(party, target)
		create(target)
		PlayerService.notify(target, "Info", "Vous avez été retiré de la party")
		return ServerNet.success()
	elseif request.action == "Lock" then
		if not isLeader then
			return ServerNet.failure("Réservé au leader")
		end
		party.locked = request.value == true
		sync(party)
		return ServerNet.success()
	elseif request.action == "SetMode" then
		local mode = if request.mode then GameModes.get(request.mode) else nil
		if not isLeader or not mode then
			return ServerNet.failure("Mode invalide")
		end
		local ranked = request.value == true and mode.ranked
		if not ranked and not mode.casual then
			return ServerNet.failure("Mode indisponible en casual")
		end
		party.mode = mode.id
		party.ranked = ranked
		sync(party)
		return ServerNet.success()
	elseif request.action == "Promote" then
		local target = if request.target then Players:GetPlayerByUserId(request.target) else nil
		if not isLeader or not target or partyOf[target] ~= party then
			return ServerNet.failure("Promotion impossible")
		end
		party.leader = target
		sync(party)
		return ServerNet.success()
	end
	return ServerNet.failure("Action inconnue")
end

function PartyService.Init() end

function PartyService.Start()
	if not ServerRole.isLobby() then
		return
	end
	PlayerService.Ready:Connect(function(player: Player)
		PartyService.ensure(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local party = partyOf[player]
		if party then
			removeMember(party, player)
		end
		for _, other in parties do
			if other.invites[player] then
				other.invites[player] = nil
			end
		end
	end)
	ServerNet.onInvoke("PartyAction", { capacity = 8, refill = 2 }, function(payload: any): PartyAction?
		return if isAction(payload) then payload :: PartyAction else nil
	end, handle)
end

return PartyService
