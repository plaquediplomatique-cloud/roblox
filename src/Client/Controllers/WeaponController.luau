--!strict
--[[
	WeaponController — gunplay client : PRÉDICTION totale, AUTORITÉ serveur.

	Ce que le joueur ressent tout de suite (0 ms) :
	  tir, son, flash, recul, douille, traceur, impact au mur, impact sur la cible prédite.
	Ce qui attend la confirmation serveur (≈ ping) :
	  hitmarker, chiffres de dégâts, son de kill — jamais de "faux hitmarker".

	Contrat avec CombatService (voir Server/Services/CombatService) :
	  * AmmoSync fixe l'état de référence : chargeurs, réserve, graine, compteur de tirs.
	  * Chaque tir envoie {w, n, o, a, s, t, ads}. Le client calcule EXACTEMENT les mêmes
	    directions que le serveur (Spread.directions + Spread.seed(graine, n)) : la balle
	    prédite et la balle serveur sont la même balle.
	  * t = horloge serveur du tir planifié (pas de la frame) : deux tirs rattrapés dans
	    la même frame gardent leur intervalle réel (le serveur vérifie la cadence).
	  * Le cône `s` est la formule partagée (Spread.cone) — le serveur impose un minimum.

	Recul : pattern fixe (apprenable) + aléa léger, multiplicateurs ADS/accroupi,
	récupération "intelligente" : le retour automatique ne rend que la part de dérive que
	le joueur n'a PAS déjà compensée à la souris (pas de sur-correction vers le sol).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local Spread = require(Shared.Combat.Spread)
local Hitbox = require(Shared.Combat.Hitbox)
local Ballistics = require(Shared.Combat.Ballistics)
local MathUtil = require(Shared.Util.MathUtil)
local Signal = require(Shared.Util.Signal)
local Net = require(Shared.Net.Net)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Animator = require(script.Parent.Parent.Weapons.Animator)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local CameraController = require(script.Parent.CameraController)
local MovementController = require(script.Parent.MovementController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local EffectsController = require(script.Parent.EffectsController)
local AudioController = require(script.Parent.AudioController)

type WeaponDef = Types.WeaponDef
type WeaponSlot = Types.WeaponSlot

export type HudState = {
	def: WeaponDef?,
	slot: WeaponSlot?,
	mag: number,
	reserve: number,
	capacity: number,
	reloading: boolean,
	reloadProgress: number,
	ads: number,
	scoped: boolean,
	cone: number,
	ready: boolean,
}

local WeaponController = {
	Changed = Signal.new() :: Signal.Signal<>,
	Fired = Signal.new() :: Signal.Signal<WeaponDef>,
	HitConfirmed = Signal.new() :: Signal.Signal<Types.HitReport, WeaponDef?>,
	Equipped = Signal.new() :: Signal.Signal<WeaponDef>,
	Disarmed = Signal.new() :: Signal.Signal<>,
	DryFire = Signal.new() :: Signal.Signal<>,
}

local SLOT_ORDER: { WeaponSlot } = { "Primary", "Secondary", "Melee" }
local MAX_SHOTS_PER_FRAME = 3
local SEMI_BUFFER = 0.12 -- un clic légèrement trop tôt est mémorisé, pas perdu

local player = Players.LocalPlayer

type Reload = {
	slot: WeaponSlot,
	startedAt: number,
	duration: number,
	shell: boolean,
	inserted: number,
	needed: number,
}

type Target = {
	model: Model,
	root: BasePart,
	stance: Types.Stance,
	lean: number,
	armor: number,
}

-- État de référence (AmmoSync) + prédiction
local armed = false
local lastSyncAt = -math.huge
local slots: { [string]: Types.SlotAmmo } = {}
local equippedSlot: WeaponSlot = "Primary"
local current: WeaponDef? = nil
local seedBase = 0
local counter = 1
local equippedOnce: { [string]: boolean } = {}

-- Cadence
local readyAt = 0
local nextShotAt = 0
local lastShotClock = -math.huge
local lastShotServer = -math.huge
local lastShotWeapon = ""
local bloom = 0
local heldTime = 0
local burstRemaining = 0
local burstReadyAt = 0
local semiQueuedAt: number? = nil
local cycleUntil = 0
local meleeReadyAt = 0
local dryClicked = false

-- Visée
local adsWanted = false
local adsToggled = false
local adsAlpha = 0

-- Rechargement
local reload: Reload? = nil

-- Recul
local sprayIndex = 0
local recoveryPool = Vector2.zero

local rng = Random.new()
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Include
local thicknessParams = RaycastParams.new()
thicknessParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------------------------------------
-- Contexte
---------------------------------------------------------------------------------------------

local function geometryRoots(): { Instance }
	local roots: { Instance } = {}
	for _, name in { "Arenas", "Hub" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(roots, folder)
		end
	end
	return roots
end

local function slotAmmo(): Types.SlotAmmo?
	return slots[equippedSlot]
end

local function combatOpen(): boolean
	local kind = ClientState.arena()
	if kind == "Training" then
		return true
	elseif kind == "Match" then
		local data = ClientState.matchData()
		return data ~= nil and (data.phase == "Live" or data.phase == "Planted")
	end
	return false
end

local function isBusy(): boolean
	local character = MovementController.character()
	return character ~= nil and character:GetAttribute("Busy") == true
end

local function isAlive(): boolean
	local _, humanoid = MovementController.character()
	return humanoid ~= nil and humanoid.Health > 0
end

local function skinFor(weaponId: string): Types.ItemDef
	local data = ClientState.profileData()
	return Cosmetics.resolveSkin(if data then data.Cosmetics.WeaponSkins else {}, weaponId)
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function reloadProgress(): number
	local active = reload
	if not active then
		return 0
	end
	return math.clamp((os.clock() - active.startedAt) / math.max(active.duration, 0.01), 0, 1)
end

---------------------------------------------------------------------------------------------
-- Visée (ADS)
---------------------------------------------------------------------------------------------

local function canAim(def: WeaponDef, now: number): boolean
	-- Seul le verrou (sniper) fait perdre la lunette pendant le réarmement ; la pompe non.
	return def.category ~= "Melee"
		and reload == nil
		and now >= readyAt
		and (now >= cycleUntil or def.fire.mode ~= "Bolt")
		and not isBusy()
end

local function updateAds(dt: number, now: number)
	local def = current
	local wanted = false
	if def and armed then
		local held = if SettingsController.get().Controls.ToggleAds then adsToggled else InputController.isDown("Aim")
		if held and ViewmodelController.isPlaying("Inspect") then
			ViewmodelController.stop()
		end
		wanted = held and canAim(def, now)
	end
	if wanted ~= adsWanted then
		adsWanted = wanted
		if def then
			MovementController.setWeaponModifiers(def.handling.moveMultiplier, def.handling.adsMoveMultiplier, wanted)
		end
	end
	local adsTime = if def then def.handling.adsTime else 0.2
	local step = dt / math.max(adsTime, 0.05)
	adsAlpha = if wanted then math.min(1, adsAlpha + step) else math.max(0, adsAlpha - step * 1.25)
	ViewmodelController.setAds(adsAlpha)
	local zoom = if def then def.handling.zoom else 1
	local eased = adsAlpha * adsAlpha * (3 - 2 * adsAlpha)
	CameraController.setZoom(MathUtil.lerp(1, zoom, eased), 1)
end

---------------------------------------------------------------------------------------------
-- Prédiction de touche (mêmes hitboxes que le serveur)
---------------------------------------------------------------------------------------------

local function stanceOf(model: Model): Types.Stance
	local value = model:GetAttribute("Stance")
	if value == "Crouch" then
		return "Crouch"
	elseif value == "Slide" then
		return "Slide"
	end
	return "Stand"
end

local function gatherTargets(): { Target }
	local targets: { Target } = {}
	local mine = player.Character
	local myTeam = if mine then mine:GetAttribute("Team") else nil
	local myKind = ClientState.arena()
	for _, tag in { "Combatant", "TrainingBot" } do
		if tag == "TrainingBot" and myKind ~= "Training" then
			continue
		end
		for _, instance in CollectionService:GetTagged(tag) do
			if not instance:IsA("Model") or instance == mine or instance:GetAttribute("Alive") ~= true then
				continue
			end
			if tag == "Combatant" then
				if instance:GetAttribute("ArenaKind") ~= myKind then
					continue
				end
				local team = instance:GetAttribute("Team")
				if type(myTeam) == "string" and myTeam ~= "" and team == myTeam then
					continue
				end
			end
			local root = instance:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local lean = instance:GetAttribute("Lean")
				local armor = instance:GetAttribute("Armor")
				table.insert(targets, {
					model = instance,
					root = root,
					stance = stanceOf(instance),
					lean = if type(lean) == "number" then lean else 0,
					armor = if type(armor) == "number" then armor else 0,
				})
			end
		end
	end
	return targets
end

local function nearestTarget(
	origin: Vector3,
	direction: Vector3,
	maxDistance: number,
	targets: { Target }
): (Target?, Hitbox.HitResult?)
	local best: Target? = nil
	local bestResult: Hitbox.HitResult? = nil
	local bestDistance = maxDistance
	for _, target in targets do
		local result =
			Hitbox.raycast(origin, direction, bestDistance, target.root.CFrame, target.stance, target.lean, 0)
		if result and result.distance < bestDistance then
			best = target
			bestResult = result
			bestDistance = result.distance
		end
	end
	return best, bestResult
end

type WorldImpact = { position: Vector3, normal: Vector3, material: Enum.Material }

type TraceResult = {
	endpoint: Vector3,
	target: Target?,
	zone: Types.HitZone?,
	wallbang: boolean,
	impacts: { WorldImpact },
}

local function thicknessAt(hit: RaycastResult, direction: Vector3): (number, RaycastResult?)
	local probe = 6
	thicknessParams.FilterDescendantsInstances = { hit.Instance }
	local back = Workspace:Raycast(hit.Position + direction * probe, -direction * probe, thicknessParams)
	if back then
		return math.max(probe - back.Distance, 0.05), back
	end
	return probe, nil
end

--[[ Trajectoire complète d'une balle, pénétration comprise (miroir de CombatService). ]]
local function trace(def: WeaponDef, start: Vector3, direction: Vector3, targets: { Target }): TraceResult
	local origin = start
	local remaining = def.damage.range
	local budget = def.damage.penetration
	local wallbang = false
	local impacts: { WorldImpact } = {}
	local endpoint = origin + direction * remaining
	for pass = 0, Ballistics.MAX_PENETRATIONS do
		local world = Workspace:Raycast(origin, direction * remaining, worldParams)
		local worldDistance = if world then world.Distance else remaining
		local target, result = nearestTarget(origin, direction, worldDistance, targets)
		if target and result then
			return {
				endpoint = result.position,
				target = target,
				zone = result.zone,
				wallbang = wallbang,
				impacts = impacts,
			}
		end
		if not world then
			break
		end
		endpoint = world.Position
		table.insert(impacts, { position = world.Position, normal = world.Normal, material = world.Material })
		if pass == Ballistics.MAX_PENETRATIONS then
			break
		end
		local thickness, exit = thicknessAt(world, direction)
		local impenetrable = world.Instance:GetAttribute("Impenetrable") == true
		local factor, left = Ballistics.penetrate(budget, thickness, world.Material, impenetrable)
		if factor == nil then
			break
		end
		if exit then
			table.insert(impacts, { position = exit.Position, normal = exit.Normal, material = exit.Material })
		end
		budget = left
		wallbang = true
		origin = world.Position + direction * (thickness + 0.05)
		remaining -= worldDistance + thickness
		if remaining <= 1 then
			break
		end
	end
	return { endpoint = endpoint, target = nil, zone = nil, wallbang = wallbang, impacts = impacts }
end

---------------------------------------------------------------------------------------------
-- Recul
---------------------------------------------------------------------------------------------

local function applyRecoil(def: WeaponDef)
	local recoil = def.recoil
	local pattern = recoil.pattern
	local count = #pattern
	local index = math.floor(sprayIndex) + 1
	if index > count then
		local loopLength = count - recoil.loopFrom + 1
		index = recoil.loopFrom + ((index - recoil.loopFrom) % math.max(loopLength, 1))
	end
	local kick = if count > 0 then pattern[math.clamp(index, 1, count)] else Vector2.zero
	sprayIndex += 1

	local multiplier = MathUtil.lerp(1, recoil.adsMultiplier, adsAlpha)
	if MovementController.stance() ~= "Stand" then
		multiplier *= recoil.crouchMultiplier
	end
	local yaw = (kick.X + rng:NextNumber(-recoil.randomYaw, recoil.randomYaw)) * multiplier
	local pitch = (kick.Y + rng:NextNumber(-recoil.randomPitch, recoil.randomPitch)) * multiplier
	CameraController.addRecoil(yaw, pitch)
	recoveryPool += Vector2.new(yaw, pitch) * recoil.recoveryRatio

	-- Cosmétique (n'affecte pas la visée) : punch, roulis, shake.
	local side = if yaw >= 0 then 1 else -1
	local visual = MathUtil.lerp(1, 0.45, adsAlpha)
	CameraController.punch(
		Vector3.new(recoil.punch * 1.4, -side * recoil.punch * 0.3, side * recoil.punchRoll * 1.2) * visual
	)
	CameraController.shake(recoil.shake * MathUtil.lerp(1, 0.4, adsAlpha))
	if def.category == "Sniper" or def.category == "Shotgun" then
		CameraController.fovPop(-1.2)
	end
end

local function recover(def: WeaponDef, dt: number, now: number)
	-- Compensation du joueur : elle "consomme" la dérive à récupérer.
	local yawInput, pitchInput = CameraController.lastInput()
	local pool = recoveryPool
	if pool.Magnitude > 1e-4 then
		local inputPitch = math.deg(pitchInput) -- négatif = vers le bas
		local inputYaw = -math.deg(yawInput) -- positif = vers la droite
		local y = pool.Y
		if y > 0 and inputPitch < 0 then
			y = math.max(0, y + inputPitch)
		end
		local x = pool.X
		if x > 0 and inputYaw < 0 then
			x = math.max(0, x + inputYaw)
		elseif x < 0 and inputYaw > 0 then
			x = math.min(0, x + inputYaw)
		end
		pool = Vector2.new(x, y)
	end
	local recoil = def.recoil
	local idle = now - lastShotClock
	if idle > recoil.recoveryDelay then
		local magnitude = pool.Magnitude
		if magnitude > 1e-4 then
			local step = math.min(magnitude, recoil.recoverySpeed * dt)
			local delta = pool.Unit * step
			CameraController.addRecoil(-delta.X, -delta.Y)
			pool -= delta
		end
		-- Le pattern "redescend" : un tir après une pause repart plus bas dans le motif.
		local shotsPerSecond = Weapons.currentRpm(def, 0) / 60
		sprayIndex = math.max(0, sprayIndex - dt * shotsPerSecond * 1.6)
	end
	recoveryPool = pool
end

---------------------------------------------------------------------------------------------
-- Tir
---------------------------------------------------------------------------------------------

local function muzzleOrigin(fallback: Vector3, direction: Vector3): Vector3
	if ViewmodelController.isScoped() then
		return fallback + direction * 1.5 + Vector3.new(0, -0.35, 0)
	end
	local muzzle = ViewmodelController.attachment("Muzzle")
	return if muzzle then muzzle.WorldPosition else fallback
end

local startReloadDeferred: () -> ()

local function fireOnce(def: WeaponDef, scheduledAt: number, frameClock: number, frameServer: number)
	local ammo = slotAmmo()
	if not ammo then
		return
	end
	-- Horloge serveur du tir PLANIFIÉ, jamais plus rapprochée du tir précédent que la
	-- cadence (la synchro d'horloge peut "sauter" de quelques ms entre deux frames).
	local shotServerTime = frameServer - (frameClock - scheduledAt)
	if lastShotWeapon == def.id then
		shotServerTime = math.max(shotServerTime, lastShotServer + Weapons.minInterval(def) * 0.97)
	end
	local origin, aim = CameraController.getAim()
	local cone = Spread.cone(def.spread, {
		ads = adsAlpha,
		speedRatio = MovementController.speedRatio(),
		airborne = MovementController.isAirborne(),
		crouched = MovementController.stance() ~= "Stand",
		bloom = Spread.decayBloom(def.spread, bloom, shotServerTime - lastShotServer),
		firstShot = shotServerTime - lastShotServer >= def.spread.firstShotReset,
	})
	local shot = counter
	local packet: Types.FirePacket = {
		w = def.id,
		n = shot,
		o = origin,
		a = aim,
		s = cone,
		t = shotServerTime,
		ads = adsAlpha >= 0.75,
	}
	Net.event("Fire"):FireServer(packet)

	-- État prédit (le serveur fait exactement la même comptabilité).
	counter += 1
	ammo.mag -= 1
	bloom = Spread.bloomAfterShot(def.spread, bloom, shotServerTime - lastShotServer)
	lastShotServer = shotServerTime
	lastShotWeapon = def.id
	lastShotClock = scheduledAt

	-- Balles prédites : mêmes directions que le serveur.
	local directions =
		Spread.directions(aim, cone, Spread.seed(seedBase, shot), def.damage.pellets, def.spread.pelletCone)
	worldParams.FilterDescendantsInstances = geometryRoots()
	local targets = gatherTargets()
	local startVisual = muzzleOrigin(origin, aim)
	local tracerProfile = def.tracer
	local skin = skinFor(def.id)
	local tracerColor = (skin.fx and skin.fx.tracerColor) or tracerProfile.color
	local impactSounds = 0
	for index, direction in directions do
		local result = trace(def, origin, direction, targets)
		for _, impact in result.impacts do
			EffectsController.impact(impact.position, impact.normal, impact.material, "World")
			if impactSounds < 2 then
				impactSounds += 1
				AudioController.impact(impact.material, impact.position, false)
			end
		end
		local target = result.target
		if target then
			EffectsController.impact(
				result.endpoint,
				-direction,
				Enum.Material.Plastic,
				if target.armor > 0 then "Armor" else "Character"
			)
		end
		local everyShot = tracerProfile.every <= 1 or shot % tracerProfile.every == 0
		if everyShot and (index == 1 or def.damage.pellets <= 4 or index % 2 == 0) then
			EffectsController.tracer(
				startVisual,
				result.endpoint,
				tracerColor,
				tracerProfile.width,
				tracerProfile.speed,
				tracerProfile.length
			)
		end
	end

	AudioController.weaponShot(def, startVisual, true)
	ViewmodelController.onShot(def, MovementController.stance() ~= "Stand")
	applyRecoil(def)
	local low = math.max(3, math.floor(def.ammo.magazine * 0.2))
	if ammo.mag > 0 and ammo.mag <= low then
		AudioController.play("Weapon.Dry", { volume = 0.25, pitch = 1.5 })
	end
	ViewmodelController.setEmpty(ammo.mag <= 0)
	WeaponController.Fired:Fire(def)
	WeaponController.Changed:Fire()
	if ammo.mag <= 0 and ammo.reserve > 0 and SettingsController.get().Controls.AutoReload then
		task.delay(0.22, function()
			if current == def and reload == nil and not InputController.isDown("Fire") then
				startReloadDeferred()
			end
		end)
	end

	-- Culasse / pompe : cycle animé, la lunette se baisse pendant le réarmement.
	local mode = def.fire.mode
	if mode == "Bolt" or mode == "Pump" then
		local interval = 60 / def.fire.rpm
		cycleUntil = scheduledAt + interval
		if ammo.mag > 0 then
			ViewmodelController.play(Animator.cycle(def, interval * 0.85))
		end
	end
end

local function startReload(force: boolean?)
	local def = current
	local ammo = slotAmmo()
	if not (def and ammo and armed) or reload ~= nil or def.ammo.reloadStyle == "None" then
		return
	end
	local capacity = Weapons.reloadCapacity(def, ammo.mag)
	if ammo.mag >= capacity or ammo.reserve <= 0 or isBusy() then
		return
	end
	local now = os.clock()
	if not force and now < readyAt then
		return
	end
	Net.event("Reload"):FireServer(true)
	burstRemaining = 0
	semiQueuedAt = nil
	local needed = math.min(capacity - ammo.mag, ammo.reserve)
	if def.ammo.reloadStyle == "Shell" then
		local duration = def.ammo.shellStartTime + needed * def.ammo.shellInsertTime + def.ammo.shellEndTime
		local active: Reload = {
			slot = equippedSlot,
			startedAt = now,
			duration = duration,
			shell = true,
			inserted = 0,
			needed = needed,
		}
		reload = active
		local function insertNext()
			if reload ~= active then
				return
			end
			if active.inserted >= active.needed then
				ViewmodelController.play(Animator.shellEnd(def), nil, function()
					if reload == active then
						reload = nil
						WeaponController.Changed:Fire()
					end
				end)
				return
			end
			ViewmodelController.play(Animator.shellInsert(def), nil, function()
				if reload ~= active then
					return
				end
				local slot = slots[active.slot]
				if slot and slot.reserve > 0 then
					slot.mag += 1
					slot.reserve -= 1
					active.inserted += 1
					ViewmodelController.setEmpty(false)
					WeaponController.Changed:Fire()
				end
				insertNext()
			end)
		end
		ViewmodelController.play(Animator.shellStart(def), nil, insertNext)
	else
		local empty = ammo.mag == 0
		local duration = if empty then def.ammo.emptyReloadTime else def.ammo.reloadTime
		local active: Reload = {
			slot = equippedSlot,
			startedAt = now,
			duration = duration,
			shell = false,
			inserted = 0,
			needed = needed,
		}
		reload = active
		ViewmodelController.play(Animator.reload(def, empty, duration), nil, function()
			if reload ~= active then
				return
			end
			reload = nil
			local slot = slots[active.slot]
			if slot then
				local add = math.min(Weapons.reloadCapacity(def, slot.mag) - slot.mag, slot.reserve)
				slot.mag += add
				slot.reserve -= add
			end
			ViewmodelController.setEmpty(false)
			WeaponController.Changed:Fire()
		end)
	end
	WeaponController.Changed:Fire()
end

startReloadDeferred = function()
	startReload()
end

local function cancelReload()
	if reload then
		reload = nil
		ViewmodelController.stop()
	end
end

---------------------------------------------------------------------------------------------
-- Équipement
---------------------------------------------------------------------------------------------

local function equip(slot: WeaponSlot, fromServer: boolean?)
	local ammo = slots[slot]
	local def = if ammo then Weapons.get(ammo.w) else nil
	if not (ammo and def) then
		return
	end
	if current == def and equippedSlot == slot and not fromServer then
		return
	end
	cancelReload()
	if not fromServer then
		Net.event("Equip"):FireServer(slot)
	end
	equippedSlot = slot
	current = def
	local first = not equippedOnce[def.id]
	equippedOnce[def.id] = true
	local now = os.clock()
	readyAt = now + def.handling.equipTime
	nextShotAt = readyAt
	cycleUntil = 0
	burstRemaining = 0
	semiQueuedAt = nil
	heldTime = 0
	sprayIndex = 0
	recoveryPool = Vector2.zero
	adsToggled = false
	ViewmodelController.equip(def, skinFor(def.id), def.handling.equipTime, first)
	ViewmodelController.setEmpty(ammo.mag <= 0)
	MovementController.setWeaponModifiers(def.handling.moveMultiplier, def.handling.adsMoveMultiplier, false)
	adsWanted = false
	WeaponController.Equipped:Fire(def)
	WeaponController.Changed:Fire()
end

local function cycleSlot(direction: number)
	local index = table.find(SLOT_ORDER, equippedSlot) or 1
	for step = 1, #SLOT_ORDER do
		local candidate: WeaponSlot = SLOT_ORDER[((index - 1 + direction * step) % #SLOT_ORDER) + 1]
		if slots[candidate] then
			equip(candidate)
			return
		end
	end
end

local function disarmLocal()
	armed = false
	current = nil
	reload = nil
	slots = {}
	adsWanted = false
	adsToggled = false
	adsAlpha = 0
	burstRemaining = 0
	semiQueuedAt = nil
	table.clear(equippedOnce)
	ViewmodelController.clear()
	ViewmodelController.setAds(0)
	CameraController.setZoom(1, 1)
	MovementController.setWeaponModifiers(1, 1, false)
	WeaponController.Disarmed:Fire()
	WeaponController.Changed:Fire()
end

---------------------------------------------------------------------------------------------
-- Mêlée
---------------------------------------------------------------------------------------------

local function melee(def: WeaponDef, heavy: boolean)
	local profile = def.melee
	local now = os.clock()
	if not profile or now < meleeReadyAt or now < readyAt or isBusy() or not combatOpen() then
		return
	end
	meleeReadyAt = now + (if heavy then profile.heavyCooldown else profile.lightCooldown)
	ViewmodelController.play(Animator.melee(heavy), function(event: string)
		if event ~= "Strike" then
			return
		end
		local _, aim = CameraController.getAim()
		local packet: Types.MeleePacket = { heavy = heavy, a = aim, t = serverNow() }
		Net.event("Melee"):FireServer(packet)
		CameraController.punch(Vector3.new(if heavy then -2 else -1, if heavy then 2.5 else 1.5, 0))
	end)
end

---------------------------------------------------------------------------------------------
-- Boucle
---------------------------------------------------------------------------------------------

local function triggerHeld(): boolean
	return InputController.isDown("Fire")
end

local function canFire(def: WeaponDef, now: number): boolean
	return armed
		and isAlive()
		and now >= readyAt
		and now >= cycleUntil
		and reload == nil
		and not isBusy()
		and combatOpen()
		and def.category ~= "Melee"
end

local function onDry(def: WeaponDef)
	if dryClicked then
		return
	end
	dryClicked = true
	AudioController.play(def.audio.dry)
	WeaponController.DryFire:Fire()
	if SettingsController.get().Controls.AutoReload then
		startReload()
	end
end

local function step(dt: number)
	local def = current
	local now = os.clock()
	updateAds(dt, now)
	if not (def and armed) then
		return
	end
	ViewmodelController.setLowered(isBusy())
	recover(def, dt, now)

	local ammo = slotAmmo()
	if not ammo then
		return
	end
	local held = triggerHeld()
	if not held then
		dryClicked = false
		heldTime = math.max(0, heldTime - dt * 2)
	end

	-- Un tir pendant un rechargement cartouche par cartouche l'interrompt (comme le serveur).
	local active = reload
	if active and active.shell and held and ammo.mag > 0 then
		cancelReload()
		readyAt = now + 0.12
	end

	if not canFire(def, now) then
		return
	end
	if ViewmodelController.isPlaying("Inspect") and held then
		ViewmodelController.stop()
	end

	local mode = def.fire.mode
	local frameServer = serverNow()
	if mode == "Auto" then
		if not held then
			return
		end
		-- Planning périmé (gâchette relâchée) : on repart de maintenant, jamais plus tôt.
		if nextShotAt < now - 0.1 then
			nextShotAt = now
		end
		local shots = 0
		while held and nextShotAt <= now and shots < MAX_SHOTS_PER_FRAME do
			if ammo.mag <= 0 then
				onDry(def)
				return
			end
			local scheduled = nextShotAt
			fireOnce(def, scheduled, now, frameServer)
			local rpm = Weapons.currentRpm(def, heldTime)
			heldTime += 60 / rpm
			nextShotAt = scheduled + 60 / rpm
			shots += 1
		end
	elseif mode == "Burst" then
		local queuedBurst = semiQueuedAt
		if burstRemaining == 0 and queuedBurst and now - queuedBurst <= SEMI_BUFFER and now >= burstReadyAt then
			semiQueuedAt = nil
			if ammo.mag <= 0 then
				onDry(def)
				return
			end
			burstRemaining = def.fire.burstCount
			nextShotAt = now
		elseif queuedBurst and now - queuedBurst > SEMI_BUFFER then
			semiQueuedAt = nil
		end
		if burstRemaining > 0 then
			local shots = 0
			while burstRemaining > 0 and nextShotAt <= now and shots < MAX_SHOTS_PER_FRAME do
				if ammo.mag <= 0 then
					burstRemaining = 0
					onDry(def)
					return
				end
				local scheduled = nextShotAt
				fireOnce(def, scheduled, now, frameServer)
				burstRemaining -= 1
				nextShotAt = scheduled + 60 / def.fire.burstRpm
				shots += 1
				if burstRemaining == 0 then
					burstReadyAt = scheduled + 60 / def.fire.burstRpm + def.fire.burstCooldown
				end
			end
		end
	else
		-- Semi / Bolt / Pump : un tir par pression, clic mémorisé SEMI_BUFFER secondes.
		local queued = semiQueuedAt
		if queued and now - queued <= SEMI_BUFFER and now >= nextShotAt then
			semiQueuedAt = nil
			if ammo.mag <= 0 then
				onDry(def)
				return
			end
			fireOnce(def, now, now, frameServer)
			nextShotAt = now + 60 / def.fire.rpm
		elseif queued and now - queued > SEMI_BUFFER then
			semiQueuedAt = nil
		end
	end
end

---------------------------------------------------------------------------------------------
-- Réseau
---------------------------------------------------------------------------------------------

local function onAmmoSync(packet: Types.AmmoSyncPacket?)
	if packet == nil then
		disarmLocal()
		return
	end
	local wasArmed = armed
	lastSyncAt = os.clock()
	seedBase = packet.seed
	counter = packet.counter
	for name, ammo in packet.slots do
		local existing = slots[name]
		if existing and existing.w == ammo.w then
			existing.mag = ammo.mag
			existing.reserve = ammo.reserve
		else
			slots[name] = { w = ammo.w, mag = ammo.mag, reserve = ammo.reserve }
		end
	end
	for name in slots do
		if packet.slots[name] == nil then
			slots[name] = nil
		end
	end
	armed = true
	local equippedName = packet.equipped
	if not wasArmed and (equippedName == "Primary" or equippedName == "Secondary" or equippedName == "Melee") then
		lastShotServer = -math.huge
		bloom = 0
		equip(equippedName :: WeaponSlot, true)
	elseif not slots[equippedSlot] then
		cycleSlot(1)
	else
		-- Resynchronisation : le serveur a refusé quelque chose, on repart de sa vérité.
		if not packet.reloading and reload and not (reload :: Reload).shell then
			local active = reload :: Reload
			if os.clock() - active.startedAt > active.duration + 0.5 then
				reload = nil
			end
		end
		local ammo = slotAmmo()
		ViewmodelController.setEmpty(ammo ~= nil and ammo.mag <= 0)
	end
	WeaponController.Changed:Fire()
end

local function onShotResult(result: Types.ShotResult)
	local def = Weapons.get(result.w)
	for _, report in result.hits do
		WeaponController.HitConfirmed:Fire(report, def)
	end
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function WeaponController.isArmed(): boolean
	return armed
end

function WeaponController.equipped(): WeaponDef?
	return current
end

function WeaponController.adsAlpha(): number
	return adsAlpha
end

--[[ Cône instantané (degrés) pour le réticule dynamique. ]]
function WeaponController.currentCone(): number
	local def = current
	if not def then
		return 0
	end
	local now = serverNow()
	local since = now - lastShotServer
	return Spread.cone(def.spread, {
		ads = adsAlpha,
		speedRatio = MovementController.speedRatio(),
		airborne = MovementController.isAirborne(),
		crouched = MovementController.stance() ~= "Stand",
		bloom = Spread.decayBloom(def.spread, bloom, since),
		firstShot = since >= def.spread.firstShotReset,
	})
end

local hud: HudState = {
	def = nil,
	slot = nil,
	mag = 0,
	reserve = 0,
	capacity = 0,
	reloading = false,
	reloadProgress = 0,
	ads = 0,
	scoped = false,
	cone = 0,
	ready = false,
}

--[[ État lu chaque frame par le HUD (table réutilisée : zéro allocation). ]]
function WeaponController.hudState(): HudState
	local def = current
	local ammo = slotAmmo()
	hud.def = def
	hud.slot = if def then equippedSlot else nil
	hud.mag = if ammo then ammo.mag else 0
	hud.reserve = if ammo then ammo.reserve else 0
	hud.capacity = if def then def.ammo.magazine else 0
	hud.reloading = reload ~= nil
	hud.reloadProgress = reloadProgress()
	hud.ads = adsAlpha
	hud.scoped = ViewmodelController.isScoped()
	hud.cone = WeaponController.currentCone()
	hud.ready = os.clock() >= readyAt
	return hud
end

function WeaponController.slots(): { [string]: Types.SlotAmmo }
	return slots
end

function WeaponController.start()
	Net.event("AmmoSync").OnClientEvent:Connect(onAmmoSync)
	Net.event("ShotResult").OnClientEvent:Connect(onShotResult)

	InputController.ActionBegan:Connect(function(action: string)
		local def = current
		if not (def and armed) then
			return
		end
		local now = os.clock()
		if action == "Fire" then
			if def.category == "Melee" then
				melee(def, false)
			elseif def.fire.mode ~= "Auto" then
				semiQueuedAt = now
			end
		elseif action == "Aim" then
			if def.category == "Melee" then
				melee(def, true)
			elseif SettingsController.get().Controls.ToggleAds then
				adsToggled = not adsToggled
			end
		elseif action == "Reload" then
			startReload()
		elseif action == "Primary" or action == "Secondary" or action == "Melee" then
			equip(action :: WeaponSlot)
		elseif action == "Cycle" then
			cycleSlot(1)
		elseif action == "Inspect" then
			if
				reload == nil
				and adsAlpha < 0.05
				and now >= readyAt
				and not ViewmodelController.isPlaying()
				and not triggerHeld()
			then
				local skin = skinFor(def.id)
				local flourish = skin.fx ~= nil and skin.fx.inspectFlourish == true
				ViewmodelController.play(Animator.inspect(def, flourish))
			end
		end
	end)
	InputController.Scrolled:Connect(function(delta: number)
		if armed and current then
			cycleSlot(if delta > 0 then -1 else 1)
		end
	end)

	player.CharacterAdded:Connect(function(character: Model)
		-- L'AmmoSync de cette vie peut arriver AVANT CharacterAdded : on la garde.
		if armed and os.clock() - lastSyncAt < 1.5 then
			equip(equippedSlot, true)
		else
			disarmLocal()
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(disarmLocal)
		end
	end)

	-- Après la caméra (Camera + 1) et le viewmodel (+2) : visée et muzzle de la frame.
	RunService:BindToRenderStep("AS_Weapon", Enum.RenderPriority.Camera.Value + 3, step)
end

return WeaponController
