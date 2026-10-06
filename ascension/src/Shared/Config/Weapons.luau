--!strict
--[[
	Weapons — catalogue brut. Ajouter une arme = ajouter UNE ligne ici (aucun script).

	Les statistiques (dégâts, cadence, bonus d'XP, niveau requis) ne sont PAS saisies : elles
	sont dérivées du palier `Tier` par Rules/WeaponCatalog + Rules/Curves, pour que
	l'équilibrage reste cohérent quand le catalogue grandit.

	  Main     = 60 armes de la voie principale (gratuites au niveau requis, dans l'ordre)
	  Hunted   = armes de chasse (boss, succès, événements) : palier fractionnaire entre deux
	             armes principales, rareté plus haute, capacité spéciale.

	Couleurs : { lame/tête, manche, accent/lueur } en hexadécimal.
	Spéciaux : voir Rules/Combat (DoubleHit, LowHpBonus, EveryNth, CoinBonus, XPBonus,
	           ComboWindow, CritChance).
]]

export type Special = {
	Type: string,
	Name: string,
	Chance: number?,
	Threshold: number?,
	Mult: number?,
	N: number?,
	Value: number?,
}

export type Raw = {
	Id: string,
	Name: string,
	Archetype: string,
	Rarity: string,
	Colors: { string },
	Special: Special?,
	Tier: number?, -- Hunted uniquement (les armes principales prennent leur index)
	Source: string?, -- "Boss" | "Achievement" | "Event" | "Chest"
	Zone: string?, -- zone d'origine (boss) pour les armes de chasse
	Blurb: string?,
}

local CLEAVE = { Type = "DoubleHit", Name = "Cleave", Chance = 0.15 }
local EXECUTE = { Type = "LowHpBonus", Name = "Executioner", Threshold = 0.3, Mult = 1.5 }
local SURGE = { Type = "EveryNth", Name = "Surge", N = 5, Mult = 2 }
local FORTUNE = { Type = "CoinBonus", Name = "Fortune", Value = 0.15 }
local SCHOLAR = { Type = "XPBonus", Name = "Scholar", Value = 0.15 }
local FRENZY = { Type = "ComboWindow", Name = "Frenzy", Value = 1 }
local KEEN = { Type = "CritChance", Name = "Keen Edge", Value = 0.08 }

local function w(
	id: string,
	name: string,
	archetype: string,
	rarity: string,
	a: string,
	b: string,
	c: string,
	special: Special?
): Raw
	return { Id = id, Name = name, Archetype = archetype, Rarity = rarity, Colors = { a, b, c }, Special = special }
end

-- Ordre = palier (1..60). 6 armes par zone.
local main: { Raw } = {
	-- 1 Training Village
	w("WoodenStick", "Wooden Stick", "Stick", "Common", "#B88A57", "#8A5D34", "#D9B98A"),
	w("ReinforcedStick", "Reinforced Stick", "Stick", "Common", "#C79A66", "#8A5D34", "#7A7F87"),
	w("Fork", "Fork", "Fork", "Common", "#C9D1DA", "#9A6A3E", "#FFFFFF"),
	w("KitchenKnife", "Kitchen Knife", "Knife", "Uncommon", "#DDE4EB", "#B5532E", "#FFFFFF"),
	w("IronSword", "Iron Sword", "Sword", "Uncommon", "#B8C2CE", "#6B4A2B", "#E0B040"),
	w("KnightSword", "Knight Sword", "Sword", "Uncommon", "#D6DEE8", "#2D4F9E", "#F2C14E"),
	-- 2 Forest
	w("HunterDagger", "Hunter's Dagger", "Dagger", "Uncommon", "#9FB7A4", "#5C4026", "#C7E08A"),
	w("WoodcutterAxe", "Woodcutter Axe", "Axe", "Uncommon", "#A9B4BE", "#7A5230", "#6FB86B"),
	w("ThornSpear", "Thorn Spear", "Spear", "Rare", "#6FBF73", "#6B4A2B", "#2F8F46"),
	w("MossyHammer", "Mossy Hammer", "Hammer", "Rare", "#7C8F78", "#6B4A2B", "#9BD66B", KEEN),
	w("LeafKatana", "Leaf Katana", "Katana", "Rare", "#8EE08A", "#2E6B3A", "#E8FFD0"),
	w("ElderStaff", "Elder Staff", "Staff", "Rare", "#8A5D34", "#5C3A1E", "#7CFF9B"),
	-- 3 Desert
	w("Scimitar", "Scimitar", "Sword", "Rare", "#E8D9A8", "#A8652E", "#F2B63D"),
	w("CactusClub", "Cactus Club", "Club", "Rare", "#4FBF7A", "#2F8F5A", "#FF9BC8"),
	w("SunSpear", "Sun Spear", "Spear", "Epic", "#FFD66B", "#B5732E", "#FF8A3D", SCHOLAR),
	w("SandstormScythe", "Sandstorm Scythe", "Scythe", "Epic", "#D9B77A", "#8A5D34", "#FFE3A0"),
	w("GoldenMace", "Golden Mace", "Mace", "Epic", "#F2C14E", "#8A5D34", "#FFF0A8", FORTUNE),
	w("MirageBlades", "Mirage Blades", "DoubleBlade", "Epic", "#FFC27A", "#A8652E", "#FFF2C8", CLEAVE),
	-- 4 Ice Kingdom
	w("FrostDagger", "Frost Dagger", "Dagger", "Epic", "#A8E4FF", "#4A6FA8", "#FFFFFF"),
	w("IcicleSpear", "Icicle Spear", "Spear", "Epic", "#C8F0FF", "#5C7FB8", "#7AD0FF"),
	w("GlacierHammer", "Glacier Hammer", "Hammer", "Epic", "#8AD0F5", "#3E5E94", "#E8FBFF", EXECUTE),
	w("FrostbiteAxe", "Frostbite Axe", "Axe", "Legendary", "#9FE0FF", "#3E5E94", "#FFFFFF"),
	w("SnowflakeKatana", "Snowflake Katana", "Katana", "Legendary", "#E4F7FF", "#4A6FA8", "#8AD8FF", KEEN),
	w("BlizzardGreatsword", "Blizzard Greatsword", "Greatsword", "Legendary", "#BDEBFF", "#35508A", "#FFFFFF", SURGE),
	-- 5 Volcano
	w("MagmaBlade", "Magma Blade", "Sword", "Legendary", "#FF7A2E", "#3A2A2A", "#FFD23D"),
	w("ObsidianAxe", "Obsidian Axe", "Axe", "Legendary", "#2E2630", "#4A3030", "#FF5A2E", EXECUTE),
	w("LavaMace", "Lava Mace", "Mace", "Mythic", "#FF5A2E", "#3A2A2A", "#FFC13D"),
	w("EmberScythe", "Ember Scythe", "Scythe", "Mythic", "#FF8A3D", "#3A2A2A", "#FFE08A"),
	w("InfernoHammer", "Inferno Hammer", "Hammer", "Mythic", "#E8451E", "#2E2020", "#FFB03D", SURGE),
	w("DragonfangKatana", "Dragonfang Katana", "Katana", "Mythic", "#FF5030", "#2E2020", "#FFD08A", CLEAVE),
	-- 6 Sky Realm
	w("CloudTrident", "Cloud Trident", "Trident", "Mythic", "#FFFFFF", "#9FC8F5", "#FFB6DC"),
	w("StormSpear", "Storm Spear", "Spear", "Mythic", "#BFD8FF", "#4A5F9E", "#FFF06B", KEEN),
	w("SkybreakerGreatsword", "Skybreaker Greatsword", "Greatsword", "Mythic", "#D8E8FF", "#4A5F9E", "#FFFFFF"),
	w("WindTwins", "Wind Twin Blades", "DoubleBlade", "Mythic", "#CFF5E8", "#3E7F8F", "#FFFFFF", FRENZY),
	w("AuroraStaff", "Aurora Staff", "Staff", "Divine", "#FFB6DC", "#8A7FD8", "#9FFFE0"),
	w("ZephyrKatana", "Zephyr Katana", "Katana", "Divine", "#E8FFF8", "#6FA8D8", "#FFFFFF", FORTUNE),
	-- 7 Cyber City
	w("PlasmaKnife", "Plasma Knife", "Knife", "Divine", "#00F0FF", "#262A44", "#FFFFFF"),
	w("NeonKatana", "Neon Katana", "Katana", "Divine", "#FF3CC8", "#1E2038", "#00F0FF", KEEN),
	w("LaserSaber", "Laser Saber", "EnergyBlade", "Divine", "#00F0FF", "#2A2E50", "#FFFFFF"),
	w("CircuitHammer", "Circuit Hammer", "Hammer", "Divine", "#7A8CFF", "#262A44", "#00FFC8", SURGE),
	w("PulseTwins", "Pulse Twin Sabers", "DoubleBlade", "Divine", "#FF3CC8", "#2A2E50", "#00F0FF", CLEAVE),
	w("QuantumScythe", "Quantum Scythe", "Scythe", "Divine", "#7AFFE0", "#262A44", "#FF3CC8", SCHOLAR),
	-- 8 The Void
	w("ShadowDagger", "Shadow Dagger", "Dagger", "Divine", "#2A1A44", "#140A24", "#B45AFF"),
	w("UmbraKatana", "Umbra Katana", "Katana", "Divine", "#1E1236", "#0F0818", "#9A5AFF", EXECUTE),
	w("DarkMatterAxe", "Dark Matter Axe", "Axe", "Cosmic", "#2A1650", "#140A24", "#C46AFF"),
	w("EclipseScythe", "Eclipse Scythe", "Scythe", "Cosmic", "#1A0E34", "#0F0818", "#FFB46B"),
	w("HorizonHammer", "Event Horizon Hammer", "Hammer", "Cosmic", "#241448", "#0F0818", "#FF6BD8", SURGE),
	w("SingularitySpear", "Singularity Spear", "Spear", "Cosmic", "#160A2E", "#0F0818", "#8A6BFF", KEEN),
	-- 9 Divine Realm
	w("HaloStaff", "Halo Staff", "Staff", "Cosmic", "#FFF2B0", "#F2E2B8", "#FFFFFF"),
	w("SeraphBlade", "Seraph Blade", "Sword", "Cosmic", "#FFFFFF", "#E8C860", "#FFF2B0", FORTUNE),
	w("AscendedTrident", "Ascended Trident", "Trident", "Cosmic", "#FFE98A", "#F2E2B8", "#FFFFFF"),
	w("JudgementGreatsword", "Judgement Greatsword", "Greatsword", "Secret", "#FFFFFF", "#E8C860", "#FFD95E", SURGE),
	w("CelestialTwins", "Celestial Twin Blades", "DoubleBlade", "Secret", "#FFF8D8", "#E8C860", "#FFFFFF", CLEAVE),
	w("GodfallHammer", "Godfall Hammer", "Hammer", "Secret", "#FFE070", "#F8F0D8", "#FFFFFF", EXECUTE),
	-- 10 Secret Realm
	w("RealityScythe", "Reality Scythe", "Scythe", "Secret", "#FF50BE", "#1E0F28", "#FFFFFF", SCHOLAR),
	w("ParadoxKatana", "Paradox Katana", "Katana", "Secret", "#FF78D2", "#1E0F28", "#00F0FF", KEEN),
	w("OmegaBlade", "Omega Energy Blade", "EnergyBlade", "Godly", "#FFFFFF", "#2A1038", "#FF50BE", FRENZY),
	w("InfinityClaymore", "Infinity Claymore", "Greatsword", "Godly", "#FFFFFF", "#FFD95E", "#FF50BE", SURGE),
	w("TheLastWord", "The Last Word", "Greatsword", "Godly", "#FFF2FF", "#2A1038", "#FFD95E", EXECUTE),
	w("AscensionStaff", "Ascension Staff", "Staff", "Godly", "#FFFFFF", "#FFD95E", "#FF50BE", FORTUNE),
}

local function h(
	id: string,
	name: string,
	archetype: string,
	rarity: string,
	tier: number,
	source: string,
	zone: string?,
	a: string,
	b: string,
	c: string,
	special: Special,
	blurb: string
): Raw
	return {
		Id = id,
		Name = name,
		Archetype = archetype,
		Rarity = rarity,
		Colors = { a, b, c },
		Special = special,
		Tier = tier,
		Source = source,
		Zone = zone,
		Blurb = blurb,
	}
end

local hunted: { Raw } = {
	h(
		"ToyHammer",
		"Toy Hammer",
		"Hammer",
		"Common",
		2.5,
		"Chest",
		nil,
		"#FF6B6B",
		"#FFD93D",
		"#FFFFFF",
		FRENZY,
		"Squeaky and surprisingly sturdy."
	),
	h(
		"CandySword",
		"Candy Sword",
		"Sword",
		"Uncommon",
		3.5,
		"Chest",
		nil,
		"#FF9ECF",
		"#FFFFFF",
		"#FF4D8D",
		SCHOLAR,
		"Sweet. Very sweet."
	),
	h(
		"PirateCutlass",
		"Pirate Cutlass",
		"Sword",
		"Rare",
		9.5,
		"Chest",
		nil,
		"#D6DEE8",
		"#5C3A1E",
		"#FFC13D",
		FORTUNE,
		"Arr, a collectible."
	),
	h(
		"CoralSpear",
		"Coral Spear",
		"Spear",
		"Rare",
		14.5,
		"Chest",
		nil,
		"#FF8A7A",
		"#FFE4D6",
		"#5AD8D0",
		KEEN,
		"Washed up from a faraway beach."
	),
	h(
		"JesterMace",
		"Jester's Mace",
		"Mace",
		"Epic",
		16.5,
		"Chest",
		nil,
		"#B45AFF",
		"#FFD93D",
		"#FF4D6D",
		CLEAVE,
		"Hits twice as funny."
	),
	h(
		"NeonNunchaku",
		"Neon Nunchaku",
		"DoubleBlade",
		"Epic",
		22.5,
		"Chest",
		nil,
		"#3DFFB0",
		"#262A44",
		"#FF3CC8",
		FRENZY,
		"Wah-ta!"
	),
	h(
		"DragonTooth",
		"Dragon Tooth",
		"Dagger",
		"Legendary",
		28.5,
		"Chest",
		nil,
		"#FFF2D6",
		"#8A3A2E",
		"#FF8A3D",
		EXECUTE,
		"Still warm."
	),
	h(
		"PhoenixBlade",
		"Phoenix Blade",
		"Katana",
		"Mythic",
		34.5,
		"Chest",
		nil,
		"#FF7A3D",
		"#3A2020",
		"#FFE08A",
		SURGE,
		"Burns bright, burns twice."
	),
	h(
		"StarfallStaff",
		"Starfall Staff",
		"Staff",
		"Mythic",
		40.5,
		"Chest",
		nil,
		"#B6A8FF",
		"#262A5C",
		"#FFF2A8",
		SCHOLAR,
		"Wishes included."
	),
	h(
		"RubberChicken",
		"Rubber Chicken",
		"Club",
		"Rare",
		4.5,
		"Achievement",
		nil,
		"#FFE14D",
		"#FF8A3D",
		"#FFFFFF",
		FRENZY,
		"Squeaks on every hit. Earned by landing 1,000 hits."
	),
	h(
		"GildedFork",
		"Gilded Fork",
		"Fork",
		"Legendary",
		5.5,
		"Chest",
		nil,
		"#FFD95E",
		"#B5732E",
		"#FFFFFF",
		FORTUNE,
		"A fork fit for a king."
	),
	h(
		"PitchforkOfDoom",
		"Pitchfork of Doom",
		"Trident",
		"Epic",
		6.5,
		"Boss",
		"Village",
		"#C9D1DA",
		"#6B4A2B",
		"#EB5A46",
		SURGE,
		"Dropped by the Big Scarecrow."
	),
	h(
		"TreantBranch",
		"Treant Branch",
		"Staff",
		"Epic",
		12.5,
		"Boss",
		"Forest",
		"#7CFF9B",
		"#5C3A1E",
		"#C8FFB0",
		SCHOLAR,
		"Dropped by the Elder Treant."
	),
	h(
		"PharaohKhopesh",
		"Pharaoh's Khopesh",
		"Sword",
		"Legendary",
		18.5,
		"Boss",
		"Desert",
		"#FFD66B",
		"#A8652E",
		"#28AAA0",
		EXECUTE,
		"Dropped by the Sand Pharaoh."
	),
	h(
		"ColossusCrusher",
		"Colossus Crusher",
		"Hammer",
		"Legendary",
		24.5,
		"Boss",
		"Ice",
		"#BDEBFF",
		"#3E5E94",
		"#FFFFFF",
		CLEAVE,
		"Dropped by the Frost Colossus."
	),
	h(
		"TitanCoreBlade",
		"Titan Core Blade",
		"Greatsword",
		"Mythic",
		30.5,
		"Boss",
		"Volcano",
		"#FF5A2E",
		"#2E2020",
		"#FFE08A",
		SURGE,
		"Dropped by the Inferno Titan."
	),
	h(
		"GriffinTalon",
		"Griffin Talon",
		"Scythe",
		"Mythic",
		36.5,
		"Boss",
		"Sky",
		"#FFFFFF",
		"#6FA8D8",
		"#FFF06B",
		KEEN,
		"Dropped by the Storm Griffin."
	),
	h(
		"MainframeSaber",
		"Mainframe Saber",
		"EnergyBlade",
		"Divine",
		42.5,
		"Boss",
		"Cyber",
		"#00FFC8",
		"#262A44",
		"#FF3CC8",
		FRENZY,
		"Dropped by the Mainframe Core."
	),
	h(
		"VoidBlade",
		"Void Blade",
		"Greatsword",
		"Secret",
		48.5,
		"Boss",
		"Void",
		"#1A0A30",
		"#0A0414",
		"#C46AFF",
		EXECUTE,
		"Rarely dropped by the Eater of Stars."
	),
	h(
		"ArchangelSpear",
		"Archangel Spear",
		"Spear",
		"Cosmic",
		54.5,
		"Boss",
		"Divine",
		"#FFFFFF",
		"#E8C860",
		"#FFD95E",
		FORTUNE,
		"Dropped by Archangel Prime."
	),
	h(
		"GodSlayer",
		"Godslayer",
		"Greatsword",
		"Godly",
		60.5,
		"Boss",
		"Secret",
		"#FFFFFF",
		"#1E0F28",
		"#FF50BE",
		SURGE,
		"The Last Dummy guards it. Barely."
	),
	h(
		"CandyCaneClub",
		"Candy Cane Club",
		"Club",
		"Epic",
		10.5,
		"Event",
		nil,
		"#FF4D6D",
		"#FFFFFF",
		"#FF4D6D",
		SCHOLAR,
		"Winter event exclusive."
	),
	h(
		"CrownOfBlades",
		"Crown of Blades",
		"DoubleBlade",
		"Godly",
		62,
		"Achievement",
		nil,
		"#FFFFFF",
		"#FFD95E",
		"#FFD95E",
		CLEAVE,
		"Awarded for reaching Ascension 5."
	),
}

return {
	Main = main,
	Hunted = hunted,
}
