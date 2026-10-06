--!strict
--[[
	GameModes — définition des modes de jeu (règles de manche, victoire, prolongations).

	Objectifs :
	  * "Elimination" : la manche se gagne en éliminant toute l'équipe adverse ; au
	    temps écoulé, l'équipe avec le plus de survivants puis le plus de PV gagne.
	  * "Uplink" : attaque/défense. Les attaquants posent la charge Aether sur un site
	    (4 s), les défenseurs la désamorcent (7 s, checkpoint à mi-parcours). Victoire
	    attaque = élimination avant pose ou détonation ; victoire défense = élimination
	    avant pose, temps écoulé sans pose, ou désamorçage.
	Prolongations : à (roundsToWin−1) partout, il faut 2 manches d'écart ; les côtés
	alternent à chaque manche ; après `overtimeMaxRounds`, mort subite.
]]

export type ModeDef = {
	id: string,
	displayName: string,
	tagline: string,
	teamSize: number,
	objective: "Elimination" | "Uplink",
	roundsToWin: number,
	halfAfter: number, -- échange de côtés après N manches (0 = jamais)
	roundTime: number,
	prepTime: number,
	roundEndTime: number,
	introTime: number,
	matchEndTime: number,
	plantTime: number,
	defuseTime: number,
	fuseTime: number,
	pistolRounds: boolean,
	shields: number,
	overtime: boolean,
	overtimeMaxRounds: number,
	ranked: boolean,
	casual: boolean,
	maps: { string },
}

local GameModes = {}

GameModes.defs = {
	Duel = {
		id = "Duel",
		displayName = "DUEL",
		tagline = "1v1 — Élimination pure, premier à 7",
		teamSize = 1,
		objective = "Elimination",
		roundsToWin = 7,
		halfAfter = 6,
		roundTime = 60,
		prepTime = 6,
		roundEndTime = 4,
		introTime = 7,
		matchEndTime = 12,
		plantTime = 0,
		defuseTime = 0,
		fuseTime = 0,
		pistolRounds = false,
		shields = 50,
		overtime = true,
		overtimeMaxRounds = 4,
		ranked = true,
		casual = true,
		maps = { "kestrel", "monolith" },
	},
	Wingman = {
		id = "Wingman",
		displayName = "WINGMAN",
		tagline = "2v2 — Attaque/Défense, un site, premier à 7",
		teamSize = 2,
		objective = "Uplink",
		roundsToWin = 7,
		halfAfter = 6,
		roundTime = 90,
		prepTime = 10,
		roundEndTime = 5,
		introTime = 8,
		matchEndTime = 12,
		plantTime = 4,
		defuseTime = 7,
		fuseTime = 40,
		pistolRounds = true,
		shields = 50,
		overtime = true,
		overtimeMaxRounds = 4,
		ranked = true,
		casual = true,
		maps = { "helix", "monolith" },
	},
	Squad = {
		id = "Squad",
		displayName = "SQUAD",
		tagline = "3v3 — Attaque/Défense, deux sites, premier à 8",
		teamSize = 3,
		objective = "Uplink",
		roundsToWin = 8,
		halfAfter = 7,
		roundTime = 100,
		prepTime = 12,
		roundEndTime = 5,
		introTime = 8,
		matchEndTime = 12,
		plantTime = 4,
		defuseTime = 7,
		fuseTime = 40,
		pistolRounds = true,
		shields = 50,
		overtime = true,
		overtimeMaxRounds = 6,
		ranked = true,
		casual = true,
		maps = { "spire", "monolith" },
	},
	Clash2 = {
		id = "Clash2",
		displayName = "CLASH 2v2",
		tagline = "2v2 — Élimination par manches, premier à 5",
		teamSize = 2,
		objective = "Elimination",
		roundsToWin = 5,
		halfAfter = 4,
		roundTime = 75,
		prepTime = 8,
		roundEndTime = 4,
		introTime = 6,
		matchEndTime = 10,
		plantTime = 0,
		defuseTime = 0,
		fuseTime = 0,
		pistolRounds = false,
		shields = 50,
		overtime = false,
		overtimeMaxRounds = 0,
		ranked = false,
		casual = true,
		maps = { "kestrel", "helix", "monolith" },
	},
	Clash3 = {
		id = "Clash3",
		displayName = "CLASH 3v3",
		tagline = "3v3 — Élimination par manches, premier à 5",
		teamSize = 3,
		objective = "Elimination",
		roundsToWin = 5,
		halfAfter = 4,
		roundTime = 90,
		prepTime = 8,
		roundEndTime = 4,
		introTime = 6,
		matchEndTime = 10,
		plantTime = 0,
		defuseTime = 0,
		fuseTime = 0,
		pistolRounds = false,
		shields = 50,
		overtime = false,
		overtimeMaxRounds = 0,
		ranked = false,
		casual = true,
		maps = { "spire", "helix", "monolith" },
	},
} :: { [string]: ModeDef }

GameModes.order = { "Duel", "Wingman", "Squad", "Clash2", "Clash3" }

function GameModes.get(id: string): ModeDef?
	return GameModes.defs[id]
end

--[[ Clé de file d'attente : "Squad:R" (ranked) ou "Squad:C" (casual). ]]
function GameModes.queueKey(modeId: string, ranked: boolean): string
	return modeId .. (if ranked then ":R" else ":C")
end

--[[
	Manche "pistolet" : 1re manche de chaque mi-temps (pas en prolongation).
	Loadout limité au secondaire + mêlée, sans bouclier.
]]
function GameModes.isPistolRound(mode: ModeDef, round: number): boolean
	if not mode.pistolRounds then
		return false
	end
	return round == 1 or (mode.halfAfter > 0 and round == mode.halfAfter + 1)
end

return GameModes
