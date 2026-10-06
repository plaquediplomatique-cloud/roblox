--!strict
--[[
	Profile — schéma du profil joueur, valeurs par défaut, MIGRATIONS et assainissement.

	Tout ce qui sort du DataStore passe par `Profile.load(raw)` : données manquantes complétées,
	types forcés, nombres fous (NaN, inf, négatifs, absurdes) ramenés dans les bornes, armes ou
	améliorations inconnues retirées. Un profil corrompu devient un profil jouable, jamais un crash.
]]

local Game = require(script.Parent.Parent.Config.Game)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local Zones = require(script.Parent.Parent.Config.Zones)
local Decor = require(script.Parent.Parent.Config.Decor)
local Loot = require(script.Parent.Parent.Config.Loot)
local WeaponCatalog = require(script.Parent.WeaponCatalog)

export type QuestItem = { Id: string, Progress: number, Claimed: boolean }

export type Profile = {
	Version: number,
	Level: number,
	XP: number,
	Coins: number,
	Stars: number,
	Weapons: { [string]: boolean },
	Collection: { [string]: boolean }, -- armes déjà possédées un jour (survit à l'Ascension)
	Equipped: string,
	Upgrades: { [string]: number },
	Zones: { [string]: boolean },
	Base: { Owned: { [string]: boolean }, Slots: { [string]: string } },
	Stats: {
		Hits: number,
		Kills: number,
		Crits: number,
		BestCombo: number,
		Bosses: number,
		MaxHit: number,
		TotalDamage: number,
		PlaySeconds: number,
		Ascensions: number,
	},
	Quests: { Day: number, Week: number, Items: { QuestItem } },
	Achievements: { [string]: number }, -- 1 = atteint, 2 = récompense prise
	Daily: { Streak: number, LastClaim: number },
	Chests: { [string]: number },
	Pity: { Boss: number, Chest: number },
	Boosts: { XP: number }, -- expiration (timestamp unix)
	Purchases: { string }, -- derniers ReceiptId traités (idempotence)
	Settings: { Music: boolean, Sfx: boolean, Shake: boolean, DamageNumbers: boolean },
	Created: number,
	LastSeen: number,
}

local Profile = {}

local MAX_NUMBER = 1e18
local MAX_PURCHASES = 60

local function defaultProfile(now: number): Profile
	local upgrades = {}
	for _, upgrade in Upgrades.List do
		upgrades[upgrade.Id] = 0
	end
	local starter = WeaponCatalog.StarterId
	return {
		Version = Game.ProfileVersion,
		Level = 1,
		XP = 0,
		Coins = Game.StartingCoins,
		Stars = 0,
		Weapons = { [starter] = true },
		Collection = { [starter] = true },
		Equipped = starter,
		Upgrades = upgrades,
		Zones = { [Zones.List[1].Id] = true },
		Base = { Owned = { PlantPot = true }, Slots = {} },
		Stats = {
			Hits = 0,
			Kills = 0,
			Crits = 0,
			BestCombo = 0,
			Bosses = 0,
			MaxHit = 0,
			TotalDamage = 0,
			PlaySeconds = 0,
			Ascensions = 0,
		},
		Quests = { Day = 0, Week = 0, Items = {} },
		Achievements = {},
		Daily = { Streak = 0, LastClaim = 0 },
		Chests = {},
		Pity = { Boss = 0, Chest = 0 },
		Boosts = { XP = 0 },
		Purchases = {},
		Settings = { Music = true, Sfx = true, Shake = true, DamageNumbers = true },
		Created = now,
		LastSeen = now,
	}
end

Profile.default = defaultProfile

---------------------------------------------------------------------------------------------
-- Migrations : Migrations[n] transforme un profil de version n en version n+1.
---------------------------------------------------------------------------------------------

export type MigrationTable = { [number]: (data: { [string]: any }) -> () }

local MIGRATIONS: MigrationTable = {}

function Profile.migrate(data: { [string]: any }, migrations: MigrationTable?, target: number?): { [string]: any }
	local steps = migrations or MIGRATIONS
	local goal = target or Game.ProfileVersion
	local version = data.Version
	if type(version) ~= "number" or version ~= version or version < 0 then
		version = 0
	end
	while version < goal do
		local step = steps[version]
		if step then
			step(data)
		end
		version += 1
	end
	data.Version = goal
	return data
end

---------------------------------------------------------------------------------------------
-- Assainissement
---------------------------------------------------------------------------------------------

local function num(value: any, fallback: number, min: number, max: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, min, max)
end

local function int(value: any, fallback: number, min: number, max: number): number
	return math.floor(num(value, fallback, min, max))
end

local function asMap(value: any): { [string]: any }
	if type(value) == "table" then
		return value :: { [string]: any }
	end
	return {}
end

local function bool(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function boolMap(value: any, valid: (string) -> boolean): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(value) == "table" then
		for key, flag in value do
			if type(key) == "string" and flag == true and valid(key) then
				out[key] = true
			end
		end
	end
	return out
end

function Profile.sanitize(raw: any, now: number): Profile
	local base = defaultProfile(now)
	if type(raw) ~= "table" then
		return base
	end
	local data = raw :: { [string]: any }

	local profile = base
	profile.Level = int(data.Level, 1, 1, Game.MaxLevel)
	profile.XP = if profile.Level >= Game.MaxLevel then 0 else num(data.XP, 0, 0, MAX_NUMBER)
	profile.Coins = math.floor(num(data.Coins, base.Coins, 0, MAX_NUMBER))
	profile.Stars = int(data.Stars, 0, 0, Game.AscensionMaxStars)

	-- Armes : seulement des identifiants connus ; l'arme de départ n'est jamais perdue.
	local function isWeapon(id: string): boolean
		return WeaponCatalog.ById[id] ~= nil
	end
	profile.Weapons = boolMap(data.Weapons, isWeapon)
	profile.Collection = boolMap(data.Collection, isWeapon)
	profile.Weapons[WeaponCatalog.StarterId] = true
	for id in profile.Weapons do
		profile.Collection[id] = true
	end
	-- Les armes principales dues au niveau actuel sont rétablies (protège d'une perte de données).
	for _, weapon in WeaponCatalog.mainUnlockedAt(profile.Level) do
		profile.Weapons[weapon.Id] = true
		profile.Collection[weapon.Id] = true
	end
	local equipped = data.Equipped
	if type(equipped) == "string" and profile.Weapons[equipped] then
		profile.Equipped = equipped
	else
		profile.Equipped = WeaponCatalog.bestOwned(profile.Weapons).Id
	end

	local upgrades = asMap(data.Upgrades)
	for _, upgrade in Upgrades.List do
		profile.Upgrades[upgrade.Id] = int(upgrades[upgrade.Id], 0, 0, upgrade.Max)
	end

	profile.Zones = boolMap(data.Zones, function(id)
		return Zones.ById[id] ~= nil
	end)
	profile.Zones[Zones.List[1].Id] = true
	-- Une zone n'est jamais « débloquée » au-dessus du niveau requis par erreur de données : on garde.

	local base_ = asMap(data.Base)
	profile.Base.Owned = boolMap(base_.Owned, function(id)
		return Decor.ById[id] ~= nil
	end)
	profile.Base.Owned.PlantPot = true
	if type(base_.Slots) == "table" then
		for slot, itemId in base_.Slots :: { [string]: any } do
			if type(slot) == "string" and #slot <= 12 and type(itemId) == "string" and profile.Base.Owned[itemId] then
				profile.Base.Slots[slot] = itemId
			end
		end
	end

	local stats = asMap(data.Stats)
	local statsOut = profile.Stats :: { [string]: number }
	for key, default in statsOut do
		statsOut[key] = math.floor(num(stats[key], default, 0, MAX_NUMBER))
	end

	local quests = asMap(data.Quests)
	profile.Quests.Day = int(quests.Day, 0, 0, 1e7)
	profile.Quests.Week = int(quests.Week, 0, 0, 1e7)
	if type(quests.Items) == "table" then
		for _, item in quests.Items :: { any } do
			if type(item) == "table" and type(item.Id) == "string" and #profile.Quests.Items < 12 then
				table.insert(profile.Quests.Items, {
					Id = item.Id,
					Progress = math.floor(num(item.Progress, 0, 0, MAX_NUMBER)),
					Claimed = bool(item.Claimed, false),
				})
			end
		end
	end

	if type(data.Achievements) == "table" then
		for id, state in data.Achievements :: { [string]: any } do
			if type(id) == "string" and (state == 1 or state == 2) then
				profile.Achievements[id] = state
			end
		end
	end

	local daily = asMap(data.Daily)
	profile.Daily.Streak = int(daily.Streak, 0, 0, 1e6)
	profile.Daily.LastClaim = int(daily.LastClaim, 0, 0, 4e9)

	if type(data.Chests) == "table" then
		for id, count in data.Chests :: { [string]: any } do
			if type(id) == "string" and Loot.ById[id] then
				profile.Chests[id] = int(count, 0, 0, 1e6)
			end
		end
	end

	local pity = asMap(data.Pity)
	profile.Pity.Boss = int(pity.Boss, 0, 0, 1e6)
	profile.Pity.Chest = int(pity.Chest, 0, 0, 1e6)

	local boosts = asMap(data.Boosts)
	profile.Boosts.XP = int(boosts.XP, 0, 0, 4e9)

	if type(data.Purchases) == "table" then
		for _, receipt in data.Purchases :: { any } do
			if type(receipt) == "string" and #receipt <= 80 and #profile.Purchases < MAX_PURCHASES then
				table.insert(profile.Purchases, receipt)
			end
		end
	end

	local settings = asMap(data.Settings)
	local settingsOut = profile.Settings :: { [string]: boolean }
	for key, default in settingsOut do
		settingsOut[key] = bool(settings[key], default)
	end

	profile.Created = int(data.Created, now, 0, 4e9)
	profile.LastSeen = int(data.LastSeen, now, 0, 4e9)
	profile.Version = Game.ProfileVersion
	return profile
end

-- Point d'entrée : migration puis assainissement.
function Profile.load(raw: any, now: number): Profile
	if type(raw) ~= "table" then
		return defaultProfile(now)
	end
	return Profile.sanitize(Profile.migrate(raw :: { [string]: any }), now)
end

-- Ajoute un ReceiptId traité (anneau borné) ; renvoie false s'il l'était déjà.
function Profile.recordPurchase(profile: Profile, receiptId: string): boolean
	for _, existing in profile.Purchases do
		if existing == receiptId then
			return false
		end
	end
	table.insert(profile.Purchases, receiptId)
	while #profile.Purchases > MAX_PURCHASES do
		table.remove(profile.Purchases, 1)
	end
	return true
end

return Profile
