--!strict
--[[
	SoundPack — sons de tir maison (assets/sounds/weapons/*.mp3, générés par
	tools/gen_weapon_sounds.py) : « pew / thock » courts et ronds, sans traîne ni écho.

	Roblox ne lit que des sons importés : importer les .mp3 (Creator Hub → Création →
	Audio, ou Studio → Asset Manager → Bulk Import), puis coller ici les identifiants
	(« rbxassetid://123… »), un par variation. Tant qu'une liste est vide, le jeu garde le
	son de repli de Config/Sounds (adouci). Dès qu'elle est remplie, le son du pack est
	joué tel quel : pas d'égaliseur, pas de couches, pas de coupe (il est déjà mixé).
]]

export type PackEntry = { files: { string }, ids: { string }, volume: number }

local function entry(file: string, volume: number): PackEntry
	return {
		files = { file .. "_1.mp3", file .. "_2.mp3", file .. "_3.mp3" },
		ids = {}, -- ← coller ici les rbxassetid:// des trois fichiers
		volume = volume,
	}
end

local SoundPack: { [string]: PackEntry } = {
	["Weapon.Rifle.Fire"] = entry("rifle", 0.5),
	["Weapon.Rifle.Burst"] = entry("rifle", 0.48),
	["Weapon.Rifle.Suppressed"] = entry("suppressed", 0.45),
	["Weapon.SMG.Fire"] = entry("smg", 0.45),
	["Weapon.MP.Fire"] = entry("mp", 0.42),
	["Weapon.LMG.Fire"] = entry("lmg", 0.5),
	["Weapon.DMR.Fire"] = entry("dmr", 0.52),
	["Weapon.Sniper.Fire"] = entry("sniper", 0.55),
	["Weapon.Shotgun.Fire"] = entry("shotgun", 0.55),
	["Weapon.Shotgun.Auto"] = entry("shotgun", 0.5),
	["Weapon.Pistol.Fire"] = entry("pistol", 0.45),
	["Weapon.Revolver.Fire"] = entry("revolver", 0.52),
	["Weapon.Distant.Rifle"] = entry("distant", 0.35),
	["Weapon.Distant.Light"] = entry("distant", 0.3),
	["Weapon.Distant.Heavy"] = entry("distant", 0.4),
	["Weapon.Distant.Sniper"] = entry("distant", 0.45),
	["Weapon.Mech.Rifle"] = entry("mech", 0.2),
	["Weapon.Mech.Light"] = entry("mech", 0.16),
}

return SoundPack
