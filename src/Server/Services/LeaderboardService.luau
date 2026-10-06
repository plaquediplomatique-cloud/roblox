--!strict
--[[
	LeaderboardService — classement global classé (OrderedDataStore par saison).

	* Score = rankIndex × 100 + RR (tri stable et lisible : un APEX III à 40 RR = 2040).
	* Écriture à la fin de chaque match classé (et au chargement, pour corriger).
	* Lecture du top 50 toutes les 120 s (budget DataStore maîtrisé), noms résolus et mis
	  en cache, publié dans le replica "Leaderboard" (tous les clients) : affiché sur le
	  mur du Hall of Fame et dans le menu.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Ranks = require(Shared.Config.Ranks)
local Progression = require(Shared.Config.Progression)
local Logger = require(Shared.Util.Logger)
local DataService = require(script.Parent.DataService)
local ReplicaService = require(script.Parent.ReplicaService)

local log = Logger.new("Leaderboard")

local REFRESH_INTERVAL = 120
local TOP = 50

local LeaderboardService = {}

local store: OrderedDataStore? = nil
local replica: ReplicaService.Replica
local nameCache: { [number]: string } = {}

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string" then name else ("Agent " .. userId)
	nameCache[userId] = resolved
	return resolved
end

function LeaderboardService.submit(player: Player)
	local data = DataService.getData(player)
	local ordered = store
	if not (data and ordered) or data.Rank.Placements < Ranks.PLACEMENT_MATCHES then
		return
	end
	local score = Ranks.ladderScore(data.Rank.RankIndex, data.Rank.RR)
	task.spawn(function()
		local ok, err = pcall(function()
			ordered:SetAsync(tostring(player.UserId), math.floor(score))
		end)
		if not ok then
			log:warn("submit failed", err)
		end
	end)
end

local function refresh()
	local ordered = store
	if not ordered then
		return
	end
	local ok, pages = pcall(function()
		return ordered:GetSortedAsync(false, TOP)
	end)
	if not ok or not pages then
		log:warn("refresh failed", pages)
		return
	end
	local entries = {}
	for rank, entry in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(entry.key) or 0
		local score = tonumber(entry.value) or 0
		table.insert(entries, {
			rank = rank,
			userId = userId,
			name = nameOf(userId),
			score = score,
			rankIndex = math.floor(score / 100),
			rr = score % 100,
		})
	end
	replica:SetValues({}, { entries = entries, updatedAt = os.time() })
end

function LeaderboardService.Init()
	replica = ReplicaService.new({
		token = "Leaderboard",
		data = { entries = {}, updatedAt = 0, season = Progression.PASS_SEASON },
		replicateTo = "All",
	})
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore("AetherStrike_Ladder_S" .. Progression.PASS_SEASON)
	end)
	if ok then
		store = result
	end
end

function LeaderboardService.Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		LeaderboardService.submit(player)
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return LeaderboardService
