--!strict
--[[
	RankMath — calculs purs de MMR et de RR (testés unitairement, voir tests/).

	MMR (caché) : Elo d'équipe. Attendu = 1 / (1 + 10^((MMRadv − MMRéquipe)/400)).
	  K = 64 pendant les placements, puis décroît linéairement jusqu'à 24 sur 30 matchs.
	  La performance individuelle (−1..1, dérivée du score de combat relatif) module le
	  delta de ±15 % : on récompense l'impact sans transformer le jeu en course aux kills.

	RR (visible) : base 18 par victoire/défaite, + convergence vers le rang attendu
	  (±4 RR par division d'écart, plafonné à ±10), + performance (±6).
	  Victoire : [8, 35] ; défaite : −[6, 32] ; égalité : [−5, 5].
	  Promotion à 100 RR (le surplus est conservé), rétrogradation sous 0 (RR = 75 + delta
	  restant) — jamais sous Recruit I. AETHER n'a pas de plafond de RR.
]]

local Ranks = require(script.Parent.Parent.Config.Ranks)

export type RankState = {
	MMR: number,
	Uncertainty: number,
	RankIndex: number,
	RR: number,
	Placements: number,
	Matches: number,
	Wins: number,
	Losses: number,
	Peak: number,
}

export type Outcome = {
	won: boolean,
	draw: boolean,
	teamMMR: number,
	enemyMMR: number,
	performance: number,
}

export type Result = {
	state: RankState,
	mmrDelta: number,
	rrDelta: number,
	promoted: boolean,
	demoted: boolean,
	placed: boolean,
	inPlacements: boolean,
}

local RankMath = {}

function RankMath.expected(teamMMR: number, enemyMMR: number): number
	return 1 / (1 + 10 ^ ((enemyMMR - teamMMR) / 400))
end

function RankMath.kFactor(matches: number, placements: number): number
	if placements < Ranks.PLACEMENT_MATCHES then
		return 64
	end
	local t = math.clamp((matches - Ranks.PLACEMENT_MATCHES) / 30, 0, 1)
	return 48 + (24 - 48) * t
end

function RankMath.mmrDelta(state: RankState, outcome: Outcome): number
	local score = if outcome.won then 1 elseif outcome.draw then 0.5 else 0
	local k = RankMath.kFactor(state.Matches, state.Placements)
	local delta = k * (score - RankMath.expected(outcome.teamMMR, outcome.enemyMMR))
	local performance = math.clamp(outcome.performance, -1, 1)
	if delta >= 0 then
		delta *= 1 + 0.15 * performance
	else
		delta *= 1 - 0.15 * performance
	end
	return math.floor(delta + 0.5)
end

function RankMath.rrDelta(rankIndex: number, newMMR: number, outcome: Outcome): number
	local convergence = math.clamp((Ranks.expectedIndex(newMMR) - rankIndex) * 4, -10, 10)
	local performance = math.clamp(outcome.performance, -1, 1) * 6
	if outcome.draw then
		return math.floor(math.clamp(convergence * 0.5 + performance, -5, 5) + 0.5)
	elseif outcome.won then
		return math.floor(math.clamp(18 + convergence + performance, 8, 35) + 0.5)
	else
		return -math.floor(math.clamp(18 - convergence - performance, 6, 32) + 0.5)
	end
end

--[[ Applique un delta de RR avec promotions/rétrogradations en cascade. ]]
function RankMath.applyRR(rankIndex: number, rr: number, delta: number): (number, number)
	local index, value = rankIndex, rr + delta
	while value >= 100 and index < Ranks.MAX_INDEX do
		value -= 100
		index += 1
	end
	while value < 0 do
		if index <= 0 then
			value = 0
			break
		end
		-- Rétrogradation : on retombe au plus à 75 RR dans la division inférieure.
		index -= 1
		value = math.min(value + 100, 75)
	end
	return index, value
end

--[[ Rang de sortie de placement : bridé à SENTINEL III pour que l'élite se mérite. ]]
function RankMath.placementRank(mmr: number): number
	return math.min(math.floor(Ranks.expectedIndex(mmr)), 14)
end

function RankMath.process(state: RankState, outcome: Outcome): Result
	local new = table.clone(state)
	local mmrDelta = RankMath.mmrDelta(state, outcome)
	new.MMR = math.max(Ranks.MMR_FLOOR, state.MMR + mmrDelta)
	new.Matches += 1
	new.Uncertainty = math.max(60, state.Uncertainty * 0.92)
	if outcome.won then
		new.Wins += 1
	elseif not outcome.draw then
		new.Losses += 1
	end

	local result: Result = {
		state = new,
		mmrDelta = mmrDelta,
		rrDelta = 0,
		promoted = false,
		demoted = false,
		placed = false,
		inPlacements = false,
	}

	if state.Placements < Ranks.PLACEMENT_MATCHES then
		new.Placements += 1
		if new.Placements >= Ranks.PLACEMENT_MATCHES then
			new.RankIndex = RankMath.placementRank(new.MMR)
			new.RR = 25
			result.placed = true
		else
			result.inPlacements = true
		end
	else
		local delta = RankMath.rrDelta(state.RankIndex, new.MMR, outcome)
		local index, rr = RankMath.applyRR(state.RankIndex, state.RR, delta)
		new.RankIndex = index
		new.RR = rr
		result.rrDelta = delta
		result.promoted = index > state.RankIndex
		result.demoted = index < state.RankIndex
	end
	new.Peak = math.max(new.Peak, new.RankIndex)
	return result
end

return RankMath
