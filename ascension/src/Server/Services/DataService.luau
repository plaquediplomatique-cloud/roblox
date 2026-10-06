--!strict
--[[
	DataService — persistance robuste des profils.

	* verrou de session (Rules/SessionLock) : un seul serveur écrit un profil à la fois ;
	* UpdateAsync (jamais SetAsync) : lecture-modification-écriture atomique ;
	* nouvelles tentatives avec attente exponentielle (Game.SaveRetries) ;
	* autosave étalé (un joueur à la fois) ; sauvegarde au départ ; BindToClose en parallèle
	  avec budget de temps ;
	* données assainies et migrées à chaque chargement (Rules/Profile) ;
	* repli en mémoire en Studio sans « Enable Studio Access to API Services ».
	Le profil vivant reste en mémoire : les services le mutent, DataService l'écrit.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Game = require(Shared.Config.Game)
local Profile = require(Shared.Rules.Profile)
local SessionLock = require(Shared.Rules.SessionLock)
local Logger = require(Shared.Util.Logger)

local log = Logger.new("Data")

local DataService = {}

type Entry = { Profile: Profile.Profile, Dirty: boolean, Saving: boolean, Released: boolean, Refused: number }

local entries: { [Player]: Entry } = {}
local releasing: { [number]: boolean } = {} -- userId en cours de libération (un rechargement attend)
local memoryStore: { [string]: any } = {}
local useMemory = false
local store: GlobalDataStore? = nil

local function getStore(): GlobalDataStore?
	if useMemory then
		return nil
	end
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Game.DataStoreName)
	end)
	if ok then
		store = result
		return store
	end
	useMemory = true
	return nil
end

local function keyFor(userId: number): string
	return "P_" .. tostring(userId)
end

local function isStudioApiError(message: string): boolean
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "Studio access to APIs is not allowed", 1, true) ~= nil
end

-- UpdateAsync avec repli mémoire. `transform` suit le contrat d'UpdateAsync (nil = annuler).
local function update(key: string, transform: (any) -> any): (boolean, any)
	local ds = getStore()
	if ds then
		local ok, result = pcall(function()
			return ds:UpdateAsync(key, transform)
		end)
		if ok then
			return true, result
		end
		local message = tostring(result)
		if RunService:IsStudio() and isStudioApiError(message) then
			log:warn("API DataStore indisponible en Studio : repli mémoire (non persistant)")
			useMemory = true
		else
			return false, message
		end
	end
	local updated = transform(memoryStore[key])
	if updated ~= nil then
		memoryStore[key] = updated
	end
	return true, updated
end

local function retry<T>(attempts: number, fn: () -> (boolean, T)): (boolean, T)
	local ok, result
	for attempt = 1, attempts do
		ok, result = fn()
		if ok then
			return true, result
		end
		if attempt < attempts then
			task.wait(math.min(8, 2 ^ (attempt - 1)))
		end
	end
	return false, result
end

---------------------------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------------------------

-- Charge (et verrouille) le profil. Yield. Renvoie nil + raison en cas d'échec.
function DataService.load(player: Player): (Profile.Profile?, string?)
	local key = keyFor(player.UserId)
	-- Une libération précédente du même joueur sur ce serveur doit finir avant de relire le profil.
	local waited = 0
	while releasing[player.UserId] and waited < 20 do
		task.wait(0.25)
		waited += 0.25
	end
	local locked = false
	local ok, record = retry(Game.SaveRetries, function()
		local success, result = update(key, function(old: any)
			local updated, acquired = SessionLock.acquire(old, game.JobId, os.time(), Game.SessionLockSeconds)
			locked = acquired
			return updated
		end)
		if success and not locked then
			return false, "locked"
		end
		return success, result
	end)
	if not ok or not locked then
		return nil, if locked == false and ok == false then "locked" else tostring(record)
	end
	local raw = if type(record) == "table" then (record :: any).Data else nil
	local profile = Profile.load(raw, os.time())
	entries[player] = { Profile = profile, Dirty = raw == nil, Saving = false, Released = false, Refused = 0 }
	return profile, nil
end

function DataService.get(player: Player): Profile.Profile?
	local entry = entries[player]
	return if entry then entry.Profile else nil
end

function DataService.markDirty(player: Player)
	local entry = entries[player]
	if entry then
		entry.Dirty = true
	end
end

---------------------------------------------------------------------------------------------
-- Sauvegarde
---------------------------------------------------------------------------------------------

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: { [any]: any } do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- Écrit le profil. Si une écriture est déjà en cours, ATTEND (jamais de sauvegarde finale perdue).
local function write(player: Player, entry: Entry, release: boolean): boolean
	while entry.Saving do
		task.wait(0.1)
	end
	entry.Saving = true
	entry.Dirty = false -- remis à true si l'écriture échoue ; un `mark` pendant l'écriture le re-salira
	entry.Profile.LastSeen = os.time()
	local snapshot = deepCopy(entry.Profile) -- instantané cohérent AVANT tout yield
	local committed = true
	local ok = retry(Game.SaveRetries, function()
		local success = update(keyFor(player.UserId), function(old: any)
			local record = SessionLock.commit(old, snapshot, game.JobId, os.time(), Game.SessionLockSeconds, release)
			committed = record ~= nil
			return record
		end)
		return success, nil
	end)
	entry.Saving = false
	if ok and committed then
		entry.Refused = 0
		return true
	end
	entry.Dirty = true
	if ok and not committed then
		entry.Refused += 1
		log:error("verrou perdu : écriture refusée pour", player.Name)
		if entry.Refused >= 3 and not release then
			-- Un autre serveur détient le profil : continuer à jouer ici ne serait jamais sauvegardé.
			player:Kick("Your session was taken over by another server. Please rejoin.")
		end
	else
		log:error("échec de sauvegarde pour", player.Name)
	end
	return false
end

function DataService.save(player: Player): boolean
	local entry = entries[player]
	if not entry then
		return false
	end
	return write(player, entry, false)
end

-- Sauvegarde finale + libération du verrou (départ du joueur).
function DataService.release(player: Player)
	local entry = entries[player]
	if not entry or entry.Released then
		return
	end
	entry.Released = true
	local userId = player.UserId
	releasing[userId] = true
	write(player, entry, true)
	entries[player] = nil
	releasing[userId] = nil
end

function DataService.start()
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(DataService.release, player)
	end)

	-- Autosave : un joueur à la fois (liste copiée : `entries` change pendant les yields), protégé par pcall.
	task.spawn(function()
		while true do
			task.wait(Game.AutosaveSeconds)
			local list: { { Player: Player, Entry: Entry } } = {}
			for player, entry in entries do
				table.insert(list, { Player = player, Entry = entry })
			end
			for _, item in list do
				if item.Entry.Dirty and not item.Entry.Released then
					pcall(write, item.Player, item.Entry, false)
					task.wait(0.25)
				end
			end
		end
	end)

	-- Arrêt du serveur : tout le monde en parallèle, budget borné.
	game:BindToClose(function()
		local pending = 0
		local list: { { Player: Player, Entry: Entry } } = {}
		for player, entry in entries do
			table.insert(list, { Player = player, Entry = entry })
		end
		for _, item in list do
			if not item.Entry.Released then
				pending += 1
				task.spawn(function()
					item.Entry.Released = true
					write(item.Player, item.Entry, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + Game.ShutdownBudgetSeconds
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
