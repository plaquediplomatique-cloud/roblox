--[[ Tests : rangs/MMR, matchmaking, règles de manche et de match. ]]

local RankMath = req(Shared.Rules.RankMath)
local MatchmakingAlgorithm = req(Shared.Rules.MatchmakingAlgorithm)
local MatchRules = req(Shared.Rules.MatchRules)
local GameModes = req(Shared.Config.GameModes)
local Ranks = req(Shared.Config.Ranks)

local function rankState(overrides)
	local state = {
		MMR = 1000,
		Uncertainty = 350,
		RankIndex = 6,
		RR = 50,
		Placements = 5,
		Matches = 20,
		Wins = 10,
		Losses = 10,
		Peak = 6,
	}
	for key, value in overrides or {} do
		state[key] = value
	end
	return state
end

T.describe("RankMath", function()
	T.it("victoire attendue contre plus faible rapporte moins que l'exploit", function()
		local favored = RankMath.mmrDelta(
			rankState(),
			{ won = true, draw = false, teamMMR = 1200, enemyMMR = 1000, performance = 0 }
		)
		local upset = RankMath.mmrDelta(
			rankState(),
			{ won = true, draw = false, teamMMR = 1000, enemyMMR = 1200, performance = 0 }
		)
		T.expect(upset > favored, ("%d > %d"):format(upset, favored))
	end)
	T.it("promotion avec report du surplus", function()
		local index, rr = RankMath.applyRR(6, 90, 25)
		T.eq(index, 7)
		T.eq(rr, 15)
	end)
	T.it("rétrogradation : on retombe à 75 RR max", function()
		local index, rr = RankMath.applyRR(6, 5, -20)
		T.eq(index, 5)
		T.eq(rr, 75)
	end)
	T.it("jamais sous Recruit I", function()
		local index, rr = RankMath.applyRR(0, 3, -30)
		T.eq(index, 0)
		T.eq(rr, 0)
	end)
	T.it("placements : rang attribué au 5e match, bridé à Sentinel III", function()
		local state = rankState({ Placements = 4, MMR = 2400, RankIndex = 0, RR = 0 })
		local result =
			RankMath.process(state, { won = true, draw = false, teamMMR = 2400, enemyMMR = 2400, performance = 1 })
		T.expect(result.placed, "placé")
		T.eq(result.state.RankIndex, 14)
	end)
	T.it("un joueur sous-classé gagne plus de RR", function()
		local outcome = { won = true, draw = false, teamMMR = 1500, enemyMMR = 1500, performance = 0 }
		local under = RankMath.rrDelta(3, 1500, outcome)
		local fair = RankMath.rrDelta(math.floor(Ranks.expectedIndex(1500)), 1500, outcome)
		T.expect(under > fair, ("%d > %d"):format(under, fair))
	end)
	T.it("bornes de RR respectées", function()
		for perf = -1, 1, 0.5 do
			local win =
				RankMath.rrDelta(0, 2000, { won = true, draw = false, teamMMR = 1, enemyMMR = 1, performance = perf })
			local loss =
				RankMath.rrDelta(20, 600, { won = false, draw = false, teamMMR = 1, enemyMMR = 1, performance = perf })
			T.expect(win >= 8 and win <= 35, "win " .. win)
			T.expect(loss <= -6 and loss >= -32, "loss " .. loss)
		end
	end)
end)

local function ticket(id, mmr, players, waited, rank)
	local list = {}
	for index = 1, players do
		table.insert(list, id * 10 + index)
	end
	return {
		id = tostring(id),
		players = list,
		mmr = mmr,
		minRank = rank or 6,
		maxRank = rank or 6,
		enqueuedAt = 1000 - (waited or 0),
		mode = "Squad",
		ranked = true,
		serverId = "local",
	}
end

T.describe("Matchmaking", function()
	T.it("6 solos proches -> un 3v3 équilibré", function()
		local tickets = {}
		for index, mmr in { 1000, 1010, 1020, 1030, 1040, 1050 } do
			table.insert(tickets, ticket(index, mmr, 1, 5))
		end
		local proposals, remaining = MatchmakingAlgorithm.run(tickets, 3, true, 1000)
		T.eq(#proposals, 1)
		T.eq(#remaining, 0)
		local p = proposals[1]
		T.expect(math.abs(p.mmrA - p.mmrB) <= 10, "écart " .. math.abs(p.mmrA - p.mmrB))
	end)
	T.it("une party n'est jamais séparée", function()
		local tickets = { ticket(1, 1000, 3, 5), ticket(2, 1005, 1, 5), ticket(3, 1010, 1, 5), ticket(4, 995, 1, 5) }
		local proposals = MatchmakingAlgorithm.run(tickets, 3, true, 1000)
		T.eq(#proposals, 1)
		local p = proposals[1]
		local partyTeam = nil
		for _, t in p.teamA do
			if t.id == "1" then
				partyTeam = "A"
			end
		end
		for _, t in p.teamB do
			if t.id == "1" then
				partyTeam = "B"
			end
		end
		T.expect(partyTeam ~= nil, "party placée")
		local team = if partyTeam == "A" then p.teamA else p.teamB
		T.eq(#team, 1, "la party remplit seule son équipe")
	end)
	T.it("écart de MMR trop grand : pas de match tant que la fenêtre ne s'élargit pas", function()
		local fresh = { ticket(1, 800, 1, 0), ticket(2, 1300, 1, 0) }
		local proposals = MatchmakingAlgorithm.run(fresh, 1, false, 1000)
		T.eq(#proposals, 0)
		local waited = { ticket(1, 800, 1, 90), ticket(2, 1300, 1, 90) }
		proposals = MatchmakingAlgorithm.run(waited, 1, false, 1000)
		T.eq(#proposals, 1)
	end)
	T.it("classé : écart de rang contrôlé", function()
		local tickets = { ticket(1, 1000, 1, 0, 0), ticket(2, 1000, 1, 0, 15) }
		local proposals = MatchmakingAlgorithm.run(tickets, 1, true, 1000)
		T.eq(#proposals, 0)
	end)
end)

T.describe("MatchRules", function()
	local squad = GameModes.defs.Squad
	local duel = GameModes.defs.Duel
	T.it("premier à 8 en Squad", function()
		T.eq(MatchRules.matchWinner(squad, 8, 3), "A")
		T.eq(MatchRules.matchWinner(squad, 6, 7), nil)
	end)
	T.it("prolongation : 2 manches d'écart requises", function()
		T.eq(MatchRules.matchWinner(duel, 7, 6), nil)
		T.eq(MatchRules.matchWinner(duel, 8, 6), "A")
		T.eq(MatchRules.matchWinner(duel, 7, 7), nil)
	end)
	T.it("mort subite après le maximum de prolongations", function()
		-- 6-6 puis 4 manches de prolongation jouées (8-8), la suivante décide.
		T.eq(MatchRules.matchWinner(duel, 8, 8), nil)
		T.eq(MatchRules.matchWinner(duel, 9, 8), "A")
	end)
	T.it("échange de côtés à la mi-temps puis à chaque manche de prolongation", function()
		T.expect(MatchRules.sideSwapDue(squad, 7, 4, 3), "mi-temps")
		T.expect(not MatchRules.sideSwapDue(squad, 8, 5, 3), "pas après")
		T.expect(MatchRules.sideSwapDue(squad, 15, 8, 7), "prolongation")
	end)
	local function situation(overrides)
		local s = {
			objective = "Uplink",
			sides = { A = "Attack", B = "Defense" },
			aliveA = 3,
			aliveB = 3,
			planted = false,
			defused = false,
			detonated = false,
			timeUp = false,
			snapshotA = { alive = 3, health = 450 },
			snapshotB = { alive = 3, health = 450 },
		}
		for key, value in overrides do
			s[key] = value
		end
		return s
	end
	T.it("Uplink : temps écoulé sans pose = victoire défense", function()
		local winner, reason = MatchRules.evaluateRound(situation({ timeUp = true }))
		T.eq(winner, "B")
		T.eq(reason, "Time")
	end)
	T.it("Uplink : charge posée, attaquants morts -> la manche continue", function()
		local winner = MatchRules.evaluateRound(situation({ planted = true, aliveA = 0 }))
		T.eq(winner, nil)
	end)
	T.it("Uplink : détonation / désamorçage", function()
		T.eq((MatchRules.evaluateRound(situation({ planted = true, detonated = true }))), "A")
		T.eq((MatchRules.evaluateRound(situation({ planted = true, defused = true }))), "B")
	end)
	T.it("Élimination au temps : survivants puis PV", function()
		local s = situation({
			objective = "Elimination",
			timeUp = true,
			snapshotA = { alive = 2, health = 80 },
			snapshotB = { alive = 2, health = 150 },
		})
		T.eq((MatchRules.evaluateRound(s)), "B")
	end)
	T.it("manches pistolet : 1re de chaque mi-temps", function()
		T.expect(GameModes.isPistolRound(squad, 1), "1")
		T.expect(GameModes.isPistolRound(squad, 8), "8")
		T.expect(not GameModes.isPistolRound(squad, 2), "2")
		T.expect(not GameModes.isPistolRound(duel, 1), "duel")
	end)
end)
