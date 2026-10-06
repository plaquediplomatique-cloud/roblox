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
		displayName = "AETHER SPIRE",
		tagline = "Hub opérationnel — Niveau 88",
		theme = "Hangar orbital suspendu, néons cyan, plateformes de lancement",
		modes = {},
		sites = {},
		size = Vector2.new(220, 180),
		ambientSound = "Ambient.Hum",
		tips = {},
		lighting = {
			clockTime = 21.5,
			brightness = 1.6,
			ambient = rgb(22, 26, 34),
			outdoorAmbient = rgb(48, 56, 72),
			exposure = 0.1,
			colorShiftTop = rgb(120, 210, 255),
			diffuseScale = 1,
			specularScale = 1,
			atmosphere = {
				density = 0.32,
				offset = 0.1,
				color = rgb(70, 90, 120),
				decay = rgb(40, 30, 70),
				glare = 0.2,
				haze = 1.6,
			},
			colorCorrection = { brightness = 0.02, contrast = 0.12, saturation = 0.05, tint = rgb(235, 245, 255) },
			bloom = { intensity = 0.8, size = 28, threshold = 0.92 },
			sunRays = { intensity = 0.04, spread = 0.6 },
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
			"Les CONTENEURS (gauche) offrent des angles courts : idéal pour les SMG.",
			"La PASSERELLE (droite) est rapide mais exposée depuis la Tour.",
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
				density = 0.38,
				offset = 0.05,
				color = rgb(90, 80, 75),
				decay = rgb(60, 40, 30),
				glare = 0.1,
				haze = 2.2,
			},
			colorCorrection = { brightness = 0.03, contrast = 0.16, saturation = -0.05, tint = rgb(255, 240, 225) },
			bloom = { intensity = 0.7, size = 24, threshold = 0.9 },
			sunRays = { intensity = 0.02, spread = 0.4 },
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
			"Le site VAULT a deux accès : MAIN (large) et SHAFT (vertical, discret).",
			"L'ATRIUM relie les deux accès : le défenseur qui le tient voit les rotations.",
			"Le verre de l'atrium se traverse : écoutez avant de peek.",
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
			"Les TUNNELS permettent une rotation sûre mais lente entre A et B.",
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
				density = 0.33,
				offset = 0.12,
				color = rgb(190, 170, 175),
				decay = rgb(120, 90, 110),
				glare = 0.6,
				haze = 1.4,
			},
			colorCorrection = { brightness = 0.01, contrast = 0.14, saturation = 0.05, tint = rgb(255, 244, 236) },
			bloom = { intensity = 0.6, size = 26, threshold = 0.93 },
			sunRays = { intensity = 0.12, spread = 0.7 },
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
			"Les BALCONS offrent du high-ground sur chaque site ; les ascenseurs sont bruyants.",
			"En Duel, seule l'arène centrale est active : pas de site, élimination pure.",
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
