--!strict
--[[
	Game — constantes de design globales. Tous les « nombres magiques » du jeu sont ici ou
	dans les autres fichiers de Config : l'équilibrage ne demande jamais de toucher à la logique.
]]

return {
	Name = "Smash Ascension",
	ProfileVersion = 1,
	DataStoreName = "SmashAscension_Profiles_v1",
	LeaderboardPrefix = "SmashAscension_LB_v1_",

	-- Progression
	MaxLevel = 120,
	AscensionMinLevel = 100,
	AscensionStarXP = 0.10, -- +10 % XP par étoile
	AscensionStarCoins = 0.10,
	AscensionStarDamage = 0.25,
	AscensionMaxStars = 99,

	-- Combat
	BaseSwingsPerSecond = 1.8,
	MinSwingInterval = 0.2, -- jamais plus rapide, quelles que soient les améliorations
	SwingBurst = 2, -- jetons de tolérance réseau (rafale max)
	SwingTolerance = 0.88, -- le serveur accepte un coup à 88 % de l'intervalle théorique
	ReachPadding = 4, -- studs de tolérance (latence, déplacement)
	BaseReach = 7,
	ComboWindow = 2.2,
	ComboDecayStep = 0.35, -- une fois la fenêtre dépassée : -1 combo par pas
	ComboMax = 100,
	ComboPerStep = 0.01, -- +1 % par point de combo (x2 à 100)
	BaseCritChance = 0.05,
	BaseCritMult = 1.5,
	MegaCritShare = 0.15, -- part des critiques qui deviennent « méga »
	MegaCritMult = 1.6,
	CritChanceCap = 0.6,

	-- Mannequins
	DummyRespawn = 0.9,
	DummyRegenDelay = 4,
	DummyHitsToKillAtZoneStart = 9,
	BossHitsToKillAtZoneStart = 700,
	BossRespawnSeconds = 300,
	BossMinPlayers = 1,

	-- Économie
	CoinsPerKillBase = 6,
	CoinsPerKillGrowth = 1.5, -- par zone
	StartingCoins = 0,

	-- Persistance
	AutosaveSeconds = 60,
	SaveRetries = 4,
	SessionLockSeconds = 120,
	ShutdownBudgetSeconds = 25,

	-- Monétisation : plafond de multiplicateur XP issu de l'argent réel (anti pay-to-win)
	PaidXPMultiplierCap = 3,

	-- Réseau
	FxBroadcastRadius = 90,
	MaxPlayersPerServer = 12,
}
