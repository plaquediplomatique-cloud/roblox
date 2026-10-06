--!strict
--[[
	Œuf — nombres de design de la boucle d'éclosion.

	Le tout premier œuf est court : la première récompense doit arriver dans la première
	minute de jeu. Les suivants ralentissent pour laisser le temps d'explorer l'île.
]]

return {
	firstHatchSeconds = 8,
	hatchSeconds = 30,
	-- Délai entre l'éclosion (révélation) et l'arrivée de l'œuf suivant dans le nid.
	nextEggDelay = 2.5,
	-- Nombre de pets qui suivent le joueur (les plus récents).
	maxFollowers = 3,
	promptDistance = 12,
	promptHoldSeconds = 0.35,
}
