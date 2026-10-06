--!strict
--[[
	SwingPose — animation de frappe PROCÉDURALE (aucun asset d'animation) : pour un style et un
	temps normalisé t∈[0,1], renvoie les angles à appliquer au bras droit, à la taille et à la
	racine. Pure et testée : l'orientation de la lame est vérifiée par le calcul.

	Repère (R15) : l'épaule reçoit  C0 * Ry(Yaw) * Rx(Shoulder)  ; Rx(+) lève le bras vers l'avant.
	L'arme est soudée à la main avec Rx(GripAngle) : en pose « prêt » (Shoulder = 75°) la lame
	pointe vers l'avant et à 45° vers le haut.
]]

local SwingPose = {}

export type Pose = {
	Shoulder: number, -- rad : élévation du bras (0 = le long du corps, π/2 = horizontal)
	Yaw: number, -- rad : balayage latéral du bras
	Torso: number, -- rad : torsion de la taille
	Lunge: number, -- studs : poussée du buste vers l'avant
}

export type Key = { T: number, Shoulder: number, Yaw: number, Torso: number, Lunge: number }

SwingPose.ReadyShoulder = math.rad(75)
SwingPose.GripAngle = math.rad(-120)
SwingPose.ImpactTime = 0.42 -- fraction de l'animation où le coup « touche » (déclenche les effets)

local function k(t: number, shoulderDeg: number, yawDeg: number, torsoDeg: number, lunge: number): Key
	return { T = t, Shoulder = math.rad(shoulderDeg), Yaw = math.rad(yawDeg), Torso = math.rad(torsoDeg), Lunge = lunge }
end

-- Chaque style : clés triées par T ; T=0 et T=1 = pose « prêt ». Impact à ImpactTime.
SwingPose.Styles = {
	Overhead = {
		k(0, 75, 0, 0, 0),
		k(0.2, 165, 0, 6, -0.2),
		k(0.42, 26, 0, -8, 0.7),
		k(0.62, 60, 0, -3, 0.3),
		k(1, 75, 0, 0, 0),
	},
	Slash = {
		k(0, 75, 0, 0, 0),
		k(0.2, 100, 65, 28, -0.2),
		k(0.42, 78, -70, -34, 0.6),
		k(0.65, 70, -25, -10, 0.2),
		k(1, 75, 0, 0, 0),
	},
	Stab = {
		k(0, 75, 0, 0, 0),
		k(0.22, 62, 18, 14, -0.5),
		k(0.42, 92, -4, -12, 1.4),
		k(0.62, 88, 0, -4, 0.8),
		k(1, 75, 0, 0, 0),
	},
	Spin = {
		k(0, 75, 0, 0, 0),
		k(0.15, 92, 30, 25, 0),
		k(0.42, 92, -30, -200, 0.4),
		k(0.7, 88, 0, -330, 0.2),
		k(1, 75, 0, -360, 0),
	},
	Slam = {
		k(0, 75, 0, 0, 0),
		k(0.3, 175, 0, 8, -0.3),
		k(0.42, 20, 0, -10, 1),
		k(0.7, 40, 0, -4, 0.5),
		k(1, 75, 0, 0, 0),
	},
}

local function easeInOut(x: number): number
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Pose pour le style donné (inconnu => Overhead) à l'instant normalisé t.
function SwingPose.sample(style: string, t: number): Pose
	local keys: { Key } = SwingPose.Styles[style] or SwingPose.Styles.Overhead
	t = math.clamp(t, 0, 1)
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b.T then
			local span = b.T - a.T
			local alpha = if span <= 0 then 1 else easeInOut((t - a.T) / span)
			return {
				Shoulder = lerp(a.Shoulder, b.Shoulder, alpha),
				Yaw = lerp(a.Yaw, b.Yaw, alpha),
				Torso = lerp(a.Torso, b.Torso, alpha),
				Lunge = lerp(a.Lunge, b.Lunge, alpha),
			}
		end
	end
	local last = keys[#keys]
	return { Shoulder = last.Shoulder, Yaw = last.Yaw, Torso = last.Torso, Lunge = last.Lunge }
end

-- Pose de repos (arme en garde).
function SwingPose.ready(): Pose
	return { Shoulder = SwingPose.ReadyShoulder, Yaw = 0, Torso = 0, Lunge = 0 }
end

-- Direction de la lame dans le repère du torse pour une pose (±π près si Spin : la torsion tourne le tout).
function SwingPose.bladeDirection(pose: Pose): Vector3
	local rotation = CFrame.Angles(0, pose.Yaw, 0)
		* CFrame.Angles(pose.Shoulder, 0, 0)
		* CFrame.Angles(SwingPose.GripAngle, 0, 0)
	return rotation:VectorToWorldSpace(Vector3.yAxis)
end

return SwingPose
