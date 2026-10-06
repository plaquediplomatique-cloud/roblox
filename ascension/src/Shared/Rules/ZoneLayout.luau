--!strict
--[[
	ZoneLayout — emplacement des 10 royaumes dans le monde (pur, testé). Le village est au
	centre ; les autres zones sont réparties sur un grand cercle, certaines en altitude.
	Serveur (construction, téléportation) et client (ambiance : éclairage, musique) utilisent
	les mêmes fonctions : la zone d'un joueur se déduit uniquement de sa position.
]]

local Zones = require(script.Parent.Parent.Config.Zones)

local ZoneLayout = {}

ZoneLayout.Radius = 130 -- rayon du sol d'une zone (hors village)
ZoneLayout.VillageRadius = 230
ZoneLayout.Ring = 800 -- distance du village aux autres zones
ZoneLayout.Altitude = { 0, 0, 0, 0, 0, 220, 0, 320, 440, 560 } -- Y du sol par zone

function ZoneLayout.center(index: number): Vector3
	if index == 1 then
		return Vector3.new(0, 0, 0)
	end
	local angle = (index - 2) * (2 * math.pi / (Zones.Count - 1)) + math.rad(20)
	return Vector3.new(math.sin(angle) * ZoneLayout.Ring, ZoneLayout.Altitude[index], math.cos(angle) * ZoneLayout.Ring)
end

function ZoneLayout.radius(index: number): number
	return if index == 1 then ZoneLayout.VillageRadius else ZoneLayout.Radius
end

-- Point d'arrivée (entrée de la zone, face au centre).
function ZoneLayout.spawn(index: number): CFrame
	local center = ZoneLayout.center(index)
	if index == 1 then
		return CFrame.new(center + Vector3.new(0, 4, 40))
	end
	local outward = Vector3.new(center.X, 0, center.Z).Unit
	local position = center + outward * (ZoneLayout.Radius * 0.72) + Vector3.new(0, 4, 0)
	local back = outward
	local right = Vector3.yAxis:Cross(back)
	return CFrame.fromMatrix(position, right, Vector3.yAxis, back) -- regarde (-Z) vers le centre
end

-- Zone contenant la position (nil entre deux zones, ou dans le vide).
function ZoneLayout.zoneAt(position: Vector3): number?
	for index = Zones.Count, 1, -1 do
		local center = ZoneLayout.center(index)
		local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
		if flat <= ZoneLayout.radius(index) + 40 and math.abs(position.Y - center.Y) < 120 then
			return index
		end
	end
	return nil
end

-- Arène du boss (angle fixe par zone pour la lisibilité).
function ZoneLayout.bossArena(index: number): Vector3
	local center = ZoneLayout.center(index)
	local r = ZoneLayout.radius(index)
	local offset = if index == 1 then Vector3.new(0, 0, -(r * 0.7)) else Vector3.new(0, 0, -r * 0.62)
	return center + offset
end

-- 6 positions de mannequins de terrain, autour du centre.
function ZoneLayout.dummyPositions(index: number): { Vector3 }
	local center = ZoneLayout.center(index)
	local out: { Vector3 } = {}
	local radius = if index == 1 then 52 else 34
	for i = 1, 6 do
		local angle = (i - 1) * math.pi / 3 + math.rad(30)
		table.insert(out, center + Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius))
	end
	return out
end

return ZoneLayout
