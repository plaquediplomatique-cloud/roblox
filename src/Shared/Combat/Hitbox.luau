--!strict
--[[
	Hitbox — détection de touche rayon / boîtes orientées (OBB), partagée client/serveur.

	Les hitboxes de gameplay NE SONT PAS les Parts visuelles du personnage :
	  * elles dépendent uniquement de (CFrame du HRP, posture, lean) — données que le
	    serveur connaît et historise pour la compensation de latence ;
	  * elles sont immunisées contre les manipulations client (avatar minuscule, parts
	    redimensionnées, animations trafiquées) ;
	  * elles sont identiques pour tous (équité compétitive).

	Pipeline d'un test :
	  1. broadphase : rayon / sphère englobante (rejette 95 % des cibles en ~10 ops),
	  2. narrowphase : rayon / OBB pour chaque partie, on garde la plus proche,
	  3. `inflate` élargit les boîtes (tolérance d'interpolation côté serveur).
]]

local Types = require(script.Parent.Parent.Types)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)
local Stances = require(script.Parent.Stances)

export type Box = {
	name: string,
	zone: Types.HitZone,
	cframe: CFrame,
	half: Vector3,
}

export type HitResult = {
	distance: number,
	zone: Types.HitZone,
	part: string,
	position: Vector3,
}

local Hitbox = {}

local function flatRoot(rootCFrame: CFrame): CFrame
	local _, yaw, _ = rootCFrame:ToEulerAnglesYXZ()
	return CFrame.new(rootCFrame.Position) * CFrame.Angles(0, yaw, 0)
end

--[[ Construit les boîtes monde d'une cible. `out` permet de réutiliser un tableau (zéro alloc). ]]
function Hitbox.compose(rootCFrame: CFrame, stance: Types.Stance, lean: number, out: { Box }?): { Box }
	local boxes = out or {}
	local profile = Stances.profiles[stance]
	local base = flatRoot(rootCFrame)
	local leanCFrame = Stances.leanTransform(lean)
	for index, hitPart in profile.parts do
		local local_ = if hitPart.upper then leanCFrame * hitPart.offset else hitPart.offset
		local existing = boxes[index]
		local cframe = base * local_
		local half = hitPart.size * 0.5
		if existing then
			existing.name = hitPart.name
			existing.zone = hitPart.zone
			existing.cframe = cframe
			existing.half = half
		else
			boxes[index] = { name = hitPart.name, zone = hitPart.zone, cframe = cframe, half = half }
		end
	end
	while #boxes > #profile.parts do
		table.remove(boxes)
	end
	return boxes
end

--[[
	Lance un rayon contre une cible. `direction` doit être unitaire.
	Renvoie le résultat le plus proche ou nil.
]]
function Hitbox.raycast(
	origin: Vector3,
	direction: Vector3,
	maxDistance: number,
	rootCFrame: CFrame,
	stance: Types.Stance,
	lean: number,
	inflate: number
): HitResult?
	local profile = Stances.profiles[stance]
	local base = flatRoot(rootCFrame)
	local center = base * profile.broadphaseCenter
	local entry = MathUtil.raySphere(origin, direction, center, profile.broadphaseRadius + inflate)
	if entry == nil or entry > maxDistance then
		return nil
	end

	local leanCFrame = Stances.leanTransform(lean)
	local inflation = Vector3.new(inflate, inflate, inflate)
	local bestDistance = math.huge
	local bestPart: HitboxPart? = nil
	for _, hitPart in profile.parts do
		local local_ = if hitPart.upper then leanCFrame * hitPart.offset else hitPart.offset
		local t = MathUtil.rayOBB(origin, direction, base * local_, hitPart.size * 0.5 + inflation, maxDistance)
		if t and t < bestDistance then
			bestDistance = t
			bestPart = hitPart
		end
	end
	if bestPart == nil then
		return nil
	end
	return {
		distance = bestDistance,
		zone = bestPart.zone,
		part = bestPart.name,
		position = origin + direction * bestDistance,
	}
end

type HitboxPart = Stances.HitboxPart

--[[ Centre approximatif de la cible (pour les indicateurs, la killcam, l'aim-assist mobile). ]]
function Hitbox.centerOf(rootCFrame: CFrame, stance: Types.Stance): Vector3
	return flatRoot(rootCFrame) * Stances.profiles[stance].broadphaseCenter
end

function Hitbox.headOf(rootCFrame: CFrame, stance: Types.Stance, lean: number): Vector3
	local profile = Stances.profiles[stance]
	local head = profile.parts[1]
	local local_ = Stances.leanTransform(lean) * head.offset
	return (flatRoot(rootCFrame) * local_).Position
end

return Hitbox
