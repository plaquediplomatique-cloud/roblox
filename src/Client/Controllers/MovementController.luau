--!strict
--[[
	MovementController — déplacement compétitif "Source-like" piloté sur un Humanoid.

	Le Humanoid reste le corps physique (collisions, sol, marches) mais NOTRE modèle
	décide de la vitesse : chaque frame on part de la vitesse RÉELLE (murs, collisions
	pris en compte), on applique friction/accélération, puis on impose le résultat via
	Humanoid:Move(direction) + WalkSpeed = |v|. Résultat :
	  * démarrage nerveux, arrêt net, COUNTER-STRAFE (≈70 ms pour retrouver la précision),
	  * air-control limité (courber sa trajectoire, pas voler),
	  * bunny-hop LÉGER : un saut dans la fenêtre d'atterrissage évite la friction, mais
	    la vitesse est plafonnée et chaque hop rogne l'excédent,
	  * glissade : élan initial, friction croissante, gain en pente, steering léger,
	    slide-jump (conserve 85 % de l'élan, plafonné en l'air),
	  * buffer de saut (120 ms) et coyote time (80 ms) : les commandes ne "ratent" jamais.
	Postures (Stand/Crouch/Slide) : HipHeight physique + géométrie partagée (Stances),
	répliquées au serveur (hitboxes) ; la visée part en binaire à 30 Hz.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Movement = require(Shared.Config.Movement)
local Stances = require(Shared.Combat.Stances)
local Spring = require(Shared.Util.Spring)
local Signal = require(Shared.Util.Signal)
local MathUtil = require(Shared.Util.MathUtil)
local Net = require(Shared.Net.Net)
local LookCodec = require(Shared.Net.LookCodec)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsController = require(script.Parent.SettingsController)
local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer

local MovementController = {
	Jumped = Signal.new() :: Signal.Signal<>,
	Landed = Signal.new() :: Signal.Signal<number>,
	SlideStarted = Signal.new() :: Signal.Signal<>,
	SlideEnded = Signal.new() :: Signal.Signal<>,
	Footstep = Signal.new() :: Signal.Signal<Enum.Material, number>,
	StanceChanged = Signal.new() :: Signal.Signal<Types.Stance>,
}

local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local align: AlignOrientation? = nil

local stance: Types.Stance = "Stand"
local walking = false
local crouchToggled = false
local walkToggled = false
local standHip = 2
local firstPerson = false
local frozen = false

local leanSpring = Spring.number(0, Movement.lean.speed, 1)
local tiltSpring = Spring.number(0, 12, 0.8)
local bobAmplitude = Spring.number(0, 10, 1)
local bobPhase = 0
local stepDistance = 0

local slideTime = 0
local slideSpeed = 0
local slideDir = Vector3.new(0, 0, -1)
local slideCooldownUntil = 0
local airborneSince = 0

local grounded = true
local wasGrounded = true
local lastGroundedAt = 0
local lastJumpAt = 0
local jumpBufferedAt: number? = nil
local lastLandAt = 0
local landingSlowUntil = 0
local airCap = Movement.runSpeed * Movement.maxAirSpeedRatio
local fallSpeed = 0
local hopChain = 0

local weaponMove = 1
local adsMove = 1
local adsActive = false

local lastStancePacket = ""
local lastStanceSent = 0
local lookAccumulator = 0
local hullParams = RaycastParams.new()
hullParams.FilterType = Enum.RaycastFilterType.Exclude

---------------------------------------------------------------------------------------------
-- Modèle de vitesse
---------------------------------------------------------------------------------------------

local function applyFriction(velocity: Vector3, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.05 then
		return Vector3.zero
	end
	local control = math.max(speed, Movement.stopSpeed)
	local newSpeed = math.max(speed - control * Movement.friction * dt, 0)
	return velocity * (newSpeed / speed)
end

local function accelerate(
	velocity: Vector3,
	wishDir: Vector3,
	wishSpeed: number,
	accel: number,
	dt: number,
	cap: number?
): Vector3
	if wishSpeed <= 0 then
		return velocity
	end
	local current = velocity:Dot(wishDir)
	local limit = if cap then math.min(wishSpeed, cap) else wishSpeed
	local add = limit - current
	if add <= 0 then
		return velocity
	end
	local accelSpeed = math.min(accel * dt * wishSpeed, add)
	return velocity + wishDir * accelSpeed
end

---------------------------------------------------------------------------------------------
-- Postures
---------------------------------------------------------------------------------------------

local function hasHeadroom(): boolean
	local r = root
	if not (r and character) then
		return true
	end
	hullParams.FilterDescendantsInstances = { character :: Instance }
	local needed = math.max(0, standHip - (humanoid and humanoid.HipHeight or standHip)) + 0.6
	return Workspace:Spherecast(r.Position, 0.9, Vector3.new(0, needed + 1.2, 0), hullParams) == nil
end

local function sendStance(force: boolean)
	local leanInt = if leanSpring.target > 0.5 then 1 elseif leanSpring.target < -0.5 then -1 else 0
	local key = ("%s|%d|%s|%s"):format(stance, leanInt, tostring(adsActive), tostring(walking))
	if key == lastStancePacket and not force then
		return
	end
	if os.clock() - lastStanceSent < 0.08 and not force then
		return
	end
	lastStancePacket = key
	lastStanceSent = os.clock()
	local packet: Types.StancePacket = { stance = stance, lean = leanInt, ads = adsActive, walking = walking }
	Net.event("Stance"):FireServer(packet)
end

local function setStance(newStance: Types.Stance)
	if stance == newStance then
		return
	end
	stance = newStance
	local h = humanoid
	if h then
		h.HipHeight = math.max(0.3, standHip + Stances.profiles[newStance].hipHeightOffset)
	end
	MovementController.StanceChanged:Fire(newStance)
	sendStance(true)
end

local function startSlide(velocity: Vector3)
	slideTime = 0
	slideDir = if velocity.Magnitude > 0.1 then velocity.Unit else slideDir
	slideSpeed = math.min(math.max(velocity.Magnitude, Movement.slide.startSpeed), Movement.slide.speedCap)
	setStance("Slide")
	tiltSpring.target = Movement.slide.cameraTilt
	CameraController.setFovKick(Movement.slide.fovKick)
	MovementController.SlideStarted:Fire()
end

local function endSlide(toCrouch: boolean)
	if stance ~= "Slide" then
		return
	end
	slideCooldownUntil = os.clock() + Movement.slide.cooldown
	tiltSpring.target = 0
	CameraController.setFovKick(0)
	if toCrouch or not hasHeadroom() then
		setStance("Crouch")
	else
		setStance("Stand")
	end
	MovementController.SlideEnded:Fire()
end

local function wantsCrouch(): boolean
	if SettingsController.get().Controls.ToggleCrouch then
		return crouchToggled
	end
	return InputController.isDown("Crouch")
end

---------------------------------------------------------------------------------------------
-- Boucle
---------------------------------------------------------------------------------------------

local function floorNormal(): Vector3
	local r = root
	if not (r and character) then
		return Vector3.yAxis
	end
	hullParams.FilterDescendantsInstances = { character :: Instance }
	local result = Workspace:Raycast(r.Position, Vector3.new(0, -(standHip + 3), 0), hullParams)
	return if result then result.Normal else Vector3.yAxis
end

local function tryJump(now: number, flat: Vector3): boolean
	local h = humanoid
	if not h then
		return false
	end
	local canGround = grounded or now - lastGroundedAt <= Movement.coyoteTime
	if not canGround or now - lastJumpAt < Movement.jumpCooldown then
		return false
	end
	if stance == "Crouch" and not hasHeadroom() then
		return false
	end
	local carry = flat.Magnitude
	if stance == "Slide" then
		carry = slideSpeed * Movement.slide.jumpCarry
		endSlide(false)
	elseif stance == "Crouch" then
		setStance("Stand")
	end
	-- Bunny-hop léger : l'excédent au-dessus de la vitesse de course s'érode à chaque hop.
	if now - lastLandAt <= Movement.bhopWindow then
		hopChain += 1
		local excess = math.max(carry - Movement.runSpeed, 0)
		carry = Movement.runSpeed + excess * (Movement.bhopDecay ^ hopChain)
	else
		hopChain = 0
	end
	airCap = math.max(Movement.runSpeed * Movement.maxAirSpeedRatio, math.min(carry, Movement.slide.speedCap))
	h:ChangeState(Enum.HumanoidStateType.Jumping)
	lastJumpAt = now
	jumpBufferedAt = nil
	MovementController.Jumped:Fire()
	return true
end

local function step(dt: number)
	local h, r = humanoid, root
	if not (h and r and character) or h.Health <= 0 then
		return
	end
	local now = os.clock()
	local yaw = select(1, CameraController.getYawPitch())
	-- Gel : cinématique, ou action d'objectif en cours (attribut Busy posé par le serveur).
	local blocked = frozen or (character :: Model):GetAttribute("Busy") == true
	local moveLocal = if blocked then Vector3.zero else InputController.moveVector()
	local wishWorld = CFrame.Angles(0, yaw, 0) * moveLocal
	if not firstPerson then
		-- Hub : déplacement relatif à la caméra, rotation libre du personnage.
		wishWorld = CFrame.Angles(0, yaw, 0) * moveLocal
	end
	local wishDir = if wishWorld.Magnitude > 0.01 then wishWorld.Unit else Vector3.zero
	local analog = math.min(moveLocal.Magnitude, 1)

	grounded = h.FloorMaterial ~= Enum.Material.Air
	local velocity = r.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)

	-- Atterrissage
	if grounded then
		if not wasGrounded then
			lastLandAt = now
			MovementController.Landed:Fire(fallSpeed)
			if fallSpeed > Movement.landing.hardSpeed then
				landingSlowUntil = now + Movement.landing.slowDuration
			end
			local kick = math.min(fallSpeed * Movement.camera.landKick, Movement.camera.landKickMax)
			CameraController.punch(Vector3.new(-kick * 2.2, 0, 0))
			fallSpeed = 0
		end
		lastGroundedAt = now
	else
		if wasGrounded then
			airborneSince = now
		end
		fallSpeed = math.max(fallSpeed, -velocity.Y)
	end
	wasGrounded = grounded

	-- Marche / accroupi / glissade
	local controls = SettingsController.get().Controls
	walking = if controls.ToggleWalk then walkToggled else InputController.isDown("Walk")
	local crouch = wantsCrouch()
	if stance == "Stand" and crouch then
		if
			grounded
			and flat.Magnitude >= Movement.runSpeed * Movement.slide.minEntrySpeedRatio
			and now >= slideCooldownUntil
			and not walking
		then
			startSlide(flat)
		else
			setStance("Crouch")
		end
	elseif stance == "Crouch" and not crouch and hasHeadroom() then
		setStance("Stand")
	elseif stance == "Slide" and not crouch then
		endSlide(false)
	end

	-- Saut (buffer + coyote)
	local buffered = jumpBufferedAt
	if buffered and now - buffered <= Movement.jumpBuffer and not blocked then
		tryJump(now, flat)
	end

	-- Vitesse souhaitée
	local base = if stance == "Crouch"
		then Movement.crouchSpeed
		elseif walking then Movement.walkSpeed
		else Movement.runSpeed
	local multiplier = weaponMove * (if adsActive then adsMove else 1)
	if now < landingSlowUntil then
		multiplier *= Movement.landing.slowMultiplier
	end
	local tagged = character and character:GetAttribute("TaggedUntil")
	if type(tagged) == "number" and Workspace:GetServerTimeNow() < tagged then
		multiplier *= Movement.tagging.multiplier
	end
	local wishSpeed = base * multiplier * analog

	if stance == "Slide" then
		slideTime += dt
		local normal = floorNormal()
		local downhill = normal:Dot(slideDir)
		local decel = Movement.slide.friction + Movement.slide.frictionGrowth * slideTime
		slideSpeed = math.clamp(
			slideSpeed - decel * dt + Workspace.Gravity * downhill * Movement.slide.slopeGain * dt,
			0,
			Movement.slide.speedCap
		)
		if wishDir.Magnitude > 0 then
			local steered = slideDir + wishDir * Movement.slide.steer * dt * 4
			slideDir = MathUtil.flat(steered).Unit
		end
		flat = slideDir * slideSpeed
		local airborneTooLong = not grounded and now - airborneSince > 0.15
		if slideSpeed < Movement.crouchSpeed + 0.5 or slideTime > Movement.slide.maxDuration or airborneTooLong then
			endSlide(wantsCrouch())
		end
	elseif grounded then
		local hopping = now - lastLandAt <= Movement.bhopWindow and jumpBufferedAt ~= nil
		if not hopping then
			flat = applyFriction(flat, dt)
		end
		flat = accelerate(flat, wishDir, wishSpeed, Movement.groundAccelerate, dt, nil)
		airCap = Movement.runSpeed * Movement.maxAirSpeedRatio
	else
		flat = accelerate(flat, wishDir, wishSpeed, Movement.airAccelerate, dt, Movement.airWishCap)
		if flat.Magnitude > airCap then
			flat = flat.Unit * airCap
		end
	end

	-- Application au Humanoid
	local speed = flat.Magnitude
	if speed > 0.05 then
		h:Move(flat / speed, false)
		h.WalkSpeed = speed
	else
		h:Move(Vector3.zero, false)
		h.WalkSpeed = 0
	end

	-- Orientation du corps
	local aligner = align
	if aligner then
		if firstPerson then
			aligner.CFrame = CFrame.Angles(0, yaw, 0)
		elseif speed > 1 then
			local targetYaw = math.atan2(-flat.X, -flat.Z)
			local _, currentYaw = aligner.CFrame:ToEulerAnglesYXZ()
			local blended = currentYaw + MathUtil.wrapAngle(targetYaw - currentYaw) * math.min(1, dt * 12)
			aligner.CFrame = CFrame.Angles(0, blended, 0)
		end
	end

	-- Lean (bloqué par les murs)
	local leanTarget = 0
	if firstPerson and controls.LeanEnabled and stance ~= "Slide" and not frozen then
		if InputController.isDown("LeanRight") then
			leanTarget += 1
		end
		if InputController.isDown("LeanLeft") then
			leanTarget -= 1
		end
		if leanTarget ~= 0 then
			hullParams.FilterDescendantsInstances = { character :: Instance }
			local eye = Stances.eyePosition(r.CFrame, stance, 0)
			local side = CFrame.Angles(0, yaw, 0).RightVector * leanTarget
			if Workspace:Spherecast(eye, 0.45, side * 1.2, hullParams) then
				leanTarget *= Movement.lean.blockedFraction
			end
		end
	end
	leanSpring.target = leanTarget
	leanSpring:step(dt)
	tiltSpring:step(dt)

	-- Pas et bob
	if grounded and stance ~= "Slide" and speed > 1 then
		local stride = if stance == "Crouch" then 4.4 else Movement.footsteps.strideLength
		stepDistance += speed * dt
		bobPhase += speed * dt / stride * math.pi
		if stepDistance >= stride then
			stepDistance = 0
			local volume = if walking
				then Movement.footsteps.walkVolume
				elseif stance == "Crouch" then Movement.footsteps.crouchVolume
				else Movement.footsteps.runVolume * math.clamp(speed / Movement.runSpeed, 0.4, 1)
			MovementController.Footstep:Fire(h.FloorMaterial, volume)
		end
		bobAmplitude.target = math.clamp(speed / Movement.runSpeed, 0, 1.2)
	else
		bobAmplitude.target = 0
	end
	bobAmplitude:step(dt)

	sendStance(false)

	-- Visée -> serveur (binaire, 30 Hz)
	lookAccumulator += dt
	if lookAccumulator >= 1 / 30 then
		lookAccumulator = 0
		local _, pitch = CameraController.getYawPitch()
		Net.unreliable("LookUpdate"):FireServer(LookCodec.encodeLocal(yaw, pitch))
	end
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function MovementController.setWeaponModifiers(moveMultiplier: number, adsMultiplier: number, ads: boolean)
	weaponMove = moveMultiplier
	adsMove = adsMultiplier
	if ads ~= adsActive then
		adsActive = ads
		sendStance(true)
	end
end

function MovementController.setFirstPerson(enabled: boolean)
	firstPerson = enabled
	local model = character
	if model then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") or descendant:IsA("Decal") then
				(descendant :: any).LocalTransparencyModifier = if enabled then 1 else 0
			end
		end
	end
	if not enabled then
		leanSpring:snap(0)
	end
end

function MovementController.setFrozen(value: boolean)
	frozen = value
end

function MovementController.speedRatio(): number
	local r = root
	if not r then
		return 0
	end
	local v = r.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude / (Movement.runSpeed * weaponMove)
end

function MovementController.isAirborne(): boolean
	return not grounded
end

function MovementController.stance(): Types.Stance
	return stance
end

function MovementController.lean(): number
	return leanSpring.position
end

function MovementController.bob(): (number, number)
	return bobPhase, bobAmplitude.position
end

function MovementController.character(): (Model?, Humanoid?, BasePart?)
	return character, humanoid, root
end

local function bodyState(): CameraController.BodyState
	local phase, amplitude = bobPhase, bobAmplitude.position
	local vertical = math.sin(phase * 2) * amplitude * Movement.camera.bobVertical
	local horizontal = math.cos(phase) * amplitude * Movement.camera.bobVertical * 0.6
	return {
		root = root,
		character = character,
		eye = Stances.eyeOffset(stance, leanSpring.position),
		bobOffset = Vector3.new(horizontal, vertical, 0),
		bobRoll = math.sin(phase) * amplitude * Movement.camera.bobRoll,
		-- Roulis de lean identique à Stances.leanTransform : la caméra suit la hitbox.
		tilt = tiltSpring.position - leanSpring.position * math.deg(Stances.LEAN_ROLL),
		grounded = grounded,
	}
end

local function onCharacter(model: Model)
	character = model
	local h = model:WaitForChild("Humanoid", 10)
	local r = model:WaitForChild("HumanoidRootPart", 10)
	if not (h and h:IsA("Humanoid") and r and r:IsA("BasePart")) then
		return
	end
	humanoid = h
	root = r
	h.AutoRotate = false
	h:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	standHip = h.HipHeight
	local hip = model:GetAttribute("StandHipHeight")
	if type(hip) == "number" then
		standHip = hip
	end
	stance = "Stand"
	slideSpeed = 0
	leanSpring:snap(0)
	tiltSpring:snap(0)
	CameraController.setFovKick(0)
	local attachment = Instance.new("Attachment")
	attachment.Name = "AS_Align"
	attachment.Parent = r
	local aligner = Instance.new("AlignOrientation")
	aligner.Mode = Enum.OrientationAlignmentMode.OneAttachment
	aligner.Attachment0 = attachment
	aligner.Responsiveness = 200
	aligner.MaxTorque = math.huge
	aligner.RigidityEnabled = false
	local _, currentYaw = r.CFrame:ToEulerAnglesYXZ()
	aligner.CFrame = CFrame.Angles(0, currentYaw, 0)
	aligner.Parent = r
	align = aligner
	CameraController.setYawPitch(currentYaw, 0)
	model.DescendantAdded:Connect(function(descendant)
		if firstPerson and (descendant:IsA("BasePart") or descendant:IsA("Decal")) then
			(descendant :: any).LocalTransparencyModifier = 1
		end
	end)
	MovementController.setFirstPerson(firstPerson)
	sendStance(true)
end

function MovementController.start()
	CameraController.setBodyProvider(bodyState)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		character, humanoid, root, align = nil, nil, nil, nil
	end)
	InputController.ActionBegan:Connect(function(action: string)
		if action == "Jump" then
			jumpBufferedAt = os.clock()
		elseif action == "Crouch" then
			crouchToggled = not crouchToggled
		elseif action == "Walk" then
			walkToggled = not walkToggled
		end
	end)
	ClientState.MenuChanged:Connect(function(open: boolean)
		if open then
			crouchToggled = false
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return MovementController
