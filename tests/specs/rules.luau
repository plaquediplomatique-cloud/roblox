--[[ Tests : rangs/MMR, matchmaking, règles de manche et de match, pas, avatars. ]]

local RankMath = req(Shared.Rules.RankMath)
local MatchmakingAlgorithm = req(Shared.Rules.MatchmakingAlgorithm)
local MatchRules = req(Shared.Rules.MatchRules)
local GameModes = req(Shared.Config.GameModes)
local Ranks = req(Shared.Config.Ranks)
local Footsteps = req(Shared.Rules.Footsteps)
local AvatarRules = req(Shared.Rules.AvatarRules)
local Movement = req(Shared.Config.Movement)

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

T.describe("Pas et sprint", function()
	T.it("marche silencieuse, sprint plus fort que la course", function()
		T.eq(Footsteps.volume("Stand", true, Movement.runSpeed), 0, "marche (Alt) silencieuse")
		T.eq(Footsteps.volume("Stand", false, Movement.walkSpeed), 0, "allure de marche (stick) silencieuse")
		local run = Footsteps.volume("Stand", false, Movement.runSpeed)
		local sprint = Footsteps.volume("Stand", false, Movement.sprintSpeed)
		local crouch = Footsteps.volume("Crouch", false, Movement.crouchSpeed)
		T.expect(run > 0.5, "course audible " .. run)
		T.expect(sprint > run, "sprint plus fort")
		T.expect(crouch > 0 and crouch < run, "accroupi feutré")
		T.eq(Footsteps.volume("Slide", false, 25), 0, "glissade")
	end)
	T.it("foulée plus longue en sprint", function()
		T.expect(Footsteps.stride("Stand", Movement.sprintSpeed) > Footsteps.stride("Stand", Movement.runSpeed))
		T.expect(Footsteps.stride("Crouch", Movement.crouchSpeed) < Footsteps.stride("Stand", Movement.runSpeed))
	end)
	T.it("le sprint reste sous les seuils de l'anti-triche", function()
		local sustained = math.max(Movement.sprintSpeed, Movement.runSpeed * Movement.maxAirSpeedRatio) * 1.08 * 1.15
		T.expect(Movement.sprintSpeed * 1.1 < sustained, "marge réseau sur le sprint")
		T.expect(Movement.sprintSpeed < Movement.slide.startSpeed, "la glissade reste un gain")
	end)
end)

T.describe("Avatar en combat", function()
	T.it("retire les accessoires volumineux, garde les compacts", function()
		T.expect(AvatarRules.oversized(Vector3.new(5, 1, 1)), "épée dorsale")
		T.expect(AvatarRules.oversized(Vector3.new(2.2, 2.2, 2.2)), "volume")
		T.expect(not AvatarRules.oversized(Vector3.new(1.4, 1, 1.4)), "chapeau compact")
		local slots = {}
		for _, field in AvatarRules.MATCH_REMOVED_SLOTS do
			slots[field] = true
		end
		T.expect(slots.BackAccessory and slots.WaistAccessory, "dos et taille retirés")
		T.expect(not slots.HatAccessory and not slots.HairAccessory, "chapeau et cheveux gardés")
	end)
end)

local Onboarding = req(Shared.Rules.Onboarding)

T.describe("Onboarding", function()
	local function step(matches, trained, missions)
		return Onboarding.nextStep({ matches = matches, trainedThisSession = trained, missionsToClaim = missions }, "M")
	end
	T.it("une consigne à la fois, puis plus rien", function()
		T.expect(step(0, false, 0).id == "Training", "nouveau joueur : stand de tir d'abord")
		T.expect(step(0, true, 0).id == "FirstMatch", "après le stand : première partie")
		T.expect(step(0, true, 0).text:find("%[M%]") ~= nil, "la touche du menu est rappelée")
		T.expect(step(1, false, 2).id == "Missions", "missions à réclamer")
		T.expect(step(1, false, 2).text:find("2 missions") ~= nil, "pluriel")
		T.expect(step(1, false, 0) == nil, "rien à faire : pas de consigne")
		T.expect(step(Onboarding.GUIDED_MATCHES, false, 5) == nil, "joueur installé : plus de guidage")
	end)
end)
