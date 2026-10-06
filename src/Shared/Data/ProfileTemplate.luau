--!strict
--[[
	ProfileTemplate — schéma du profil persistant, migrations versionnées, réconciliation.

	* `new()` : profil neuf (premier lancement).
	* `migrate(data)` : applique séquentiellement les migrations v(n) -> v(n+1).
	  On ne modifie JAMAIS le sens d'un champ existant sans migration.
	* `reconcile(data)` : complète les clés manquantes depuis le gabarit (ajout de
	  nouvelles fonctionnalités sans casser les anciens profils) et répare les sections
	  invalides (ex. réglages corrompus -> valeurs par défaut).
]]

local Types = require(script.Parent.Parent.Types)
local Settings = require(script.Parent.Parent.Config.Settings)
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)
local Weapons = require(script.Parent.Parent.Config.Weapons)
local Ranks = require(script.Parent.Parent.Config.Ranks)
local Progression = require(script.Parent.Parent.Config.Progression)

local ProfileTemplate = {}

ProfileTemplate.VERSION = 3

function ProfileTemplate.new(): Types.ProfileData
	return {
		Version = ProfileTemplate.VERSION,
		Level = 1,
		XP = 0,
		Currency = { Flux = 500, Crystals = 0 },
		Rank = {
			MMR = Ranks.START_MMR,
			Uncertainty = 350,
			RankIndex = 0,
			RR = 0,
			Placements = 0,
			Wins = 0,
			Losses = 0,
			Peak = 0,
			Season = Progression.PASS_SEASON,
			Matches = 0,
		},
		Stats = {
			Kills = 0,
			Deaths = 0,
			Assists = 0,
			Headshots = 0,
			Matches = 0,
			Wins = 0,
			Damage = 0,
			ShotsFired = 0,
			ShotsHit = 0,
			Plants = 0,
			Defuses = 0,
			Aces = 0,
			Clutches = 0,
			PlayTime = 0,
		},
		Loadout = {
			Primary = Weapons.DEFAULT_LOADOUT.Primary,
			Secondary = Weapons.DEFAULT_LOADOUT.Secondary,
			Melee = Weapons.DEFAULT_LOADOUT.Melee,
		},
		Cosmetics = {
			WeaponSkins = {},
			Operator = "op_standard",
			KillEffect = "ke_none",
			Emotes = { "em_salute", "", "", "" },
			Banner = "bn_default",
			Title = "",
		},
		Inventory = Cosmetics.starterInventory(),
		Pass = {
			Season = Progression.PASS_SEASON,
			XP = 0,
			Premium = false,
			Claimed = {},
		},
		Missions = {
			Day = 0,
			Daily = {},
			Rerolls = 1,
			Week = 0,
			Weekly = {},
		},
		Settings = Settings.defaults(),
		Purchases = {},
		LastMatch = nil,
		Moderation = { Suspicion = 0, Flags = {} },
		Meta = { FirstJoin = 0, LastJoin = 0, Sessions = 0 },
	}
end

--[[ Migrations : index = version source. Chaque fonction transforme en place. ]]
local MIGRATIONS: { [number]: (any) -> () } = {
	-- v1 -> v2 : ajout du bloc Moderation et des Emotes sur 4 emplacements.
	[1] = function(data: any)
		data.Moderation = data.Moderation or { Suspicion = 0, Flags = {} }
		local cosmetics = data.Cosmetics
		if type(cosmetics) == "table" and type(cosmetics.Emotes) == "table" then
			while #cosmetics.Emotes < 4 do
				table.insert(cosmetics.Emotes, "")
			end
		end
	end,
	-- v2 -> v3 : Maj devient le sprint, la marche silencieuse passe sur Alt, touche « Options ».
	-- Une touche déjà prise par le joueur n'est jamais volée : on prend la suivante libre.
	[2] = function(data: any)
		local settings = data.Settings
		local keybinds = if type(settings) == "table" and type(settings.Keybinds) == "table"
			then settings.Keybinds
			else nil
		if not keybinds then
			return
		end
		if keybinds.Walk == "LeftShift" then
			keybinds.Walk = nil
		end
		local used: { [string]: boolean } = {}
		for _, key in keybinds do
			used[key] = true
		end
		for _, entry in
			{
				{ action = "Sprint", keys = { "LeftShift", "CapsLock", "V" } },
				{ action = "Walk", keys = { "LeftAlt", "X", "Z" } },
				{ action = "Options", keys = { "P", "O", "F1" } },
			}
		do
			if keybinds[entry.action] == nil then
				for _, key in entry.keys do
					if not used[key] then
						keybinds[entry.action] = key
						used[key] = true
						break
					end
				end
			end
		end
	end,
}

function ProfileTemplate.migrate(data: any): any
	if type(data) ~= "table" then
		return ProfileTemplate.new()
	end
	local version = if type(data.Version) == "number" then data.Version else 1
	while version < ProfileTemplate.VERSION do
		local migration = MIGRATIONS[version]
		if migration then
			migration(data)
		end
		version += 1
	end
	data.Version = ProfileTemplate.VERSION
	return data
end

local function isArray(value: any): boolean
	return type(value) == "table" and (next(value) == nil or value[1] ~= nil)
end

local function fill(target: any, template: any)
	for key, default in template do
		local current = target[key]
		if current == nil then
			target[key] = if type(default) == "table" then table.clone(default) else default
		elseif type(default) == "table" and type(current) == "table" and not isArray(default) then
			fill(current, default)
		elseif type(default) ~= type(current) then
			-- Type corrompu : on restaure la valeur par défaut.
			target[key] = if type(default) == "table" then table.clone(default) else default
		end
	end
end

function ProfileTemplate.reconcile(data: any): Types.ProfileData
	local template = ProfileTemplate.new() :: any
	fill(data, template)
	if not Settings.validate(data.Settings) then
		data.Settings = Settings.defaults()
	end
	for slot, weaponId in data.Loadout do
		if not Weapons.isValidForSlot(weaponId, slot) then
			data.Loadout[slot] = (Weapons.DEFAULT_LOADOUT :: any)[slot]
		end
	end
	for itemId in Cosmetics.starterInventory() do
		data.Inventory[itemId] = true
	end
	return data :: Types.ProfileData
end

return ProfileTemplate
