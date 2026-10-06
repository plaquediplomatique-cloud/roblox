--!strict
--[[
	Net — registre centralisé de TOUS les remotes du jeu.

	* Un seul endroit déclare chaque remote, son type et son dossier :
	    ReplicatedStorage.Remotes/<Dossier>/<Nom>
	  -> aucune chaîne magique dispersée, revue de sécurité exhaustive en un coup d'oeil.
	* Trois types :
	    Event      : RemoteEvent fiable et ordonné (actions de gameplay, état)
	    Unreliable : UnreliableRemoteEvent (flux haute fréquence où le dernier paquet
	                 seul compte : direction de visée, visuels de tirs des autres joueurs)
	    Function   : RemoteFunction client -> serveur uniquement (requêtes de lobby avec
	                 réponse). Le serveur n'invoque JAMAIS un client (un client peut ne
	                 jamais répondre et bloquer le thread serveur).
	* Côté serveur, les handlers sont branchés via ServerNet (validation + rate limit).
	* Le remote "AdminCommand" est un pot de miel : aucun client légitime ne l'appelle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type RemoteKind = "Event" | "Unreliable" | "Function"

export type EventName =
	"Fire"
	| "Reload"
	| "Equip"
	| "Melee"
	| "ShotResult"
	| "DamageTaken"
	| "Kill"
	| "AmmoSync"
	| "Stance"
	| "Interact"
	| "MatchEvent"
	| "LoadoutSelect"
	| "Killcam"
	| "Notify"
	| "MatchFound"
	| "SettingsSave"
	| "Emote"
	| "ReplicaCreate"
	| "ReplicaUpdate"
	| "ReplicaDestroy"
	| "ReplicaRequest"
	| "AdminCommand"

export type UnreliableName = "LookUpdate" | "LookBatch" | "ShotVisual"

export type FunctionName =
	"PartyAction"
	| "QueueAction"
	| "InventoryAction"
	| "MissionAction"
	| "ShopAction"
	| "TrainingAction"
	| "CustomAction"
	| "ProfileQuery"

type Definition = { kind: RemoteKind, folder: string }

local DEFINITIONS: { [string]: Definition } = {
	-- Combat
	Fire = { kind = "Event", folder = "Combat" },
	Reload = { kind = "Event", folder = "Combat" },
	Equip = { kind = "Event", folder = "Combat" },
	Melee = { kind = "Event", folder = "Combat" },
	ShotResult = { kind = "Event", folder = "Combat" },
	DamageTaken = { kind = "Event", folder = "Combat" },
	Kill = { kind = "Event", folder = "Combat" },
	AmmoSync = { kind = "Event", folder = "Combat" },
	ShotVisual = { kind = "Unreliable", folder = "Combat" },
	-- Mouvement / visée
	Stance = { kind = "Event", folder = "Movement" },
	LookUpdate = { kind = "Unreliable", folder = "Movement" },
	LookBatch = { kind = "Unreliable", folder = "Movement" },
	-- Match
	Interact = { kind = "Event", folder = "Match" },
	MatchEvent = { kind = "Event", folder = "Match" },
	LoadoutSelect = { kind = "Event", folder = "Match" },
	Killcam = { kind = "Event", folder = "Match" },
	-- Lobby / méta
	Notify = { kind = "Event", folder = "Lobby" },
	MatchFound = { kind = "Event", folder = "Lobby" },
	SettingsSave = { kind = "Event", folder = "Lobby" },
	Emote = { kind = "Event", folder = "Lobby" },
	PartyAction = { kind = "Function", folder = "Lobby" },
	QueueAction = { kind = "Function", folder = "Lobby" },
	InventoryAction = { kind = "Function", folder = "Lobby" },
	MissionAction = { kind = "Function", folder = "Lobby" },
	ShopAction = { kind = "Function", folder = "Lobby" },
	TrainingAction = { kind = "Function", folder = "Lobby" },
	CustomAction = { kind = "Function", folder = "Lobby" },
	ProfileQuery = { kind = "Function", folder = "Lobby" },
	-- Réplication d'état
	ReplicaCreate = { kind = "Event", folder = "Replica" },
	ReplicaUpdate = { kind = "Event", folder = "Replica" },
	ReplicaDestroy = { kind = "Event", folder = "Replica" },
	ReplicaRequest = { kind = "Event", folder = "Replica" },
	-- Pot de miel anti-exploit
	AdminCommand = { kind = "Event", folder = "Admin" },
}

local ROOT_NAME = "Remotes"
local CLASS_BY_KIND: { [RemoteKind]: string } = {
	Event = "RemoteEvent",
	Unreliable = "UnreliableRemoteEvent",
	Function = "RemoteFunction",
}

local Net = {}

local cache: { [string]: Instance } = {}
local root: Folder? = nil

--[[ Serveur : crée l'arborescence complète. Doit être appelé avant tout autre service. ]]
function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server-only")
	if root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = ROOT_NAME
	local subfolders: { [string]: Folder } = {}
	for name, definition in DEFINITIONS do
		local sub: Folder? = subfolders[definition.folder]
		if sub == nil then
			local created = Instance.new("Folder")
			created.Name = definition.folder
			created.Parent = folder
			subfolders[definition.folder] = created
			sub = created
		end
		local remote = Instance.new(CLASS_BY_KIND[definition.kind])
		remote.Name = name
		remote.Parent = sub
		cache[name] = remote
	end
	folder.Parent = ReplicatedStorage
	root = folder
end

local function resolve(name: string, kind: RemoteKind): Instance
	local cached = cache[name]
	if cached then
		return cached
	end
	local definition = DEFINITIONS[name]
	assert(definition, "Unknown remote " .. name)
	assert(definition.kind == kind, ("Remote %s is %s, not %s"):format(name, definition.kind, kind))
	assert(RunService:IsClient(), "Server remotes must be created by Net.setup()")
	local folder = root
	if not folder then
		local found = ReplicatedStorage:WaitForChild(ROOT_NAME, 60)
		assert(found and found:IsA("Folder"), "Remotes folder missing")
		folder = found :: Folder
		root = folder
	end
	local sub = (folder :: Folder):WaitForChild(definition.folder, 30)
	assert(sub, "Remote folder missing: " .. definition.folder)
	local remote = (sub :: Instance):WaitForChild(name, 30)
	assert(remote, "Remote missing: " .. name)
	cache[name] = remote :: Instance
	return remote :: Instance
end

function Net.event(name: EventName): RemoteEvent
	return resolve(name, "Event") :: RemoteEvent
end

function Net.unreliable(name: UnreliableName): UnreliableRemoteEvent
	return resolve(name, "Unreliable") :: UnreliableRemoteEvent
end

function Net.func(name: FunctionName): RemoteFunction
	return resolve(name, "Function") :: RemoteFunction
end

function Net.definitions(): { [string]: Definition }
	return DEFINITIONS
end

return Net
