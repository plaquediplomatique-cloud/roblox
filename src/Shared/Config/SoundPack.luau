--!strict
--[[
	SoundPack — sons maison générés par code : tirs (assets/sounds/weapons,
	tools/gen_weapon_sounds.py), pas par matériau (assets/sounds/foley) et interface
	(assets/sounds/ui, tools/gen_foley_sounds.py). Courts, secs, sans traîne ni écho.

	Roblox ne lit que des sons importés : importer les .mp3 (Creator Hub → Création →
	Audio, ou Studio → Asset Manager → Bulk Import), puis coller ici les identifiants
	(« rbxassetid://123… »), un par variation. Tant qu'une liste est vide, le jeu garde le
	son de repli de Config/Sounds (adouci). Dès qu'elle est remplie, le son du pack est
	joué tel quel : pas d'égaliseur, pas de couches, pas de coupe (il est déjà mixé).
]]

export type PackEntry = { files: { string }, ids: { string }, volume: number }

-- `count` variations numérotées (file_1.mp3 …) ; 0 = un seul fichier sans numéro.
local function entry(file: string, volume: number, count: number?): PackEntry
	local variations = count or 3
	local files = {}
	if variations == 0 then
		files = { file .. ".mp3" }
	else
		for index = 1, variations do
			table.insert(files, ("%s_%d.mp3"):format(file, index))
		end
	end
	return {
		files = files,
		ids = {}, -- ← coller ici les rbxassetid:// des fichiers ci-dessus
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

	-- Pas par matériau (assets/sounds/foley, tools/gen_foley_sounds.py) : 4 variations.
	["Step.Default"] = entry("step_concrete", 0.4, 4),
	["Step.Hard"] = entry("step_concrete", 0.42, 4),
	["Step.Metal"] = entry("step_metal", 0.42, 4),
	["Step.Wood"] = entry("step_wood", 0.42, 4),
	["Step.Soft"] = entry("step_soft", 0.3, 4),

	-- Interface (assets/sounds/ui) : bips ronds, discrets.
	["UI.Hover"] = entry("ui_hover", 0.25, 0),
	["UI.Click"] = entry("ui_click", 0.4, 0),
	["UI.Back"] = entry("ui_back", 0.35, 0),
	["UI.Confirm"] = entry("ui_confirm", 0.4, 0),
	["UI.Error"] = entry("ui_error", 0.4, 0),
	["UI.Tick"] = entry("ui_tick", 0.3, 0),
	["UI.Reward"] = entry("ui_reward", 0.45, 0),
}

return SoundPack
