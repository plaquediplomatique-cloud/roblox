--!strict
--[[
	Raretés — chances d'éclosion (poids relatifs, somme = 100) et couleur d'identité.

	L'ordre de `order` va du plus commun au plus rare : il sert à l'affichage (collection)
	et à décider quelles éclosions méritent une annonce à tout le serveur.
]]

export type RarityInfo = {
	id: string,
	name: string,
	weight: number,
	color: Color3,
	announce: boolean, -- annoncée aux autres joueurs du serveur
}

local order: { string } = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local info: { [string]: RarityInfo } = {
	Common = { id = "Common", name = "Common", weight = 60, color = Color3.fromRGB(176, 190, 204), announce = false },
	Uncommon = {
		id = "Uncommon",
		name = "Uncommon",
		weight = 25,
		color = Color3.fromRGB(110, 214, 140),
		announce = false,
	},
	Rare = { id = "Rare", name = "Rare", weight = 10, color = Color3.fromRGB(84, 168, 255), announce = false },
	Epic = { id = "Epic", name = "Epic", weight = 4, color = Color3.fromRGB(190, 120, 255), announce = true },
	Legendary = {
		id = "Legendary",
		name = "Legendary",
		weight = 1,
		color = Color3.fromRGB(255, 196, 64),
		announce = true,
	},
}

return {
	order = order,
	info = info,
}
