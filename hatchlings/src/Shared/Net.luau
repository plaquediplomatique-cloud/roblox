--!strict
--[[
	Net — noms des remotes. Un seul remote (serveur → clients) : le joueur n'envoie rien,
	l'éclosion passe par un ProximityPrompt validé côté serveur.
]]

return {
	folderName = "HatchlingsRemotes",
	petHatched = "PetHatched", -- (ownerName: string, ownerUserId: number, petId: string, isNew: boolean)
	eggTag = "HatchlingEgg", -- tag CollectionService posé sur chaque modèle d'œuf
	discoveredAttribute = "Discovered", -- attribut du Player : ids de pets séparés par des virgules
}
