--!strict
--[[
	Onboarding — « prochaine étape » affichée au hub pour les premières sessions.

	Principe (skill roblox-game-ux) : apprendre en faisant. Une seule consigne courte à la
	fois, qui disparaît dès qu'elle est accomplie ; jamais de mur d'instructions.
	  1. s'échauffer au stand de tir (une fois par session tant qu'aucun match n'est joué),
	  2. lancer sa première partie,
	  3. réclamer ses récompenses de missions (premières parties),
	puis plus rien : le hub reste propre pour les joueurs installés.
]]

export type Step = {
	id: "Training" | "FirstMatch" | "Missions",
	title: string, -- étiquette courte (« OBJECTIF »)
	text: string, -- la consigne
	target: string?, -- tag CollectionService du lieu visé (distance affichée), sinon nil
}

export type Progress = {
	matches: number, -- parties jouées (profil)
	trainedThisSession: boolean, -- passé par le stand de tir pendant cette session
	missionsToClaim: number, -- missions terminées non réclamées
}

local Onboarding = {}

Onboarding.GUIDED_MATCHES = 3 -- au-delà, plus de guidage (joueur installé)

function Onboarding.nextStep(progress: Progress, menuKey: string): Step?
	if progress.matches >= Onboarding.GUIDED_MATCHES then
		return nil
	end
	if progress.matches == 0 and not progress.trainedThisSession then
		return {
			id = "Training",
			title = "OBJECTIF",
			text = "Échauffe-toi au stand de tir",
			target = "TrainingZone",
		}
	end
	if progress.matches == 0 then
		return {
			id = "FirstMatch",
			title = "OBJECTIF",
			text = ("Lance ta première partie  ·  [%s] puis JOUER"):format(menuKey),
			target = nil,
		}
	end
	if progress.missionsToClaim > 0 then
		return {
			id = "Missions",
			title = "RÉCOMPENSE",
			text = ("%d mission%s à réclamer  ·  [%s] puis MISSIONS"):format(
				progress.missionsToClaim,
				if progress.missionsToClaim > 1 then "s" else "",
				menuKey
			),
			target = nil,
		}
	end
	return nil
end

return Onboarding
