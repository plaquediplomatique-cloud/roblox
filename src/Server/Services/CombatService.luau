--!strict
--[[
	CombatService — gunplay AUTORITAIRE côté serveur.

	Le client prédit tout (impacts, hitmarkers, recul) pour un ressenti instantané ;
	le serveur décide de tout (munitions, dégâts, morts). Pipeline d'un tir :

	  1. Contexte  : joueur vivant, phase de combat ouverte, pas occupé (pose/désamorçage).
	  2. Arme      : l'arme tirée est l'arme équipée côté serveur ; temps d'équipement écoulé.
	  3. Séquence  : n == compteur attendu (rejeu / saut = désynchro -> resync).
	  4. Munitions : chargeur serveur > 0 ; rechargement en cours = refus (sauf cartouches).
	  5. Cadence   : intervalle client ≥ 90 % du minimum + fenêtre glissante serveur d'1 s.
	  6. Origine   : distance à l'oeil serveur ≤ 3.5 + vitesse × 0.35 studs.
	  7. Spread    : cône déclaré ≥ cône MINIMAL plausible (état observé par le serveur).
	                 Sinon on utilise le minimum (le cheat ne gagne rien) + signalement.
	  8. Visée     : vitesse angulaire implicite > 3500°/s = suspicion (heuristique douce) ;
	                 audit statistique de pré-compensation de dispersion (SpreadAudit).
	  9. Résolution: directions recalculées (graine serveur), raycast monde + hitboxes
	                 rembobinées (LagCompensationService), pénétration matériau/épaisseur.
	 10. Effets    : dégâts, kill, assists, killfeed de l'arène, killcam, retours client.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local Movement = require(Shared.Config.Movement)
local Spread = require(Shared.Combat.Spread)
local SpreadAudit = require(Shared.Combat.SpreadAudit)
local Ballistics = require(Shared.Combat.Ballistics)
local Hitbox = require(Shared.Combat.Hitbox)
local MathUtil = require(Shared.Util.MathUtil)
local Guard = require(Shared.Util.Guard)
local Logger = require(Shared.Util.Logger)
local Net = require(Shared.Net.Net)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local GameEvents = require(script.Parent.Parent.GameEvents)
local DataService = require(script.Parent.DataService)
local ArenaService = require(script.Parent.ArenaService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local CharacterService = require(script.Parent.CharacterService)
local LagCompensationService = require(script.Parent.LagCompensationService)

local log = Logger.new("Combat")

type WeaponDef = Types.WeaponDef
type Target = LagCompensationService.Target

type SlotState = { weaponId: string, mag: number, reserve: number }

type ReloadState = {
	slot: Types.WeaponSlot,
	startedAt: number,
	duration: number,
	shell: boolean,
}

type State = {
	player: Player,
	slots: { [string]: SlotState },
	equipped: Types.WeaponSlot,
	equippedAt: number,
	reload: ReloadState?,
	counter: number,
	seedBase: number,
	lastShotClient: number,
	lastShotWeapon: string,
	recentShots: { number },
	bloom: number,
	held: number,
	meleeReadyAt: number,
	airborneSince: number?,
	streak: number,
}

local HIT_INFLATE = 0.12
local AIM_SNAP_LIMIT = math.rad(3500)
local SLOT_ORDER: { Types.WeaponSlot } = { "Primary", "Secondary", "Melee" }

local CombatService = {}

local states: { [Player]: State } = {}
-- Audit de dispersion par JOUEUR (et non par armement) : les fenêtres de 40 paires de
-- tirs couvrent plusieurs manches.
local audits: { [Player]: SpreadAudit.Audit } = {}
local phaseResolver: (Player) -> boolean = function(_player: Player): boolean
	return false
end
local firstBloodResolver: (Player) -> boolean = function(_player: Player): boolean
	return false
end

local remotes: {
	shotResult: RemoteEvent,
	damageTaken: RemoteEvent,
	kill: RemoteEvent,
	ammoSync: RemoteEvent,
	killcam: RemoteEvent,
	shotVisual: UnreliableRemoteEvent,
}

---------------------------------------------------------------------------------------------
-- Injection (évite les dépendances circulaires avec MatchService)
---------------------------------------------------------------------------------------------

--[[ MatchService fournit "le combat est-il ouvert pour ce joueur ?" (phase Live/Planted). ]]
function CombatService.setPhaseResolver(fn: (Player) -> boolean)
	phaseResolver = fn
end

--[[ MatchService indique si un kill serait le premier de la manche. ]]
function CombatService.setFirstBloodResolver(fn: (Player) -> boolean)
	firstBloodResolver = fn
end

local function combatAllowed(player: Player): boolean
	local kind = ArenaService.get(player)
	if kind == "Training" then
		return true
	elseif kind == "Match" then
		return phaseResolver(player)
	end
	return false
end

---------------------------------------------------------------------------------------------
-- État d'armement
---------------------------------------------------------------------------------------------

local function skinFor(player: Player, weaponId: string): Types.ItemDef
	local data = DataService.getData(player)
	return Cosmetics.resolveSkin(if data then data.Cosmetics.WeaponSkins else {}, weaponId)
end

local function publishEquipped(state: State)
	local character = state.player.Character
	local slot = state.slots[state.equipped]
	if character and slot then
		character:SetAttribute("Weapon", slot.weaponId)
		character:SetAttribute("Skin", skinFor(state.player, slot.weaponId).id)
	end
end

local function sync(state: State)
	local slots: { [string]: Types.SlotAmmo } = {}
	for name, slot in state.slots do
		slots[name] = { w = slot.weaponId, mag = slot.mag, reserve = slot.reserve }
	end
	local packet: Types.AmmoSyncPacket = {
		slots = slots,
		equipped = state.equipped,
		seed = state.seedBase,
		counter = state.counter,
		reloading = state.reload ~= nil,
	}
	remotes.ammoSync:FireClient(state.player, packet)
end

export type Loadout = { Primary: string?, Secondary: string?, Melee: string? }

--[[
	Arme un joueur (spawn de manche, entrée au Training Range).
	`infiniteReserve` : réserve illimitée (Training Range).
]]
function CombatService.arm(player: Player, loadout: Loadout, infiniteReserve: boolean?)
	local slots: { [string]: SlotState } = {}
	for _, slotName in SLOT_ORDER do
		local weaponId = (loadout :: any)[slotName]
		local def = if weaponId then Weapons.get(weaponId) else nil
		if def and def.slot == slotName then
			local reserve = if infiniteReserve then 9999 else def.ammo.reserve
			slots[slotName] = { weaponId = def.id, mag = def.ammo.magazine, reserve = reserve }
		end
	end
	local equipped: Types.WeaponSlot = if slots.Primary
		then "Primary"
		elseif slots.Secondary then "Secondary"
		else "Melee"
	local now = Workspace:GetServerTimeNow()
	local state: State = {
		player = player,
		slots = slots,
		equipped = equipped,
		equippedAt = now,
		reload = nil,
		counter = 1,
		seedBase = Random.new():NextInteger(1, 2 ^ 30),
		lastShotClient = 0,
		lastShotWeapon = "",
		recentShots = {},
		bloom = 0,
		held = 0,
		meleeReadyAt = 0,
		airborneSince = nil,
		streak = 0,
	}
	states[player] = state
	publishEquipped(state)
	sync(state)
end

function CombatService.disarm(player: Player)
	states[player] = nil
	local character = player.Character
	if character then
		character:SetAttribute("Weapon", nil)
		character:SetAttribute("Skin", nil)
	end
	remotes.ammoSync:FireClient(player, nil)
end

function CombatService.isArmed(player: Player): boolean
	return states[player] ~= nil
end

---------------------------------------------------------------------------------------------
-- Rechargement
---------------------------------------------------------------------------------------------

local function shellsInserted(def: WeaponDef, reload: ReloadState, now: number, needed: number): number
	local elapsed = now - reload.startedAt - def.ammo.shellStartTime
	if elapsed <= 0 then
		return 0
	end
	return math.clamp(math.floor(elapsed / def.ammo.shellInsertTime), 0, needed)
end

--[[ Termine ou interrompt un rechargement ; renvoie true si des munitions ont été ajoutées. ]]
local function settleReload(state: State, now: number, interrupted: boolean): boolean
	local reload = state.reload
	if not reload then
		return false
	end
	local slot = state.slots[reload.slot]
	local def = slot and Weapons.get(slot.weaponId)
	if not (slot and def) then
		state.reload = nil
		return false
	end
	local needed = math.min(Weapons.reloadCapacity(def, slot.mag) - slot.mag, slot.reserve)
	local added = 0
	if reload.shell then
		added = shellsInserted(def, reload, now, needed)
	elseif not interrupted and now >= reload.startedAt + reload.duration * 0.92 then
		added = needed
	elseif interrupted then
		added = 0
	else
		return false
	end
	slot.mag += added
	slot.reserve -= added
	state.reload = nil
	return added > 0
end

local function reloadDuration(def: WeaponDef, slot: SlotState): number
	local ammo = def.ammo
	if ammo.reloadStyle == "Shell" then
		local needed = math.min(ammo.magazine - slot.mag, slot.reserve)
		return ammo.shellStartTime + needed * ammo.shellInsertTime + ammo.shellEndTime
	end
	return if slot.mag == 0 then ammo.emptyReloadTime else ammo.reloadTime
end

local function onReload(player: Player, _payload: boolean)
	local state = states[player]
	if not state or state.reload or not CharacterService.isAlive(player) then
		return
	end
	local slot = state.slots[state.equipped]
	local def = slot and Weapons.get(slot.weaponId)
	if not (slot and def) or def.ammo.reloadStyle == "None" then
		return
	end
	if slot.mag >= Weapons.reloadCapacity(def, slot.mag) or slot.reserve <= 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local reload: ReloadState = {
		slot = state.equipped,
		startedAt = now,
		duration = reloadDuration(def, slot),
		shell = def.ammo.reloadStyle == "Shell",
	}
	state.reload = reload
	task.delay(reload.duration, function()
		if states[player] == state and state.reload == reload then
			settleReload(state, Workspace:GetServerTimeNow(), false)
			sync(state)
		end
	end)
end

local function onEquip(player: Player, slotName: Types.WeaponSlot)
	local state = states[player]
	if not state or state.equipped == slotName or not state.slots[slotName] then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if state.reload then
		settleReload(state, now, true)
	end
	state.equipped = slotName
	state.equippedAt = now
	state.held = 0
	publishEquipped(state)
end

---------------------------------------------------------------------------------------------
-- Validation d'un tir
---------------------------------------------------------------------------------------------

local function maxShotsPerSecond(def: WeaponDef): number
	local fire = def.fire
	if fire.mode == "Burst" then
		return fire.burstCount / (fire.burstCount * 60 / fire.burstRpm + fire.burstCooldown)
	end
	local rpm = if fire.spinUp then fire.spinUp.endRpm else fire.rpm
	return rpm / 60
end

local function minimumCone(def: WeaponDef, state: State, packet: Types.FirePacket, now: number): number
	local character, humanoid, root = CharacterService.getCharacter(state.player)
	if not (character and humanoid and root) then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local runSpeed = Movement.runSpeed * def.handling.moveMultiplier
	local adsTrusted = packet.ads and character:GetAttribute("Ads") == true
	local airborne = state.airborneSince ~= nil and now - (state.airborneSince :: number) > 0.25
	local sinceLast = packet.t - state.lastShotClient
	local firstShot = sinceLast >= def.spread.firstShotReset
	local bloom = if firstShot then 0 else Spread.decayBloom(def.spread, state.bloom, sinceLast) * 0.5
	local cone = Spread.cone(def.spread, {
		ads = if adsTrusted then 1 else 0,
		speedRatio = flatSpeed / runSpeed * 0.75,
		airborne = airborne,
		crouched = CharacterService.stanceOf(character) ~= "Stand",
		bloom = bloom,
		firstShot = firstShot,
	})
	return cone * 0.85
end

local function checkAimSnap(player: Player, aim: Vector3, now: number)
	local look = CharacterService.getLook(player)
	if not look then
		return
	end
	local lookDir = MathUtil.directionFromYawPitch(look.yaw, look.pitch)
	local angle = MathUtil.angleBetween(lookDir, aim)
	local dt = math.max(now - look.t, 1 / 30)
	if angle > math.rad(20) and angle / dt > AIM_SNAP_LIMIT then
		AntiCheatService.flag(player, "AimSnap", 1.5)
	end
end

---------------------------------------------------------------------------------------------
-- Résolution
---------------------------------------------------------------------------------------------

local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	for _, target in LagCompensationService.all() do
		table.insert(excluded, target.model)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	params.FilterDescendantsInstances = excluded
	return params
end

local function measureThickness(hit: RaycastResult, direction: Vector3): number
	local probe = 6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { hit.Instance }
	local back = Workspace:Raycast(hit.Position + direction * probe, -direction * probe, params)
	if back then
		return math.max(probe - back.Distance, 0.05)
	end
	return probe
end

local function enemyFilter(shooter: Player): (Target) -> boolean
	local arena = ArenaService.idOf(shooter)
	local character = shooter.Character
	local team = if character then character:GetAttribute("Team") else nil
	return function(target: Target): boolean
		if target.player == shooter or target.arena ~= arena or not target.alive() then
			return false
		end
		if target.kind == "Bot" then
			return true
		end
		local otherTeam = target.team()
		return team == nil or team == "" or otherTeam ~= team
	end
end

type PendingHit = {
	target: Target,
	damage: number,
	zone: Types.HitZone,
	wallbang: boolean,
	position: Vector3,
	distance: number,
	direction: Vector3,
}

local ZONE_PRIORITY: { [string]: number } = { Head = 3, Body = 2, Limb = 1 }

local function sendKillcam(victim: Player, killer: Player, weaponId: string, headshot: boolean)
	local now = Workspace:GetServerTimeNow()
	local function track(player: Player): { Types.KillcamSample }
		local samples: { Types.KillcamSample } = {}
		local poses = LagCompensationService.history(player.UserId, now - 3.2, now)
		local looksList = CharacterService.lookHistory(player, now - 3.4, now)
		local lookIndex = 1
		local step = 0
		for _, snapshot in poses do
			step += 1
			if step % 3 == 0 then
				while lookIndex < #looksList and looksList[lookIndex + 1].t <= snapshot.t do
					lookIndex += 1
				end
				local look = looksList[lookIndex]
				table.insert(samples, {
					t = snapshot.t,
					cf = snapshot.cframe,
					stance = snapshot.stance,
					yaw = if look then look.yaw else 0,
					pitch = if look then look.pitch else 0,
				})
			end
		end
		return samples
	end
	local health, armor = CharacterService.health(killer)
	local packet: Types.KillcamPacket = {
		killer = killer.UserId,
		killerName = killer.DisplayName,
		weapon = weaponId,
		killerTrack = track(killer),
		victimTrack = track(victim),
		killTime = now,
		headshot = headshot,
		killerHealth = health,
		killerArmor = armor,
	}
	remotes.killcam:FireClient(victim, packet)
end

local function handleKill(shooter: Player, state: State?, def: WeaponDef, hit: PendingHit, noscope: boolean)
	local target = hit.target
	local character, humanoid = CharacterService.getCharacter(shooter)
	local arena = ArenaService.idOf(shooter)
	if target.kind == "Bot" then
		GameEvents.TrainingHit:Fire({ player = shooter, headshot = hit.zone == "Head", killed = true })
		return
	end
	local victim = target.player :: Player
	local victimState = states[victim]
	if victimState then
		victimState.streak = 0
	end
	local streak = 0
	if state then
		state.streak += 1
		streak = state.streak
	end
	local firstBlood = firstBloodResolver(shooter)
	local assisters = CharacterService.assisters(victim, shooter)
	GameEvents.Kill:Fire({
		killer = shooter,
		victim = victim,
		victimBotId = nil,
		weaponId = def.id,
		category = def.category,
		slot = def.slot,
		headshot = hit.zone == "Head",
		wallbang = hit.wallbang,
		slide = character ~= nil and CharacterService.stanceOf(character) == "Slide",
		airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air,
		noscope = noscope,
		firstBlood = firstBlood,
		distance = hit.distance,
		arena = arena,
		assisters = assisters,
	})

	local data = DataService.getData(shooter)
	local killEffect = if data then data.Cosmetics.KillEffect else "ke_none"
	local skin = skinFor(shooter, def.id)
	if skin.fx and skin.fx.killEffect then
		killEffect = skin.fx.killEffect
	end
	local assistIds = {}
	for _, assister in assisters do
		table.insert(assistIds, assister.UserId)
	end
	local event: Types.KillEvent = {
		killer = shooter.UserId,
		killerName = shooter.DisplayName,
		victim = victim.UserId,
		victimName = victim.DisplayName,
		weapon = def.id,
		headshot = hit.zone == "Head",
		wallbang = hit.wallbang,
		noscope = noscope,
		firstBlood = firstBlood,
		killerTeam = tostring(if character then character:GetAttribute("Team") else ""),
		victimTeam = target.team(),
		assists = assistIds,
		killEffect = killEffect,
		streak = streak,
	}
	ServerNet.fireList(remotes.kill, ArenaService.playersIn(arena), event)
	sendKillcam(victim, shooter, def.id, hit.zone == "Head")
end

local function applyHits(
	shooter: Player,
	state: State?,
	def: WeaponDef,
	pending: { [number]: PendingHit },
	shot: number,
	noscope: boolean
)
	local reports: { Types.HitReport } = {}
	local arena = ArenaService.idOf(shooter)
	for _, hit in pending do
		local target = hit.target
		local result = target.receive(hit.damage, {
			attacker = shooter,
			weaponId = def.id,
			zone = hit.zone,
			wallbang = hit.wallbang,
			direction = hit.direction,
			distance = hit.distance,
			backstab = false,
		})
		table.insert(reports, {
			victim = target.id,
			zone = hit.zone,
			damage = hit.damage,
			killed = result.killed,
			wallbang = hit.wallbang,
			armorBroken = result.armorLoss > 0 and result.armor <= 0,
			position = hit.position,
		})
		if target.player then
			local packet: Types.DamageTaken = {
				from = (shooter.Character and shooter.Character:GetPivot().Position) or hit.position,
				damage = hit.damage,
				zone = hit.zone,
				health = result.health,
				armor = result.armor,
				attacker = shooter.UserId,
			}
			remotes.damageTaken:FireClient(target.player, packet)
		else
			GameEvents.TrainingHit:Fire({ player = shooter, headshot = hit.zone == "Head", killed = false })
		end
		GameEvents.Damage:Fire({
			attacker = shooter,
			victim = target.player,
			victimBotId = if target.kind == "Bot" then target.id else nil,
			amount = result.healthLoss + result.armorLoss,
			zone = hit.zone,
			weaponId = def.id,
			arena = arena,
		})
		if result.killed then
			handleKill(shooter, state, def, hit, noscope)
		end
	end
	local packet: Types.ShotResult = { n = shot, w = def.id, hits = reports }
	remotes.shotResult:FireClient(shooter, packet)
end

local function resolveShot(
	shooter: Player,
	state: State,
	def: WeaponDef,
	packet: Types.FirePacket,
	directions: { Vector3 }
)
	local rewind = LagCompensationService.rewindTime(packet.t)
	local params = worldParams()
	local filter = enemyFilter(shooter)
	local pending: { [number]: PendingHit } = {}
	local endpoints: { Vector3 } = {}

	for _, direction in directions do
		local origin = packet.o
		local remaining = def.damage.range
		local budget = def.damage.penetration
		local multiplier = 1
		local wallbang = false
		local travelled = 0
		local endpoint = origin + direction * remaining
		for pass = 0, Ballistics.MAX_PENETRATIONS do
			local world = Workspace:Raycast(origin, direction * remaining, params)
			local worldDistance = if world then world.Distance else remaining
			local hit = LagCompensationService.raycast(origin, direction, worldDistance, rewind, filter, HIT_INFLATE)
			if hit then
				local distance = travelled + hit.result.distance
				local damage = Ballistics.damage(def.damage, hit.result.zone, distance, multiplier)
				local existing = pending[hit.target.id]
				if existing then
					existing.damage += damage
					existing.wallbang = existing.wallbang or wallbang
					if ZONE_PRIORITY[hit.result.zone] > ZONE_PRIORITY[existing.zone] then
						existing.zone = hit.result.zone
						existing.position = hit.result.position
					end
				else
					pending[hit.target.id] = {
						target = hit.target,
						damage = damage,
						zone = hit.result.zone,
						wallbang = wallbang,
						position = hit.result.position,
						distance = distance,
						direction = direction,
					}
				end
				endpoint = hit.result.position
				break
			end
			if not world then
				break
			end
			endpoint = world.Position
			if pass == Ballistics.MAX_PENETRATIONS then
				break
			end
			local thickness = measureThickness(world, direction)
			local impenetrable = world.Instance:GetAttribute("Impenetrable") == true
			local factor, left = Ballistics.penetrate(budget, thickness, world.Material, impenetrable)
			if factor == nil then
				break
			end
			multiplier *= factor
			budget = left
			wallbang = true
			travelled += worldDistance + thickness
			origin = world.Position + direction * (thickness + 0.05)
			remaining -= worldDistance + thickness
			if remaining <= 1 then
				break
			end
		end
		table.insert(endpoints, endpoint)
	end

	local noscope = def.handling.scopeOverlay and not packet.ads
	applyHits(shooter, state, def, pending, packet.n, noscope)

	-- Visuels pour les autres joueurs de l'arène (non fiable : seul le présent compte)
	local slot = shooter:GetAttribute("NetSlot")
	if type(slot) == "number" then
		local visual: Types.ShotVisualPacket = { s = slot, w = def.id, o = packet.o, e = endpoints }
		for _, other in ArenaService.playersIn(ArenaService.idOf(shooter)) do
			if other ~= shooter then
				remotes.shotVisual:FireClient(other, visual)
			end
		end
	end
	GameEvents.ShotFired:Fire(shooter, def.id, #directions)
end

local isFire = Guard.shape({
	w = Guard.string(16),
	n = Guard.integer(1, 2 ^ 31),
	o = Guard.vector3(1e5),
	a = Guard.unitVector(0.02),
	s = Guard.range(0, 45),
	t = Guard.number,
	ads = Guard.boolean,
})

local function parseFire(packet: any): Types.FirePacket?
	return if isFire(packet) then packet :: Types.FirePacket else nil
end

local function onFire(player: Player, packet: Types.FirePacket)
	local state = states[player]
	if not state or not CharacterService.isAlive(player) or not combatAllowed(player) then
		return
	end
	local character = player.Character
	if character and character:GetAttribute("Busy") == true then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local slot = state.slots[state.equipped]
	local def = Weapons.get(packet.w)
	if not (slot and def) or slot.weaponId ~= packet.w or def.category == "Melee" then
		sync(state)
		return
	end
	if packet.n ~= state.counter then
		if packet.n < state.counter then
			AntiCheatService.flag(player, "ShotReplay", 2)
		end
		sync(state)
		return
	end
	if now - state.equippedAt < def.handling.equipTime * 0.7 then
		AntiCheatService.flag(player, "FastEquip", 1)
		sync(state)
		return
	end
	if state.reload then
		if state.reload.shell then
			settleReload(state, now, true)
		elseif not settleReload(state, now, false) then
			sync(state)
			return
		end
	end
	if slot.mag <= 0 then
		sync(state)
		return
	end
	if math.abs(packet.t - now) > 1.0 then
		AntiCheatService.flag(player, "ShotClock", 1)
		sync(state)
		return
	end
	-- Cadence : entre deux tirs de la MÊME arme (un changement d'arme est déjà borné par
	-- le temps d'équipement ; sinon SMG -> sniper serait refusé à tort).
	local interval = packet.t - state.lastShotClient
	if state.lastShotWeapon == def.id and interval < Weapons.minInterval(def) * 0.9 then
		AntiCheatService.flag(player, "FireRate", 2)
		sync(state)
		return
	end
	local recent = state.recentShots
	while #recent > 0 and now - recent[1] > 1 do
		table.remove(recent, 1)
	end
	if #recent >= math.ceil(maxShotsPerSecond(def)) + 2 then
		AntiCheatService.flag(player, "FireRateWindow", 3)
		sync(state)
		return
	end
	local eye = CharacterService.eyePosition(player)
	local _, _, root = CharacterService.getCharacter(player)
	if not (eye and root) then
		return
	end
	local tolerance = 3.5 + root.AssemblyLinearVelocity.Magnitude * 0.35
	if (packet.o - eye).Magnitude > tolerance then
		AntiCheatService.flag(player, "ShotOrigin", 3)
		sync(state)
		return
	end

	local minCone = minimumCone(def, state, packet, now)
	if packet.s < minCone - 0.05 then
		AntiCheatService.flag(player, "NoSpread", 1.5)
	end
	local cone = math.max(packet.s, minCone)
	checkAimSnap(player, packet.a, now)

	-- Le tir est accepté : on le "consomme".
	slot.mag -= 1
	state.counter += 1
	if def.fire.spinUp and interval < (60 / def.fire.spinUp.startRpm) * 1.6 then
		state.held += interval
	else
		state.held = 0
	end
	state.bloom = Spread.bloomAfterShot(def.spread, state.bloom, interval)
	state.lastShotClient = packet.t
	state.lastShotWeapon = def.id
	table.insert(recent, now)

	local seed = Spread.seed(state.seedBase, packet.n)
	local directions = Spread.directions(packet.a, cone, seed, def.damage.pellets, def.spread.pelletCone)
	local audit = audits[player]
	if not audit then
		audit = SpreadAudit.new()
		audits[player] = audit
	end
	local correlation = SpreadAudit.observe(audit, def.id, packet.t, packet.a, cone, SpreadAudit.offset(cone, seed))
	if correlation and correlation <= SpreadAudit.FLAG_CORRELATION then
		AntiCheatService.flag(player, "SpreadCompensation", 4)
	end
	resolveShot(player, state, def, packet, directions)
end

---------------------------------------------------------------------------------------------
-- Mêlée
---------------------------------------------------------------------------------------------

local isMelee = Guard.shape({ heavy = Guard.boolean, a = Guard.unitVector(0.02), t = Guard.number })

local function onMelee(player: Player, packet: Types.MeleePacket)
	local state = states[player]
	if not state or not CharacterService.isAlive(player) or not combatAllowed(player) then
		return
	end
	local slot = state.slots[state.equipped]
	local def = slot and Weapons.get(slot.weaponId)
	local melee = def and def.melee
	if not (def and melee) then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < state.meleeReadyAt then
		return
	end
	state.meleeReadyAt = now + (if packet.heavy then melee.heavyCooldown else melee.lightCooldown) * 0.85
	local eye = CharacterService.eyePosition(player)
	if not eye then
		return
	end
	local rewind = LagCompensationService.rewindTime(packet.t)
	local filter = enemyFilter(player)
	local params = worldParams()
	local best: Target? = nil
	local bestCenter = Vector3.zero
	local bestDistance = melee.range + 1.5
	for _, target in LagCompensationService.all() do
		if filter(target) then
			local cframe: CFrame, stance: Types.Stance = LagCompensationService.poseAt(target, rewind)
			local center = Hitbox.centerOf(cframe, stance)
			local offset = center - eye
			local distance = offset.Magnitude
			if
				distance < bestDistance
				and math.deg(MathUtil.angleBetween(packet.a, offset)) <= melee.coneDegrees + 10
			then
				if Workspace:Raycast(eye, offset, params) == nil then
					best = target
					bestCenter = center
					bestDistance = distance
				end
			end
		end
	end
	if not best then
		return
	end
	local attackDir = (bestCenter - eye).Unit
	local facing: Vector3
	if best.player then
		local look = CharacterService.getLook(best.player)
		facing = if look then MathUtil.directionFromYawPitch(look.yaw, 0) else best.root.CFrame.LookVector
	else
		facing = best.root.CFrame.LookVector
	end
	local backstab = packet.heavy
		and MathUtil.flat(facing).Unit:Dot(MathUtil.flat(attackDir).Unit) > math.cos(math.rad(70))
	local damage = if backstab
		then melee.backstabDamage
		elseif packet.heavy then melee.heavyDamage
		else melee.lightDamage
	local pending: { [number]: PendingHit } = {
		[best.id] = {
			target = best,
			damage = damage,
			zone = "Body",
			wallbang = false,
			position = bestCenter,
			distance = bestDistance,
			direction = attackDir,
		},
	}
	applyHits(player, state, def :: WeaponDef, pending, 0, false)
end

---------------------------------------------------------------------------------------------
-- Cycle de vie
---------------------------------------------------------------------------------------------

function CombatService.Init()
	remotes = {
		shotResult = Net.event("ShotResult"),
		damageTaken = Net.event("DamageTaken"),
		kill = Net.event("Kill"),
		ammoSync = Net.event("AmmoSync"),
		killcam = Net.event("Killcam"),
		shotVisual = Net.unreliable("ShotVisual"),
	}
end

function CombatService.Start()
	ServerNet.onEvent("Fire", { capacity = 24, refill = 20 }, parseFire, onFire)
	ServerNet.onEvent("Melee", { capacity = 6, refill = 4 }, function(packet: any): Types.MeleePacket?
		return if isMelee(packet) then packet :: Types.MeleePacket else nil
	end, onMelee)
	ServerNet.onEvent("Reload", { capacity = 4, refill = 2 }, function(...: any): boolean?
		return true
	end, onReload)
	ServerNet.onEvent("Equip", { capacity = 10, refill = 6 }, function(slot: any): Types.WeaponSlot?
		return if slot == "Primary" or slot == "Secondary" or slot == "Melee" then slot else nil
	end, onEquip)

	CharacterService.Died:Connect(function(player: Player)
		states[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		audits[player] = nil
	end)

	-- Suivi "en l'air" pour le cône minimal (évite de faire confiance au client).
	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for player, state in states do
			local _, humanoid = CharacterService.getCharacter(player)
			if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
				state.airborneSince = state.airborneSince or now
			else
				state.airborneSince = nil
			end
		end
	end)
	log:debug("combat ready")
end

return CombatService
