--!strict
--[[
	MatchmakingAlgorithm — formation de matchs équilibrés (pur, testé unitairement).

	Entrée : tickets d'une file (un ticket = une party de 1..teamSize joueurs, MMR moyen,
	bornes de rang, heure d'entrée). Sortie : propositions de matchs + tickets restants.

	1. Les tickets les plus anciens sont prioritaires (ancres).
	2. Fenêtre de MMR qui s'élargit avec l'attente : base + croissance × attente, plafonnée.
	   Classé : l'écart de rang autorisé s'élargit aussi (3 divisions, +1 / 20 s, max 9).
	3. On sélectionne, parmi les candidats compatibles les plus proches en MMR, un
	   ensemble de tickets totalisant exactement 2 × teamSize joueurs (une party n'est
	   jamais séparée), puis on cherche la partition en deux équipes qui minimise l'écart
	   de MMR moyen (énumération exhaustive : ≤ 6 tickets -> ≤ 64 sous-ensembles).
	4. Score = écart entre équipes + 0.25 × dispersion : on privilégie des équipes
	   équilibrées ET homogènes.
]]

local Types = require(script.Parent.Parent.Types)

type MatchTicket = Types.MatchTicket
type MatchProposal = Types.MatchProposal

export type Config = {
	baseWindow: number,
	windowGrowth: number,
	maxWindow: number,
	baseRankGap: number,
	rankGapGrowth: number,
	maxRankGap: number,
	candidateLimit: number,
}

local MatchmakingAlgorithm = {}

MatchmakingAlgorithm.DEFAULT_CONFIG = {
	baseWindow = 75,
	windowGrowth = 6,
	maxWindow = 600,
	baseRankGap = 3,
	rankGapGrowth = 1 / 20,
	maxRankGap = 9,
	candidateLimit = 10,
} :: Config

function MatchmakingAlgorithm.window(config: Config, waited: number): number
	return math.min(config.maxWindow, config.baseWindow + config.windowGrowth * math.max(0, waited))
end

function MatchmakingAlgorithm.rankGap(config: Config, waited: number): number
	return math.min(config.maxRankGap, config.baseRankGap + config.rankGapGrowth * math.max(0, waited))
end

local function teamAverage(tickets: { MatchTicket }): number
	local total, count = 0, 0
	for _, ticket in tickets do
		total += ticket.mmr * #ticket.players
		count += #ticket.players
	end
	return if count > 0 then total / count else 0
end

--[[ Meilleure partition de `group` en deux équipes de `teamSize` joueurs. ]]
function MatchmakingAlgorithm.bestSplit(group: { MatchTicket }, teamSize: number): MatchProposal?
	local count = #group
	local best: MatchProposal? = nil
	local bestDiff = math.huge
	-- Le ticket 1 est toujours dans l'équipe A : évite les partitions symétriques en double.
	for mask = 0, (2 ^ (count - 1)) - 1 do
		local teamA: { MatchTicket } = { group[1] }
		local teamB: { MatchTicket } = {}
		local sizeA = #group[1].players
		for index = 2, count do
			if bit32.band(mask, 2 ^ (index - 2)) ~= 0 then
				table.insert(teamA, group[index])
				sizeA += #group[index].players
			else
				table.insert(teamB, group[index])
			end
		end
		if sizeA == teamSize then
			local mmrA, mmrB = teamAverage(teamA), teamAverage(teamB)
			local diff = math.abs(mmrA - mmrB)
			if diff < bestDiff then
				bestDiff = diff
				best = { teamA = teamA, teamB = teamB, mmrA = mmrA, mmrB = mmrB, quality = 0 }
			end
		end
	end
	return best
end

local function compatible(config: Config, ranked: boolean, a: MatchTicket, b: MatchTicket, now: number): boolean
	local waited = math.max(now - a.enqueuedAt, now - b.enqueuedAt)
	if math.abs(a.mmr - b.mmr) > MatchmakingAlgorithm.window(config, waited) then
		return false
	end
	if ranked then
		local gap = math.max(a.maxRank, b.maxRank) - math.min(a.minRank, b.minRank)
		if gap > MatchmakingAlgorithm.rankGap(config, waited) then
			return false
		end
	end
	return true
end

--[[
	Cherche, parmi `candidates` (triés par proximité), un groupe contenant l'ancre et
	totalisant `needed` joueurs. DFS bornée par candidateLimit.
]]
local function findGroups(
	anchor: MatchTicket,
	candidates: { MatchTicket },
	needed: number,
	callback: ({ MatchTicket }) -> ()
)
	local chosen: { MatchTicket } = { anchor }
	local function dfs(start: number, remaining: number)
		if remaining == 0 then
			callback(table.clone(chosen))
			return
		end
		for index = start, #candidates do
			local candidate = candidates[index]
			local size = #candidate.players
			if size <= remaining then
				table.insert(chosen, candidate)
				dfs(index + 1, remaining - size)
				table.remove(chosen)
			end
		end
	end
	dfs(1, needed - #anchor.players)
end

function MatchmakingAlgorithm.run(
	tickets: { MatchTicket },
	teamSize: number,
	ranked: boolean,
	now: number,
	config: Config?
): ({ MatchProposal }, { MatchTicket })
	local cfg = config or MatchmakingAlgorithm.DEFAULT_CONFIG
	local ordered = table.clone(tickets)
	table.sort(ordered, function(a, b)
		return a.enqueuedAt < b.enqueuedAt
	end)

	local used: { [string]: boolean } = {}
	local proposals: { MatchProposal } = {}

	for _, anchor in ordered do
		if used[anchor.id] then
			continue
		end
		local candidates: { MatchTicket } = {}
		for _, other in ordered do
			if other ~= anchor and not used[other.id] and compatible(cfg, ranked, anchor, other, now) then
				table.insert(candidates, other)
			end
		end
		table.sort(candidates, function(a, b)
			return math.abs(a.mmr - anchor.mmr) < math.abs(b.mmr - anchor.mmr)
		end)
		while #candidates > cfg.candidateLimit do
			table.remove(candidates)
		end

		local best: MatchProposal? = nil
		local bestScore = math.huge
		findGroups(anchor, candidates, teamSize * 2, function(group)
			-- Tous les membres doivent être compatibles deux à deux.
			for i = 1, #group do
				for j = i + 1, #group do
					if not compatible(cfg, ranked, group[i], group[j], now) then
						return
					end
				end
			end
			local split = MatchmakingAlgorithm.bestSplit(group, teamSize)
			if split then
				local low, high = math.huge, -math.huge
				for _, ticket in group do
					low = math.min(low, ticket.mmr)
					high = math.max(high, ticket.mmr)
				end
				local score = math.abs(split.mmrA - split.mmrB) + 0.25 * (high - low)
				if score < bestScore then
					bestScore = score
					split.quality = math.clamp(1 - score / cfg.maxWindow, 0, 1)
					best = split
				end
			end
		end)

		if best then
			for _, ticket in best.teamA do
				used[ticket.id] = true
			end
			for _, ticket in best.teamB do
				used[ticket.id] = true
			end
			table.insert(proposals, best)
		end
	end

	local remaining: { MatchTicket } = {}
	for _, ticket in ordered do
		if not used[ticket.id] then
			table.insert(remaining, ticket)
		end
	end
	return proposals, remaining
end

return MatchmakingAlgorithm
