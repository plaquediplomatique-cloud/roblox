--!strict
--[[
	ViewmodelController — arme et bras en 1re personne, 100 % procéduraux.

	Tout est calculé en "espace viewmodel" (repère caméra, unités design) puis ramené au
	monde avec une échelle uniforme SCALE = 0.6 autour de l'oeil : en perspective l'image
	est identique, mais l'arme traverse 40 % de murs en moins.

	Empilement des couches (de la plus globale à la plus locale) :
	  frame   = mouvement (inertie de déplacement) · bob de pas · respiration · sway souris
	            · atterrissage   -> partagé par les épaules ET l'arme (cohérence du corps)
	  base    = hanche (hipOffset) ⟷ visée (AimPoint centré à adsDistance) selon l'alpha ADS,
	            arc + léger roulis pendant la transition, posture (accroupi / glissade),
	            abaissement (mur trop proche, action en cours) vers lowOffset
	  kick    = ressorts de recul visuel (position + rotation autour de la poignée)
	  pose    = clip de l'Animator (équipement, rechargement, inspection, mêlée, cycle)
	Les bras : IK analytique à 2 os, épaules fixes hors champ -> mains sur les attachments
	RightHand / LeftHand de l'arme (ou cible de main gauche animée par le clip).

	Le viewmodel ne touche JAMAIS à la visée : il est purement cosmétique (la caméra et
	les balles suivent CameraController.getAim()).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Cosmetics = require(Shared.Config.Cosmetics)
local Spring = require(Shared.Util.Spring)
local MathUtil = require(Shared.Util.MathUtil)
local Animator = require(script.Parent.Parent.Weapons.Animator)
local WeaponModelBuilder = require(script.Parent.Parent.Weapons.WeaponModelBuilder)
local CameraController = require(script.Parent.CameraController)
local MovementController = require(script.Parent.MovementController)
local SettingsController = require(script.Parent.SettingsController)
local AudioController = require(script.Parent.AudioController)
local EffectsController = require(script.Parent.EffectsController)

type WeaponDef = Types.WeaponDef
type BuiltWeapon = WeaponModelBuilder.BuiltWeapon

local SCALE = 0.6
local UPPER_ARM = 1.55
local FOREARM = 1.5
local RIGHT_SHOULDER = Vector3.new(0.95, -1.45, 0.5)
local LEFT_SHOULDER = Vector3.new(-0.75, -1.4, 0.35)
local RIGHT_POLE = Vector3.new(0.9, -1, 0.35)
local LEFT_POLE = Vector3.new(-1, -0.9, 0.2)
local MELEE_LEFT_REST = CFrame.new(-0.7, -1.2, -0.85)
local BLEND_TIME = 0.14

local ViewmodelController = {}

type Arm = {
	upper: BasePart,
	fore: BasePart,
	glove: BasePart,
	cuff: BasePart,
}

type Current = {
	def: WeaponDef,
	skinId: string,
	built: BuiltWeapon,
	muzzleReach: number, -- distance oeil -> bouche (studs monde), pour le test de mur
}

local rig: Model
local arms: { right: Arm, left: Arm }
local current: Current? = nil
local cache: { [string]: BuiltWeapon } = {}

local animator = Animator.newPlayer()
local externalHandler: ((string) -> ())? = nil
local blendFrom: CFrame? = nil
local blendTimer = 0
local lastPoseRoot = CFrame.identity

local adsAlpha = 0
local requestedVisible = true
local lowered = false
local empty = false
local scoped = false

local swaySpring = Spring.vector(Vector3.zero, 13, 0.72)
local moveSpring = Spring.vector(Vector3.zero, 9, 0.85)
local stanceSpring = Spring.vector(Vector3.zero, 10, 0.9)
local landSpring = Spring.vector(Vector3.zero, 14, 0.55)
local kickPos = Spring.vector(Vector3.zero, 22, 0.62)
local kickRot = Spring.vector(Vector3.zero, 20, 0.55)
local lowSpring = Spring.number(0, 12, 1)
local rng = Random.new()

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------------------------

--[[ Ramène une transformation de l'espace viewmodel (design) vers l'espace caméra réel. ]]
local function scaled(cframe: CFrame): CFrame
	return CFrame.new(cframe.Position * SCALE) * cframe.Rotation
end

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

local function newArmPart(name: string, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = rig
	return part
end

local function newArm(side: string): Arm
	local upper = newArmPart(side .. "UpperArm", Enum.Material.Fabric)
	upper.Size = Vector3.new(0.44, 0.44, UPPER_ARM) * SCALE
	local fore = newArmPart(side .. "Forearm", Enum.Material.Fabric)
	fore.Size = Vector3.new(0.36, 0.36, FOREARM) * SCALE
	local glove = newArmPart(side .. "Glove", Enum.Material.SmoothPlastic)
	glove.Size = Vector3.new(0.3, 0.24, 0.44) * SCALE
	local cuff = newArmPart(side .. "Cuff", Enum.Material.Neon)
	cuff.Size = Vector3.new(0.38, 0.38, 0.06) * SCALE
	return { upper = upper, fore = fore, glove = glove, cuff = cuff }
end

local function paintArms()
	local operatorId = Players.LocalPlayer:GetAttribute("Operator")
	local item = if type(operatorId) == "string" then Cosmetics.get(operatorId) else nil
	local palette = item and item.palette
	local sleeve = if palette then palette.Base else Color3.fromRGB(38, 42, 50)
	local glove = if palette then palette.Grip else Color3.fromRGB(22, 24, 28)
	local neon = if palette then palette.Neon else Color3.fromRGB(61, 225, 255)
	for _, arm in { arms.right, arms.left } do
		arm.upper.Color = sleeve
		arm.fore.Color = sleeve:Lerp(Color3.new(0, 0, 0), 0.15)
		arm.glove.Color = glove
		arm.cuff.Color = neon
	end
end

--[[
	IK analytique à 2 os. Renvoie la position du coude (espace viewmodel).
	Si la cible est hors de portée, le bras s'aligne (léger étirement invisible).
]]
local function solveElbow(shoulder: Vector3, hand: Vector3, pole: Vector3): Vector3
	local offset = hand - shoulder
	local distance = offset.Magnitude
	local reach = UPPER_ARM + FOREARM
	if distance < 1e-4 then
		return shoulder + pole.Unit * UPPER_ARM
	end
	local direction = offset / distance
	if distance >= reach * 0.999 then
		return shoulder + direction * (distance * UPPER_ARM / reach)
	end
	distance = math.max(distance, math.abs(UPPER_ARM - FOREARM) + 1e-3)
	local along = (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + distance * distance) / (2 * distance)
	local height = math.sqrt(math.max(UPPER_ARM * UPPER_ARM - along * along, 0))
	local bend = pole - direction * pole:Dot(direction)
	if bend.Magnitude < 1e-4 then
		bend = Vector3.yAxis:Cross(direction)
	end
	return shoulder + direction * along + bend.Unit * height
end

local function placeSegment(part: BasePart, from: Vector3, to: Vector3, camera: CFrame)
	local length = (to - from).Magnitude
	local size = part.Size
	local wanted = length * SCALE
	if math.abs(size.Z - wanted) > 0.01 then
		part.Size = Vector3.new(size.X, size.Y, wanted)
	end
	part.CFrame = camera * scaled(CFrame.lookAt((from + to) * 0.5, to))
end

local function placeArm(arm: Arm, shoulder: Vector3, hand: CFrame, pole: Vector3, camera: CFrame)
	local handPosition = hand.Position
	local elbow = solveElbow(shoulder, handPosition, pole)
	placeSegment(arm.upper, shoulder, elbow, camera)
	placeSegment(arm.fore, elbow, handPosition, camera)
	local direction = handPosition - elbow
	local wrist = if direction.Magnitude > 1e-4
		then CFrame.lookAt(handPosition, handPosition + direction)
		else CFrame.new(handPosition)
	arm.glove.CFrame = camera * scaled(wrist * CFrame.new(0, 0, -0.08))
	arm.cuff.CFrame = camera * scaled(wrist * CFrame.new(0, 0, 0.2))
end

local function setRigTransparency(value: number)
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = value
		end
	end
end

local function flashScale(def: WeaponDef): number
	local category = def.category
	if category == "Sniper" or category == "Shotgun" then
		return 0.6
	elseif category == "LMG" then
		return 0.52
	elseif category == "DMR" or category == "Revolver" then
		return 0.48
	elseif category == "SMG" or category == "MachinePistol" then
		return 0.32
	elseif category == "Pistol" then
		return 0.3
	end
	return 0.4
end

local function shellSize(def: WeaponDef): number
	local category = def.category
	if category == "Shotgun" then
		return 0.085
	elseif category == "Sniper" or category == "LMG" or category == "DMR" then
		return 0.065
	elseif category == "Pistol" or category == "SMG" or category == "MachinePistol" then
		return 0.04
	end
	return 0.05
end

---------------------------------------------------------------------------------------------
-- Événements d'animation
---------------------------------------------------------------------------------------------

local function ejectShell(state: Current)
	local ejection = state.built.attachments.Ejection
	local camera = Workspace.CurrentCamera
	if not (ejection and camera) then
		return
	end
	local _, _, root = MovementController.character()
	local inherited = if root then root.AssemblyLinearVelocity else Vector3.zero
	local cf = ejection.WorldCFrame
	local velocity = camera.CFrame:VectorToWorldSpace(
		Vector3.new(rng:NextNumber(4.5, 6.5), rng:NextNumber(3, 4.5), rng:NextNumber(0.5, 1.5))
	)
	EffectsController.shell(cf, velocity + inherited, shellSize(state.def))
end

local function onAnimationEvent(name: string)
	local state = current
	if not state then
		return
	end
	local def = state.def
	if string.sub(name, 1, 6) == "Sound:" then
		local field = string.sub(name, 7)
		local key = (def.audio :: any)[field]
		if type(key) == "string" then
			AudioController.play(key)
		end
	elseif name == "DropMag" then
		local magName = def.model.magPiece
		local mag = if magName then state.built.parts[magName] else nil
		local camera = Workspace.CurrentCamera
		if mag and camera then
			local _, _, root = MovementController.character()
			local inherited = if root then root.AssemblyLinearVelocity else Vector3.zero
			local velocity = camera.CFrame:VectorToWorldSpace(Vector3.new(0.6, -3, -0.4))
			EffectsController.dropMag(mag, velocity + inherited)
		end
	elseif name == "Shell" then
		ejectShell(state)
	elseif name == "Shells" then
		for _ = 1, 6 do
			local ejection = state.built.attachments.Ejection
			if ejection then
				EffectsController.shell(
					ejection.WorldCFrame,
					Vector3.new(rng:NextNumber(-1, 1), -rng:NextNumber(2, 4), rng:NextNumber(-1, 1)),
					shellSize(def)
				)
			end
		end
	end
	local handler = externalHandler
	if handler then
		handler(name)
	end
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

--[[ Équipe une arme : construit (ou reprend du cache) le modèle et joue l'équipement. ]]
function ViewmodelController.equip(def: WeaponDef, skin: Types.ItemDef?, duration: number, first: boolean)
	local skinId = if skin then skin.id else "default"
	local key = def.id .. "|" .. skinId
	local previous = current
	if previous then
		previous.built.model.Parent = nil
	end
	local built = cache[key]
	if not built then
		built = WeaponModelBuilder.build(def, skin, SCALE)
		cache[key] = built
	end
	local muzzle = def.model.muzzle.Position
	local reach = (def.viewmodel.hipOffset.Position + muzzle).Magnitude * SCALE
	current = { def = def, skinId = skinId, built = built, muzzleReach = reach }
	built.model.Parent = rig
	WeaponModelBuilder.setVisible(built, true)
	empty = false
	externalHandler = nil
	animator:play(Animator.equip(def, duration, first), onAnimationEvent)
	blendFrom = nil
	blendTimer = 0
	kickPos:snap(Vector3.zero)
	kickRot:snap(Vector3.zero)
end

function ViewmodelController.clear()
	local state = current
	if state then
		state.built.model.Parent = nil
	end
	current = nil
	animator:stop()
end

function ViewmodelController.current(): WeaponDef?
	local state = current
	return if state then state.def else nil
end

--[[
	Joue un clip. `onEvent` reçoit tous les événements (dont "Strike" pour la mêlée) ;
	les sons, chargeurs et douilles sont gérés ici. Un clip interrompu est fondu (0.14 s).
]]
function ViewmodelController.play(clip: Animator.Clip, onEvent: ((string) -> ())?, onDone: (() -> ())?)
	if animator:isPlaying() then
		blendFrom = lastPoseRoot
		blendTimer = BLEND_TIME
	end
	externalHandler = onEvent
	animator:play(clip, onAnimationEvent, onDone)
end

function ViewmodelController.stop()
	if animator:isPlaying() then
		blendFrom = lastPoseRoot
		blendTimer = BLEND_TIME
	end
	externalHandler = nil
	animator:stop()
end

function ViewmodelController.isPlaying(name: string?): boolean
	return animator:isPlaying(name)
end

function ViewmodelController.setAds(alpha: number)
	adsAlpha = MathUtil.clamp01(alpha)
end

function ViewmodelController.setVisible(visible: boolean)
	requestedVisible = visible
end

--[[ Abaisse l'arme (pose d'objectif, désamorçage, menu radial…). ]]
function ViewmodelController.setLowered(value: boolean)
	lowered = value
end

--[[ Culasse de pistolet bloquée en arrière quand le chargeur est vide. ]]
function ViewmodelController.setEmpty(value: boolean)
	empty = value
end

function ViewmodelController.isScoped(): boolean
	return scoped
end

function ViewmodelController.attachment(name: string): Attachment?
	local state = current
	if not state then
		return nil
	end
	return state.built.attachments[name]
end

--[[ Retour visuel d'un tir : recul du modèle, flash, douille. ]]
function ViewmodelController.onShot(def: WeaponDef, crouched: boolean)
	local state = current
	if not state then
		return
	end
	local recoil = def.recoil
	local adsFactor = MathUtil.lerp(1, 0.5, adsAlpha)
	local stanceFactor = if crouched then 0.85 else 1
	local side = rng:NextNumber(-1, 1) * recoil.kickSide
	-- Impulsions calibrées pour que le pic du ressort ≈ la valeur de config
	-- (kickBack en unités design, kickUp/kickSide en degrés).
	kickPos:impulse(Vector3.new(side * 0.4, recoil.kickUp * 0.35 * adsFactor, recoil.kickBack * 45) * stanceFactor)
	kickRot:impulse(Vector3.new(recoil.kickUp * 38 * adsFactor, side * 26 * adsFactor, side * 40) * stanceFactor)

	local muzzle = state.built.attachments.Muzzle
	if muzzle and not scoped then
		local skin = state.built.skin
		local fx = skin and skin.fx
		local color = (fx and fx.muzzleColor) or Color3.fromRGB(255, 200, 120)
		local reduced = SettingsController.get().Video.ReducedFlashes
		local scale = flashScale(def) * (if reduced then 0.55 else 1)
		EffectsController.muzzleFlash(muzzle.WorldCFrame, color, scale, def.category ~= "Pistol")
	end
	local mode = def.fire.mode
	if mode ~= "Bolt" and mode ~= "Pump" and mode ~= "Melee" and def.ammo.reloadStyle ~= "Cylinder" then
		ejectShell(state)
	end
end

---------------------------------------------------------------------------------------------
-- Mise à jour
---------------------------------------------------------------------------------------------

local function evaluatePose(dt: number): Animator.Pose
	local pose = animator:evaluate(dt)
	local from = blendFrom
	if from and blendTimer > 0 then
		blendTimer = math.max(0, blendTimer - dt)
		local t = 1 - blendTimer / BLEND_TIME
		t = t * t * (3 - 2 * t)
		pose.root = from:Lerp(pose.root, t)
		if blendTimer <= 0 then
			blendFrom = nil
		end
	end
	lastPoseRoot = pose.root
	return pose
end

local function hide()
	if rig.Parent ~= nil then
		rig.Parent = nil
	end
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local state = current
	local character, humanoid = MovementController.character()
	local alive = character ~= nil and humanoid ~= nil and humanoid.Health > 0
	if not (camera and state and alive and requestedVisible) or CameraController.getMode() ~= "FirstPerson" then
		hide()
		-- Le clip continue d'avancer (timing de gameplay), même invisible.
		evaluatePose(dt)
		return
	end
	local def = state.def
	local profile = def.viewmodel
	local built = state.built
	local video = SettingsController.get().Video
	local now = os.clock()
	local ads = adsAlpha
	local adsEase = ads * ads * (3 - 2 * ads)

	-- Lunette plein écran : le modèle disparaît une fois la visée quasi complète.
	local nowScoped = def.handling.scopeOverlay and ads > 0.85
	if nowScoped ~= scoped then
		scoped = nowScoped
		setRigTransparency(if nowScoped then 1 else 0)
	end
	if rig.Parent ~= camera then
		rig.Parent = camera
	end

	-- Animation
	local pose = evaluatePose(dt)

	-- Inertie de déplacement : l'arme "traîne" à l'opposé de la vitesse (espace caméra).
	local _, _, root = MovementController.character()
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local localVelocity = camera.CFrame:VectorToObjectSpace(velocity)
	local moveScale = 1 - 0.8 * adsEase
	moveSpring.target = Vector3.new(
		math.clamp(-localVelocity.X * 0.0035, -0.07, 0.07),
		math.clamp(-velocity.Y * 0.0025, -0.06, 0.06),
		math.clamp(localVelocity.Z * 0.0025, -0.05, 0.05)
	) * moveScale
	local moveOffset = moveSpring:step(dt)

	-- Sway : retard rotationnel sur la vitesse de visée.
	local yawInput, pitchInput = CameraController.lastInput()
	local inv = 1 / math.max(dt, 1 / 240)
	local yawRate = math.deg(yawInput) * inv
	local pitchRate = math.deg(pitchInput) * inv
	local swayScale = def.handling.swayMultiplier * (1 - 0.8 * adsEase)
	swaySpring.target = Vector3.new(
		math.clamp(-pitchRate * 0.012, -6, 6),
		math.clamp(-yawRate * 0.012, -7, 7),
		math.clamp(yawRate * 0.008, -5, 5)
	) * swayScale
	local sway = swaySpring:step(dt)

	-- Bob de pas (figure en 8) et respiration au repos.
	local phase, amplitude = MovementController.bob()
	local bobAmount = amplitude * profile.bobScale * video.ViewmodelBob * (1 - 0.85 * adsEase)
	local bobX = math.cos(phase) * 0.045 * bobAmount
	local bobY = -math.abs(math.sin(phase)) * 0.04 * bobAmount
	local bobRoll = math.cos(phase) * 1.6 * bobAmount
	local breath = (1 - math.clamp(amplitude, 0, 1)) * (1 - 0.75 * adsEase)
	local breathY = math.sin(now * 1.3) * 0.009 * breath
	local breathPitch = math.sin(now * 1.05 + 0.6) * 0.35 * breath

	local land = landSpring:step(dt)
	local frame = CFrame.new(moveOffset + land + Vector3.new(bobX, bobY + breathY, 0))
		* CFrame.Angles(math.rad(sway.X + breathPitch), math.rad(sway.Y), math.rad(sway.Z + bobRoll))

	-- Posture : accroupi = arme rentrée, glissade = arme inclinée.
	local stance = MovementController.stance()
	stanceSpring.target = if stance == "Slide"
		then Vector3.new(-0.05, -0.06, 0.04)
		elseif stance == "Crouch" then Vector3.new(-0.02, -0.025, 0.02)
		else Vector3.zero
	local stanceOffset = stanceSpring:step(dt)
	local stanceRoll = if stance == "Slide" then -12 else 0

	-- Hanche <-> visée (le point de visée de l'arme se place sur l'axe optique).
	local hip = profile.hipOffset * CFrame.new(stanceOffset) * CFrame.Angles(0, 0, math.rad(stanceRoll * (1 - adsEase)))
	local aim = CFrame.new(0, 0, -profile.adsDistance) * def.model.aimPoint:Inverse()
	local base = hip:Lerp(aim, adsEase)
	local arc = math.sin(ads * math.pi)
	base *= CFrame.new(0, -0.035 * arc, 0.02 * arc) * CFrame.Angles(0, 0, math.rad(-4) * arc)

	-- Abaissement : mur trop proche (l'arme se rétracte au lieu de traverser) ou action.
	wallParams.FilterDescendantsInstances = geometryRoots()
	local reach = state.muzzleReach + 0.35
	local hit = Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * reach, wallParams)
	local wallAlpha = if hit then math.clamp((reach - hit.Distance) / (reach * 0.55), 0, 1) else 0
	lowSpring.target = if lowered then 1 else wallAlpha * (1 - 0.5 * adsEase)
	local low = math.clamp(lowSpring:step(dt), 0, 1)
	if low > 0.001 then
		base = base:Lerp(profile.lowOffset, low * low * (3 - 2 * low))
	end

	-- Recul visuel (autour de la poignée).
	local kp = kickPos:step(dt)
	local kr = kickRot:step(dt)
	local kick = CFrame.new(kp) * CFrame.Angles(math.rad(kr.X), math.rad(kr.Y), math.rad(kr.Z))

	local weaponLocal = frame * base * kick * pose.root
	local cameraCFrame = camera.CFrame
	built.root.CFrame = cameraCFrame * scaled(weaponLocal)

	-- Pièces animées (chargeur, culasse) : le clip a priorité, sinon culasse bloquée à vide.
	local magName = def.model.magPiece
	if magName then
		WeaponModelBuilder.setPieceOffset(built, magName, pose.mag)
	end
	local boltName = def.model.boltPiece
	if boltName then
		local bolt = pose.bolt
		if bolt == CFrame.identity and empty and profile.inspect == "Pistol" and def.category == "Pistol" then
			bolt = CFrame.new(0, 0, 0.2)
		end
		WeaponModelBuilder.setPieceOffset(built, boltName, bolt)
	end

	-- Bras (IK) : épaules liées au "frame" (le corps suit l'inertie), mains sur l'arme.
	local rightHand = weaponLocal * def.model.rightHand
	local leftTarget: CFrame
	if def.category == "Melee" then
		leftTarget = frame * MELEE_LEFT_REST
	else
		leftTarget = weaponLocal * (pose.leftHand or def.model.leftHand)
	end
	placeArm(arms.right, frame * RIGHT_SHOULDER, rightHand, RIGHT_POLE, cameraCFrame)
	placeArm(arms.left, frame * LEFT_SHOULDER, leftTarget, LEFT_POLE, cameraCFrame)
end

function ViewmodelController.start()
	rig = Instance.new("Model")
	rig.Name = "Viewmodel"
	arms = { right = newArm("Right"), left = newArm("Left") }
	paintArms()
	Players.LocalPlayer:GetAttributeChangedSignal("Operator"):Connect(paintArms)

	MovementController.Landed:Connect(function(fallSpeed: number)
		landSpring:impulse(Vector3.new(0, -math.min(fallSpeed, 70) * 0.06, 0))
		kickRot:impulse(Vector3.new(-math.min(fallSpeed, 70) * 1.2, 0, 0))
	end)
	MovementController.Jumped:Connect(function()
		landSpring:impulse(Vector3.new(0, 0.9, 0))
	end)
	-- Le cycle de vie de l'arme appartient au WeaponController (AmmoSync / mort) ;
	-- ici on ne remet à zéro que l'état purement visuel.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		lowered = false
		scoped = false
		setRigTransparency(0)
	end)
	-- Après la caméra (Camera + 1) : on se cale sur le CFrame final de la frame.
	RunService:BindToRenderStep("AS_Viewmodel", Enum.RenderPriority.Camera.Value + 2, update)
end

return ViewmodelController
