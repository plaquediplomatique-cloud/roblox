--!strict
--[[
	GameEvents — bus d'événements de gameplay côté serveur.

	Les systèmes ne s'appellent pas entre eux : CombatService publie « Hit », et la progression,
	les quêtes, les succès, les classements s'abonnent. Ajouter une quête « 50 coups
	critiques » ne touche AUCUN code de combat. Les valeurs passées sont des références
	(pas de copie), les erreurs d'un abonné n'affectent pas les autres.
]]

local Signal = require(game:GetService("ReplicatedStorage").Shared.Util.Signal)
local PlayerService = require(script.Parent.Services.PlayerService)

type State = PlayerService.State

export type HitInfo = {
	Damage: number,
	Crit: number,
	Combo: number,
	Kill: boolean,
	Boss: boolean,
	ZoneIndex: number,
}

local GameEvents = {
	-- Combat
	Hit = Signal.new() :: Signal.Signal<State, HitInfo>,
	Kill = Signal.new() :: Signal.Signal<State, boolean>, -- boss ?
	-- Progression
	LevelUp = Signal.new() :: Signal.Signal<State, number, number>, -- ancien, nouveau
	XPGained = Signal.new() :: Signal.Signal<State, number>,
	CoinsGained = Signal.new() :: Signal.Signal<State, number>,
	WeaponAcquired = Signal.new() :: Signal.Signal<State, string, string>, -- id, source
	ZoneUnlocked = Signal.new() :: Signal.Signal<State, string>,
	UpgradeBought = Signal.new() :: Signal.Signal<State, string, number>,
	Ascended = Signal.new() :: Signal.Signal<State>,
	BossDefeated = Signal.new() :: Signal.Signal<State, string>, -- zone
	DecorChanged = Signal.new() :: Signal.Signal<State>,
	ProfileLoaded = Signal.new() :: Signal.Signal<State>,
}

return GameEvents
