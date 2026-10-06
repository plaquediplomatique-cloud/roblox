--!strict
--[[
	Fighter — construit le « combattant » (arme équipée + améliorations + étoiles) depuis un
	profil. Utilisé par le serveur pour résoudre les coups ET par le client pour afficher dégâts,
	puissance et cadence : un seul code, donc jamais de désaccord entre l'affichage et la réalité.
]]

local WeaponCatalog = require(script.Parent.WeaponCatalog)
local Combat = require(script.Parent.Combat)

local Fighter = {}

type ProfileLike = {
	Equipped: string,
	Stars: number,
	Upgrades: { [string]: number },
}

function Fighter.weapon(profile: ProfileLike): WeaponCatalog.Weapon
	return WeaponCatalog.ById[profile.Equipped] or WeaponCatalog.Main[1]
end

function Fighter.fromProfile(profile: ProfileLike): Combat.Fighter
	local weapon = Fighter.weapon(profile)
	local upgrades = profile.Upgrades
	return {
		Damage = weapon.Damage,
		AttackSpeed = weapon.AttackSpeed,
		PowerLevel = upgrades.Power or 0,
		SpeedLevel = upgrades.Speed or 0,
		CritChanceLevel = upgrades.CritChance or 0,
		CritDamageLevel = upgrades.CritDamage or 0,
		Stars = profile.Stars,
		Special = weapon.Special,
	}
end

return Fighter
