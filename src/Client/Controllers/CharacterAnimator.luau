--!strict
--[[
	CharacterAnimator — tous les personnages vus en 3e personne, animés PROCÉDURALEMENT.

	Hub, sans arme : animations Roblox standard (script Animate par défaut). Sinon : aucun
	asset d'animation. Chaque frame (PreSimulation, écriture de Motor6D.Transform, la
	méthode documentée pour l'animation procédurale) :

	  Bas du corps  : IK analytique à 2 os sur les VRAIES proportions du rig (longueurs
	                  mesurées sur les C0/C1) : pieds posés au sol quelle que soit la posture,
	                  cycle de pas paramétré par la vitesse réelle (phase intégrée à la
	                  distance), direction de marche (strafe, recul), saut/chute, glissade.
	  Haut du corps : visée répliquée (LookBatch 20 Hz, interpolée) répartie bassin /
	                  torse / tête, lean IDENTIQUE à la hitbox (Stances.leanTransform).
	  Arme          : modèle 3e personne (attributs Weapon/Skin) soudé au torse, orienté sur
	                  la visée ; les deux mains sont posées dessus par IK (main droite sur la
	                  poignée, gauche sur le garde-main) ; recul visible à chaque tir.
	  Emotes        : poses clés (hub).
	LOD : >150 studs une frame sur 3, >350 studs plus d'animation.

	Présentation : contour ennemi (Highlight "Occluded" : visible UNIQUEMENT là où
	l'ennemi est réellement visible — accessibilité couleur, jamais un wallhack),
	plaques de nom (hub : niveau/rang ; match : coéquipiers seulement), visuels des tirs
	des autres joueurs (ShotVisual) partant de la bouche de LEUR arme, effets de kill.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local Settings = require(Shared.Config.Settings)
local Movement = require(Shared.Config.Movement)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local Stances = require(Shared.Combat.Stances)
local Footsteps = require(Shared.Rules.Footsteps)
local MathUtil = require(Shared.Util.MathUtil)
local Net = require(Shared.Net.Net)
local LookCodec = require(Shared.Net.LookCodec)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local WeaponModelBuilder = require(script.Parent.Parent.Weapons.WeaponModelBuilder)
local CameraController = require(script.Parent.CameraController)
local SettingsController = require(script.Parent.SettingsController)
local EffectsController = require(script.Parent.EffectsController)
local AudioController = require(script.Parent.AudioController)

local TWO_PI = math.pi * 2
local rad = math.rad

local CharacterAnimator = {}

type Limb = {
	upper: Motor6D,
	lower: Motor6D,
	last: Motor6D,
	e0: Vector3, -- articulation intermédiaire au repos (repère de l'articulation haute)
	f0: Vector3, -- articulation terminale au repos (repère de l'articulation intermédiaire)
	hinge0: Vector3,
	upperLength: number,
	lowerLength: number,
	sign: number, -- +1 jambes (genou vers l'avant), -1 bras (coude vers le bas)
}

type Rig = {
	root: Motor6D,
	waist: Motor6D,
	neck: Motor6D,
	rightArm: Limb,
	leftArm: Limb,
	rightLeg: Limb,
	leftLeg: Limb,
	hipX: number,
	ankleHeight: number,
}

type ThirdPersonWeapon = {
	key: string,
	def: Types.WeaponDef,
	built: WeaponModelBuilder.BuiltWeapon,
	weld: Weld,
}

type Entry = {
	model: Model,
	player: Player?,
	isBot: boolean,
	humanoid: Humanoid,
	root: BasePart,
	rig: Rig?,
	phase: number,
	ads: number,
	sprint: number,
	kick: number,
	lastYaw: number,
	bank: number,
	rigRetryAt: number,
	frame: number,
	weapon: ThirdPersonWeapon?,
	highlight: Highlight?,
	nameplate: BillboardGui?,
	emote: { id: string, started: number }?,
	connections: { RBXScriptConnection },
	stepIndex: number,
	lastVerticalSpeed: number,
}

type Look = { yaw: number, pitch: number, targetYaw: number, targetPitch: number }

local entries: { [Model]: Entry } = {}
local looks: { [Player]: Look } = {}
local slotToPlayer: { [number]: Player } = {}

---------------------------------------------------------------------------------------------
-- Rig
---------------------------------------------------------------------------------------------

local function motor(model: Model, partName: string, jointName: string): Motor6D?
	local part = model:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function buildLimb(upper: Motor6D?, lower: Motor6D?, last: Motor6D?, sign: number): Limb?
	if not (upper and lower and last) then
		return nil
	end
	local e0 = upper.C1:Inverse() * lower.C0.Position
	local f0 = lower.C1:Inverse() * last.C0.Position
	if e0.Magnitude < 1e-3 or f0.Magnitude < 1e-3 then
		return nil
	end
	return {
		upper = upper,
		lower = lower,
		last = last,
		e0 = e0,
		f0 = f0,
		hinge0 = (upper.C1:Inverse() * lower.C0).XVector,
		upperLength = e0.Magnitude,
		lowerLength = f0.Magnitude,
		sign = sign,
	}
end

local function buildRig(model: Model): Rig?
	local root = motor(model, "LowerTorso", "Root")
	local waist = motor(model, "UpperTorso", "Waist")
	local neck = motor(model, "Head", "Neck")
	local rightArm = buildLimb(
		motor(model, "RightUpperArm", "RightShoulder"),
		motor(model, "RightLowerArm", "RightElbow"),
		motor(model, "RightHand", "RightWrist"),
		-1
	)
	local leftArm = buildLimb(
		motor(model, "LeftUpperArm", "LeftShoulder"),
		motor(model, "LeftLowerArm", "LeftElbow"),
		motor(model, "LeftHand", "LeftWrist"),
		-1
	)
	local rightLeg = buildLimb(
		motor(model, "RightUpperLeg", "RightHip"),
		motor(model, "RightLowerLeg", "RightKnee"),
		motor(model, "RightFoot", "RightAnkle"),
		1
	)
	local leftLeg = buildLimb(
		motor(model, "LeftUpperLeg", "LeftHip"),
		motor(model, "LeftLowerLeg", "LeftKnee"),
		motor(model, "LeftFoot", "LeftAnkle"),
		1
	)
	if not (root and waist and neck and rightArm and leftArm and rightLeg and leftLeg) then
		return nil
	end
	local foot = model:FindFirstChild("RightFoot")
	local ankleHeight = 0.25
	if foot and foot:IsA("BasePart") then
		ankleHeight = rightLeg.last.C1.Position.Y + foot.Size.Y / 2
	end
	return {
		root = root,
		waist = waist,
		neck = neck,
		rightArm = rightArm,
		leftArm = leftArm,
		rightLeg = rightLeg,
		leftLeg = leftLeg,
		hipX = math.abs(rightLeg.upper.C0.Position.X),
		ankleHeight = math.max(ankleHeight, 0.05),
	}
end

---------------------------------------------------------------------------------------------
-- IK à 2 os
---------------------------------------------------------------------------------------------

--[[ Repère d'un segment : le membre s'étend selon -Y, la charnière est l'axe X. ]]
local function basis(direction: Vector3, hinge: Vector3): CFrame
	local y = -direction
	local x = hinge - y * hinge:Dot(y)
	if x.Magnitude < 1e-5 then
		local fallback = if math.abs(y.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
		x = fallback - y * fallback:Dot(y)
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

local function angleYZ(v: Vector3): number
	return math.atan2(-v.Z, -v.Y)
end

--[[
	Pose un membre pour que son articulation terminale (cheville / poignet) atteigne
	`target`. `parent` = CFrame monde de la pièce porteuse. Écrit les Transform des deux
	premières articulations ; renvoie le repère monde de l'articulation terminale.
]]
local function solveLimb(limb: Limb, parent: CFrame, target: Vector3, pole: Vector3, fallbackHinge: Vector3): CFrame
	local j1 = parent * limb.upper.C0
	local origin = j1.Position
	local a, b = limb.upperLength, limb.lowerLength
	local offset = target - origin
	local distance = offset.Magnitude
	local direction = if distance > 1e-4 then offset / distance else -j1.YVector
	local reach = a + b
	local middle: Vector3
	if distance >= reach * 0.999 then
		middle = origin + direction * a
	else
		local d = math.max(distance, math.abs(a - b) + 1e-3)
		local along = (a * a - b * b + d * d) / (2 * d)
		local height = math.sqrt(math.max(a * a - along * along, 0))
		local bend = pole - direction * pole:Dot(direction)
		if bend.Magnitude < 1e-4 then
			bend = fallbackHinge:Cross(direction)
		end
		middle = origin + direction * along + bend.Unit * height
	end
	local hinge = direction:Cross(middle - origin) * limb.sign
	if hinge.Magnitude < 1e-4 then
		hinge = fallbackHinge
	end
	local t1 = basis(j1:VectorToObjectSpace((middle - origin).Unit), j1:VectorToObjectSpace(hinge.Unit))
		* basis(limb.e0.Unit, limb.hinge0):Inverse()
	limb.upper.Transform = t1
	local j2 = j1 * t1 * limb.upper.C1:Inverse() * limb.lower.C0
	local toEnd = j2:VectorToObjectSpace(target - middle)
	local t2 = CFrame.Angles(angleYZ(toEnd) - angleYZ(limb.f0), 0, 0)
	limb.lower.Transform = t2
	return j2 * t2 * limb.lower.C1:Inverse() * limb.last.C0
end

local function orientEnd(limb: Limb, j3: CFrame, desired: CFrame)
	limb.last.Transform = j3.Rotation:Inverse() * desired.Rotation * limb.last.C1.Rotation
end

local function setFK(limb: Limb, upper: CFrame, lower: CFrame)
	limb.upper.Transform = upper
	limb.lower.Transform = lower
	limb.last.Transform = CFrame.identity
end

---------------------------------------------------------------------------------------------
-- Visée répliquée
---------------------------------------------------------------------------------------------

local function refreshSlots()
	table.clear(slotToPlayer)
	for _, other in Players:GetPlayers() do
		local slot = other:GetAttribute("NetSlot")
		if type(slot) == "number" then
			slotToPlayer[slot] = other
		end
	end
end

local function onLookBatch(payload: any)
	LookCodec.decodeBatch(payload, function(slot: number, yaw: number, pitch: number)
		local owner = slotToPlayer[slot]
		if not owner or owner == Players.LocalPlayer then
			return
		end
		local look = looks[owner]
		if look then
			look.targetYaw = yaw
			look.targetPitch = pitch
		else
			looks[owner] = { yaw = yaw, pitch = pitch, targetYaw = yaw, targetPitch = pitch }
		end
	end)
end

local function stepLooks(dt: number)
	local alpha = 1 - math.exp(-16 * dt)
	for owner, look in looks do
		if owner.Parent == nil then
			looks[owner] = nil
			continue
		end
		look.yaw += MathUtil.wrapAngle(look.targetYaw - look.yaw) * alpha
		look.pitch += (look.targetPitch - look.pitch) * alpha
	end
end

--[[ Visée lissée d'un joueur (spectateur, killcam, animation). ]]
function CharacterAnimator.lookOf(target: Player): (number?, number?)
	if target == Players.LocalPlayer then
		local yaw, pitch = CameraController.getYawPitch()
		return yaw, pitch
	end
	local look = looks[target]
	if look then
		return look.yaw, look.pitch
	end
	return nil, nil
end

---------------------------------------------------------------------------------------------
-- Présentation (arme 3e personne, contours, plaques)
---------------------------------------------------------------------------------------------

local function stringAttr(instance: Instance, name: string): string?
	local value = instance:GetAttribute(name)
	return if type(value) == "string" and value ~= "" then value else nil
end

local function numberAttr(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function removeWeapon(entry: Entry)
	local weapon = entry.weapon
	if weapon then
		weapon.weld:Destroy()
		weapon.built:destroy()
		entry.weapon = nil
	end
end

local function refreshWeapon(entry: Entry)
	local weaponId = stringAttr(entry.model, "Weapon")
	local def = if weaponId then Weapons.get(weaponId) else nil
	local alive = entry.model:GetAttribute("Alive") == true
	if not (def and alive) then
		removeWeapon(entry)
		return
	end
	local skinId = stringAttr(entry.model, "Skin") or "default"
	local key = def.id .. "|" .. skinId
	local existing = entry.weapon
	if existing and existing.key == key then
		return
	end
	removeWeapon(entry)
	local upperTorso = entry.model:FindFirstChild("UpperTorso")
	if not (upperTorso and upperTorso:IsA("BasePart")) then
		return
	end
	local built = WeaponModelBuilder.build(def, Cosmetics.get(skinId), def.model.worldScale)
	built.root.Anchored = false
	for _, part in built.parts do
		part.CastShadow = true
	end
	local weld = Instance.new("Weld")
	weld.Name = "AS_WeaponWeld"
	weld.Part0 = upperTorso
	weld.Part1 = built.root
	weld.Parent = built.root
	built.model.Parent = entry.model
	entry.weapon = { key = key, def = def, built = built, weld = weld }
end

local function isEnemy(model: Model): boolean
	if CollectionService:HasTag(model, "TrainingBot") then
		return true
	end
	local kind = ClientState.arena()
	if kind ~= "Match" then
		return false
	end
	local mine = Players.LocalPlayer.Character
	local myTeam = if mine then stringAttr(mine, "Team") else nil
	local team = stringAttr(model, "Team")
	return myTeam ~= nil and team ~= nil and team ~= myTeam
end

local function makeNameplate(entry: Entry): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "AS_Nameplate"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 22)
	name.FontFace = Theme.fonts.heading
	name.TextSize = 18
	name.TextColor3 = Theme.colors.text
	name.TextStrokeTransparency = 0.6
	name.Parent = gui
	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromOffset(0, 22)
	detail.Size = UDim2.new(1, 0, 0, 18)
	detail.FontFace = Theme.fonts.mono
	detail.TextSize = 13
	detail.TextColor3 = Theme.colors.textDim
	detail.TextStrokeTransparency = 0.7
	detail.Parent = gui
	local head = entry.model:FindFirstChild("Head")
	gui.Adornee = if head and head:IsA("BasePart") then head else entry.root
	gui.Parent = entry.model
	return gui
end

local function refreshPresentation(entry: Entry)
	local model = entry.model
	local owner = entry.player
	local alive = model:GetAttribute("Alive") == true
	local kind = ClientState.arena()
	local enemy = alive and isEnemy(model)

	-- Contour ennemi : rendu seulement sur les pixels où l'ennemi est visible.
	if enemy then
		local highlight = entry.highlight
		if not highlight then
			local created = Instance.new("Highlight")
			created.Name = "AS_Enemy"
			created.DepthMode = Enum.HighlightDepthMode.Occluded
			created.FillTransparency = 0.88
			created.OutlineTransparency = 0.1
			created.Adornee = model
			created.Parent = model
			entry.highlight = created
			highlight = created
		end
		local color = Settings.enemyColor(SettingsController.get().Hud.EnemyColor)
		local current = highlight :: Highlight
		current.OutlineColor = color
		current.FillColor = color
	elseif entry.highlight then
		(entry.highlight :: Highlight):Destroy()
		entry.highlight = nil
	end

	-- Plaques : hub (tout le monde) / match (coéquipiers vivants).
	local showPlate = owner ~= nil
		and owner ~= Players.LocalPlayer
		and alive
		and (kind == "Hub" or (kind == "Match" and not enemy))
	if showPlate and owner then
		local plate = entry.nameplate or makeNameplate(entry)
		entry.nameplate = plate
		local nameLabel = plate:FindFirstChild("Name") :: TextLabel
		local detail = plate:FindFirstChild("Detail") :: TextLabel
		nameLabel.Text = owner.DisplayName
		if kind == "Hub" then
			plate.AlwaysOnTop = false
			plate.MaxDistance = 70
			local rankIndex = numberAttr(owner, "RankIndex", 0)
			local tier = Ranks.tierOf(rankIndex)
			local placed = owner:GetAttribute("Placed") == true
			local title = stringAttr(owner, "Title")
			detail.Text = ("LV %d  ·  %s%s"):format(
				numberAttr(owner, "Level", 1),
				if placed then tier.glyph .. " " .. Ranks.displayName(rankIndex) else "NON CLASSÉ",
				if title then "  ·  " .. string.upper(title) else ""
			)
			detail.TextColor3 = if placed then tier.color else Theme.colors.textDim
			nameLabel.TextColor3 = Theme.colors.text
		else
			plate.AlwaysOnTop = true
			plate.MaxDistance = 400
			detail.Text = ""
			nameLabel.TextColor3 = Theme.colors.ally
		end
	elseif entry.nameplate then
		(entry.nameplate :: BillboardGui):Destroy()
		entry.nameplate = nil
	end
end

---------------------------------------------------------------------------------------------
-- Cycle de vie des entrées
---------------------------------------------------------------------------------------------

local function untrack(model: Model)
	local entry = entries[model]
	if not entry then
		return
	end
	entries[model] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	removeWeapon(entry)
	if entry.highlight then
		(entry.highlight :: Highlight):Destroy()
	end
	if entry.nameplate then
		(entry.nameplate :: BillboardGui):Destroy()
	end
end

--[[ Réapparition d'un bot du stand : éclat cyan bref qui se dissipe (on voit d'où il sort). ]]
local function spawnFlash(model: Model)
	-- L'effet d'élimination (EffectsController.killEffect) efface le corps via
	-- LocalTransparencyModifier ; un bot est réutilisé, pas recréé : on le rend visible.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 0
		end
	end
	local flash = Instance.new("Highlight")
	flash.Name = "AS_SpawnFlash"
	flash.FillColor = Theme.colors.primary
	flash.OutlineColor = Theme.colors.primary
	flash.FillTransparency = 0.2
	flash.OutlineTransparency = 0
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = model
	local tween = TweenService:Create(
		flash,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	)
	tween.Completed:Once(function()
		flash:Destroy()
	end)
	tween:Play()
end

local function track(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local model = instance :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 5)
	local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	if not model.Parent or entries[model] then
		return
	end
	local entry: Entry = {
		model = model,
		player = Players:GetPlayerFromCharacter(model),
		isBot = CollectionService:HasTag(model, "TrainingBot"),
		humanoid = humanoid,
		root = root,
		rig = buildRig(model),
		phase = 0,
		ads = 0,
		sprint = 0,
		kick = 0,
		lastYaw = 0,
		bank = 0,
		rigRetryAt = 0,
		frame = math.random(0, 2),
		weapon = nil,
		highlight = nil,
		nameplate = nil,
		emote = nil,
		connections = {},
		stepIndex = 0,
		lastVerticalSpeed = 0,
	}
	entries[model] = entry
	local function onAttribute(name: string)
		if name == "Weapon" or name == "Skin" or name == "Alive" then
			refreshWeapon(entry)
		end
		if name == "Team" or name == "Alive" then
			refreshPresentation(entry)
		end
		if name == "Alive" and entry.isBot and model:GetAttribute("Alive") == true then
			spawnFlash(model)
		end
		if name == "Emote" then
			local value = stringAttr(model, "Emote")
			if value then
				local id = string.split(value, "|")[1]
				entry.emote = { id = id, started = os.clock() }
			end
		end
	end
	table.insert(entry.connections, model.AttributeChanged:Connect(onAttribute))
	table.insert(
		entry.connections,
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				untrack(model)
			end
		end)
	)
	refreshWeapon(entry)
	refreshPresentation(entry)
end

---------------------------------------------------------------------------------------------
-- Animation
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

type GripStyle = { hip: Vector3, ads: Vector3, tilt: number }

local SPRINT_GRIP_OFFSET = Vector3.new(-0.25, -0.12, 0.2)

local GRIPS: { [string]: GripStyle } = {
	Rifle = { hip = Vector3.new(0.55, -0.5, -0.75), ads = Vector3.new(0.32, -0.02, -0.7), tilt = 0 },
	Heavy = { hip = Vector3.new(0.62, -0.62, -0.62), ads = Vector3.new(0.36, -0.08, -0.62), tilt = 0 },
	Pistol = { hip = Vector3.new(0.3, -0.25, -1.45), ads = Vector3.new(0.18, 0.05, -1.5), tilt = 0 },
	Blade = { hip = Vector3.new(0.62, -0.7, -0.95), ads = Vector3.new(0.62, -0.7, -0.95), tilt = rad(-35) },
}

local function emotePose(entry: Entry, rig: Rig, now: number): (CFrame?, boolean)
	local emote = entry.emote
	if not emote then
		return nil, false
	end
	local t = now - emote.started
	local duration = if emote.id == "em_spin" then 2 else 3
	if t > duration then
		entry.emote = nil
		return nil, false
	end
	local fade = math.clamp(math.min(t, duration - t) / 0.25, 0, 1)
	local id = emote.id
	local rootOverride: CFrame? = nil
	if id == "em_salute" then
		setFK(
			rig.rightArm,
			CFrame.Angles(rad(95 * fade), rad(-35 * fade), rad(55 * fade)),
			CFrame.Angles(rad(125 * fade), 0, 0)
		)
		setFK(rig.leftArm, CFrame.Angles(0, 0, rad(-4)), CFrame.Angles(rad(5), 0, 0))
	elseif id == "em_wave" then
		local wave = math.sin(t * 10) * 25
		setFK(
			rig.rightArm,
			CFrame.Angles(rad(150 * fade), 0, rad(20 * fade)),
			CFrame.Angles(rad((30 + wave) * fade), 0, 0)
		)
		setFK(rig.leftArm, CFrame.Angles(0, 0, rad(-4)), CFrame.Angles(rad(5), 0, 0))
	elseif id == "em_flex" then
		setFK(
			rig.rightArm,
			CFrame.Angles(0, 0, rad(80 * fade)) * CFrame.Angles(0, rad(90), 0),
			CFrame.Angles(rad(-100 * fade), 0, 0)
		)
		setFK(
			rig.leftArm,
			CFrame.Angles(0, 0, rad(-80 * fade)) * CFrame.Angles(0, rad(-90), 0),
			CFrame.Angles(rad(-100 * fade), 0, 0)
		)
	elseif id == "em_spin" then
		rootOverride = CFrame.Angles(0, (t / duration) * TWO_PI * 2, 0)
		setFK(rig.rightArm, CFrame.Angles(0, 0, rad(75 * fade)), CFrame.identity)
		setFK(rig.leftArm, CFrame.Angles(0, 0, rad(-75 * fade)), CFrame.identity)
	elseif id == "em_glitch" then
		local step = math.floor(t / 0.06)
		local rng = Random.new(step + entry.frame)
		rootOverride = CFrame.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.1, 0.15), rng:NextNumber(-0.3, 0.3))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.3, 0.3))
		setFK(
			rig.rightArm,
			CFrame.Angles(rng:NextNumber(-1, 2), 0, rng:NextNumber(0, 1.5)),
			CFrame.Angles(rng:NextNumber(0, 2), 0, 0)
		)
		setFK(
			rig.leftArm,
			CFrame.Angles(rng:NextNumber(-1, 2), 0, -rng:NextNumber(0, 1.5)),
			CFrame.Angles(rng:NextNumber(0, 2), 0, 0)
		)
	else
		return nil, false
	end
	return rootOverride, true
end

local footParams = RaycastParams.new()
footParams.FilterType = Enum.RaycastFilterType.Include

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

--[[
	Pas des AUTRES joueurs : information tactique essentielle. Sprint = fort, course =
	audible, accroupi = feutré, marche (Alt) = silencieuse (règle partagée Rules/Footsteps) ;
	matériau du sol par raycast.
]]
local function emitFootstep(entry: Entry, stance: Types.Stance, speed: number)
	local camera = Workspace.CurrentCamera
	local position = entry.root.Position
	if not camera or (camera.CFrame.Position - position).Magnitude > Movement.footsteps.maxHearDistance then
		return
	end
	local volume = Footsteps.volume(stance, entry.model:GetAttribute("Walking") == true, speed)
	if volume <= 0.01 then
		return
	end
	footParams.FilterDescendantsInstances = geometryRoots()
	local hit = Workspace:Raycast(position, Vector3.new(0, -6, 0), footParams)
	AudioController.footstep(
		if hit then hit.Position else position - Vector3.new(0, 3, 0),
		if hit then hit.Material else Enum.Material.Concrete,
		volume,
		false
	)
end

--[[
	Le rig référence des Motor6D : si l'apparence de l'avatar est (ré)appliquée après le
	spawn, les membres sont remplacés et les anciens moteurs ne bougent plus rien (le
	personnage resterait raide). On reconstruit dès qu'un moteur est détaché ou manquant.
]]
local function ensureRig(entry: Entry): Rig?
	local rig = entry.rig
	local stale = rig == nil
		or rig.root.Parent == nil
		or rig.waist.Parent == nil
		or rig.rightLeg.upper.Parent == nil
		or rig.leftArm.upper.Parent == nil
	if stale and os.clock() >= entry.rigRetryAt then
		entry.rigRetryAt = os.clock() + 0.5
		rig = buildRig(entry.model)
		entry.rig = rig
	end
	return rig
end

local function animate(entry: Entry, dt: number, now: number, isLocal: boolean)
	local rig = ensureRig(entry)
	if not rig then
		return
	end
	local model = entry.model
	local hrp = entry.root.CFrame
	local _, hrpYaw, _ = hrp:ToEulerAnglesYXZ()
	local flatRoot = CFrame.new(hrp.Position) * CFrame.Angles(0, hrpYaw, 0)

	-- Visée
	local yaw, pitch = hrpYaw, 0
	local owner = entry.player
	if owner then
		local lookYaw, lookPitch = CharacterAnimator.lookOf(owner)
		if lookYaw and lookPitch then
			yaw, pitch = lookYaw, lookPitch
		end
	end
	local yawOffset = math.clamp(MathUtil.wrapAngle(yaw - hrpYaw), rad(-50), rad(50))

	-- État de locomotion
	local stance: Types.Stance = stanceOf(model)
	local lean = if stance == "Slide" then 0 else numberAttr(model, "Lean", 0)
	entry.ads = MathUtil.damp(entry.ads, if model:GetAttribute("Ads") == true then 1 else 0, 10, dt)
	entry.sprint = MathUtil.damp(entry.sprint, if model:GetAttribute("Sprinting") == true then 1 else 0, 10, dt)
	entry.kick = math.max(0, entry.kick - dt * 9)
	local velocity = entry.root.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flatVelocity.Magnitude
	local localMove = flatRoot:VectorToObjectSpace(flatVelocity)
	local airborne = if isLocal then entry.humanoid.FloorMaterial == Enum.Material.Air else math.abs(velocity.Y) > 4.5
	if not airborne and speed > 0.3 then
		entry.phase = (entry.phase + dt * TWO_PI * speed / (2 * Footsteps.stride(stance, speed))) % TWO_PI
	end
	if not isLocal then
		local stepIndex = math.floor(entry.phase / math.pi)
		if stepIndex ~= entry.stepIndex then
			entry.stepIndex = stepIndex
			if not airborne and speed > 1 and stance ~= "Slide" then
				emitFootstep(entry, stance, speed)
			end
		end
		-- Atterrissage lourd audible (sauts, chutes).
		if entry.lastVerticalSpeed < -18 and velocity.Y > -2 then
			AudioController.playAt("Move.Land", entry.root.Position, { occlusion = true })
		end
		entry.lastVerticalSpeed = velocity.Y
	end
	local moveAmount = math.clamp(speed / 6, 0, 1)
	-- Allure : 0 = marche, 1 = course, 2 = sprint (mélanges continus, jamais de saut de pose).
	local runBlend = math.clamp((speed - Movement.walkSpeed) / (Movement.runSpeed - Movement.walkSpeed), 0, 1)
	local sprintBlend = math.clamp((speed - Movement.runSpeed) / (Movement.sprintSpeed - Movement.runSpeed), 0, 1)
	if model:GetAttribute("Sprinting") == true then
		sprintBlend = math.max(sprintBlend, 0.6 * runBlend)
	end

	-- Emote (hub) : remplace la pose des bras ; annulée par le mouvement.
	if entry.emote and speed > 3 then
		entry.emote = nil
	end
	-- Sans arme (hub), debout, sans emote : les animations Roblox standard (Animate :
	-- marche, course, saut, chute) pilotent le corps ; on ne réécrit aucune articulation.
	if not entry.weapon and not entry.emote and stance == "Stand" then
		return
	end
	local emoteRoot, emoting = emotePose(entry, rig, now)

	-- Racine et torse
	local slideLean = if stance == "Slide" then rad(16) else 0
	-- Inclinaison franche vers l'avant selon l'allure (course 10°, sprint jusqu'à 24°), dans le
	-- sens du déplacement local (en arrière en reculant), et inclinaison dans les virages.
	local forwardRatio = math.clamp(-localMove.Z / math.max(speed, 0.001), -1, 1) * moveAmount
	local leanAngle = rad(3 + 7 * runBlend + 14 * sprintBlend)
	local forwardLean = -forwardRatio * leanAngle
	local turnRate = MathUtil.wrapAngle(hrpYaw - entry.lastYaw) / math.max(dt, 1 / 240)
	entry.lastYaw = hrpYaw
	entry.bank = MathUtil.damp(entry.bank, math.clamp(turnRate * 0.04, -1, 1) * runBlend * rad(10), 8, dt)
	local bounce = 0.06 + 0.08 * runBlend + 0.08 * sprintBlend
	local bob = if airborne then 0 else -bounce * moveAmount * math.abs(math.cos(entry.phase))
	-- Balancier du bassin et contre-rotation des épaules : la foulée vit.
	local hipSway = math.sin(entry.phase) * rad(4 + 6 * runBlend) * moveAmount
	local tRoot = CFrame.new(0, bob, 0) * CFrame.Angles(forwardLean + slideLean, hipSway, entry.bank)
	if emoteRoot then
		tRoot = emoteRoot * tRoot
	end
	rig.root.Transform = tRoot
	local tWaist = Stances.leanTransform(lean)
		* CFrame.Angles(pitch * 0.4 - slideLean * 0.7 + forwardLean * 0.45, yawOffset * 0.6 - hipSway * 1.8, 0)
	rig.waist.Transform = tWaist
	rig.neck.Transform = CFrame.Angles(pitch * 0.45 - forwardLean * 0.6, yawOffset * 0.4, 0)
	local lowerTorso = hrp * rig.root.C0 * tRoot * rig.root.C1:Inverse()
	local upperTorso = lowerTorso * rig.waist.C0 * tWaist * rig.waist.C1:Inverse()

	-- Jambes
	local footRotation = CFrame.Angles(0, hrpYaw, 0)
	local right = flatRoot.RightVector
	if stance == "Slide" then
		setFK(rig.rightLeg, CFrame.Angles(rad(70), 0, 0), CFrame.Angles(rad(-12), 0, 0))
		setFK(rig.leftLeg, CFrame.Angles(rad(20), 0, rad(-6)), CFrame.Angles(rad(-105), 0, 0))
	elseif airborne then
		local tuck = math.clamp(-velocity.Y / 40, -0.3, 1)
		setFK(rig.rightLeg, CFrame.Angles(rad(30 - 15 * tuck), 0, 0), CFrame.Angles(rad(-50 + 25 * tuck), 0, 0))
		setFK(rig.leftLeg, CFrame.Angles(rad(10 - 10 * tuck), 0, 0), CFrame.Angles(rad(-30 + 20 * tuck), 0, 0))
	else
		local profile = Stances.profiles[stance]
		local standHip = numberAttr(model, "StandHipHeight", 2)
		local footY = -(entry.root.Size.Y / 2 + standHip + profile.hipHeightOffset) + rig.ankleHeight
		local crouched = stance == "Crouch"
		local direction = if speed > 0.1 then Vector3.new(localMove.X, 0, localMove.Z).Unit else Vector3.zero
		local walking = crouched or model:GetAttribute("Walking") == true
		local stride = (if walking then 0.55 else 0.75 + 0.25 * runBlend + 0.4 * sprintBlend) * moveAmount
		local lift = (0.2 + 0.3 * runBlend + 0.35 * sprintBlend) * moveAmount
		local footX = rig.hipX + 0.05
		for index, limb in { rig.rightLeg, rig.leftLeg } do
			local side = if index == 1 then 1 else -1
			local phi = (entry.phase + (if index == 1 then 0 else math.pi)) % TWO_PI
			local along, up
			if phi < math.pi then
				along = stride * (1 - 2 * phi / math.pi)
				up = 0
			else
				local u = (phi - math.pi) / math.pi
				along = stride * (-1 + 2 * u * u * (3 - 2 * u))
				up = lift * math.sin(u * math.pi)
			end
			local restZ = if crouched then (if index == 1 then 0.45 else -0.35) else 0
			local localTarget = Vector3.new(side * footX, footY + up, restZ) + direction * along
			local pole = flatRoot.LookVector + right * (0.25 * side)
			local j3 = solveLimb(limb, lowerTorso, flatRoot * localTarget, pole, right)
			orientEnd(limb, j3, footRotation)
		end
	end

	-- Bras : arme tenue à deux mains (IK) ou bras libres (balancier / emote).
	local weapon = entry.weapon
	if weapon and not emoting then
		local def = weapon.def
		local style = if def.category == "Melee"
			then "Blade"
			elseif def.viewmodel.inspect == "Pistol" then "Pistol"
			elseif def.viewmodel.inspect == "Heavy" then "Heavy"
			else "Rifle"
		local grip = GRIPS[style]
		local aimRotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local pivot = upperTorso.Position + upperTorso.UpVector * 0.45
		local offset = grip.hip:Lerp(grip.ads, entry.ads)
			+ Vector3.new(0, 0, entry.kick * 0.22)
			+ SPRINT_GRIP_OFFSET * entry.sprint
		-- Sprint : arme portée en travers, canon vers le bas (lisible de loin : « il ne tire pas »).
		local weaponCFrame = CFrame.new(pivot)
			* aimRotation
			* CFrame.new(offset)
			* CFrame.Angles(grip.tilt + rad(9) * entry.kick - rad(38) * entry.sprint, rad(32) * entry.sprint, 0)
		weapon.weld.C0 = upperTorso:Inverse() * weaponCFrame
		local scale = def.model.worldScale
		local up = weaponCFrame.UpVector
		local rightTarget = weaponCFrame * (def.model.rightHand.Position * scale) + up * 0.22
		local leftTarget = if style == "Blade"
			then upperTorso * Vector3.new(-0.9, -0.6, -0.9)
			else weaponCFrame * (def.model.leftHand.Position * scale) + up * 0.2
		local torsoRight = upperTorso.RightVector
		local down = -upperTorso.UpVector
		local back = -upperTorso.LookVector
		solveLimb(rig.rightArm, upperTorso, rightTarget, down + torsoRight * 0.8 + back * 0.3, torsoRight)
		solveLimb(rig.leftArm, upperTorso, leftTarget, down - torsoRight * 0.8 + back * 0.3, torsoRight)
		rig.rightArm.last.Transform = CFrame.identity
		rig.leftArm.last.Transform = CFrame.identity
	elseif not emoting then
		local swing = math.cos(entry.phase) * rad(25 + 30 * runBlend + 25 * sprintBlend) * moveAmount
		local elbow = rad(10 + (35 + 50 * sprintBlend) * moveAmount)
		setFK(rig.rightArm, CFrame.Angles(-swing, 0, rad(6)), CFrame.Angles(elbow, 0, 0))
		setFK(rig.leftArm, CFrame.Angles(swing, 0, rad(-6)), CFrame.Angles(elbow, 0, 0))
	end
end

local function step(dt: number)
	stepLooks(dt)
	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local localCharacter = Players.LocalPlayer.Character
	local firstPerson = CameraController.getMode() == "FirstPerson"
	local now = os.clock()
	for model, entry in entries do
		if model:GetAttribute("Alive") ~= true then
			continue
		end
		local isLocal = model == localCharacter
		if isLocal and firstPerson then
			continue
		end
		local distance = (entry.root.Position - cameraPosition).Magnitude
		if distance > 350 then
			continue
		end
		entry.frame += 1
		local interval = if distance > 150 then 3 else 1
		if entry.frame % interval == 0 then
			animate(entry, dt * interval, now, isLocal)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Tirs et éliminations des autres joueurs
---------------------------------------------------------------------------------------------

local function onShotVisual(packet: any)
	if type(packet) ~= "table" then
		return
	end
	local visual = packet :: Types.ShotVisualPacket
	local shooter = slotToPlayer[visual.s]
	local def = Weapons.get(visual.w)
	if not (shooter and def) or typeof(visual.o) ~= "Vector3" or type(visual.e) ~= "table" then
		return
	end
	local character = shooter.Character
	local entry = if character then entries[character] else nil
	local origin = visual.o
	local weapon = entry and entry.weapon
	local muzzleAttachment = weapon and weapon.built.attachments.Muzzle
	local muzzle = if muzzleAttachment then muzzleAttachment.WorldPosition else origin
	if entry then
		entry.kick = 1
	end
	local skinId = if character then stringAttr(character, "Skin") else nil
	local skin = if skinId then Cosmetics.get(skinId) else nil
	local fx = skin and skin.fx
	local tracerColor = (fx and fx.tracerColor) or def.tracer.color
	-- Arme suppressée : de loin, ni traceur ni flash (on entend, on ne voit pas).
	local camera = Workspace.CurrentCamera
	local conceal = def.tracer.concealRange
	local concealed = conceal ~= nil and camera ~= nil and (camera.CFrame.Position - muzzle).Magnitude > conceal
	local first = visual.e[1]
	if typeof(first) == "Vector3" and not concealed then
		local flashColor = (fx and fx.muzzleColor) or Color3.fromRGB(255, 200, 120)
		EffectsController.muzzleFlash(CFrame.lookAt(muzzle, first), flashColor, 1.1, true)
	end
	for index, endpoint in visual.e do
		if typeof(endpoint) ~= "Vector3" or index > 12 then
			break
		end
		if not concealed and (index == 1 or index % 2 == 0) then
			EffectsController.tracer(
				muzzle,
				endpoint,
				tracerColor,
				def.tracer.width,
				def.tracer.speed,
				def.tracer.length
			)
		end
		if index <= 3 then
			EffectsController.impactAt(origin, endpoint, "World")
		end
	end
	AudioController.weaponShot(def, muzzle, false)
end

local function onKill(event: Types.KillEvent)
	local victim = Players:GetPlayerByUserId(event.victim)
	local model = victim and victim.Character
	if not model then
		return
	end
	local entry = entries[model]
	if entry then
		removeWeapon(entry)
	end
	local killer = Players:GetPlayerByUserId(event.killer)
	local killerCharacter = killer and killer.Character
	local skinId = if killerCharacter then stringAttr(killerCharacter, "Skin") else nil
	local skin = if skinId then Cosmetics.get(skinId) else nil
	local color = if skin and skin.palette then skin.palette.Neon else Theme.colors.primary
	EffectsController.killEffect(model, event.killEffect, color)
end

---------------------------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------------------------

function CharacterAnimator.start()
	refreshSlots()
	local function watchSlot(other: Player)
		other:GetAttributeChangedSignal("NetSlot"):Connect(refreshSlots)
	end
	for _, other in Players:GetPlayers() do
		watchSlot(other)
	end
	Players.PlayerAdded:Connect(function(other: Player)
		watchSlot(other)
		refreshSlots()
	end)
	Players.PlayerRemoving:Connect(function(other: Player)
		looks[other] = nil
		task.defer(refreshSlots)
	end)

	for _, tag in { "Combatant", "TrainingBot" } do
		for _, instance in CollectionService:GetTagged(tag) do
			task.spawn(track, instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			task.spawn(track, instance)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
			if instance:IsA("Model") then
				untrack(instance)
			end
		end)
	end

	-- Le contour / les plaques dépendent du contexte local (équipe, arène, réglages).
	local function refreshAll()
		for _, entry in entries do
			refreshPresentation(entry)
		end
	end
	ClientState.ArenaChanged:Connect(refreshAll)
	SettingsController.Changed:Connect(refreshAll)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refreshAll()
		end
	end)

	CameraController.setLookProvider(CharacterAnimator.lookOf)
	Net.unreliable("LookBatch").OnClientEvent:Connect(onLookBatch)
	Net.unreliable("ShotVisual").OnClientEvent:Connect(onShotVisual)
	Net.event("Kill").OnClientEvent:Connect(onKill)
	RunService.PreSimulation:Connect(step)
end

return CharacterAnimator
