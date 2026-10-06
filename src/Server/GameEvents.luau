--!strict
--[[
	GameEvents — bus d'événements de gameplay côté serveur.

	Découplage : CombatService ne connaît ni les missions, ni la progression, ni le
	killfeed des matchs. Il publie "Kill", et chaque système intéressé s'abonne.
	Ajouter une mission "kills en glissade" ne touche AUCUN code de combat.
]]

local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)

export type KillInfo = {
	killer: Player?,
	victim: Player?,
	victimBotId: number?,
	weaponId: string,
	category: string,
	slot: string,
	headshot: boolean,
	wallbang: boolean,
	slide: boolean,
	airborne: boolean,
	noscope: boolean,
	firstBlood: boolean,
	distance: number,
	arena: string,
	assisters: { Player },
}

export type DamageInfo = {
	attacker: Player?,
	victim: Player?,
	victimBotId: number?,
	amount: number,
	zone: string,
	weaponId: string,
	arena: string,
}

export type RoundInfo = {
	matchId: string,
	round: number,
	winners: { Player },
	losers: { Player },
	reason: string,
	clutch: Player?,
	ace: Player?,
	firstBlood: Player?,
}

export type MatchEndInfo = {
	matchId: string,
	modeId: string,
	ranked: boolean,
	winners: { Player },
	losers: { Player },
	draw: boolean,
}

export type ObjectiveInfo = {
	player: Player,
	action: "Plant" | "Defuse",
	matchId: string,
}

export type TrainingHitInfo = {
	player: Player,
	headshot: boolean,
	killed: boolean,
}

local GameEvents = {
	Kill = Signal.new() :: Signal.Signal<KillInfo>,
	Damage = Signal.new() :: Signal.Signal<DamageInfo>,
	RoundEnd = Signal.new() :: Signal.Signal<RoundInfo>,
	MatchEnd = Signal.new() :: Signal.Signal<MatchEndInfo>,
	Objective = Signal.new() :: Signal.Signal<ObjectiveInfo>,
	TrainingHit = Signal.new() :: Signal.Signal<TrainingHitInfo>,
	ShotFired = Signal.new() :: Signal.Signal<Player, string, number>,
}

return GameEvents
