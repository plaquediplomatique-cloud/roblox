--!strict
--[[
	MatchRules — règles de manche et de match, PURES (testées unitairement).

	Le MatchService (serveur) délègue ici toutes les décisions : qui gagne la manche au
	temps écoulé, quand changer de côté, quand le match se termine, prolongations, mort
	subite. Aucune dépendance à Roblox : les règles sont vérifiables hors moteur.
]]

local Types = require(script.Parent.Parent.Types)
local GameModes = require(script.Parent.Parent.Config.GameModes)

type ModeDef = GameModes.ModeDef

export type TeamSnapshot = {
	alive: number,
	health: number, -- somme PV + bouclier des survivants
}

local MatchRules = {}

function MatchRules.other(team: Types.TeamId): Types.TeamId
	if team == "A" then
		return "B"
	end
	return "A"
end

function MatchRules.isOvertime(mode: ModeDef, scoreA: number, scoreB: number): boolean
	if not mode.overtime then
		return false
	end
	local threshold = mode.roundsToWin - 1
	return scoreA >= threshold and scoreB >= threshold
end

--[[ Nombre de manches de prolongation déjà jouées. ]]
function MatchRules.overtimeRoundsPlayed(mode: ModeDef, scoreA: number, scoreB: number): number
	if not MatchRules.isOvertime(mode, scoreA, scoreB) then
		return 0
	end
	return scoreA + scoreB - 2 * (mode.roundsToWin - 1)
end

--[[ Renvoie l'équipe gagnante du match, ou nil si le match continue. ]]
function MatchRules.matchWinner(mode: ModeDef, scoreA: number, scoreB: number): Types.TeamId?
	if MatchRules.isOvertime(mode, scoreA, scoreB) then
		local played = MatchRules.overtimeRoundsPlayed(mode, scoreA, scoreB)
		local lead = scoreA - scoreB
		local suddenDeath = played > mode.overtimeMaxRounds
		local required = if suddenDeath then 1 else 2
		if lead >= required then
			return "A"
		elseif -lead >= required then
			return "B"
		end
		return nil
	end
	if scoreA >= mode.roundsToWin then
		return "A"
	elseif scoreB >= mode.roundsToWin then
		return "B"
	end
	return nil
end

--[[ Balle de match pour l'équipe `team` (une manche gagnée suffit à terminer). ]]
function MatchRules.isMatchPoint(mode: ModeDef, scoreA: number, scoreB: number, team: Types.TeamId): boolean
	local a = scoreA + (if team == "A" then 1 else 0)
	local b = scoreB + (if team == "B" then 1 else 0)
	return MatchRules.matchWinner(mode, a, b) == team
end

--[[ Faut-il changer de côté après la manche `roundPlayed` (scores APRÈS la manche) ? ]]
function MatchRules.sideSwapDue(mode: ModeDef, roundPlayed: number, scoreA: number, scoreB: number): boolean
	-- En prolongation : alternance des côtés à chaque manche jouée.
	if MatchRules.isOvertime(mode, scoreA, scoreB) and MatchRules.overtimeRoundsPlayed(mode, scoreA, scoreB) > 0 then
		return true
	end
	-- Sinon : échange unique à la mi-temps (équité des spawns, y compris en Élimination).
	return mode.halfAfter > 0 and roundPlayed == mode.halfAfter
end

--[[
	Vainqueur au temps écoulé en Élimination : plus de survivants, puis plus de PV
	cumulés ; égalité parfaite -> nil (manche nulle, aucun point).
]]
function MatchRules.eliminationTimeout(a: TeamSnapshot, b: TeamSnapshot): Types.TeamId?
	if a.alive > b.alive or (a.alive == b.alive and a.health > b.health) then
		return "A"
	elseif a.alive < b.alive or (a.alive == b.alive and a.health < b.health) then
		return "B"
	end
	return nil
end

export type RoundSituation = {
	objective: "Elimination" | "Uplink",
	sides: { A: Types.Side, B: Types.Side },
	aliveA: number,
	aliveB: number,
	planted: boolean,
	defused: boolean,
	detonated: boolean,
	timeUp: boolean,
	snapshotA: TeamSnapshot,
	snapshotB: TeamSnapshot,
}

--[[
	Décide si la manche est terminée et pour qui. Renvoie (gagnant, raison) ou nil.
	Raisons : "Elimination", "Detonation", "Defuse", "Time", "Draw".
]]
function MatchRules.evaluateRound(s: RoundSituation): (Types.TeamId?, string?)
	if s.objective == "Elimination" then
		if s.aliveA == 0 and s.aliveB == 0 then
			return nil, "Draw"
		elseif s.aliveA == 0 then
			return "B", "Elimination"
		elseif s.aliveB == 0 then
			return "A", "Elimination"
		elseif s.timeUp then
			local winner: Types.TeamId? = MatchRules.eliminationTimeout(s.snapshotA, s.snapshotB)
			local reason: string = if winner then "Time" else "Draw"
			return winner, reason
		end
		return nil, nil
	end

	local attack: Types.TeamId = if s.sides.A == "Attack" then "A" else "B"
	local defense: Types.TeamId = MatchRules.other(attack)
	local aliveAttack = if attack == "A" then s.aliveA else s.aliveB
	local aliveDefense = if defense == "A" then s.aliveA else s.aliveB

	if s.detonated then
		return attack, "Detonation"
	end
	if s.defused then
		return defense, "Defuse"
	end
	if s.planted then
		-- Charge posée : seule la détonation ou le désamorçage terminent la manche,
		-- sauf si toute la défense est morte (victoire attaque immédiate).
		if aliveDefense == 0 then
			return attack, "Elimination"
		end
		return nil, nil
	end
	if aliveDefense == 0 then
		return attack, "Elimination"
	end
	if aliveAttack == 0 then
		return defense, "Elimination"
	end
	if s.timeUp then
		return defense, "Time"
	end
	return nil, nil
end

function MatchRules.modeOrError(modeId: string): ModeDef
	local mode = GameModes.get(modeId)
	assert(mode, "unknown mode " .. modeId)
	return mode
end

return MatchRules
