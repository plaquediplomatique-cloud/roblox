--!strict
--[[
	ReplicaService — réplication d'état serveur -> clients par DELTAS (équivalent ReplicaService).

	Un "replica" = (token, données, abonnés). Toute mutation passe par son API :
	  replica:Set({"Rank","RR"}, 42)        -> met à jour la table serveur
	                                          -> envoie (id, op, chemin, valeur) aux abonnés
	Le client rejoue la même opération (ReplicaPath) : les deux copies sont identiques
	par construction, seul le delta transite. Exemples de replicas :
	  PlayerProfile (propriétaire seul), MatchState (joueurs du match), Party (membres),
	  Leaderboard (tous), TrainingStats (propriétaire).

	* Les données d'un PlayerProfile SONT la table du profil DataService (même référence) :
	  une mutation répliquée est automatiquement sauvegardée.
	* Clés privées : certaines sections ne quittent jamais le serveur (Moderation,
	  Purchases) — ni à la création, ni lors des mises à jour.
	* Les clients ne reçoivent rien avant d'avoir signalé "ReplicaRequest" (prêts à
	  écouter), puis reçoivent tous leurs replicas d'un coup.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Logger = require(Shared.Util.Logger)
local ReplicaPath = require(Shared.Replica.ReplicaPath)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Guard = require(Shared.Util.Guard)

local log = Logger.new("Replica")

type Path = ReplicaPath.Path

export type Targets = "All" | { Player }

export type Replica = {
	id: number,
	token: string,
	data: any,
	tags: { [string]: any },
	Set: (self: Replica, path: Path, value: any) -> (),
	SetValues: (self: Replica, path: Path, values: { [string]: any }) -> (),
	ArrayInsert: (self: Replica, path: Path, value: any) -> (),
	ArrayRemove: (self: Replica, path: Path, index: number) -> (),
	Increment: (self: Replica, path: Path, delta: number) -> number,
	AddPlayer: (self: Replica, player: Player) -> (),
	RemovePlayer: (self: Replica, player: Player) -> (),
	SetReplication: (self: Replica, targets: Targets) -> (),
	Destroy: (self: Replica) -> (),
	isDestroyed: (self: Replica) -> boolean,
}

export type ReplicaOptions = {
	token: string,
	data: any,
	tags: { [string]: any }?,
	replicateTo: Targets,
	private: { [string]: boolean }?,
}

type Internal = {
	id: number,
	token: string,
	data: any,
	tags: { [string]: any },
	all: boolean,
	subscribers: { [Player]: boolean },
	private: { [string]: boolean },
	destroyed: boolean,
}

local ReplicaService = {}

local replicas: { [number]: Internal } = {}
local ready: { [Player]: boolean } = {}
local nextId = 0

local createRemote: RemoteEvent
local updateRemote: RemoteEvent
local destroyRemote: RemoteEvent

local function isSubscribed(internal: Internal, player: Player): boolean
	return internal.all or internal.subscribers[player] == true
end

local function publicData(internal: Internal): any
	if next(internal.private) == nil or type(internal.data) ~= "table" then
		return internal.data
	end
	local copy = {}
	for key, value in internal.data do
		if not internal.private[key] then
			copy[key] = value
		end
	end
	return copy
end

local function sendCreate(internal: Internal, player: Player)
	createRemote:FireClient(player, {
		id = internal.id,
		token = internal.token,
		tags = internal.tags,
		data = publicData(internal),
	})
end

local function broadcast(internal: Internal, op: number, path: Path, a: any, b: any)
	if #path > 0 and internal.private[tostring(path[1])] then
		return
	end
	if internal.all then
		for player in ready do
			updateRemote:FireClient(player, internal.id, op, path, a, b)
		end
	else
		for player in internal.subscribers do
			if ready[player] then
				updateRemote:FireClient(player, internal.id, op, path, a, b)
			end
		end
	end
end

local ReplicaClass = {}
ReplicaClass.__index = ReplicaClass

local function internalOf(self: any): Internal
	return replicas[self.id] or self._internal
end

function ReplicaClass.Set(self: any, path: Path, value: any)
	local internal = internalOf(self)
	if internal.destroyed then
		return
	end
	ReplicaPath.set(internal.data, path, value)
	broadcast(internal, ReplicaPath.OP_SET, path, value, nil)
end

function ReplicaClass.SetValues(self: any, path: Path, values: { [string]: any })
	local internal = internalOf(self)
	if internal.destroyed then
		return
	end
	ReplicaPath.setValues(internal.data, path, values)
	broadcast(internal, ReplicaPath.OP_SET_VALUES, path, values, nil)
end

function ReplicaClass.ArrayInsert(self: any, path: Path, value: any)
	local internal = internalOf(self)
	if internal.destroyed then
		return
	end
	local index = ReplicaPath.arrayInsert(internal.data, path, value, nil)
	broadcast(internal, ReplicaPath.OP_ARRAY_INSERT, path, value, index)
end

function ReplicaClass.ArrayRemove(self: any, path: Path, index: number)
	local internal = internalOf(self)
	if internal.destroyed then
		return
	end
	ReplicaPath.arrayRemove(internal.data, path, index)
	broadcast(internal, ReplicaPath.OP_ARRAY_REMOVE, path, index, nil)
end

function ReplicaClass.Increment(self: any, path: Path, delta: number): number
	local internal = internalOf(self)
	local current = ReplicaPath.get(internal.data, path)
	local value = (if type(current) == "number" then current else 0) + delta
	ReplicaClass.Set(self, path, value)
	return value
end

function ReplicaClass.AddPlayer(self: any, player: Player)
	local internal = internalOf(self)
	if internal.destroyed or internal.all or internal.subscribers[player] then
		return
	end
	internal.subscribers[player] = true
	if ready[player] then
		sendCreate(internal, player)
	end
end

function ReplicaClass.RemovePlayer(self: any, player: Player)
	local internal = internalOf(self)
	if internal.destroyed or not internal.subscribers[player] then
		return
	end
	internal.subscribers[player] = nil
	if ready[player] and player.Parent then
		destroyRemote:FireClient(player, internal.id)
	end
end

function ReplicaClass.SetReplication(self: any, targets: Targets)
	local internal = internalOf(self)
	if internal.destroyed then
		return
	end
	local previous = table.clone(internal.subscribers)
	local wasAll = internal.all
	internal.all = targets == "All"
	internal.subscribers = {}
	if targets ~= "All" then
		for _, player in targets :: { Player } do
			internal.subscribers[player] = true
		end
	end
	for player in ready do
		local before = wasAll or previous[player] == true
		local after = isSubscribed(internal, player)
		if after and not before then
			sendCreate(internal, player)
		elseif before and not after then
			destroyRemote:FireClient(player, internal.id)
		end
	end
end

function ReplicaClass.Destroy(self: any)
	local internal = internalOf(self)
	if internal.destroyed then
		return
	end
	internal.destroyed = true
	for player in ready do
		if isSubscribed(internal, player) then
			destroyRemote:FireClient(player, internal.id)
		end
	end
	replicas[internal.id] = nil
end

function ReplicaClass.isDestroyed(self: any): boolean
	return internalOf(self).destroyed
end

function ReplicaService.new(options: ReplicaOptions): Replica
	nextId += 1
	local internal: Internal = {
		id = nextId,
		token = options.token,
		data = options.data,
		tags = options.tags or {},
		all = options.replicateTo == "All",
		subscribers = {},
		private = options.private or {},
		destroyed = false,
	}
	if options.replicateTo ~= "All" then
		for _, player in options.replicateTo :: { Player } do
			internal.subscribers[player] = true
		end
	end
	replicas[internal.id] = internal
	for player in ready do
		if isSubscribed(internal, player) then
			sendCreate(internal, player)
		end
	end
	local replica = setmetatable({
		id = internal.id,
		token = internal.token,
		data = internal.data,
		tags = internal.tags,
		_internal = internal,
	}, ReplicaClass)
	return (replica :: any) :: Replica
end

function ReplicaService.isReady(player: Player): boolean
	return ready[player] == true
end

function ReplicaService.Init()
	createRemote = Net.event("ReplicaCreate")
	updateRemote = Net.event("ReplicaUpdate")
	destroyRemote = Net.event("ReplicaDestroy")
end

function ReplicaService.Start()
	ServerNet.onEvent("ReplicaRequest", { capacity = 2, refill = 0.1 }, function(...: any): boolean?
		local first = ...
		return if first == nil or Guard.boolean(first) then true else nil
	end, function(player: Player, _: boolean)
		if ready[player] then
			return
		end
		ready[player] = true
		local count = 0
		for _, internal in replicas do
			if isSubscribed(internal, player) then
				sendCreate(internal, player)
				count += 1
			end
		end
		log:debug("client ready", player.Name, "replicas sent:", count)
	end)

	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		for _, internal in replicas do
			internal.subscribers[player] = nil
		end
	end)
end

return ReplicaService
