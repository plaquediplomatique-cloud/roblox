--!strict
--[[
	Incubation — règles pures du minuteur d'un œuf.

	Toutes les heures sont des temps SERVEUR (workspace:GetServerTimeNow()) : le serveur
	écrit `ReadyAt` en attribut, le client calcule l'affichage avec la même règle.
]]

local Incubation = {}

function Incubation.remaining(readyAt: number, now: number): number
	return math.max(0, readyAt - now)
end

function Incubation.isReady(readyAt: number, now: number): boolean
	return now >= readyAt
end

-- 0 → 1 ; durée nulle ou négative = déjà terminé.
function Incubation.progress(startedAt: number, readyAt: number, now: number): number
	local duration = readyAt - startedAt
	if duration <= 0 then
		return 1
	end
	return math.clamp((now - startedAt) / duration, 0, 1)
end

-- "0:07", "1:05" — arrondi au supérieur pour ne jamais afficher 0:00 avant la fin.
function Incubation.formatClock(seconds: number): string
	local total = math.ceil(math.max(0, seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

return Incubation
