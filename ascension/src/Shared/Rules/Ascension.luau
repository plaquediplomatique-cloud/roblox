--!strict
--[[
	Ascension (règles) — prestige. Réinitialise niveau, XP, zones et armes principales ;
	conserve pièces, améliorations, armes de chasse, décor et statistiques ; accorde une étoile
	(bonus permanent d'XP, de pièces et de dégâts).
]]

local Game = require(script.Parent.Parent.Config.Game)
local WeaponCatalog = require(script.Parent.WeaponCatalog)
local Zones = require(script.Parent.Parent.Config.Zones)
local Profile = require(script.Parent.Profile)

local Ascension = {}

function Ascension.canAscend(profile: Profile.Profile): (boolean, string?)
	if profile.Stars >= Game.AscensionMaxStars then
		return false, "Maximum ascension reached"
	end
	if profile.Level < Game.AscensionMinLevel then
		return false, ("Reach level %d to ascend"):format(Game.AscensionMinLevel)
	end
	return true, nil
end

-- Applique l'ascension en place. Renvoie le nombre d'étoiles obtenues.
function Ascension.apply(profile: Profile.Profile): number
	local starter = WeaponCatalog.StarterId
	local keptWeapons: { [string]: boolean } = { [starter] = true }
	for id in profile.Weapons do
		local weapon = WeaponCatalog.ById[id]
		if weapon and not weapon.Main then
			keptWeapons[id] = true
		end
	end
	profile.Weapons = keptWeapons
	profile.Level = 1
	profile.XP = 0
	profile.Zones = { [Zones.List[1].Id] = true }
	if not profile.Weapons[profile.Equipped] then
		profile.Equipped = starter
	end
	profile.Stars += 1
	profile.Stats.Ascensions += 1
	return 1
end

return Ascension
