--!strict
--[[
	SpreadAudit — détection statistique de la PRÉ-COMPENSATION de dispersion (« no-spread »).

	Limite assumée du modèle prédictif : pour afficher EXACTEMENT les balles que le serveur
	calculera, le client connaît la graine de dispersion (voir Spread). Un cheat peut donc
	calculer le décalage δn du tir n et envoyer une visée a = cible − δn : la balle part
	droit sur la cible, sans cône sous-déclaré ni snap de visée détectable.

	Signature exploitable : chez ce tricheur, la variation de visée entre deux tirs
	consécutifs contient −(δn − δn−1). Un joueur légitime ne connaît pas δ : sa visée en
	est INDÉPENDANTE. On mesure la corrélation (cosinus) entre
	  e  = variation de visée entre deux tirs (plan tangent : droite, haut),
	  Δδ = δn − δn−1,
	sur des fenêtres de WINDOW paires (même arme, écart ≤ MAX_GAP s, cône ≥ MIN_CONE°) :
	  légitime  : r ≈ N(0, 1/√WINDOW)          (σ ≈ 0.16 pour 40 paires)
	  tricheur  : r ≈ −√(σδ² / (σδ² + σh²))    (σh = mouvement humain + recul entre deux tirs)
	Le seuil de départ (−0.6, soit ≈ 3.8 σ) est À CALIBRER sur données réelles ; le
	signalement est pondéré et décroît comme tous les autres (AntiCheatService).
]]

local SpreadAudit = {}

SpreadAudit.WINDOW = 40
SpreadAudit.MAX_GAP = 0.6
SpreadAudit.MIN_CONE = 1.0
SpreadAudit.FLAG_CORRELATION = -0.6

local TWO_PI = math.pi * 2

export type Audit = {
	weapon: string,
	lastT: number,
	lastAim: Vector3?,
	lastOffset: Vector2?,
	dot: number,
	errorSq: number,
	deltaSq: number,
	count: number,
}

function SpreadAudit.new(): Audit
	return {
		weapon = "",
		lastT = -math.huge,
		lastAim = nil,
		lastOffset = nil,
		dot = 0,
		errorSq = 0,
		deltaSq = 0,
		count = 0,
	}
end

--[[ Repère tangent de la visée : le même que Spread (référence Y, X près de la verticale). ]]
local function basis(aim: Vector3): (Vector3, Vector3)
	local reference = if math.abs(aim.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = aim:Cross(reference).Unit
	local up = right:Cross(aim).Unit
	return right, up
end

--[[
	Décalage du centre de dispersion dans le plan tangent (droite, haut), en tangentes.
	Mêmes tirages, dans le même ordre, que Spread.directions (vérifié par les tests).
]]
function SpreadAudit.offset(coneDegrees: number, seed: number): Vector2
	local rng = Random.new(seed)
	local radius = math.rad(math.max(coneDegrees, 0)) * rng:NextNumber()
	local theta = rng:NextNumber() * TWO_PI
	local t = math.tan(radius)
	return Vector2.new(math.cos(theta) * t, math.sin(theta) * t)
end

--[[ Direction obtenue en appliquant un décalage tangent à une visée. ]]
function SpreadAudit.apply(aim: Vector3, offset: Vector2): Vector3
	local right, up = basis(aim)
	return (aim + right * offset.X + up * offset.Y).Unit
end

--[[
	Observe un tir accepté. Renvoie la corrélation quand une fenêtre est complète, sinon nil.
]]
function SpreadAudit.observe(
	audit: Audit,
	weaponId: string,
	t: number,
	aim: Vector3,
	coneDegrees: number,
	offset: Vector2
): number?
	local previousAim, previousOffset = audit.lastAim, audit.lastOffset
	local chained = audit.weapon == weaponId and t > audit.lastT and t - audit.lastT <= SpreadAudit.MAX_GAP
	audit.weapon = weaponId
	audit.lastT = t
	if coneDegrees < SpreadAudit.MIN_CONE then
		audit.lastAim = nil
		audit.lastOffset = nil
		return nil
	end
	audit.lastAim = aim
	audit.lastOffset = offset
	if not (chained and previousAim and previousOffset) then
		return nil
	end
	local right, up = basis(previousAim)
	local change = aim - previousAim
	local e = Vector2.new(change:Dot(right), change:Dot(up))
	local delta = offset - previousOffset
	audit.dot += e:Dot(delta)
	audit.errorSq += e:Dot(e)
	audit.deltaSq += delta:Dot(delta)
	audit.count += 1
	if audit.count < SpreadAudit.WINDOW then
		return nil
	end
	local denominator = math.sqrt(audit.errorSq * audit.deltaSq)
	local correlation = if denominator > 1e-12 then audit.dot / denominator else 0
	audit.dot, audit.errorSq, audit.deltaSq, audit.count = 0, 0, 0, 0
	return correlation
end

return SpreadAudit
