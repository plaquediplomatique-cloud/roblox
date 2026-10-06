--!strict
--[[
	Spread — dispersion DÉTERMINISTE, partagée client/serveur.

	Le client n'envoie jamais "la direction de ma balle". Il envoie :
	  * a : la direction de visée (caméra, recul compris),
	  * s : le cône de dispersion qu'il a appliqué (degrés),
	  * n : le numéro du tir.
	La graine = hash(graine_joueur_attribuée_par_le_serveur, n). Le serveur recalcule donc
	EXACTEMENT les mêmes directions, sans faire confiance au client :
	  * déclarer s≈0 ne sert à rien : le serveur applique au moins le cône minimal plausible,
	  * le client ne choisit pas sa graine (base tirée par le serveur à chaque armement, n
	    strictement séquentiel : un tir ne peut être ni rejoué ni sauté).
	La base est transmise au client (sinon pas de prédiction exacte) : un cheat peut donc
	pré-compenser le décalage connu d'avance. Cette signature est détectée statistiquement
	par SpreadAudit (corrélation visée / décalage).

	Le cône lui-même suit une formule unique (Spread.cone) : base hip/ADS, pénalité de
	mouvement au-delà de 34 % de la vitesse de course (counter-strafe récompensé), pénalité
	aérienne, bonus accroupi, bloom par tir et précision de 1re balle.
]]

local Types = require(script.Parent.Parent.Types)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)

export type SpreadState = {
	ads: number, -- 0..1 (alpha de visée)
	speedRatio: number, -- vitesse horizontale / vitesse de course
	airborne: boolean,
	crouched: boolean,
	bloom: number,
	firstShot: boolean,
}

local Spread = {}

Spread.ACCURATE_SPEED_RATIO = 0.34
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local TWO_PI = math.pi * 2

function Spread.cone(profile: Types.SpreadProfile, state: SpreadState): number
	local base = MathUtil.lerp(profile.hip, profile.ads, MathUtil.clamp01(state.ads))
	if state.firstShot then
		base *= profile.firstShotMultiplier
	end
	if state.crouched then
		base *= profile.crouchMultiplier
	end
	local moveFactor =
		MathUtil.clamp01((state.speedRatio - Spread.ACCURATE_SPEED_RATIO) / (1 - Spread.ACCURATE_SPEED_RATIO))
	local cone = base + profile.move * moveFactor
	if state.airborne then
		cone += profile.air
	end
	if not state.firstShot then
		cone += state.bloom
	end
	return cone
end

--[[ Bloom après un temps d'inactivité `idle` (secondes). ]]
function Spread.decayBloom(profile: Types.SpreadProfile, bloom: number, idle: number): number
	if idle <= profile.bloomRecoveryDelay then
		return bloom
	end
	return math.max(0, bloom - (idle - profile.bloomRecoveryDelay) * profile.bloomRecovery)
end

--[[ Bloom immédiatement après un tir, sachant le bloom précédent et le temps écoulé. ]]
function Spread.bloomAfterShot(profile: Types.SpreadProfile, bloom: number, sinceLastShot: number): number
	local decayed = Spread.decayBloom(profile, bloom, sinceLastShot)
	return math.min(profile.bloomMax, decayed + profile.bloomPerShot)
end

function Spread.seed(baseSeed: number, shotIndex: number): number
	return MathUtil.combineSeed(baseSeed, shotIndex)
end

local function basis(aim: Vector3): (Vector3, Vector3)
	local reference = if math.abs(aim.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = aim:Cross(reference).Unit
	local up = right:Cross(aim).Unit
	return right, up
end

local function offset(aim: Vector3, right: Vector3, up: Vector3, angle: number, theta: number): Vector3
	local t = math.tan(angle)
	return (aim + (right * math.cos(theta) + up * math.sin(theta)) * t).Unit
end

--[[
	Directions finales des projectiles.
	  * balle unique : décalage aléatoire dans le cône, densité plus forte au centre
	    (rayon ∝ u, pas √u) — les sprays restent lisibles et "justes" ;
	  * plombs : motif fixe en tournesol (angle d'or) centré sur une direction dispersée,
	    légère gigue seedée : forme reconnaissable, pas de "loterie" totale.
]]
function Spread.directions(
	aim: Vector3,
	coneDegrees: number,
	seed: number,
	pellets: number,
	pelletConeDegrees: number
): { Vector3 }
	local rng = Random.new(seed)
	local right, up = basis(aim)
	local radius = math.rad(math.max(coneDegrees, 0)) * rng:NextNumber()
	local theta = rng:NextNumber() * TWO_PI
	local center = if radius > 0 then offset(aim, right, up, radius, theta) else aim
	if pellets <= 1 then
		return { center }
	end

	local directions = table.create(pellets)
	local centerRight, centerUp = basis(center)
	local rotation = rng:NextNumber() * TWO_PI
	local cone = math.rad(pelletConeDegrees)
	for index = 1, pellets do
		local fraction = math.sqrt((index - 0.5) / pellets)
		local jitter = 0.85 + rng:NextNumber() * 0.3
		directions[index] =
			offset(center, centerRight, centerUp, cone * fraction * jitter, rotation + index * GOLDEN_ANGLE)
	end
	return directions
end

return Spread
