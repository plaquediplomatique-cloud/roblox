--!strict
--[[
	Daily (règles) — série de connexion. Pure : prend le temps en paramètre (jamais os.time()).

	Cycle de 7 jours. Réclamation possible toutes les 20 h ; si plus de 48 h se sont écoulées
	depuis la dernière, la série retombe au jour 1. Une horloge qui recule n'ouvre jamais
	de réclamation (anti-triche).
]]

local Config = require(script.Parent.Parent.Config.Daily)

local Daily = {}

export type State = { Streak: number, LastClaim: number }
export type Status = { CanClaim: boolean, Day: number, Streak: number, NextIn: number, Broken: boolean }

local HOUR = 3600

function Daily.status(state: State, now: number): Status
	local cycle = #Config.Days
	if state.LastClaim <= 0 then
		return { CanClaim = true, Day = 1, Streak = 0, NextIn = 0, Broken = false }
	end
	local elapsed = now - state.LastClaim
	if elapsed < 0 then
		return {
			CanClaim = false,
			Day = state.Streak % cycle + 1,
			Streak = state.Streak,
			NextIn = 1 * HOUR,
			Broken = false,
		}
	end
	if elapsed > Config.ClaimWindowHours * HOUR then
		return { CanClaim = true, Day = 1, Streak = 0, NextIn = 0, Broken = true }
	end
	local cooldown = Config.CooldownHours * HOUR
	if elapsed < cooldown then
		return {
			CanClaim = false,
			Day = state.Streak % cycle + 1,
			Streak = state.Streak,
			NextIn = cooldown - elapsed,
			Broken = false,
		}
	end
	return { CanClaim = true, Day = state.Streak % cycle + 1, Streak = state.Streak, NextIn = 0, Broken = false }
end

-- Applique la réclamation ; renvoie (jour réclamé, récompense) ou nil si impossible.
function Daily.claim(state: State, now: number): (number?, Config.Reward?)
	local status = Daily.status(state, now)
	if not status.CanClaim then
		return nil, nil
	end
	state.Streak = status.Streak + 1
	state.LastClaim = now
	return status.Day, Config.Days[status.Day]
end

return Daily
