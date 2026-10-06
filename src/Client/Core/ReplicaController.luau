--!strict
--[[
	ReplicaController — miroir client des replicas serveur.

	Le serveur envoie (création) les données complètes puis uniquement des deltas
	(opcode, chemin, valeur). On rejoue les mêmes opérations (Shared/Replica/ReplicaPath)
	et on notifie les écouteurs :
	  replica:listen({"Rank"}, fn)   -> appelé pour tout changement sous Rank.*
	  replica.Changed                -> tout changement (op, chemin)
	  ReplicaController.onNew(token, fn) -> appelé pour les replicas existants et futurs
	Les vues (HUD, lobby…) s'abonnent aux chemins qui les concernent : aucune
	interrogation périodique, aucun état dupliqué.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net.Net)
local Signal = require(Shared.Util.Signal)
local Logger = require(Shared.Util.Logger)
local ReplicaPath = require(Shared.Replica.ReplicaPath)

local log = Logger.new("Replica")

type Path = ReplicaPath.Path

export type ClientReplica = {
	id: number,
	token: string,
	tags: { [string]: any },
	data: any,
	Changed: Signal.Signal<number, Path>,
	Destroyed: Signal.Signal<>,
	listen: (self: ClientReplica, path: Path, callback: (value: any) -> ()) -> Signal.Connection,
	destroyed: boolean,
}

local ReplicaController = {}

local replicas: { [number]: ClientReplica } = {}
local creationSignals: { [string]: Signal.Signal<ClientReplica> } = {}

local function signalFor(token: string): Signal.Signal<ClientReplica>
	local signal = creationSignals[token]
	if not signal then
		signal = Signal.new()
		creationSignals[token] = signal
	end
	return signal
end

local ReplicaClass = {}
ReplicaClass.__index = ReplicaClass

function ReplicaClass.listen(self: ClientReplica, path: Path, callback: (value: any) -> ()): Signal.Connection
	return self.Changed:Connect(function(_op: number, changed: Path)
		-- Notifié si le changement touche le chemin écouté, un parent ou un enfant.
		if ReplicaPath.isPrefix(path, changed) or ReplicaPath.isPrefix(changed, path) then
			callback(ReplicaPath.get(self.data, path))
		end
	end)
end

local function create(payload: any)
	if type(payload) ~= "table" or type(payload.id) ~= "number" then
		return
	end
	local replica = setmetatable({
		id = payload.id,
		token = tostring(payload.token),
		tags = payload.tags or {},
		data = payload.data,
		Changed = Signal.new(),
		Destroyed = Signal.new(),
		destroyed = false,
	}, ReplicaClass)
	local typed = (replica :: any) :: ClientReplica
	replicas[typed.id] = typed
	signalFor(typed.token):Fire(typed)
end

function ReplicaController.onNew(token: string, callback: (ClientReplica) -> ()): Signal.Connection
	for _, replica in replicas do
		if replica.token == token then
			task.spawn(callback, replica)
		end
	end
	return signalFor(token):Connect(callback)
end

--[[ Premier replica d'un token (ex. "PlayerProfile"), ou nil. ]]
function ReplicaController.get(token: string): ClientReplica?
	for _, replica in replicas do
		if replica.token == token then
			return replica
		end
	end
	return nil
end

--[[ Attend un replica (bloquant, avec délai). ]]
function ReplicaController.wait(token: string, timeout: number): ClientReplica?
	local existing = ReplicaController.get(token)
	if existing then
		return existing
	end
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		task.wait(0.05)
		local found = ReplicaController.get(token)
		if found then
			return found
		end
	end
	return nil
end

function ReplicaController.start()
	Net.event("ReplicaCreate").OnClientEvent:Connect(create)
	Net.event("ReplicaUpdate").OnClientEvent:Connect(function(id: number, op: number, path: Path, a: any, b: any)
		local replica = replicas[id]
		if not replica then
			return
		end
		local ok, err = pcall(ReplicaPath.apply :: any, replica.data, op, path, a, b)
		if not ok then
			log:warn("apply failed", replica.token, err)
			return
		end
		replica.Changed:Fire(op, path)
	end)
	Net.event("ReplicaDestroy").OnClientEvent:Connect(function(id: number)
		local replica = replicas[id]
		if replica then
			replicas[id] = nil
			replica.destroyed = true
			replica.Destroyed:Fire()
			replica.Changed:DisconnectAll()
		end
	end)
	Net.event("ReplicaRequest"):FireServer(true)
end

return ReplicaController
