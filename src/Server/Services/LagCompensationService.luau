--!strict
--[[
	LagCompensationService — historique des poses et rembobinage pour la détection
	de touche AUTORITAIRE côté serveur.

	Problème : un tireur à 80 ms de ping voit ses adversaires là où ils étaient il y a
	~80 ms + le tampon d'interpolation. Si le serveur testait les positions actuelles,
	des tirs parfaitement visés "rateraient" -> injouable.

	Solution :
	  * À chaque Heartbeat, on enregistre pour chaque cible vivante : temps serveur,
	    CFrame du HRP, posture, lean (anneau de 64 échantillons ≈ 1 s).
	  * Pour un tir horodaté t (horloge serveur synchronisée), on reconstruit la pose
	    à (t − délai d'interpolation) par interpolation entre les deux échantillons qui
	    l'encadrent, puis on teste le rayon contre les hitboxes (Shared/Combat/Hitbox).
	  * Le rembobinage est BORNÉ (MAX_REWIND) : un client ne peut pas "remonter le temps"
	    arbitrairement pour toucher quelqu'un déjà à couvert ("favor the shooter",
	    mais dans une limite saine).
	Les cibles sont des joueurs ou des bots (Training Range) : interface uniforme.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Hitbox = require(Shared.Combat.Hitbox)

export type DamageResult = {
	killed: boolean,
	health: number,
	armor: number,
	healthLoss: number,
	armorLoss: number,
}

export type DamageInfo = {
	attacker: Player?,
	weaponId: string,
	zone: Types.HitZone,
	wallbang: boolean,
	direction: Vector3,
	distance: number,
	backstab: boolean?,
	explosive: boolean?,
}

export type Target = {
	id: number,
	kind: "Player" | "Bot",
	player: Player?,
	model: Model,
	root: BasePart,
	arena: string,
	team: () -> string,
	alive: () -> boolean,
	stance: () -> Types.Stance,
	lean: () -> number,
	receive: (amount: number, info: DamageInfo) -> DamageResult,
}

export type Snapshot = {
	t: number,
	cframe: CFrame,
	stance: Types.Stance,
	lean: number,
}

local HISTORY_SIZE = 64
local MAX_REWIND = 0.35
local INTERP_DELAY = 0.1

local LagCompensationService = {}
LagCompensationService.MAX_REWIND = MAX_REWIND
LagCompensationService.INTERP_DELAY = INTERP_DELAY

local targets: { [number]: Target } = {}
local histories: { [number]: { Snapshot } } = {}

function LagCompensationService.register(target: Target)
	targets[target.id] = target
	histories[target.id] = {}
end

function LagCompensationService.unregister(id: number)
	targets[id] = nil
	histories[id] = nil
end

function LagCompensationService.get(id: number): Target?
	return targets[id]
end

function LagCompensationService.all(): { [number]: Target }
	return targets
end

local function record(target: Target, now: number)
	local history = histories[target.id]
	if not history then
		return
	end
	if #history >= HISTORY_SIZE then
		table.remove(history, 1)
	end
	table.insert(history, {
		t = now,
		cframe = target.root.CFrame,
		stance = target.stance(),
		lean = target.lean(),
	})
end

--[[ Pose d'une cible à l'instant `t` (interpolée), ou la plus proche disponible. ]]
function LagCompensationService.poseAt(target: Target, t: number): (CFrame, Types.Stance, number)
	local history = histories[target.id]
	if not history or #history == 0 then
		return target.root.CFrame, target.stance(), target.lean()
	end
	local count = #history
	if t >= history[count].t then
		local last = history[count]
		return last.cframe, last.stance, last.lean
	end
	if t <= history[1].t then
		local first = history[1]
		return first.cframe, first.stance, first.lean
	end
	-- Recherche dichotomique de l'intervalle [i, i+1] qui encadre t.
	local low, high = 1, count
	while high - low > 1 do
		local mid = (low + high) // 2
		if history[mid].t <= t then
			low = mid
		else
			high = mid
		end
	end
	local a, b = history[low], history[high]
	local span = b.t - a.t
	local alpha = if span > 0 then (t - a.t) / span else 0
	local stance: Types.Stance = a.stance
	if alpha >= 0.5 then
		stance = b.stance
	end
	return a.cframe:Lerp(b.cframe, alpha), stance, a.lean + (b.lean - a.lean) * alpha
end

--[[ Borne un temps de tir client à la fenêtre de rembobinage autorisée. ]]
function LagCompensationService.rewindTime(clientShotTime: number): number
	local now = Workspace:GetServerTimeNow()
	return math.clamp(clientShotTime - INTERP_DELAY, now - MAX_REWIND, now)
end

export type TargetHit = {
	target: Target,
	result: Hitbox.HitResult,
}

--[[
	Rayon contre toutes les cibles acceptées par `filter`, chacune dans sa pose
	interpolée à l'instant rembobiné `t` ; garde la touche la plus proche. La tolérance
	de désynchronisation est l'`inflate` des boîtes (pas un second test à l'instant présent).
]]
function LagCompensationService.raycast(
	origin: Vector3,
	direction: Vector3,
	maxDistance: number,
	t: number,
	filter: (Target) -> boolean,
	inflate: number
): TargetHit?
	local best: TargetHit? = nil
	local bestDistance = maxDistance
	for _, target in targets do
		if not filter(target) then
			continue
		end
		local cframe: CFrame, stance: Types.Stance, lean: number = LagCompensationService.poseAt(target, t)
		local hit = Hitbox.raycast(origin, direction, bestDistance, cframe, stance, lean, inflate)
		if hit and hit.distance < bestDistance then
			bestDistance = hit.distance
			best = { target = target, result = hit }
		end
	end
	return best
end

--[[ Échantillons d'une cible sur [from, to] (killcam). ]]
function LagCompensationService.history(id: number, from: number, to: number): { Snapshot }
	local list = {}
	local source: { Snapshot } = histories[id] or {}
	for _, snapshot in source do
		if snapshot.t >= from and snapshot.t <= to then
			table.insert(list, snapshot)
		end
	end
	return list
end

function LagCompensationService.Init() end

function LagCompensationService.Start()
	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for id, target in targets do
			if target.model.Parent == nil then
				LagCompensationService.unregister(id)
			elseif target.alive() then
				record(target, now)
			end
		end
	end)
end

return LagCompensationService
