--!strict
--[[
	DataService — persistance robuste à VERROUILLAGE DE SESSION (équivalent ProfileService).

	Problème résolu : un joueur passe du lobby au serveur de match (et inversement) en
	quelques secondes. Sans verrou, deux serveurs peuvent écrire le même profil en même
	temps -> perte de progression ou DUPLICATION d'objets. Ici :

	  * Chargement = UpdateAsync qui pose un verrou { JobId, PlaceId, Time } sur l'entrée.
	    Si un AUTRE serveur détient un verrou récent, on attend et on réessaie (le serveur
	    de match libère le profil à la déconnexion). Après ~20 s on "vole" le verrou :
	    l'ancien serveur s'en apercevra à sa prochaine sauvegarde et expulsera le joueur.
	  * Sauvegarde automatique toutes les 90 s (étalées), toujours via UpdateAsync qui
	    VÉRIFIE que la session nous appartient encore — sinon : on n'écrit pas, on expulse.
	  * Libération à la déconnexion (verrou retiré), et à la fermeture du serveur
	    (BindToClose, en parallèle, borné à 25 s).
	  * Migrations + réconciliation (ProfileTemplate) à chaque chargement.
	  * Budget DataStore respecté (GetRequestBudgetForRequestType), retries exponentiels.
	  * Si le chargement échoue définitivement : le joueur est expulsé proprement. On ne
	    laisse JAMAIS jouer quelqu'un sur un profil vide qui écraserait ses vraies données.
	  * Studio sans accès API : magasin en mémoire (même sémantique), clé distincte en
	    Studio avec API pour ne jamais toucher aux profils live.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Logger = require(Shared.Util.Logger)
local ProfileTemplate = require(Shared.Data.ProfileTemplate)

local log = Logger.new("Data")

local STORE_NAME = if RunService:IsStudio() then "AetherStrike_Profiles_Studio_v1" else "AetherStrike_Profiles_v1"
local AUTOSAVE_INTERVAL = 90
local SESSION_TIMEOUT = 1800
local LOCK_STEAL_AFTER = 20
local MAX_DATA_BYTES = 3_800_000

export type Profile = {
	player: Player,
	key: string,
	data: Types.ProfileData,
	loadedAt: number,
	lastSave: number,
	released: boolean,
	saving: boolean,
}

type Session = { JobId: string, PlaceId: number, Time: number }
type Record = { Data: any, Session: Session? }

type Store = {
	update: (key: string, transform: (Record?) -> Record?) -> (),
}

local DataService = {
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, Profile>,
	ProfileReleasing = Signal.new() :: Signal.Signal<Player, Profile>,
}

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local store: Store
local usingMock = false
local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

---------------------------------------------------------------------------------------------
-- Magasins (réel / mémoire)
---------------------------------------------------------------------------------------------

local function waitForBudget()
	if usingMock then
		return
	end
	local deadline = os.clock() + 10
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) <= 0 do
		if os.clock() > deadline then
			return
		end
		task.wait(0.5)
	end
end

local function realStore(dataStore: DataStore): Store
	return {
		update = function(key: string, transform: (Record?) -> Record?)
			waitForBudget()
			dataStore:UpdateAsync(key, function(current: any, _keyInfo: DataStoreKeyInfo): (any, { number }?, {}?)
				local record: Record? = if type(current) == "table" then current :: Record else nil
				local result: any = transform(record)
				return result, nil, nil
			end)
		end,
	}
end

local function mockStore(): Store
	local memory: { [string]: Record } = {}
	return {
		update = function(key: string, transform: (Record?) -> Record?)
			local current = memory[key]
			local copy = if current then HttpService:JSONDecode(HttpService:JSONEncode(current)) else nil
			local result = transform(copy)
			if result ~= nil then
				memory[key] = HttpService:JSONDecode(HttpService:JSONEncode(result))
			end
		end,
	}
end

local function withRetries(label: string, attempts: number, fn: () -> ()): boolean
	for attempt = 1, attempts do
		local ok, err = pcall(fn :: any)
		if ok then
			return true
		end
		log:warn(label, "attempt", attempt, "failed:", err)
		task.wait(math.min(2 ^ attempt, 16))
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------------------------

type LoadStatus = "Loaded" | "Locked" | "Error"

local function tryAcquire(key: string, steal: boolean): (LoadStatus, any)
	local status: LoadStatus = "Error"
	local loadedData: any = nil
	local ok, err = pcall(function()
		store.update(key, function(record: Record?): Record?
			local current: Record = record or { Data = nil, Session = nil }
			local session = current.Session
			local now = os.time()
			if session and session.JobId ~= jobId and (now - session.Time) < SESSION_TIMEOUT and not steal then
				status = "Locked"
				return nil -- annule l'écriture
			end
			current.Session = { JobId = jobId, PlaceId = game.PlaceId, Time = now }
			status = "Loaded"
			loadedData = current.Data
			return current
		end)
	end)
	if not ok then
		log:warn("acquire failed", key, err)
		return "Error", nil
	end
	return status, loadedData
end

local function releaseLock(key: string, data: any?)
	withRetries("release " .. key, 5, function()
		store.update(key, function(record: Record?): Record?
			if not record then
				return nil
			end
			if record.Session and record.Session.JobId ~= jobId then
				return nil -- la session ne nous appartient plus : ne rien écraser
			end
			if data ~= nil then
				record.Data = data
			end
			record.Session = nil
			return record
		end)
	end)
end

local function loadProfile(player: Player)
	local key = "Player_" .. player.UserId
	loading[player] = true
	local started = os.clock()
	local attempt = 0
	local status: LoadStatus = "Error"
	local raw: any = nil
	while player.Parent == Players do
		attempt += 1
		local steal = os.clock() - started > LOCK_STEAL_AFTER
		status, raw = tryAcquire(key, steal)
		if status == "Loaded" then
			break
		end
		if attempt >= 10 then
			break
		end
		task.wait(if status == "Locked" then 3 else math.min(2 ^ attempt, 8))
	end
	loading[player] = nil

	if status ~= "Loaded" then
		if player.Parent == Players then
			log:error("profile load failed for", player.Name, "status", status)
			player:Kick("AETHER STRIKE — Impossible de charger votre profil. Réessayez dans un instant.")
		end
		return
	end

	-- Le joueur est parti pendant le chargement : on rend le verrou immédiatement.
	if player.Parent ~= Players then
		releaseLock(key, nil)
		return
	end

	local data = ProfileTemplate.reconcile(ProfileTemplate.migrate(raw or ProfileTemplate.new()))
	local now = os.time()
	if data.Meta.FirstJoin == 0 then
		data.Meta.FirstJoin = now
	end
	data.Meta.LastJoin = now
	data.Meta.Sessions += 1

	local profile: Profile = {
		player = player,
		key = key,
		data = data,
		loadedAt = now,
		lastSave = os.clock(),
		released = false,
		saving = false,
	}
	profiles[player] = profile
	log:info("profile loaded", player.Name, ("(%.2fs)"):format(os.clock() - started))
	DataService.ProfileLoaded:Fire(player, profile)
end

---------------------------------------------------------------------------------------------
-- Sauvegarde
---------------------------------------------------------------------------------------------

local function serializedSize(data: any): number
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	return if ok then #encoded else math.huge
end

--[[ Sauvegarde ; renvoie false si la session a été volée ou en cas d'échec. ]]
local function saveProfile(profile: Profile, release: boolean): boolean
	if profile.released then
		return false
	end
	if serializedSize(profile.data) > MAX_DATA_BYTES then
		log:error("profile too large, save refused", profile.key)
		return false
	end
	while profile.saving do
		task.wait(0.1)
	end
	profile.saving = true
	local stolen = false
	local snapshot = profile.data
	local ok = withRetries("save " .. profile.key, if release then 5 else 3, function()
		store.update(profile.key, function(record: Record?): Record?
			local current: Record = record or { Data = nil, Session = nil }
			if current.Session and current.Session.JobId ~= jobId then
				stolen = true
				return nil
			end
			current.Data = snapshot
			current.Session = if release then nil else { JobId = jobId, PlaceId = game.PlaceId, Time = os.time() }
			return current
		end)
	end)
	profile.saving = false
	profile.lastSave = os.clock()
	if release then
		profile.released = true
	end
	if stolen then
		profile.released = true
		log:warn("session stolen for", profile.key)
		if profile.player.Parent == Players then
			profile.player:Kick("AETHER STRIKE — Votre profil a été ouvert sur un autre serveur.")
		end
		return false
	end
	return ok
end

local function releaseProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	DataService.ProfileReleasing:Fire(player, profile)
	profile.data.Stats.PlayTime += os.time() - profile.loadedAt
	saveProfile(profile, true)
	profiles[player] = nil
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function DataService.getProfile(player: Player): Profile?
	return profiles[player]
end

function DataService.getData(player: Player): Types.ProfileData?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

--[[ Attend le profil (avec délai max). Utile aux services démarrant après le join. ]]
function DataService.waitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return profiles[player]
end

--[[ Sauvegarde immédiate (achats Robux : on n'accorde l'achat qu'une fois persisté). ]]
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return saveProfile(profile, false)
end

function DataService.isMock(): boolean
	return usingMock
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result then
		store = realStore(result)
		-- Vérifie l'accès API (Studio sans "Enable Studio Access to API Services").
		local probeOk = pcall(function()
			result:GetAsync("__probe")
		end)
		if not probeOk then
			log:warn("DataStore inaccessible : magasin mémoire utilisé (Studio).")
			store = mockStore()
			usingMock = true
		end
	else
		log:warn("DataStore indisponible : magasin mémoire utilisé.")
		store = mockStore()
		usingMock = true
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(function(player)
		loadProfile(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Attend la fin d'un éventuel chargement en cours avant de libérer.
		while loading[player] do
			task.wait(0.1)
		end
		releaseProfile(player)
	end)

	-- Sauvegarde automatique étalée.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for _, profile in profiles do
				if not profile.released and not profile.saving and now - profile.lastSave >= AUTOSAVE_INTERVAL then
					task.spawn(saveProfile, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				releaseProfile(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
