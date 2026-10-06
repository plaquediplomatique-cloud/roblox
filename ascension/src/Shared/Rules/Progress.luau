--!strict
--[[
	Progress — XP → niveaux. Pure. Au niveau maximal l'XP n'augmente plus (le jeu bascule sur
	l'Ascension) ; un gain géant franchit plusieurs niveaux d'un coup.
]]

local Game = require(script.Parent.Parent.Config.Game)
local Curves = require(script.Parent.Curves)

local Progress = {}

export type Result = { Level: number, XP: number, LevelsGained: number }

function Progress.addXP(level: number, xp: number, gain: number): Result
	if gain ~= gain or gain <= 0 or level >= Game.MaxLevel then
		return {
			Level = math.min(level, Game.MaxLevel),
			XP = if level >= Game.MaxLevel then 0 else xp,
			LevelsGained = 0,
		}
	end
	local gained = 0
	xp += gain
	while level < Game.MaxLevel do
		local need = Curves.xpToNext(level)
		if xp < need then
			break
		end
		xp -= need
		level += 1
		gained += 1
	end
	if level >= Game.MaxLevel then
		xp = 0
	end
	return { Level = level, XP = xp, LevelsGained = gained }
end

-- Fraction (0..1) vers le prochain niveau.
function Progress.fraction(level: number, xp: number): number
	if level >= Game.MaxLevel then
		return 1
	end
	return math.clamp(xp / Curves.xpToNext(level), 0, 1)
end

return Progress
