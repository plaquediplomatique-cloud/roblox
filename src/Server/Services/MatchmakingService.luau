--!strict
--[[
	MatchmakingService — files d'attente classées / casual, skill-based + rank-based.

	Deux backends, même algorithme (Shared/Rules/MatchmakingAlgorithm, testé) :

	  LOCAL (Studio, repli automatique) : tickets en mémoire du serveur ; un match trouvé
	  est joué sur une arène locale (MatchService.startLocal).

	  CLOUD (live) : file partagée par TOUS les serveurs lobby.
	    * Tickets dans un MemoryStore SortedMap par file (clé de tri = MMR, TTL 90 s
	      rafraîchi : un serveur qui crashe ne laisse pas de tickets fantômes).
	    * Un serveur LEADER (verrou MemoryStore à expiration 8 s) exécute l'algorithme
	      toutes les 2 s, réserve un serveur (TeleportService:ReserveServer), écrit la
	      MatchSpec (clé = PrivateServerId) et une affectation par ticket.
	    * Chaque serveur lobby interroge les affectations de SES tickets, affiche
	      "MATCH TROUVÉ", puis téléporte la party avec le code d'accès réservé.
	    * Un enregistrement "match actif" par joueur (30 min) permet le REJOIN.

	Statut en temps réel dans le replica de la party : temps écoulé, estimation (moyenne
	glissante des attentes récentes), joueurs en file, largeur de recherche MMR.
]]

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Guard = require(Shared.Util.Guard)
local Logger = require(Shared.Util.Logger)
local Net = require(Shared.Net.Net)
local MatchmakingAlgorithm = require(Shared.Rules.MatchmakingAlgorithm)
local ServerRole = require(script.Parent.Parent.ServerRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local ArenaService = require(script.Parent.ArenaService)
local PartyService = require(script.Parent.PartyService)
local PlayerService = require(script.Parent.PlayerService)
local MatchService = require(script.Parent.MatchService)

local log = Logger.new("Matchmaking")

local QUEUE_PREFIX = "AS_MMQ_"
local ASSIGN_MAP = "AS_MMAssign"
local SPEC_MAP = "AS_MatchSpecs"
local ACTIVE_MAP = "AS_ActiveMatch"
local LOCK_MAP = "AS_MMLock"
local TICKET_TTL = 90
local RANKED_MIN_LEVEL = 3
local FOUND_COUNTDOWN = 5

type Entry = {
	ticket: Types.MatchTicket,
	party: PartyService.Party,
	key: string,
	found: boolean,
	lastRefresh: number,
}

type Assignment = { code: string, matchId: string, map: string, mode: string }

local MatchmakingService = {}

local entries: { [string]: Entry } = {}
local localQueues: { [string]: { Types.MatchTicket } } = {}
local waitSamples: { [string]: { number } } = {}
local queueSizes: { [string]: number } = {}
local useCloud = false
local cloudFailures = 0

---------------------------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------------------------

local function modeFromKey(key: string): (GameModes.ModeDef?, boolean)
	local modeId, suffix = string.match(key, "^(%w+):(%a)$")
	local mode = if modeId then GameModes.get(modeId) else nil
	return mode, suffix == "R"
end

local function recordWait(key: string, seconds: number)
	local samples = waitSamples[key] or {}
	table.insert(samples, seconds)
	if #samples > 20 then
		table.remove(samples, 1)
	end
	waitSamples[key] = samples
end

local function estimate(key: string): number
	local samples = waitSamples[key]
	if not samples or #samples == 0 then
		return 45
	end
	local total = 0
	for _, value in samples do
		total += value
	end
	return math.floor(total / #samples + 0.5)
end

local function cloudCall<T>(label: string, fn: () -> T): (boolean, T?)
	local ok, result = pcall(fn)
	if ok then
		cloudFailures = 0
		return true, result
	end
	cloudFailures += 1
	log:warn("MemoryStore", label, result)
	if cloudFailures >= 5 and useCloud then
		useCloud = false
		log:warn("MemoryStore instable : bascule sur le matchmaking local")
	end
	return false, nil
end

local function partyPlayers(party: PartyService.Party): { Player }
	local list = {}
	for _, member in party.members do
		if member.Parent == Players then
			table.insert(list, member)
		end
	end
	return list
end

local function setStatus(entry: Entry, state: Types.QueueState)
	local mode = modeFromKey(entry.key)
	local waited = os.time() - entry.ticket.enqueuedAt
	PartyService.setQueue(entry.party, {
		state = state,
		key = entry.key,
		mode = if mode then mode.id else "",
		ranked = entry.ticket.ranked,
		since = entry.ticket.enqueuedAt,
		estimate = estimate(entry.key),
		inQueue = queueSizes[entry.key] or 0,
		searchWidth = math.floor(MatchmakingAlgorithm.window(MatchmakingAlgorithm.DEFAULT_CONFIG, waited)),
	})
end

local function idle(party: PartyService.Party)
	PartyService.setQueue(party, {
		state = "Idle",
		key = "",
		mode = "",
		ranked = false,
		since = 0,
		estimate = 0,
		inQueue = 0,
		searchWidth = 0,
	})
end

local function removeEntry(entry: Entry)
	entries[entry.ticket.id] = nil
	local queue = localQueues[entry.key]
	if queue then
		for index, ticket in queue do
			if ticket.id == entry.ticket.id then
				table.remove(queue, index)
				break
			end
		end
	end
	if useCloud then
		task.spawn(cloudCall, "remove ticket", function()
			MemoryStoreService:GetSortedMap(QUEUE_PREFIX .. entry.key):RemoveAsync(entry.ticket.id)
			return true
		end)
	end
end

local function notifyFound(players: { Player }, mapId: string, modeId: string)
	local remote = Net.event("MatchFound")
	for _, player in players do
		remote:FireClient(player, { map = mapId, mode = modeId, countdown = FOUND_COUNTDOWN })
	end
end

---------------------------------------------------------------------------------------------
-- Entrée / sortie de file
---------------------------------------------------------------------------------------------

local function join(player: Player, modeId: string, ranked: boolean): ServerNet.Response
	local party = PartyService.ensure(player)
	if party.leader ~= player then
		return ServerNet.failure("Seul le leader de la party peut lancer la recherche")
	end
	if party.queue.state ~= "Idle" then
		return ServerNet.failure("Recherche déjà en cours")
	end
	local mode = GameModes.get(modeId)
	if not mode or (ranked and not mode.ranked) or (not ranked and not mode.casual) then
		return ServerNet.failure("Mode indisponible")
	end
	if #party.members > mode.teamSize then
		return ServerNet.failure(("Party trop grande pour %s (%d max)"):format(mode.displayName, mode.teamSize))
	end
	local mmrSum, minRank, maxRank = 0, math.huge, -math.huge
	for _, member in party.members do
		local data = DataService.getData(member)
		if not data then
			return ServerNet.failure("Profil d'un membre non chargé")
		end
		local kind = ArenaService.get(member)
		if kind == "Match" or MatchService.isInMatch(member) then
			return ServerNet.failure("Un membre est déjà en match")
		end
		if ranked and data.Level < RANKED_MIN_LEVEL and not RunService:IsStudio() then
			return ServerNet.failure(("Classé débloqué au niveau %d"):format(RANKED_MIN_LEVEL))
		end
		mmrSum += data.Rank.MMR
		minRank = math.min(minRank, data.Rank.RankIndex)
		maxRank = math.max(maxRank, data.Rank.RankIndex)
	end
	local userIds = {}
	for _, member in party.members do
		table.insert(userIds, member.UserId)
	end
	local key = GameModes.queueKey(mode.id, ranked)
	local ticket: Types.MatchTicket = {
		id = HttpService:GenerateGUID(false),
		players = userIds,
		mmr = mmrSum / #party.members,
		minRank = minRank,
		maxRank = maxRank,
		enqueuedAt = os.time(),
		mode = mode.id,
		ranked = ranked,
		serverId = game.JobId,
	}
	local entry: Entry = { ticket = ticket, party = party, key = key, found = false, lastRefresh = os.clock() }
	entries[ticket.id] = entry
	if useCloud then
		local ok = cloudCall("add ticket", function()
			MemoryStoreService:GetSortedMap(QUEUE_PREFIX .. key)
				:SetAsync(ticket.id, HttpService:JSONEncode(ticket), TICKET_TTL, math.floor(ticket.mmr))
			return true
		end)
		if not ok then
			entries[ticket.id] = nil
			return ServerNet.failure("Service de matchmaking indisponible, réessayez")
		end
	else
		local queue = localQueues[key] or {}
		table.insert(queue, ticket)
		localQueues[key] = queue
	end
	setStatus(entry, "Searching")
	log:debug("ticket", ticket.id, key, "mmr", ticket.mmr)
	return ServerNet.success({ key = key })
end

local function leave(player: Player): ServerNet.Response
	local party = PartyService.get(player)
	if not party then
		return ServerNet.success()
	end
	for _, entry in entries do
		if entry.party == party and not entry.found then
			removeEntry(entry)
			idle(party)
			return ServerNet.success()
		end
	end
	return ServerNet.success()
end

---------------------------------------------------------------------------------------------
-- Backend local
---------------------------------------------------------------------------------------------

local function launchLocal(proposal: Types.MatchProposal, mode: GameModes.ModeDef, ranked: boolean)
	local teams: { A: { number }, B: { number } } = { A = {}, B = {} }
	local players: { Player } = {}
	local involved: { Entry } = {}
	for _, side in { "A", "B" } do
		local tickets: { Types.MatchTicket } = if side == "A" then proposal.teamA else proposal.teamB
		for _, ticket in tickets do
			local entry = entries[ticket.id]
			if entry then
				entry.found = true
				table.insert(involved, entry)
			end
			for _, userId in ticket.players do
				table.insert((teams :: any)[side], userId)
				local player = Players:GetPlayerByUserId(userId)
				if player then
					table.insert(players, player)
				end
			end
		end
	end
	local mapId = mode.maps[math.random(1, #mode.maps)]
	local spec: Types.MatchSpec = {
		matchId = HttpService:GenerateGUID(false),
		mode = mode.id,
		map = mapId,
		ranked = ranked,
		custom = false,
		teams = teams,
		createdAt = os.time(),
	}
	for _, entry in involved do
		recordWait(entry.key, os.time() - entry.ticket.enqueuedAt)
		setStatus(entry, "Found")
	end
	notifyFound(players, mapId, mode.id)
	task.delay(FOUND_COUNTDOWN, function()
		for _, entry in involved do
			entries[entry.ticket.id] = nil
			idle(entry.party)
		end
		local present = {}
		for _, player in players do
			if player.Parent == Players and not MatchService.isInMatch(player) then
				table.insert(present, player)
			end
		end
		if #present >= 2 then
			MatchService.startLocal(spec, present)
		end
	end)
end

local function runLocal()
	for key, queue in localQueues do
		queueSizes[key] = 0
		for _, ticket in queue do
			queueSizes[key] += #ticket.players
		end
		local mode, ranked = modeFromKey(key)
		if not mode or #queue == 0 then
			continue
		end
		local proposals, remaining = MatchmakingAlgorithm.run(queue, mode.teamSize, ranked, os.time())
		localQueues[key] = remaining
		for _, proposal in proposals do
			launchLocal(proposal, mode, ranked)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Backend cloud
---------------------------------------------------------------------------------------------

local function isLeader(): boolean
	local ok, result = cloudCall("leader", function()
		return MemoryStoreService:GetSortedMap(LOCK_MAP):UpdateAsync("leader", function(current: any): any
			if current == nil or current == game.JobId then
				return game.JobId
			end
			return nil
		end, 8)
	end)
	return ok and result == game.JobId
end

local function createCloudMatch(proposal: Types.MatchProposal, mode: GameModes.ModeDef, ranked: boolean, key: string)
	local queueMap = MemoryStoreService:GetSortedMap(QUEUE_PREFIX .. key)
	local teams: { A: { number }, B: { number } } = { A = {}, B = {} }
	local all: { Types.MatchTicket } = {}
	for _, ticket in proposal.teamA do
		table.insert(all, ticket)
		for _, userId in ticket.players do
			table.insert(teams.A, userId)
		end
	end
	for _, ticket in proposal.teamB do
		table.insert(all, ticket)
		for _, userId in ticket.players do
			table.insert(teams.B, userId)
		end
	end
	for _, ticket in all do
		cloudCall("claim", function()
			queueMap:RemoveAsync(ticket.id)
			return true
		end)
	end
	local reserved, code, privateServerId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not reserved or type(code) ~= "string" or type(privateServerId) ~= "string" then
		log:warn("ReserveServer a échoué", code)
		return
	end
	local spec: Types.MatchSpec = {
		matchId = HttpService:GenerateGUID(false),
		mode = mode.id,
		map = mode.maps[math.random(1, #mode.maps)],
		ranked = ranked,
		custom = false,
		teams = teams,
		createdAt = os.time(),
	}
	cloudCall("spec", function()
		MemoryStoreService:GetHashMap(SPEC_MAP):SetAsync(privateServerId, HttpService:JSONEncode(spec), 600)
		return true
	end)
	local assignment: Assignment = { code = code, matchId = spec.matchId, map = spec.map, mode = spec.mode }
	local encoded = HttpService:JSONEncode(assignment)
	for _, ticket in all do
		cloudCall("assign", function()
			MemoryStoreService:GetHashMap(ASSIGN_MAP):SetAsync(ticket.id, encoded, 120)
			return true
		end)
		for _, userId in ticket.players do
			cloudCall("active", function()
				MemoryStoreService:GetHashMap(ACTIVE_MAP):SetAsync(tostring(userId), encoded, 1800)
				return true
			end)
		end
	end
	log:info("match cloud créé", spec.matchId, spec.mode, spec.map)
end

local function runCloudLeader()
	if not isLeader() then
		return
	end
	for _, modeId in GameModes.order do
		local mode = GameModes.defs[modeId]
		for _, ranked in { true, false } do
			if (ranked and not mode.ranked) or (not ranked and not mode.casual) then
				continue
			end
			local key = GameModes.queueKey(modeId, ranked)
			local ok, items = cloudCall("range", function()
				return MemoryStoreService:GetSortedMap(QUEUE_PREFIX .. key):GetRangeAsync(Enum.SortDirection.Ascending, 200)
			end)
			if not ok or type(items) ~= "table" then
				continue
			end
			local tickets: { Types.MatchTicket } = {}
			local count = 0
			for _, item in items :: { any } do
				local decoded = pcall(function()
					local ticket = HttpService:JSONDecode(item.value)
					table.insert(tickets, ticket)
					count += #ticket.players
				end)
				if not decoded then
					continue
				end
			end
			queueSizes[key] = count
			if #tickets < 2 then
				continue
			end
			local proposals = MatchmakingAlgorithm.run(tickets, mode.teamSize, ranked, os.time())
			for _, proposal in proposals do
				task.spawn(createCloudMatch, proposal, mode, ranked, key)
			end
		end
	end
end

local function teleportToMatch(entry: Entry, assignment: Assignment)
	local players = partyPlayers(entry.party)
	recordWait(entry.key, os.time() - entry.ticket.enqueuedAt)
	setStatus(entry, "Found")
	notifyFound(players, assignment.map, assignment.mode)
	task.delay(FOUND_COUNTDOWN - 1, function()
		setStatus(entry, "Launching")
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = assignment.code
		options:SetTeleportData({ matchId = assignment.matchId, map = assignment.map, mode = assignment.mode })
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players, options)
		end)
		entries[entry.ticket.id] = nil
		if not ok then
			log:warn("téléportation match échouée", err)
			idle(entry.party)
			for _, player in players do
				PlayerService.notify(player, "Error", "Téléportation vers le match impossible")
			end
		end
	end)
end

local function pollAssignments()
	for _, entry in entries do
		if entry.found then
			continue
		end
		-- Rafraîchit le TTL du ticket.
		if os.clock() - entry.lastRefresh > 25 then
			entry.lastRefresh = os.clock()
			task.spawn(cloudCall, "refresh", function()
				MemoryStoreService:GetSortedMap(QUEUE_PREFIX .. entry.key)
					:SetAsync(entry.ticket.id, HttpService:JSONEncode(entry.ticket), TICKET_TTL, math.floor(entry.ticket.mmr))
				return true
			end)
		end
		local ok, value = cloudCall("poll", function()
			return MemoryStoreService:GetHashMap(ASSIGN_MAP):GetAsync(entry.ticket.id)
		end)
		if ok and type(value) == "string" then
			local decoded, assignment = pcall(HttpService.JSONDecode, HttpService, value)
			if decoded and type(assignment) == "table" and type(assignment.code) == "string" then
				entry.found = true
				task.spawn(teleportToMatch, entry, assignment :: Assignment)
			end
		end
	end
end

local function rejoin(player: Player): ServerNet.Response
	if not useCloud then
		return ServerNet.failure("Aucun match à rejoindre")
	end
	local ok, value = cloudCall("rejoin", function()
		return MemoryStoreService:GetHashMap(ACTIVE_MAP):GetAsync(tostring(player.UserId))
	end)
	if not ok or type(value) ~= "string" then
		return ServerNet.failure("Aucun match à rejoindre")
	end
	local decoded, assignment = pcall(HttpService.JSONDecode, HttpService, value)
	if not decoded or type(assignment) ~= "table" then
		return ServerNet.failure("Match introuvable")
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = assignment.code
	local teleported = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	return if teleported then ServerNet.success() else ServerNet.failure("Téléportation impossible")
end

---------------------------------------------------------------------------------------------
-- Cycle de vie
---------------------------------------------------------------------------------------------

type QueueRequest = { action: string, mode: string?, ranked: boolean? }

local isRequest = Guard.shape({
	action = Guard.oneOf({ "Join", "Leave", "Rejoin" }),
	mode = Guard.optional(Guard.string(16)),
	ranked = Guard.optional(Guard.boolean),
})

function MatchmakingService.Init()
	useCloud = ServerRole.cloudAvailable()
end

function MatchmakingService.Start()
	if not ServerRole.isLobby() then
		return
	end
	ServerNet.onInvoke("QueueAction", { capacity = 6, refill = 1 }, function(payload: any): QueueRequest?
		return if isRequest(payload) then payload :: QueueRequest else nil
	end, function(player: Player, request: QueueRequest): ServerNet.Response
		if request.action == "Join" and request.mode then
			return join(player, request.mode, request.ranked == true)
		elseif request.action == "Leave" then
			return leave(player)
		elseif request.action == "Rejoin" then
			return rejoin(player)
		end
		return ServerNet.failure("Requête invalide")
	end)

	-- Toute modification de party annule sa recherche.
	PartyService.Changed:Connect(function(party: PartyService.Party)
		for _, entry in entries do
			if entry.party == party and not entry.found then
				local members = {}
				for _, member in party.members do
					members[member.UserId] = true
				end
				local same = #entry.ticket.players == #party.members
				for _, userId in entry.ticket.players do
					same = same and members[userId] == true
				end
				if not same then
					removeEntry(entry)
					idle(party)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, entry in entries do
			if table.find(entry.ticket.players, player.UserId) and not entry.found then
				removeEntry(entry)
			end
		end
	end)

	-- Proposition de rejoindre un match en cours (déconnexion).
	PlayerService.Ready:Connect(function(player: Player)
		if not useCloud then
			return
		end
		local ok, value = cloudCall("active check", function()
			return MemoryStoreService:GetHashMap(ACTIVE_MAP):GetAsync(tostring(player.UserId))
		end)
		if ok and type(value) == "string" then
			PlayerService.notify(player, "RejoinAvailable", "Un match est en cours : REJOINDRE ?")
		end
	end)

	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			if useCloud then
				if tick % 2 == 0 then
					runCloudLeader()
				end
				pollAssignments()
			else
				runLocal()
			end
			for _, entry in entries do
				if not entry.found then
					setStatus(entry, "Searching")
				end
			end
		end
	end)
	log:info("matchmaking prêt (backend " .. (if useCloud then "cloud" else "local") .. ")")
end

return MatchmakingService
