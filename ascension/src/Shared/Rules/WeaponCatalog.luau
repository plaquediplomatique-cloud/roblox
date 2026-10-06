--!strict
--[[
	WeaponCatalog — catalogue d'armes DÉRIVÉ des données brutes (Config/Weapons).

	Calcule pour chaque arme : dégâts, cadence, portée, bonus d'XP, niveau requis, zone.
	Ajouter 100 armes = ajouter 100 lignes dans Config/Weapons ; rien ici ne change.
]]

local Weapons = require(script.Parent.Parent.Config.Weapons)
local Archetypes = require(script.Parent.Parent.Config.Archetypes)
local Rarities = require(script.Parent.Parent.Config.Rarities)
local Zones = require(script.Parent.Parent.Config.Zones)
local Game = require(script.Parent.Parent.Config.Game)
local Curves = require(script.Parent.Curves)

export type Weapon = {
	Id: string,
	Name: string,
	Tier: number,
	Index: number, -- ordre d'affichage (par palier)
	Main: boolean,
	Archetype: string,
	ArchetypeData: Archetypes.Archetype,
	Rarity: Rarities.Rarity,
	Colors: { Color3 },
	Damage: number,
	AttackSpeed: number, -- coups/seconde de base de l'arme
	Reach: number,
	XPBoost: number,
	Level: number?, -- niveau requis (armes principales)
	ZoneIndex: number,
	Special: Weapons.Special?,
	Source: string, -- "Level" | "Boss" | "Chest" | "Achievement" | "Event"
	BossZone: string?,
	Blurb: string,
}

local CatalogModule = {}

local list: { Weapon } = {}
local main: { Weapon } = {}
local hunted: { Weapon } = {}
local byId: { [string]: Weapon } = {}

local function colorsFrom(hex: { string }): { Color3 }
	local out = {}
	for _, value in hex do
		table.insert(out, Color3.fromHex(value))
	end
	return out
end

local function build(raw: Weapons.Raw, tier: number, isMain: boolean, level: number?, zoneIndex: number): Weapon
	local archetype = Archetypes[raw.Archetype]
	local rarity = Rarities.ById[raw.Rarity]
	assert(archetype, "archetype inconnu: " .. raw.Archetype .. " (" .. raw.Id .. ")")
	assert(rarity, "rareté inconnue: " .. raw.Rarity .. " (" .. raw.Id .. ")")
	return {
		Id = raw.Id,
		Name = raw.Name,
		Tier = tier,
		Index = 0,
		Main = isMain,
		Archetype = raw.Archetype,
		ArchetypeData = archetype,
		Rarity = rarity,
		Colors = colorsFrom(raw.Colors),
		Damage = Curves.weaponDamage(tier),
		AttackSpeed = Game.BaseSwingsPerSecond * archetype.Speed,
		Reach = archetype.Reach,
		XPBoost = Curves.weaponXPBoost(tier),
		Level = level,
		ZoneIndex = zoneIndex,
		Special = raw.Special,
		Source = if isMain then "Level" else (raw.Source or "Chest"),
		BossZone = raw.Zone,
		Blurb = raw.Blurb or "",
	}
end

for i, raw in Weapons.Main do
	local zoneIndex = (i - 1) // Zones.WeaponsPerZone + 1
	local slot = (i - 1) % Zones.WeaponsPerZone + 1
	local zone = Zones.List[zoneIndex]
	local level = zone.MinLevel + zone.WeaponOffsets[slot]
	local weapon = build(raw, i, true, level, zoneIndex)
	table.insert(main, weapon)
end
for _, raw in Weapons.Hunted do
	local tier = raw.Tier or 1
	local zoneIndex = math.clamp(math.ceil(tier / Zones.WeaponsPerZone), 1, Zones.Count)
	table.insert(hunted, build(raw, tier, false, nil, zoneIndex))
end

for _, weapon in main do
	table.insert(list, weapon)
end
for _, weapon in hunted do
	table.insert(list, weapon)
end
table.sort(list, function(a, b)
	if a.Tier == b.Tier then
		return a.Id < b.Id
	end
	return a.Tier < b.Tier
end)
for i, weapon in list do
	weapon.Index = i
	byId[weapon.Id] = weapon
end

CatalogModule.List = list
CatalogModule.Main = main
CatalogModule.Hunted = hunted
CatalogModule.ById = byId
CatalogModule.StarterId = main[1].Id

function CatalogModule.get(id: string): Weapon?
	return byId[id]
end

-- Armes principales débloquées à ce niveau (dans l'ordre).
function CatalogModule.mainUnlockedAt(level: number): { Weapon }
	local out = {}
	for _, weapon in main do
		if (weapon.Level :: number) <= level then
			table.insert(out, weapon)
		end
	end
	return out
end

-- Meilleure arme possédée (dégâts max) parmi un ensemble { [id] = true }.
function CatalogModule.bestOwned(owned: { [string]: boolean }): Weapon
	local best = main[1]
	for _, weapon in list do
		if owned[weapon.Id] and weapon.Damage > best.Damage then
			best = weapon
		end
	end
	return best
end

-- Prochaine arme principale non possédée (pour « prochain objectif »).
function CatalogModule.nextMain(owned: { [string]: boolean }): Weapon?
	for _, weapon in main do
		if not owned[weapon.Id] then
			return weapon
		end
	end
	return nil
end

-- Armes de chasse d'une rareté donnée (tables de butin).
function CatalogModule.huntedByRarity(rarityId: string, source: string?): { Weapon }
	local out = {}
	for _, weapon in hunted do
		if weapon.Rarity.Id == rarityId and (source == nil or weapon.Source == source) then
			table.insert(out, weapon)
		end
	end
	return out
end

local KNOWN_SPECIALS = {
	DoubleHit = true,
	LowHpBonus = true,
	EveryNth = true,
	CoinBonus = true,
	XPBonus = true,
	ComboWindow = true,
	CritChance = true,
}

-- Vérifie la cohérence du catalogue ; renvoie la liste des problèmes (vide = OK).
function CatalogModule.validate(): { string }
	local errors = {}
	local seen: { [string]: boolean } = {}
	for _, weapon in list do
		if seen[weapon.Id] then
			table.insert(errors, "id dupliqué: " .. weapon.Id)
		end
		seen[weapon.Id] = true
		if weapon.Special and not KNOWN_SPECIALS[weapon.Special.Type] then
			table.insert(errors, weapon.Id .. ": spécial inconnu " .. weapon.Special.Type)
		end
		if #weapon.Colors < 3 then
			table.insert(errors, weapon.Id .. ": 3 couleurs requises")
		end
	end
	if #main ~= Zones.Count * Zones.WeaponsPerZone then
		table.insert(errors, ("%d armes principales, %d attendues"):format(#main, Zones.Count * Zones.WeaponsPerZone))
	end
	for i = 2, #main do
		local a, b = main[i - 1], main[i]
		if (b.Level :: number) <= (a.Level :: number) then
			table.insert(errors, ("niveaux non croissants: %s -> %s"):format(a.Id, b.Id))
		end
		if b.Damage <= a.Damage then
			table.insert(errors, ("dégâts non croissants: %s -> %s"):format(a.Id, b.Id))
		end
		if b.Rarity.Order < a.Rarity.Order then
			table.insert(errors, ("rareté décroissante: %s -> %s"):format(a.Id, b.Id))
		end
		if (b.Level :: number) > Game.MaxLevel then
			table.insert(errors, b.Id .. ": niveau > MaxLevel")
		end
	end
	for _, weapon in hunted do
		if weapon.Tier < 1 or weapon.Tier > #main + 3 then
			table.insert(errors, weapon.Id .. ": palier hors plage")
		end
	end
	return errors
end

return CatalogModule
