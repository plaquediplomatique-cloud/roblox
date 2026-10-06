--!strict
--[[
	CameraController — caméra scriptée, cœur du "game feel".

	Séparation fondamentale :
	  VISÉE (yaw/pitch)      : ce que la balle suit. Modifiée par la souris et le recul
	                           "réel" (pattern). Jamais par les effets cosmétiques.
	  RENDU (CFrame caméra)  : visée + punch (ressort) + shake (trauma²·bruit de Perlin)
	                           + roulis (lean, glissade, bob) + offsets de bob.
	Les effets sont donc généreux sans jamais tricher sur l'endroit où l'on tire.

	Modes :
	  FirstPerson  : match / Training. Oeil = géométrie de posture partagée (Stances),
	                 lissage vertical des marches, FOV à ressort (ADS, glissade, kill).
	  ThirdPerson  : hub. Épaule droite, collision par Spherecast, souris verrouillée.
	  Cinematic    : chemins de keyframes (intro de map, "match trouvé"), easing.
	  Spectate     : vue d'un coéquipier (visée répliquée lissée).
	  Scripted     : CFrame imposé chaque frame (killcam).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Spring = require(Shared.Util.Spring)
local Signal = require(Shared.Util.Signal)
local MathUtil = require(Shared.Util.MathUtil)
local Stances = require(Shared.Combat.Stances)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsController = require(script.Parent.SettingsController)
local InputController = require(script.Parent.InputController)

export type Mode = "FirstPerson" | "ThirdPerson" | "Cinematic" | "Spectate" | "Scripted"

export type BodyState = {
	root: BasePart?,
	character: Model?,
	eye: Vector3, -- offset local de l'oeil (posture lissée)
	bobOffset: Vector3,
	bobRoll: number, -- degrés
	tilt: number, -- degrés (glissade)
	grounded: boolean,
}

local CameraController = {
	ModeChanged = Signal.new() :: Signal.Signal<Mode>,
}

local DEG_PER_PIXEL = 0.07
local MAX_PITCH = math.rad(86)

local mode: Mode = "ThirdPerson"
local yaw = 0
local pitch = 0
local lastPitchInput = 0
local lastYawInput = 0
local punch = Spring.vector(Vector3.zero, 24, 0.5)
local fovSpring = Spring.number(78, 16, 0.9)
local popSpring = Spring.number(0, 14, 0.45)
local trauma = 0
local zoom = 1
local sensitivityMultiplier = 1
local fovKick = 0
local smoothY: number? = nil
local thirdDistance = Spring.number(9, 12, 1)
local shakeSeed = math.random() * 1000
local cinematic: { frames: { CFrame }, start: number, duration: number, done: (() -> ())? }? = nil
local spectateTarget: Player? = nil
local spectateYaw, spectatePitch = 0, 0
local scriptedCFrame: CFrame? = nil
local scriptedFov: number? = nil
local lastAimOrigin = Vector3.zero

local bodyProvider: () -> BodyState = function(): BodyState
	return {
		root = nil,
		character = nil,
		eye = Vector3.new(0, 1.7, 0),
		bobOffset = Vector3.zero,
		bobRoll = 0,
		tilt = 0,
		grounded = true,
	}
end
local lookProvider: (Player) -> (number?, number?) = function(_player: Player): (number?, number?)
	return nil, nil
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function CameraController.setBodyProvider(fn: () -> BodyState)
	bodyProvider = fn
end

function CameraController.setLookProvider(fn: (Player) -> (number?, number?))
	lookProvider = fn
end

function CameraController.setMode(newMode: Mode)
	if newMode == mode then
		return
	end
	mode = newMode
	smoothY = nil
	if newMode ~= "Cinematic" then
		cinematic = nil
	end
	if newMode ~= "Scripted" then
		scriptedCFrame = nil
		scriptedFov = nil
	end
	CameraController.ModeChanged:Fire(newMode)
end

function CameraController.getMode(): Mode
	return mode
end

function CameraController.getYawPitch(): (number, number)
	return yaw, pitch
end

function CameraController.setYawPitch(newYaw: number, newPitch: number)
	yaw = newYaw
	pitch = math.clamp(newPitch, -MAX_PITCH, MAX_PITCH)
end

--[[ Entrée souris de la frame (radians) — utilisée pour la compensation de recul. ]]
function CameraController.lastInput(): (number, number)
	return lastYawInput, lastPitchInput
end

--[[ Recul "réel" : déplace la visée. x = droite (+), y = haut (+), en degrés. ]]
function CameraController.addRecoil(yawDegrees: number, pitchDegrees: number)
	yaw -= math.rad(yawDegrees)
	pitch = math.clamp(pitch + math.rad(pitchDegrees), -MAX_PITCH, MAX_PITCH)
end

--[[ Punch visuel (degrés : pitch, yaw, roll) — n'affecte pas la visée. ]]
function CameraController.punch(impulse: Vector3)
	punch:impulse(impulse * 24)
end

function CameraController.shake(amount: number)
	trauma = math.min(1, trauma + amount)
end

function CameraController.setZoom(newZoom: number, sensitivity: number)
	zoom = math.max(newZoom, 1)
	sensitivityMultiplier = sensitivity
end

function CameraController.setFovKick(degrees: number)
	fovKick = degrees
end

function CameraController.fovPop(degrees: number)
	popSpring:impulse(degrees * 14)
end

--[[ Origine et direction de VISÉE (ce que suivent les balles). ]]
function CameraController.getAim(): (Vector3, Vector3)
	return lastAimOrigin, MathUtil.directionFromYawPitch(yaw, pitch)
end

function CameraController.playPath(frames: { CFrame }, duration: number, done: (() -> ())?)
	if #frames == 0 then
		if done then
			done()
		end
		return
	end
	CameraController.setMode("Cinematic")
	cinematic = { frames = frames, start = os.clock(), duration = duration, done = done }
end

function CameraController.spectate(target: Player?)
	spectateTarget = target
	if target then
		CameraController.setMode("Spectate")
	end
end

function CameraController.spectateTarget(): Player?
	return spectateTarget
end

function CameraController.setScripted(cframe: CFrame, fov: number?)
	CameraController.setMode("Scripted")
	scriptedCFrame = cframe
	scriptedFov = fov
end

---------------------------------------------------------------------------------------------
-- Mise à jour
---------------------------------------------------------------------------------------------

local function readLook(dt: number)
	local delta = InputController.consumeLook(dt)
	local settings = SettingsController.get().Controls
	local zoomScale = if zoom > 1.01
		then (1 / zoom) * (if zoom > 2.5 then settings.ScopeMultiplier else settings.AdsMultiplier)
		else 1
	local degPerPixel = DEG_PER_PIXEL * settings.Sensitivity * sensitivityMultiplier * zoomScale
	local dYaw = -math.rad(delta.X * degPerPixel)
	local dPitch = -math.rad(delta.Y * degPerPixel) * (if settings.InvertY then -1 else 1)
	yaw = MathUtil.wrapAngle(yaw + dYaw)
	pitch = math.clamp(pitch + dPitch, -MAX_PITCH, MAX_PITCH)
	lastYawInput = dYaw
	lastPitchInput = dPitch
end

local function shakeAngles(now: number): Vector3
	local intensity = trauma * trauma * SettingsController.get().Video.CameraShake
	if intensity <= 0.0001 then
		return Vector3.zero
	end
	local frequency = 22
	local maxAngle = math.rad(3.2)
	return Vector3.new(
		math.noise(shakeSeed, now * frequency) * maxAngle * intensity,
		math.noise(shakeSeed + 13.7, now * frequency) * maxAngle * intensity,
		math.noise(shakeSeed + 41.1, now * frequency) * maxAngle * 0.6 * intensity
	)
end

local function firstPerson(camera: Camera, dt: number, now: number)
	local body = bodyProvider()
	local root = body.root
	if not root then
		return
	end
	local base = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	local eye = base * body.eye
	lastAimOrigin = eye
	local y = eye.Y
	local current = smoothY
	if current and body.grounded and math.abs(current - y) < 2.5 then
		y = MathUtil.damp(current, y, 22, dt)
	end
	smoothY = y
	local video = SettingsController.get().Video
	local punchAngles = punch:step(dt)
	local shake = shakeAngles(now)
	local roll = math.rad(body.bobRoll * video.HeadBob + body.tilt)
	local aim = CFrame.new(eye.X, y, eye.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	camera.CFrame = aim
		* CFrame.new(body.bobOffset * video.HeadBob)
		* CFrame.Angles(
			math.rad(punchAngles.X) + shake.X,
			math.rad(punchAngles.Y) + shake.Y,
			roll + math.rad(punchAngles.Z) + shake.Z
		)
	local baseFov = video.Fov
	fovSpring.target = baseFov / zoom + fovKick
	camera.FieldOfView = math.clamp(fovSpring:step(dt) + popSpring:step(dt), 20, 110)
end

local thirdParams = RaycastParams.new()
thirdParams.FilterType = Enum.RaycastFilterType.Exclude

local function thirdPerson(camera: Camera, dt: number)
	local body = bodyProvider()
	local root = body.root
	if not root then
		return
	end
	local focus = root.Position + Vector3.new(0, 2.4, 0)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.clamp(pitch, -1.2, 1.1), 0, 0)
	local shoulder = rotation * Vector3.new(1.7, 0.4, 0)
	local backward = rotation * Vector3.new(0, 0, 1)
	local start = focus + shoulder
	thirdParams.FilterDescendantsInstances = if body.character then { body.character :: Instance } else {}
	local desired = 9
	local hit = Workspace:Spherecast(start, 0.6, backward * desired, thirdParams)
	local distance = if hit then math.max(hit.Distance - 0.2, 1.2) else desired
	if distance < thirdDistance.position then
		thirdDistance:snap(distance)
	else
		thirdDistance.target = distance
	end
	local d = thirdDistance:step(dt)
	camera.CFrame = CFrame.new(start + backward * d) * rotation
	fovSpring.target = 72
	camera.FieldOfView = fovSpring:step(dt)
	lastAimOrigin = camera.CFrame.Position
end

local function cinematicStep(camera: Camera)
	local current = cinematic
	if not current then
		return
	end
	local t = math.clamp((os.clock() - current.start) / current.duration, 0, 1)
	local frames = current.frames
	local segments = #frames - 1
	if segments <= 0 then
		camera.CFrame = frames[1]
	else
		local position = t * segments
		local index = math.min(math.floor(position) + 1, segments)
		local local_ = position - (index - 1)
		local eased = local_ * local_ * (3 - 2 * local_)
		camera.CFrame = frames[index]:Lerp(frames[index + 1], eased)
	end
	camera.FieldOfView = 60
	if t >= 1 then
		cinematic = nil
		if current.done then
			task.spawn(current.done)
		end
	end
end

local function spectateStep(camera: Camera, dt: number)
	local target = spectateTarget
	local character = target and target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (target and character and root and root:IsA("BasePart")) then
		return
	end
	local targetYaw, targetPitch = lookProvider(target)
	if targetYaw and targetPitch then
		spectateYaw = spectateYaw + MathUtil.wrapAngle(targetYaw - spectateYaw) * math.min(1, dt * 14)
		spectatePitch = MathUtil.damp(spectatePitch, targetPitch, 14, dt)
	end
	local stanceAttr = character:GetAttribute("Stance")
	local stance: Types.Stance = if stanceAttr == "Crouch"
		then "Crouch"
		elseif stanceAttr == "Slide" then "Slide"
		else "Stand"
	local leanAttr = character:GetAttribute("Lean")
	local lean = if type(leanAttr) == "number" then leanAttr else 0
	local base = CFrame.new(root.Position) * CFrame.Angles(0, spectateYaw, 0)
	local eye = base * Stances.eyeOffset(stance, lean)
	camera.CFrame = CFrame.new(eye) * CFrame.Angles(0, spectateYaw, 0) * CFrame.Angles(spectatePitch, 0, 0)
	camera.FieldOfView = SettingsController.get().Video.Fov
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local now = os.clock()
	trauma = math.max(0, trauma - dt * 1.8)
	if mode == "FirstPerson" or mode == "ThirdPerson" then
		readLook(dt)
	else
		InputController.consumeLook(dt)
	end
	if mode == "FirstPerson" then
		firstPerson(camera, dt, now)
	elseif mode == "ThirdPerson" then
		thirdPerson(camera, dt)
	elseif mode == "Cinematic" then
		cinematicStep(camera)
	elseif mode == "Spectate" then
		spectateStep(camera, dt)
	elseif mode == "Scripted" then
		local cframe = scriptedCFrame
		if cframe then
			camera.CFrame = cframe
			camera.FieldOfView = scriptedFov or 70
		end
	end
	-- Souris : verrouillée en jeu, libre dans les menus et sur mobile.
	local gameplay = (mode == "FirstPerson" or mode == "ThirdPerson") and not ClientState.menuOpen
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	else
		UserInputService.MouseBehavior = if gameplay then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = not gameplay
	end
end

function CameraController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		smoothY = nil
	end)
	RunService:BindToRenderStep("AS_Camera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
