--!strict
--[[
	Cosmetics — catalogue complet : skins d'armes, tenues d'opérateur, effets de kill,
	emotes, bannières. Rareté : Common → Rare → Epic → Legendary → Mythic.

	Les skins d'armes sont des "collections" (finitions) appliquées à TOUTES les armes :
	8 collections × 14 armes = 112 skins générés. Une finition définit une palette
	(résolue sur les rôles de couleur des modèles procéduraux), des matériaux et des FX :
	  * Epic       : pulsation néon,
	  * Legendary  : base translucide + aura de particules + animation d'inspection,
	  * Mythic     : dégradé animé cyan↔magenta, aura, traceurs/muzzle flash colorés,
	                 effet de kill intégré — exclusif au Pass premium.
	Aucun cosmétique ne modifie la silhouette ou la hitbox (équité compétitive).
]]

local Types = require(script.Parent.Parent.Types)
local Weapons = require(script.Parent.Weapons)

type ItemDef = Types.ItemDef
type Palette = Types.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Cosmetics = {}

Cosmetics.rarities = {
	Common = { order = 1, color = rgb(167, 177, 188), price = 300, label = "COMMUN" },
	Rare = { order = 2, color = rgb(61, 155, 255), price = 800, label = "RARE" },
	Epic = { order = 3, color = rgb(176, 77, 255), price = 1800, label = "ÉPIQUE" },
	Legendary = { order = 4, color = rgb(255, 181, 71), price = 3600, label = "LÉGENDAIRE" },
	Mythic = { order = 5, color = rgb(255, 61, 127), price = 0, label = "MYTHIQUE" },
} :: { [Types.Rarity]: { order: number, color: Color3, price: number, label: string } }

Cosmetics.items = {} :: { [string]: ItemDef }
Cosmetics.order = {} :: { string }

local function add(item: ItemDef)
	assert(Cosmetics.items[item.id] == nil, "duplicate cosmetic " .. item.id)
	Cosmetics.items[item.id] = item
	table.insert(Cosmetics.order, item.id)
end

local function palette(
	base: Color3,
	secondary: Color3,
	accent: Color3,
	neon: Color3,
	metal: Color3?,
	grip: Color3?
): Palette
	return {
		Base = base,
		Secondary = secondary,
		Accent = accent,
		Neon = neon,
		Metal = metal or rgb(58, 62, 70),
		Glass = rgb(140, 220, 255),
		Grip = grip or rgb(28, 30, 34),
	}
end

---------------------------------------------------------------------------------------------
-- Collections de skins d'armes
---------------------------------------------------------------------------------------------

type SkinLine = {
	id: string,
	name: string,
	rarity: Types.Rarity,
	purchasable: boolean,
	palette: Palette,
	materials: Types.MaterialSet,
	fx: Types.SkinFx,
	description: string,
}

Cosmetics.skinLines = {
	{
		id = "default",
		name = "Standard",
		rarity = "Common",
		purchasable = false,
		palette = palette(rgb(46, 50, 58), rgb(30, 33, 38), rgb(80, 86, 96), rgb(61, 225, 255)),
		materials = {
			Base = Enum.Material.Metal,
			Secondary = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.Metal,
		},
		fx = {},
		description = "Finition d'usine, gris acier et filet cyan.",
	},
	{
		id = "obsidian",
		name = "Obsidian",
		rarity = "Common",
		purchasable = true,
		palette = palette(rgb(18, 18, 20), rgb(10, 10, 12), rgb(230, 230, 235), rgb(245, 245, 255)),
		materials = {
			Base = Enum.Material.SmoothPlastic,
			Secondary = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.Metal,
		},
		fx = {},
		description = "Noir mat absolu, accents blanc pur.",
	},
	{
		id = "arctic",
		name = "Arctic Circuit",
		rarity = "Rare",
		purchasable = true,
		palette = palette(
			rgb(228, 234, 240),
			rgb(170, 180, 192),
			rgb(70, 80, 95),
			rgb(80, 230, 255),
			rgb(150, 158, 170),
			rgb(60, 66, 76)
		),
		materials = {
			Base = Enum.Material.SmoothPlastic,
			Secondary = Enum.Material.Metal,
			Accent = Enum.Material.Metal,
		},
		fx = {},
		description = "Céramique blanche parcourue de pistes cyan.",
	},
	{
		id = "ember",
		name = "Ember Forge",
		rarity = "Rare",
		purchasable = true,
		palette = palette(rgb(52, 36, 30), rgb(28, 22, 20), rgb(160, 90, 50), rgb(255, 120, 40), rgb(90, 70, 60)),
		materials = {
			Base = Enum.Material.CorrodedMetal,
			Secondary = Enum.Material.Metal,
			Accent = Enum.Material.Metal,
		},
		fx = {},
		description = "Acier brûlé, braises orange dans les rainures.",
	},
	{
		id = "solar",
		name = "Solar Flare",
		rarity = "Epic",
		purchasable = true,
		palette = palette(rgb(255, 170, 40), rgb(60, 40, 20), rgb(255, 230, 160), rgb(255, 200, 60), rgb(120, 90, 50)),
		materials = {
			Base = Enum.Material.Metal,
			Secondary = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.Metal,
		},
		fx = { neonPulse = 1.2 },
		description = "Or solaire, coeur néon qui pulse comme une étoile.",
	},
	{
		id = "crimson",
		name = "Crimson Protocol",
		rarity = "Epic",
		purchasable = true,
		palette = palette(rgb(150, 18, 32), rgb(16, 14, 16), rgb(40, 36, 40), rgb(255, 50, 70), rgb(70, 60, 64)),
		materials = {
			Base = Enum.Material.SmoothPlastic,
			Secondary = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.Metal,
		},
		fx = { neonPulse = 2.0, tracerColor = rgb(255, 80, 90) },
		description = "Rouge protocole d'urgence, pulsation d'alerte.",
	},
	{
		id = "specter",
		name = "Specter",
		rarity = "Legendary",
		purchasable = true,
		palette = palette(
			rgb(120, 100, 200),
			rgb(30, 24, 50),
			rgb(200, 180, 255),
			rgb(180, 110, 255),
			rgb(70, 60, 110),
			rgb(24, 20, 40)
		),
		materials = {
			Base = Enum.Material.Glass,
			Secondary = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.Metal,
		},
		fx = { neonPulse = 0.8, aura = true, inspectFlourish = true, tracerColor = rgb(190, 140, 255) },
		description = "Verre spectral et brume violette. Animation d'inspection exclusive.",
	},
	{
		id = "aether",
		name = "Aether Prime",
		rarity = "Mythic",
		purchasable = false,
		palette = palette(
			rgb(14, 16, 24),
			rgb(30, 34, 48),
			rgb(230, 240, 255),
			rgb(61, 225, 255),
			rgb(90, 96, 120),
			rgb(20, 22, 30)
		),
		materials = {
			Base = Enum.Material.Metal,
			Secondary = Enum.Material.SmoothPlastic,
			Accent = Enum.Material.Metal,
		},
		fx = {
			gradientShift = true,
			aura = true,
			inspectFlourish = true,
			tracerColor = rgb(61, 225, 255),
			muzzleColor = rgb(160, 120, 255),
			killEffect = "ke_rift",
		},
		description = "La finition originelle. Néon vivant cyan↔magenta, aura, traceurs et kill effect Rift.",
	},
} :: { SkinLine }

function Cosmetics.skinId(lineId: string, weaponId: string): string
	return "skin_" .. lineId .. "_" .. weaponId
end

for _, line in Cosmetics.skinLines do
	for _, weaponId in Weapons.order do
		local weapon = Weapons.defs[weaponId]
		add({
			id = Cosmetics.skinId(line.id, weaponId),
			kind = "WeaponSkin",
			displayName = weapon.shortName .. " " .. line.name,
			rarity = line.rarity,
			price = if line.purchasable then Cosmetics.rarities[line.rarity].price else nil,
			weaponId = weaponId,
			line = line.id,
			palette = line.palette,
			materials = line.materials,
			fx = line.fx,
			description = line.description,
		})
	end
end

---------------------------------------------------------------------------------------------
-- Tenues d'opérateur (palette appliquée à l'équipement procédural du personnage)
---------------------------------------------------------------------------------------------

local function operator(
	id: string,
	name: string,
	rarity: Types.Rarity,
	purchasable: boolean,
	p: Palette,
	fx: Types.SkinFx,
	description: string
)
	add({
		id = id,
		kind = "Operator",
		displayName = name,
		rarity = rarity,
		price = if purchasable then Cosmetics.rarities[rarity].price else nil,
		palette = p,
		fx = fx,
		description = description,
	})
end

operator(
	"op_standard",
	"Standard Issue",
	"Common",
	false,
	palette(rgb(44, 48, 56), rgb(26, 28, 32), rgb(90, 96, 106), rgb(61, 225, 255)),
	{},
	"Tenue réglementaire Aether Corps."
)
operator(
	"op_nightops",
	"Night Ops",
	"Rare",
	true,
	palette(rgb(20, 22, 26), rgb(12, 12, 14), rgb(60, 64, 70), rgb(120, 255, 170)),
	{},
	"Camouflage nocturne, visière verte."
)
operator(
	"op_ronin",
	"Cyber Ronin",
	"Epic",
	true,
	palette(rgb(120, 20, 30), rgb(20, 18, 20), rgb(220, 200, 170), rgb(255, 60, 80)),
	{ neonPulse = 1.0 },
	"Armure laquée et visière écarlate."
)
operator(
	"op_wraith",
	"Wraith",
	"Legendary",
	true,
	palette(rgb(60, 50, 110), rgb(20, 16, 36), rgb(190, 170, 255), rgb(170, 100, 255)),
	{ aura = true, neonPulse = 0.7 },
	"Silhouette spectrale nimbée de brume."
)
operator(
	"op_ascendant",
	"Aether Ascendant",
	"Mythic",
	false,
	palette(rgb(16, 18, 26), rgb(34, 38, 52), rgb(235, 240, 255), rgb(61, 225, 255)),
	{ gradientShift = true, aura = true },
	"L'uniforme des légendes. Exclusif Pass premium."
)

---------------------------------------------------------------------------------------------
-- Effets de kill, emotes, bannières
---------------------------------------------------------------------------------------------

local function simple(
	id: string,
	kind: Types.ItemKind,
	name: string,
	rarity: Types.Rarity,
	purchasable: boolean,
	description: string
)
	add({
		id = id,
		kind = kind,
		displayName = name,
		rarity = rarity,
		price = if purchasable then Cosmetics.rarities[rarity].price else nil,
		description = description,
	})
end

simple("ke_none", "KillEffect", "Aucun", "Common", false, "Pas d'effet.")
simple("ke_voltage", "KillEffect", "Voltage", "Rare", true, "Des arcs électriques parcourent la cible.")
simple(
	"ke_disintegrate",
	"KillEffect",
	"Désintégration",
	"Epic",
	true,
	"La cible se dissout en particules lumineuses."
)
simple("ke_shatter", "KillEffect", "Shatter", "Legendary", true, "La cible éclate en cubes de néon.")
simple("ke_rift", "KillEffect", "Rift", "Mythic", false, "Une singularité avale la cible.")

simple("em_salute", "Emote", "Salut", "Common", false, "Salut militaire réglementaire.")
simple("em_wave", "Emote", "Signe", "Common", true, "Un signe de la main.")
simple("em_flex", "Emote", "Démonstration", "Rare", true, "Bras levés, posture de champion.")
simple("em_spin", "Emote", "Toupie", "Epic", true, "Une rotation parfaitement inutile.")
simple("em_glitch", "Emote", "Glitch", "Legendary", true, "Le corps se désynchronise de la réalité.")

simple("bn_default", "Banner", "Aether Corps", "Common", false, "Bannière réglementaire.")
simple("bn_circuit", "Banner", "Circuit", "Rare", true, "Pistes de circuit lumineuses.")
simple("bn_aurora", "Banner", "Aurore", "Epic", true, "Une aurore boréale numérique.")
simple("bn_apex", "Banner", "Apex", "Legendary", false, "Réservée aux sommets.")

---------------------------------------------------------------------------------------------
-- Inventaire de départ et accès
---------------------------------------------------------------------------------------------

function Cosmetics.starterInventory(): { [string]: boolean }
	local owned: { [string]: boolean } = {
		op_standard = true,
		ke_none = true,
		em_salute = true,
		bn_default = true,
	}
	for _, weaponId in Weapons.order do
		owned[Cosmetics.skinId("default", weaponId)] = true
	end
	return owned
end

function Cosmetics.get(id: string): ItemDef?
	return Cosmetics.items[id]
end

function Cosmetics.defaultSkin(weaponId: string): string
	return Cosmetics.skinId("default", weaponId)
end

--[[ Skin effectif d'une arme pour un joueur (retombe sur la finition par défaut). ]]
function Cosmetics.resolveSkin(weaponSkins: { [string]: string }, weaponId: string): ItemDef
	local id = weaponSkins[weaponId]
	local item = if id then Cosmetics.items[id] else nil
	if item and item.kind == "WeaponSkin" and item.weaponId == weaponId then
		return item
	end
	return Cosmetics.items[Cosmetics.defaultSkin(weaponId)]
end

return Cosmetics
