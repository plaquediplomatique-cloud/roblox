--!strict
--[[
	Stances — géométrie de gameplay de chaque posture, partagée client/serveur.

	Une seule source de vérité pour :
	  * la hauteur des hanches (Humanoid.HipHeight relative) -> collision/hauteur physique,
	  * la position de l'oeil (caméra 1re personne ET validation d'origine des tirs serveur),
	  * la disposition des hitboxes (prédiction client ET détection serveur).

	Toutes les positions sont relatives au CENTRE du HumanoidRootPart (HRP), orienté
	selon le yaw du joueur. Avec un HipHeight R15 standard de 2, le centre du HRP est à
	3 studs du sol debout.

	Hauteurs de référence (debout, sol = 0) :
	  oeil 4.7 | tête 4.07–5.17 | torse 2.5–4.08 | jambes 0–2.5
	Accroupi (HipHeight −1.4) : oeil 3.3 | sommet de tête 3.77  => une caisse de 4 studs
	cache entièrement un joueur accroupi, mais pas un joueur debout (oeil à 4.7) :
	c'est la base de toute la grammaire de couverture des maps (voir docs/05).
]]

local Types = require(script.Parent.Parent.Types)

export type HitboxPart = {
	name: string,
	zone: Types.HitZone,
	offset: CFrame,
	size: Vector3,
	upper: boolean, -- suit l'inclinaison (lean)
}

export type StanceProfile = {
	hipHeightOffset: number,
	eye: Vector3,
	parts: { HitboxPart },
	broadphaseCenter: Vector3,
	broadphaseRadius: number,
}

local function part(name: string, zone: Types.HitZone, position: Vector3, size: Vector3, upper: boolean, rotation: CFrame?): HitboxPart
	local offset = CFrame.new(position)
	if rotation then
		offset *= rotation
	end
	return { name = name, zone = zone, offset = offset, size = size, upper = upper }
end

local Stances = {}

Stances.LEAN_OFFSET = 0.55 -- translation latérale du haut du corps (studs) à lean = ±1
Stances.LEAN_ROLL = math.rad(12) -- rotation du haut du corps autour du bassin

Stances.profiles = {
	Stand = {
		hipHeightOffset = 0,
		eye = Vector3.new(0, 1.7, -0.15),
		broadphaseCenter = Vector3.new(0, -0.4, 0),
		broadphaseRadius = 3.4,
		parts = {
			part("Head", "Head", Vector3.new(0, 1.62, -0.05), Vector3.new(1.05, 1.1, 1.05), true),
			part("Torso", "Body", Vector3.new(0, 0.5, 0), Vector3.new(1.9, 1.15, 1.0), true),
			part("Pelvis", "Body", Vector3.new(0, -0.25, 0), Vector3.new(1.8, 0.5, 0.95), false),
			part("LeftLeg", "Limb", Vector3.new(-0.45, -1.75, 0), Vector3.new(0.8, 2.5, 0.8), false),
			part("RightLeg", "Limb", Vector3.new(0.45, -1.75, 0), Vector3.new(0.8, 2.5, 0.8), false),
		},
	},
	Crouch = {
		hipHeightOffset = -1.4,
		eye = Vector3.new(0, 1.7, -0.3),
		broadphaseCenter = Vector3.new(0, 0.1, -0.1),
		broadphaseRadius = 2.9,
		parts = {
			part("Head", "Head", Vector3.new(0, 1.62, -0.2), Vector3.new(1.05, 1.1, 1.05), true),
			part("Torso", "Body", Vector3.new(0, 0.48, -0.15), Vector3.new(1.9, 1.15, 1.05), true),
			part("Pelvis", "Body", Vector3.new(0, -0.25, 0.05), Vector3.new(1.8, 0.5, 1.0), false),
			part("LeftLeg", "Limb", Vector3.new(-0.45, -1.05, -0.35), Vector3.new(0.8, 1.1, 1.5), false),
			part("RightLeg", "Limb", Vector3.new(0.45, -1.05, -0.35), Vector3.new(0.8, 1.1, 1.5), false),
		},
	},
	Slide = {
		hipHeightOffset = -1.7,
		eye = Vector3.new(0, 1.32, 0.45),
		broadphaseCenter = Vector3.new(0, 0, -0.3),
		broadphaseRadius = 3.0,
		parts = {
			part("Head", "Head", Vector3.new(0, 1.25, 0.75), Vector3.new(1.05, 1.1, 1.05), true),
			part("Torso", "Body", Vector3.new(0, 0.35, 0.35), Vector3.new(1.9, 1.15, 1.0), true, CFrame.Angles(math.rad(30), 0, 0)),
			part("Pelvis", "Body", Vector3.new(0, -0.3, 0), Vector3.new(1.8, 0.5, 0.95), false),
			part("LeftLeg", "Limb", Vector3.new(-0.45, -0.95, -1.0), Vector3.new(0.8, 0.7, 2.2), false),
			part("RightLeg", "Limb", Vector3.new(0.45, -0.95, -1.0), Vector3.new(0.8, 0.7, 2.2), false),
		},
	},
} :: { [Types.Stance]: StanceProfile }

--[[
	Transformation du haut du corps pour un lean donné (−1 gauche … +1 droite).
	Appliquée autour du centre du HRP : rotation (roll) puis décalage latéral.
	La caméra et les hitboxes utilisent EXACTEMENT cette fonction : ce que le joueur voit
	en se penchant correspond au volume touchable par l'adversaire.
]]
function Stances.leanTransform(lean: number): CFrame
	if lean == 0 then
		return CFrame.identity
	end
	return CFrame.new(lean * Stances.LEAN_OFFSET, 0, 0) * CFrame.Angles(0, 0, -lean * Stances.LEAN_ROLL)
end

function Stances.eyeOffset(stance: Types.Stance, lean: number): Vector3
	local profile = Stances.profiles[stance]
	return Stances.leanTransform(lean) * profile.eye
end

--[[ Position monde de l'oeil à partir du CFrame du HRP (seul le yaw du HRP est utilisé). ]]
function Stances.eyePosition(rootCFrame: CFrame, stance: Types.Stance, lean: number): Vector3
	local _, yaw, _ = rootCFrame:ToEulerAnglesYXZ()
	local flat = CFrame.new(rootCFrame.Position) * CFrame.Angles(0, yaw, 0)
	return flat * Stances.eyeOffset(stance, lean)
end

return Stances
