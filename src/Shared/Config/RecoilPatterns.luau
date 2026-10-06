--!strict
--[[
	RecoilPatterns — construction lisible des patterns de recul.

	Un pattern est une suite de segments { nombre de tirs, pitch/tir, yaw/tir }.
	Exemple VK-12 : 3 tirs doux, 7 tirs de montée verticale, puis balayage gauche/droite.
	Le joueur apprend la FORME (contrôlable, compétitif) ; la composante aléatoire
	(randomYaw/randomPitch, petite) empêche le "pixel-perfect" scripté.
]]

local RecoilPatterns = {}

export type Segment = { count: number, pitch: number, yaw: number, pitchEnd: number?, yawEnd: number? }

--[[ Chaque segment peut interpoler pitch/yaw de sa valeur de départ à pitchEnd/yawEnd. ]]
function RecoilPatterns.build(segments: { Segment }): { Vector2 }
	local pattern: { Vector2 } = {}
	for _, segment in segments do
		for index = 1, segment.count do
			local t = if segment.count > 1 then (index - 1) / (segment.count - 1) else 0
			local pitch = segment.pitch + ((segment.pitchEnd or segment.pitch) - segment.pitch) * t
			local yaw = segment.yaw + ((segment.yawEnd or segment.yaw) - segment.yaw) * t
			table.insert(pattern, Vector2.new(yaw, pitch))
		end
	end
	return pattern
end

--[[ Somme d'un pattern sur N tirs (doc / équilibrage / tests). ]]
function RecoilPatterns.total(pattern: { Vector2 }, shots: number): Vector2
	local sum = Vector2.zero
	for index = 1, math.min(shots, #pattern) do
		sum += pattern[index]
	end
	return sum
end

return RecoilPatterns
