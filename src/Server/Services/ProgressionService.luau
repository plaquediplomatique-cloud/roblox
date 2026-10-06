--!strict
--[[
	ProgressionService — XP, niveaux, Aether Pass, rang classé, résumé post-match.

	En fin de match (MatchService -> processMatch) pour chaque joueur présent :
	  1. XP détaillée (kills, assists, headshots, first bloods, manches, objectifs, MVP,
	     victoire, participation) -> niveaux (Flux + objets jalons) + XP de Pass.
	  2. Statistiques de carrière.
	  3. Classé : MMR (Elo d'équipe) + RR (convergence + performance) via RankMath,
	     promotions/rétrogradations notifiées, classement mis à jour.
	  4. Résumé "LastMatch" écrit dans le profil : le lobby l'affiche à l'arrivée (le
	     verrou de session garantit qu'il est sauvegardé avant le chargement côté lobby).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Progression = require(Shared.Config.Progression)
local Ranks = require(Shared.Config.Ranks)
local RankMath = require(Shared.Rules.RankMath)
local Guard = require(Shared.Util.Guard)
local Logger = require(Shared.Util.Logger)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local InventoryService = require(script.Parent.InventoryService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MatchInstance = require(script.Parent.Parent.Match.MatchInstance)

local log = Logger.new("Progression")

local ProgressionService = {}

--[[ Ajoute de l'XP (niveau + Pass). Renvoie le nombre de niveaux gagnés. ]]
function ProgressionService.awardXP(player: Player, amount: number): number
	local data = DataService.getData(player)
	if not data or amount <= 0 then
		return 0
	end
	local before = data.Level
	local level, xp, gained = Progression.addXP(data.Level, data.XP, amount)
	PlayerService.set(player, { "XP" }, xp)
	if gained > 0 then
		PlayerService.set(player, { "Level" }, level)
		for reached = before + 1, level do
			InventoryService.addFlux(player, Progression.LEVEL_FLUX)
			local reward = Progression.levelRewards[reached]
			if reward then
				InventoryService.grant(player, reward)
			end
		end
		PlayerService.notify(player, "LevelUp", "NIVEAU " .. level, { level = level })
		PlayerService.refreshPublic(player)
	end
	local passBefore = Progression.passTier(data.Pass.XP)
	PlayerService.increment(player, { "Pass", "XP" }, amount)
	local passAfter = Progression.passTier(data.Pass.XP)
	if passAfter > passBefore then
		PlayerService.notify(player, "PassTier", "AETHER PASS — PALIER " .. passAfter, { tier = passAfter })
	end
	return gained
end

function ProgressionService.claimPass(player: Player, tier: number, track: "free" | "premium"): ServerNet.Response
	local data = DataService.getData(player)
	if not data then
		return ServerNet.failure("Profil non chargé")
	end
	if tier < 1 or tier > Progression.passTier(data.Pass.XP) then
		return ServerNet.failure("Palier non atteint")
	end
	if track == "premium" and not data.Pass.Premium then
		return ServerNet.failure("Pass premium requis")
	end
	local claimKey = track .. ":" .. tier
	if data.Pass.Claimed[claimKey] then
		return ServerNet.failure("Déjà récupéré")
	end
	local reward = Progression.passRewards[tier]
	if not reward then
		return ServerNet.failure("Palier invalide")
	end
	PlayerService.set(player, { "Pass", "Claimed", claimKey }, true)
	local item = if track == "free" then reward.free else reward.premium
	local flux = if track == "free" then reward.freeFlux else reward.premiumFlux
	if item then
		InventoryService.grant(player, item)
	end
	if flux then
		InventoryService.addFlux(player, flux)
	end
	return ServerNet.success({ item = item, flux = flux })
end

local function teamAverageMMR(result: MatchInstance.MatchResult, team: Types.TeamId): number
	local total, count = 0, 0
	for _, entry in result.players do
		local data = DataService.getData(entry.player)
		if data and entry.team == team then
			total += data.Rank.MMR
			count += 1
		end
	end
	return if count > 0 then total / count else 1000
end

function ProgressionService.processMatch(result: MatchInstance.MatchResult)
	local mmr = { A = teamAverageMMR(result, "A"), B = teamAverageMMR(result, "B") }
	local scoreSum, scoreCount = 0, 0
	for _, entry in result.players do
		scoreSum += entry.stats.score
		scoreCount += 1
	end
	local averageScore = if scoreCount > 0 then scoreSum / scoreCount else 1

	for _, entry in result.players do
		local player = entry.player
		local data = DataService.getData(player)
		if not data then
			continue
		end
		local stats = entry.stats
		local won = result.winner ~= nil and result.winner == entry.team
		local draw = result.draw
		local isMvp = result.mvp == player

		-- 1. XP détaillée
		local breakdown: { { label: string, amount: number } } = {}
		local total = 0
		local function add(label: string, amount: number)
			if amount > 0 then
				table.insert(breakdown, { label = label, amount = amount })
				total += amount
			end
		end
		add("Éliminations", stats.kills * Progression.XP.Kill)
		add("Assistances", stats.assists * Progression.XP.Assist)
		add("Headshots", stats.headshots * Progression.XP.Headshot)
		add("First bloods", stats.firstBloods * Progression.XP.FirstBlood)
		add("Manches gagnées", result.scores[entry.team] * Progression.XP.RoundWin)
		add("Objectifs", stats.plants * Progression.XP.Plant + stats.defuses * Progression.XP.Defuse)
		add("Match terminé", Progression.XP.MatchComplete)
		if won then
			add("Victoire", Progression.XP.MatchWin)
		end
		if isMvp then
			add("MVP", Progression.XP.MVP)
		end
		local levelBefore = data.Level
		ProgressionService.awardXP(player, total)

		-- 2. Statistiques de carrière
		PlayerService.increment(player, { "Stats", "Kills" }, stats.kills)
		PlayerService.increment(player, { "Stats", "Deaths" }, stats.deaths)
		PlayerService.increment(player, { "Stats", "Assists" }, stats.assists)
		PlayerService.increment(player, { "Stats", "Headshots" }, stats.headshots)
		PlayerService.increment(player, { "Stats", "Damage" }, stats.damage)
		PlayerService.increment(player, { "Stats", "Plants" }, stats.plants)
		PlayerService.increment(player, { "Stats", "Defuses" }, stats.defuses)
		PlayerService.increment(player, { "Stats", "Matches" }, 1)
		if won then
			PlayerService.increment(player, { "Stats", "Wins" }, 1)
		end

		-- 3. Rang classé
		local rankBefore, rrBefore = data.Rank.RankIndex, data.Rank.RR
		local rrDelta = 0
		if result.ranked then
			local enemy: Types.TeamId = if entry.team == "A" then "B" else "A"
			local performance = math.clamp((stats.score - averageScore) / math.max(averageScore, 1), -1, 1)
			local outcome: RankMath.Outcome = {
				won = won,
				draw = draw,
				teamMMR = mmr[entry.team],
				enemyMMR = mmr[enemy],
				performance = performance,
			}
			local ranked = RankMath.process(data.Rank :: any, outcome)
			PlayerService.set(player, { "Rank" }, ranked.state)
			rrDelta = ranked.rrDelta
			if ranked.promoted or ranked.placed then
				PlayerService.notify(player, "RankUp", Ranks.displayName(ranked.state.RankIndex), { rankIndex = ranked.state.RankIndex })
			elseif ranked.demoted then
				PlayerService.notify(player, "RankDown", Ranks.displayName(ranked.state.RankIndex), { rankIndex = ranked.state.RankIndex })
			end
			LeaderboardService.submit(player)
		end

		-- 4. Résumé post-match
		local summary: Types.PostMatchSummary = {
			matchId = result.matchId,
			mode = result.modeId,
			map = result.mapId,
			ranked = result.ranked,
			result = if draw then "Draw" elseif won then "Victory" else "Defeat",
			scoreFor = result.scores[entry.team],
			scoreAgainst = result.scores[if entry.team == "A" then "B" else "A"],
			kills = stats.kills,
			deaths = stats.deaths,
			assists = stats.assists,
			damage = stats.damage,
			headshots = stats.headshots,
			score = stats.score,
			rounds = result.rounds,
			mvp = isMvp,
			xpGained = total,
			xpBreakdown = breakdown,
			levelBefore = levelBefore,
			levelAfter = data.Level,
			rrBefore = rrBefore,
			rrAfter = data.Rank.RR,
			rankBefore = rankBefore,
			rankAfter = data.Rank.RankIndex,
			rrDelta = rrDelta,
			timestamp = os.time(),
			seen = false,
		}
		PlayerService.set(player, { "LastMatch" }, summary)
		PlayerService.refreshPublic(player)
	end
	log:info("progression appliquée", result.matchId, #result.players, "joueurs")
end

function ProgressionService.Init() end

function ProgressionService.Start()
	-- Marque le résumé comme vu (le client le signale après l'écran de stats).
	ServerNet.onInvoke("ProfileQuery", { capacity = 6, refill = 2 }, function(payload: any): { action: string }?
		local valid = Guard.shape({ action = Guard.oneOf({ "SeenLastMatch" }) })
		return if valid(payload) then payload :: { action: string } else nil
	end, function(player: Player, _payload: { action: string }): ServerNet.Response
		local data = DataService.getData(player)
		if data and data.LastMatch then
			PlayerService.set(player, { "LastMatch", "seen" }, true)
		end
		return ServerNet.success()
	end)
end

return ProgressionService
