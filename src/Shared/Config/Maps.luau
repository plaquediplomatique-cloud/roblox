--!strict
--[[
	Maps — métadonnées des cartes (affichage, modes supportés, ambiance lumineuse).

	La géométrie est décrite par les blueprints serveur (Server/Maps/Blueprints/*) ;
	ce module partagé ne contient que ce dont le client a besoin : nom, sites, profil
	d'éclairage/post-process, astuces pour l'écran de chargement.
]]

local Types = require(script.Parent.Parent.Types)

type LightingProfile = Types.LightingProfile
type MapInfo = Types.MapInfo

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Maps = {}

Maps.defs = {
	hub = {
		id = "hub",
		displayName = "AETHER HQ",
		tagline = "Quartier général — Niveau 88",
		theme = "Siège de l'escouade en plein jour : atrium sous verrière, salons, café, stand de tir",
		modes = {},
		sites = {},
		size = Vector2.new(220, 180),
		ambientSound = "Ambient.Hum",
		tips = {},
		weather = { kind = "Motes", intensity = 0.3, lightning = false },
		ambience = {
			outdoorReverb = "Room",
			indoorReverb = "Room",
			spots = {
				{ key = "Ambient.Chime", interval = NumberRange.new(40, 80), distance = NumberRange.new(20, 50) },
				{ key = "Ambient.Hvac", interval = NumberRange.new(14, 30), distance = NumberRange.new(10, 30) },
				{ key = "Ambient.Traffic", interval = NumberRange.new(10, 22), distance = NumberRange.new(80, 160) },
			},
		},
		lighting = {
			clockTime = 15.6,
			brightness = 2.6,
			ambient = rgb(92, 92, 98),
			outdoorAmbient = rgb(150, 150, 160),
			exposure = 0,
			colorShiftTop = rgb(255, 236, 210),
			diffuseScale = 1,
			specularScale = 0.8,
			atmosphere = {
				density = 0.26,
				offset = 0.2,
				color = rgb(205, 218, 232),
				decay = rgb(120, 140, 162),
				glare = 0.15,
				haze = 1.1,
			},
			colorCorrection = { brightness = 0.01, contrast = 0.08, saturation = 0.06, tint = rgb(255, 250, 244) },
			bloom = { intensity = 0.35, size = 24, threshold = 1.4 },
			sunRays = { intensity = 0.06, spread = 0.5 },
			shadowSoftness = 0.3,
			sky = { stars = 0, sunSize = 14, moonSize = 10, celestial = true },
			clouds = { cover = 0.5, density = 0.55, color = rgb(250, 250, 255) },
		},
	},
	kestrel = {
		id = "kestrel",
		displayName = "KESTREL YARD",
		tagline = "Dépôt de fret sur toit — Secteur 7",
		theme = "Néo-industriel nocturne : conteneurs, passerelles, lampes au sodium, pluie",
		modes = { "Duel", "Clash2" },
		sites = {},
		size = Vector2.new(140, 96),
		ambientSound = "Ambient.Industrial",
		tips = {
			"La TOUR centrale domine le mid : la prendre, c'est contrôler les rotations.",
			"Les CONTENEURS (nord) offrent des angles courts : idéal pour les SMG.",
			"La PASSERELLE (sud) est rapide mais exposée depuis la Tour et la fenêtre.",
		},
		weather = { kind = "Rain", intensity = 0.8, lightning = true },
		ambience = {
			outdoorReverb = "Alley",
			indoorReverb = "Room",
			spots = {
				{ key = "Ambient.Creak", interval = NumberRange.new(9, 20), distance = NumberRange.new(30, 80) },
				{ key = "Ambient.Drip", interval = NumberRange.new(3, 8), distance = NumberRange.new(6, 22) },
			},
		},
		lighting = {
			clockTime = 0.5,
			brightness = 1.2,
			ambient = rgb(24, 22, 26),
			outdoorAmbient = rgb(52, 50, 58),
			exposure = 0.2,
			colorShiftTop = rgb(255, 170, 90),
			diffuseScale = 0.9,
			specularScale = 1,
			atmosphere = {
				density = 0.34,
				offset = 0.05,
				color = rgb(90, 80, 75),
				decay = rgb(60, 40, 30),
				glare = 0.1,
				haze = 1.8,
			},
			colorCorrection = { brightness = 0.03, contrast = 0.16, saturation = -0.05, tint = rgb(255, 240, 225) },
			bloom = { intensity = 0.7, size = 24, threshold = 0.9 },
			sunRays = { intensity = 0.02, spread = 0.4 },
			shadowSoftness = 0.35,
			sky = { stars = 600, sunSize = 21, moonSize = 11, celestial = true },
			clouds = { cover = 0.86, density = 0.55, color = rgb(46, 44, 50) },
		},
	},
	helix = {
		id = "helix",
		displayName = "HELIX VAULT",
		tagline = "Chambre forte Helix Bank — Étage 140",
		theme = "Banque corporatiste high-tech : marbre noir, verre, lumière blanche clinique",
		modes = { "Wingman", "Clash2", "Clash3" },
		sites = { "VAULT" },
		size = Vector2.new(150, 120),
		ambientSound = "Ambient.Hum",
		tips = {
			"Le VAULT s'attaque par MAIN (large, sous les portiques) ou par SERVICE (porte ouest, discrète).",
			"L'ATRIUM relie les deux accès : le défenseur qui le tient voit les rotations.",
			"Le verre de l'atrium se traverse : écoutez avant de peek.",
		},
		weather = { kind = "Motes", intensity = 0.5, lightning = false },
		ambience = {
			outdoorReverb = "Hallway",
			indoorReverb = "Hallway",
			spots = {
				{ key = "Ambient.Chime", interval = NumberRange.new(25, 50), distance = NumberRange.new(20, 60) },
				{ key = "Ambient.Hvac", interval = NumberRange.new(10, 20), distance = NumberRange.new(10, 40) },
			},
		},
		lighting = {
			clockTime = 14,
			brightness = 2.2,
			ambient = rgb(40, 44, 52),
			outdoorAmbient = rgb(90, 100, 115),
			exposure = 0,
			colorShiftTop = rgb(200, 230, 255),
			diffuseScale = 1,
			specularScale = 1,
			atmosphere = {
				density = 0.25,
				offset = 0.2,
				color = rgb(170, 190, 210),
				decay = rgb(110, 130, 160),
				glare = 0.3,
				haze = 1.0,
			},
			colorCorrection = { brightness = 0, contrast = 0.1, saturation = -0.1, tint = rgb(240, 248, 255) },
			bloom = { intensity = 0.55, size = 22, threshold = 0.95 },
			sunRays = { intensity = 0.06, spread = 0.5 },
			shadowSoftness = 0.15,
			sky = { stars = 0, sunSize = 21, moonSize = 11, celestial = true },
			clouds = { cover = 0.5, density = 0.3, color = rgb(245, 248, 255) },
		},
	},
	spire = {
		id = "spire",
		displayName = "SPIRE-9",
		tagline = "Complexe de recherche — Falaise de Vael",
		theme = "Station scientifique sur falaise gelée au crépuscule : réacteur, datacenter, téléphérique",
		modes = { "Squad", "Clash3" },
		sites = { "A", "B" },
		size = Vector2.new(200, 170),
		ambientSound = "Ambient.Wind",
		tips = {
			"A = RÉACTEUR (ouvert, longues lignes) ; B = DATACORE (intérieur, close-range).",
			"La PLAZA au centre donne accès aux deux sites : la défense doit la contester tôt.",
			"Rotations : la BACK ROAD pour la défense, le COURTYARD pour l'attaque — rapides mais exposées.",
		},
		weather = { kind = "Snow", intensity = 0.6, lightning = false },
		ambience = {
			outdoorReverb = "Mountains",
			indoorReverb = "Room",
			spots = {
				{ key = "Ambient.Gust", interval = NumberRange.new(6, 14), distance = NumberRange.new(30, 90) },
				{ key = "Ambient.IceCrack", interval = NumberRange.new(15, 35), distance = NumberRange.new(40, 120) },
				{ key = "Ambient.Creak", interval = NumberRange.new(20, 40), distance = NumberRange.new(80, 180) },
			},
		},
		lighting = {
			clockTime = 17.6,
			brightness = 2.4,
			ambient = rgb(38, 40, 52),
			outdoorAmbient = rgb(110, 105, 125),
			exposure = 0.05,
			colorShiftTop = rgb(255, 180, 140),
			diffuseScale = 1,
			specularScale = 1,
			atmosphere = {
				density = 0.28,
				offset = 0.12,
				color = rgb(190, 170, 175),
				decay = rgb(120, 90, 110),
				glare = 0.6,
				haze = 1.2,
			},
			colorCorrection = { brightness = 0.01, contrast = 0.14, saturation = 0.05, tint = rgb(255, 244, 236) },
			bloom = { intensity = 0.6, size = 26, threshold = 0.93 },
			sunRays = { intensity = 0.12, spread = 0.7 },
			shadowSoftness = 0.3,
			sky = { stars = 300, sunSize = 26, moonSize = 11, celestial = true },
			clouds = { cover = 0.62, density = 0.4, color = rgb(214, 172, 168) },
		},
	},
	monolith = {
		id = "monolith",
		displayName = "MONOLITH",
		tagline = "Relais orbital Aether-0",
		theme = "Station spatiale autour d'un monolithe noir : verticalité, magenta et vide étoilé",
		modes = { "Duel", "Wingman", "Squad", "Clash2", "Clash3" },
		sites = { "A", "B" },
		size = Vector2.new(176, 150),
		ambientSound = "Ambient.Hum",
		tips = {
			"Le MONOLITHE bloque toute ligne de vue au centre : on le contourne par les ANNEAUX.",
			"Les BALCONS (y = 7) dominent l'ANNEAU : on y monte par des rampes à claire-voie, bruyantes.",
			"En Duel, seule l'arène centrale est active : pas de site, élimination pure.",
		},
		weather = { kind = "Embers", intensity = 0.5, lightning = false },
		ambience = {
			outdoorReverb = "StoneRoom",
			indoorReverb = "Room",
			spots = {
				{ key = "Ambient.Pulse", interval = NumberRange.new(8, 16), distance = NumberRange.new(20, 60) },
				{ key = "Ambient.Creak", interval = NumberRange.new(12, 25), distance = NumberRange.new(30, 90) },
			},
		},
		lighting = {
			clockTime = 2,
			brightness = 1.1,
			ambient = rgb(30, 22, 40),
			outdoorAmbient = rgb(60, 50, 80),
			exposure = 0.15,
			colorShiftTop = rgb(220, 120, 255),
			diffuseScale = 0.9,
			specularScale = 1,
			atmosphere = {
				density = 0.2,
				offset = 0,
				color = rgb(60, 40, 90),
				decay = rgb(30, 20, 60),
				glare = 0,
				haze = 0.6,
			},
			colorCorrection = { brightness = 0.02, contrast = 0.18, saturation = 0.12, tint = rgb(248, 238, 255) },
			bloom = { intensity = 0.9, size = 30, threshold = 0.9 },
			sunRays = { intensity = 0, spread = 0 },
			shadowSoftness = 0.2,
			sky = { stars = 5000, sunSize = 12, moonSize = 8, celestial = false },
			clouds = nil,
		},
	},
} :: { [string]: MapInfo }

Maps.competitive = { "kestrel", "helix", "spire", "monolith" }

function Maps.get(id: string): MapInfo?
	return Maps.defs[id]
end

function Maps.supports(mapId: string, modeId: string): boolean
	local info = Maps.defs[mapId]
	return info ~= nil and table.find(info.modes, modeId) ~= nil
end

return Maps
