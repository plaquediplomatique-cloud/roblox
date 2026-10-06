--!strict
--[[
	Footsteps — volume et foulée d'un pas selon l'allure.

	Règle partagée par le joueur local (MovementController) et les autres joueurs
	(CharacterAnimator) : ce que j'entends de moi est ce que les autres entendent.
	  * marche (Alt) ou allure de marche (stick à mi-course) : silencieux,
	  * accroupi : feutré,
	  * course : audible, sprint : plus fort (le sprint se paie en discrétion),
	  * glissade : pas de pas (le frottement a son propre son).
]]

local Types = require(script.Parent.Parent.Types)
local Movement = require(script.Parent.Parent.Config.Movement)

local Footsteps = {}

local WALK_TOLERANCE = 0.5

function Footsteps.volume(stance: Types.Stance, walking: boolean, speed: number): number
	if stance == "Slide" or speed <= 0 then
		return 0
	end
	if stance == "Crouch" then
		return Movement.footsteps.crouchVolume * math.clamp(speed / Movement.crouchSpeed, 0.4, 1)
	end
	if walking or speed <= Movement.walkSpeed + WALK_TOLERANCE then
		return Movement.footsteps.walkVolume
	end
	local t = math.clamp((speed - Movement.walkSpeed) / (Movement.sprintSpeed - Movement.walkSpeed), 0, 1)
	return Movement.footsteps.runVolume * (0.55 + 0.45 * t)
end

--[[ Distance entre deux pas : plus longue en sprint, plus courte accroupi. ]]
function Footsteps.stride(stance: Types.Stance, speed: number): number
	if stance == "Crouch" then
		return Movement.footsteps.crouchStride
	end
	local sprintBlend =
		math.clamp((speed - Movement.runSpeed) / math.max(Movement.sprintSpeed - Movement.runSpeed, 0.01), 0, 1)
	return Movement.footsteps.strideLength
		+ (Movement.sprint.strideLength - Movement.footsteps.strideLength) * sprintBlend
end

return Footsteps
