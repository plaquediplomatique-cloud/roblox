--!strict
--[[
	Leaderboards (règles) — métriques de classement calculées côté serveur depuis le profil.
	Le client ne soumet JAMAIS un score. `Weekly` utilise une clé de semaine (cf. Quests.weekNumber).
]]

local Combat = require(script.Parent.Combat)

local Leaderboards = {}

export type Metric = { Id: string, Name: string, Weekly: boolean }

Leaderboards.Metrics = {
	{ Id = "Power", Name = "Power", Weekly = false },
	{ Id = "Level", Name = "Level", Weekly = false },
	{ Id = "Damage", Name = "Best Hit", Weekly = false },
	{ Id = "Playtime", Name = "Playtime", Weekly = false },
	{ Id = "BestCombo", Name = "Best Combo", Weekly = false },
	{ Id = "WeeklyKills", Name = "Weekly Kills", Weekly = true },
} :: { Metric }

-- Valeur (entier) à publier pour une métrique.
function Leaderboards.value(metric: string, profile: any, fighter: Combat.Fighter, weeklyKills: number): number
	if metric == "Power" then
		return Combat.powerRating(fighter)
	elseif metric == "Level" then
		return profile.Stars * 1000 + profile.Level
	elseif metric == "Damage" then
		return profile.Stats.MaxHit
	elseif metric == "Playtime" then
		return math.floor(profile.Stats.PlaySeconds / 60)
	elseif metric == "BestCombo" then
		return profile.Stats.BestCombo
	elseif metric == "WeeklyKills" then
		return weeklyKills
	end
	return 0
end

-- Les OrderedDataStore n'acceptent que des entiers sûrs (|n| < 2^53).
function Leaderboards.clampScore(value: number): number
	if value ~= value then
		return 0
	end
	return math.floor(math.clamp(value, 0, 9e15))
end

return Leaderboards
