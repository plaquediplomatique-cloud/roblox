--!strict
--[[
	NumberFormat — affichage compact des grands nombres (1.2K, 3.45M, 7.8Qa…).
	Les nombres du jeu montent à ~1e17 : tout l'UI passe par ici.
]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local NumberFormat = {}

local function trim(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- 999 -> "999" ; 1234 -> "1.23K" ; 1.5e6 -> "1.5M"
function NumberFormat.compact(value: number): string
	if value ~= value then
		return "0"
	end
	if value < 0 then
		return "-" .. NumberFormat.compact(-value)
	end
	if value < 1000 then
		return trim(string.format(if value < 10 and value % 1 ~= 0 then "%.1f" else "%.0f", value))
	end
	local exponent = math.min(#SUFFIXES - 1, math.floor(math.log10(value) / 3))
	local scaled = value / 10 ^ (exponent * 3)
	-- Évite "1000K" : si l'arrondi atteint 1000, on passe au suffixe suivant.
	local text = string.format(if scaled < 10 then "%.2f" elseif scaled < 100 then "%.1f" else "%.0f", scaled)
	if tonumber(text) :: number >= 1000 and exponent < #SUFFIXES - 1 then
		exponent += 1
		text = string.format("%.2f", value / 10 ^ (exponent * 3))
	end
	return trim(text) .. SUFFIXES[exponent + 1]
end

-- 3725 -> "1h 02m" ; 75 -> "1m 15s" ; 9 -> "9s"
function NumberFormat.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- 0.153 -> "15.3%" ; 0.5 -> "50%"
function NumberFormat.percent(fraction: number): string
	return trim(string.format("%.1f", fraction * 100)) .. "%"
end

-- Arrondi à `digits` chiffres significatifs (dégâts d'armes lisibles : 1 234 567 -> 1 200 000).
function NumberFormat.roundSignificant(value: number, digits: number): number
	if value == 0 or value ~= value then
		return 0
	end
	local magnitude = math.floor(math.log10(math.abs(value))) + 1
	local factor = 10 ^ (digits - magnitude)
	return math.floor(value * factor + 0.5) / factor
end

return NumberFormat
