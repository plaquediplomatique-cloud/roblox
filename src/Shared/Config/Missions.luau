--!strict
--[[
	Missions — missions quotidiennes (3/jour, 1 reroll) et défis hebdomadaires (4/semaine).

	Tirage DÉTERMINISTE : graine = (UserId, numéro du jour/semaine). Pas de stockage
	du "pool" côté serveur, pas d'abus par reconnexion, résultat identique sur tous les
	serveurs. La progression écoute le bus d'événements de gameplay (GameEvents).

	Les filtres permettent de pousser la variété (classes d'armes, headshots, objectifs,
	Training Range) et donc la découverte de tout l'arsenal.
]]

export type MissionFilter = {
	category: string?,
	headshot: boolean?,
	wallbang: boolean?,
	slide: boolean?,
	ranked: boolean?,
}

export type MissionDef = {
	id: string,
	text: string, -- "{n}" est remplacé par l'objectif
	event: string,
	filter: MissionFilter,
	target: number,
	xp: number,
	flux: number,
	weight: number,
}

local Missions = {}

Missions.DAILY_COUNT = 3
Missions.WEEKLY_COUNT = 4
Missions.DAILY_REROLLS = 1

Missions.daily = {
	{
		id = "d_kills",
		text = "Éliminer {n} ennemis",
		event = "Kill",
		filter = {},
		target = 12,
		xp = 1500,
		flux = 100,
		weight = 3,
	},
	{
		id = "d_headshots",
		text = "Réaliser {n} kills à la tête",
		event = "Kill",
		filter = { headshot = true },
		target = 6,
		xp = 1800,
		flux = 120,
		weight = 2,
	},
	{
		id = "d_ar",
		text = "Éliminer {n} ennemis au fusil d'assaut",
		event = "Kill",
		filter = { category = "AssaultRifle" },
		target = 8,
		xp = 1500,
		flux = 100,
		weight = 2,
	},
	{
		id = "d_smg",
		text = "Éliminer {n} ennemis au SMG",
		event = "Kill",
		filter = { category = "SMG" },
		target = 8,
		xp = 1500,
		flux = 100,
		weight = 2,
	},
	{
		id = "d_sniper",
		text = "Éliminer {n} ennemis au sniper ou DMR",
		event = "Kill",
		filter = { category = "Precision" },
		target = 5,
		xp = 1800,
		flux = 120,
		weight = 1,
	},
	{
		id = "d_shotgun",
		text = "Éliminer {n} ennemis au fusil à pompe",
		event = "Kill",
		filter = { category = "Shotgun" },
		target = 5,
		xp = 1600,
		flux = 110,
		weight = 1,
	},
	{
		id = "d_pistol",
		text = "Éliminer {n} ennemis avec une arme secondaire",
		event = "Kill",
		filter = { category = "Secondary" },
		target = 5,
		xp = 1600,
		flux = 110,
		weight = 2,
	},
	{
		id = "d_slide",
		text = "Éliminer {n} ennemis en glissade",
		event = "Kill",
		filter = { slide = true },
		target = 3,
		xp = 2000,
		flux = 140,
		weight = 1,
	},
	{
		id = "d_rounds",
		text = "Gagner {n} manches",
		event = "RoundWin",
		filter = {},
		target = 8,
		xp = 1500,
		flux = 100,
		weight = 3,
	},
	{
		id = "d_win",
		text = "Gagner {n} match",
		event = "MatchWin",
		filter = {},
		target = 1,
		xp = 2000,
		flux = 150,
		weight = 2,
	},
	{
		id = "d_play",
		text = "Terminer {n} matchs",
		event = "MatchPlayed",
		filter = {},
		target = 2,
		xp = 1500,
		flux = 100,
		weight = 3,
	},
	{
		id = "d_damage",
		text = "Infliger {n} dégâts",
		event = "Damage",
		filter = {},
		target = 2500,
		xp = 1500,
		flux = 100,
		weight = 2,
	},
	{
		id = "d_objective",
		text = "Poser ou désamorcer {n} charges",
		event = "Objective",
		filter = {},
		target = 2,
		xp = 1800,
		flux = 120,
		weight = 1,
	},
	{
		id = "d_firstblood",
		text = "Obtenir {n} first bloods",
		event = "FirstBlood",
		filter = {},
		target = 2,
		xp = 1800,
		flux = 120,
		weight = 1,
	},
	{
		id = "d_wallbang",
		text = "Éliminer {n} ennemis à travers un mur",
		event = "Kill",
		filter = { wallbang = true },
		target = 1,
		xp = 2000,
		flux = 150,
		weight = 1,
	},
	{
		id = "d_training",
		text = "Toucher {n} cibles au Training Range",
		event = "TrainingHit",
		filter = {},
		target = 150,
		xp = 1000,
		flux = 80,
		weight = 2,
	},
} :: { MissionDef }

Missions.weekly = {
	{
		id = "w_wins",
		text = "Gagner {n} matchs",
		event = "MatchWin",
		filter = {},
		target = 8,
		xp = 8000,
		flux = 500,
		weight = 3,
	},
	{
		id = "w_kills",
		text = "Éliminer {n} ennemis",
		event = "Kill",
		filter = {},
		target = 80,
		xp = 8000,
		flux = 500,
		weight = 3,
	},
	{
		id = "w_headshots",
		text = "Réaliser {n} kills à la tête",
		event = "Kill",
		filter = { headshot = true },
		target = 35,
		xp = 9000,
		flux = 600,
		weight = 2,
	},
	{
		id = "w_ranked",
		text = "Gagner {n} matchs classés",
		event = "MatchWin",
		filter = { ranked = true },
		target = 4,
		xp = 10000,
		flux = 700,
		weight = 2,
	},
	{
		id = "w_clutch",
		text = "Remporter {n} clutchs",
		event = "Clutch",
		filter = {},
		target = 3,
		xp = 9000,
		flux = 600,
		weight = 1,
	},
	{
		id = "w_objective",
		text = "Poser ou désamorcer {n} charges",
		event = "Objective",
		filter = {},
		target = 10,
		xp = 8000,
		flux = 500,
		weight = 2,
	},
	{
		id = "w_damage",
		text = "Infliger {n} dégâts",
		event = "Damage",
		filter = {},
		target = 15000,
		xp = 8000,
		flux = 500,
		weight = 2,
	},
} :: { MissionDef }

Missions.byId = {} :: { [string]: MissionDef }
for _, def in Missions.daily do
	Missions.byId[def.id] = def
end
for _, def in Missions.weekly do
	Missions.byId[def.id] = def
end

function Missions.dayIndex(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function Missions.weekIndex(unixTime: number): number
	-- Les semaines commencent le lundi (le 01/01/1970 était un jeudi).
	return math.floor((unixTime / 86400 + 3) / 7)
end

--[[ Tirage pondéré sans remise, déterministe. `exclude` évite de retirer les mêmes missions. ]]
function Missions.roll(
	pool: { MissionDef },
	count: number,
	seed: number,
	exclude: { [string]: boolean }?
): { MissionDef }
	local rng = Random.new(seed)
	local candidates: { MissionDef } = {}
	for _, def in pool do
		if not (exclude and exclude[def.id]) then
			table.insert(candidates, def)
		end
	end
	local picked: { MissionDef } = {}
	while #picked < count and #candidates > 0 do
		local total = 0
		for _, def in candidates do
			total += def.weight
		end
		local roll = rng:NextNumber() * total
		local chosen = #candidates
		for index, def in candidates do
			roll -= def.weight
			if roll <= 0 then
				chosen = index
				break
			end
		end
		table.insert(picked, table.remove(candidates, chosen) :: MissionDef)
	end
	return picked
end

function Missions.format(def: MissionDef): string
	return (string.gsub(def.text, "{n}", tostring(def.target)))
end

--[[ Catégories logiques utilisées par les filtres ("Precision", "Secondary"). ]]
function Missions.categoryMatches(filterCategory: string, weaponCategory: string, weaponSlot: string): boolean
	if filterCategory == weaponCategory then
		return true
	end
	if filterCategory == "Precision" then
		return weaponCategory == "Sniper" or weaponCategory == "DMR"
	end
	if filterCategory == "Secondary" then
		return weaponSlot == "Secondary"
	end
	return false
end

return Missions
