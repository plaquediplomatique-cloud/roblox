--!strict
--[[
	Achievements (règles) — évaluation des succès depuis le profil et réclamation idempotente.
	États dans Profile.Achievements : 1 = atteint (à récupérer), 2 = récompense prise.
]]

local Config = require(script.Parent.Parent.Config.Achievements)
local Zones = require(script.Parent.Parent.Config.Zones)

local Achievements = {}

type Profile = {
	Level: number,
	Weapons: { [string]: boolean },
	Collection: { [string]: boolean },
	Zones: { [string]: boolean },
	Stats: { [string]: number },
	Achievements: { [string]: number },
}

local function count(map: { [string]: boolean }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

function Achievements.metricValue(profile: Profile, metric: string): number
	if metric == "Level" then
		return profile.Level
	elseif metric == "Weapons" then
		return count(profile.Collection)
	elseif metric == "Zones" then
		return count(profile.Zones)
	elseif metric == "PlayHours" then
		return math.floor(profile.Stats.PlaySeconds / 3600)
	end
	return profile.Stats[metric] or 0
end

-- Marque les succès atteints ; renvoie la liste des nouveaux.
function Achievements.evaluate(profile: Profile): { Config.Achievement }
	local fresh: { Config.Achievement } = {}
	for _, achievement in Config.List do
		if profile.Achievements[achievement.Id] == nil then
			if Achievements.metricValue(profile, achievement.Metric) >= achievement.Target then
				profile.Achievements[achievement.Id] = 1
				table.insert(fresh, achievement)
			end
		end
	end
	return fresh
end

function Achievements.claim(profile: Profile, id: string): Config.Achievement?
	local achievement = Config.ById[id]
	if not achievement or profile.Achievements[id] ~= 1 then
		return nil
	end
	profile.Achievements[id] = 2
	return achievement
end

Achievements.ZoneCount = Zones.Count

return Achievements
