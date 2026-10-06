--!strict
--[[
	Net — registre centralisé de TOUS les remotes de Smash Ascension.

	Un seul endroit déclare chaque remote (revue de sécurité exhaustive en un coup d'œil).
	  C2S  : client -> serveur (intentions : jamais de valeurs de jeu)
	  S2C  : serveur -> client (résultats autoritaires, retours visuels)
	  Unreliable : flux visuels perdables (frappes des autres joueurs)
	Le serveur crée les remotes (Net.init) ; le client les attend (Net.get).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

export type Kind = "Event" | "Unreliable" | "Function"

local DECLARATION: { [string]: Kind } = {
	-- C2S : actions
	Swing = "Event",
	Equip = "Event",
	BuyUpgrade = "Event",
	UnlockZone = "Event",
	Teleport = "Event",
	Ascend = "Event",
	ClaimDaily = "Event",
	ClaimQuest = "Event",
	ClaimAchievement = "Event",
	OpenChest = "Event",
	BuyDecor = "Event",
	PlaceDecor = "Event",
	SetSetting = "Event",
	RequestSync = "Event",
	-- C2S avec réponse
	GetLeaderboard = "Function",
	-- S2C
	Sync = "Event",
	HitResult = "Event",
	LevelUp = "Event",
	Notify = "Event",
	ChestResult = "Event",
	WeaponUnlocked = "Event",
	-- Flux visuels
	SwingFx = "Unreliable",
}

Net.Declaration = DECLARATION

local FOLDER_NAME = "Remotes"

local function folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Serveur : crée tous les remotes. À appeler une fois, avant tout handler.
function Net.init()
	assert(RunService:IsServer(), "Net.init est réservé au serveur")
	local root = folder()
	for name, kind in DECLARATION do
		if not root:FindFirstChild(name) then
			local remote: Instance
			if kind == "Function" then
				remote = Instance.new("RemoteFunction")
			elseif kind == "Unreliable" then
				remote = Instance.new("UnreliableRemoteEvent")
			else
				remote = Instance.new("RemoteEvent")
			end
			remote.Name = name
			remote.Parent = root
		end
	end
end

local cache: { [string]: Instance } = {}

local function resolve(name: string): Instance
	local kind = DECLARATION[name]
	assert(kind, "remote non déclaré: " .. name)
	local cached = cache[name]
	if cached then
		return cached
	end
	local remote = folder():WaitForChild(name, 30)
	assert(remote, "remote introuvable: " .. name)
	cache[name] = remote
	return remote
end

function Net.event(name: string): RemoteEvent
	return resolve(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return resolve(name) :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	return resolve(name) :: RemoteFunction
end

return Net
