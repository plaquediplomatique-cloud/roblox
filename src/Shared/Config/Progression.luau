--!strict
--[[
	Progression — XP, niveaux, récompenses de niveau et Aether Pass (battle pass "soft").

	Principes :
	  * Toute action utile rapporte de l'XP (kill, assist, objectif, victoire de manche),
	    la victoire de match est la plus grosse source : on récompense le jeu d'équipe.
	  * Courbe de niveau douce (1500 XP + 125/niveau) : un niveau ≈ 1 à 2 matchs au début.
	  * Le Pass utilise la MÊME XP (aucune grind parallèle) : 50 paliers de 3000 XP.
	  * Piste gratuite généreuse (Flux + cosmétiques), piste premium = cosmétiques exclusifs.
	    Aucune récompense ne donne d'avantage en jeu (toutes les armes sont débloquées).
]]

export type PassReward = {
	free: string?,
	premium: string?,
	freeFlux: number?,
	premiumFlux: number?,
}

local Progression = {}

Progression.MAX_LEVEL = 200
Progression.LEVEL_FLUX = 100

Progression.XP = {
	Kill = 75,
	Assist = 30,
	Headshot = 25,
	FirstBlood = 50,
	RoundWin = 100,
	Plant = 75,
	Defuse = 100,
	Clutch = 150,
	Ace = 300,
	MatchComplete = 500,
	MatchWin = 1000,
	MVP = 200,
	DailyMission = 0, -- défini par mission
}

function Progression.xpForLevel(level: number): number
	return 1500 + (math.clamp(level, 1, Progression.MAX_LEVEL) - 1) * 125
end

--[[ Ajoute de l'XP ; renvoie (niveau, xp dans le niveau, niveaux gagnés). ]]
function Progression.addXP(level: number, xp: number, amount: number): (number, number, number)
	local newLevel, newXP, gained = level, xp + math.max(0, amount), 0
	while newLevel < Progression.MAX_LEVEL do
		local needed = Progression.xpForLevel(newLevel)
		if newXP < needed then
			break
		end
		newXP -= needed
		newLevel += 1
		gained += 1
	end
	if newLevel >= Progression.MAX_LEVEL then
		newXP = math.min(newXP, Progression.xpForLevel(Progression.MAX_LEVEL))
	end
	return newLevel, newXP, gained
end

--[[ Récompenses d'objets aux niveaux jalons (en plus des Flux à chaque niveau). ]]
Progression.levelRewards = {
	[5] = "em_wave",
	[10] = "skin_obsidian_p10",
	[15] = "bn_circuit",
	[20] = "skin_arctic_vk12",
	[30] = "ke_voltage",
	[40] = "skin_ember_kr7",
	[50] = "op_nightops",
	[75] = "skin_crimson_ar9",
	[100] = "skin_specter_ionblade",
} :: { [number]: string }

---------------------------------------------------------------------------------------------
-- Aether Pass — Saison 1 "IGNITION"
---------------------------------------------------------------------------------------------

Progression.PASS_SEASON = 1
Progression.PASS_NAME = "SAISON 1 — IGNITION"
Progression.PASS_TIER_XP = 3000
Progression.PASS_TIERS = 50

local passRewards: { [number]: PassReward } = {}
for tier = 1, Progression.PASS_TIERS do
	local reward: PassReward = {}
	if tier % 2 == 1 then
		reward.freeFlux = 150
	end
	if tier % 5 == 0 then
		reward.premiumFlux = 300
	end
	passRewards[tier] = reward
end

-- Jalons cosmétiques (gratuits et premium)
passRewards[3].free = "skin_obsidian_sx5"
passRewards[4].premium = "skin_solar_vk12"
passRewards[8].free = "em_flex"
passRewards[10].premium = "op_ronin"
passRewards[12].free = "skin_arctic_ar9"
passRewards[15].premium = "skin_crimson_r44"
passRewards[18].free = "bn_aurora"
passRewards[20].premium = "ke_disintegrate"
passRewards[24].free = "skin_ember_hmg40"
passRewards[25].premium = "skin_specter_rs1"
passRewards[30].premium = "em_glitch"
passRewards[32].free = "skin_solar_dm4"
passRewards[35].premium = "op_wraith"
passRewards[40].premium = "ke_shatter"
passRewards[42].free = "skin_crimson_mp6"
passRewards[45].premium = "skin_aether_ar9"
passRewards[47].premium = "ke_rift"
passRewards[48].free = "skin_specter_p10"
passRewards[49].premium = "op_ascendant"
passRewards[50].premium = "skin_aether_vk12"
passRewards[50].free = "bn_apex"

Progression.passRewards = passRewards

function Progression.passTier(passXP: number): number
	return math.clamp(math.floor(passXP / Progression.PASS_TIER_XP), 0, Progression.PASS_TIERS)
end

return Progression
