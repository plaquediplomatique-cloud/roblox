--!strict
--[[
	Animate — animations de locomotion du personnage (remplace le script Roblox par défaut).

	Pourquoi un script maison : Roblox n'insère son « Animate » que si StarterCharacterScripts
	n'en contient pas. Une ancienne version vide restée dans la place (synchro Rojo, fichier
	.rbxl sauvegardé) bloquait donc toute animation : personnage « droit comme un piquet ».
	Ce script porte le même nom, il écrase l'ancien à chaque synchro et ne dépend plus de
	l'insertion automatique.

	Animations : celles du pack de l'avatar du joueur quand Roblox les a injectées sous ce
	script (valeurs `idle`, `walk`, `run`…, comme pour l'Animate officiel), sinon les
	animations R15 standard de Roblox. En combat, CharacterAnimator réécrit les articulations
	après l'animation (PreSimulation) : les deux systèmes ne se gênent pas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movement = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Movement"))

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart
local animator = (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")) :: Animator

-- Animations R15 standard de Roblox (repli quand l'avatar n'a pas de pack).
local DEFAULTS: { [string]: string } = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	climb = "rbxassetid://507765644",
	swim = "rbxassetid://913384386",
	swimidle = "rbxassetid://913389285",
}
local LOOPED: { [string]: boolean } = {
	idle = true,
	walk = true,
	run = true,
	fall = true,
	climb = true,
	swim = true,
	swimidle = true,
}
local FADE = 0.2
local WALK_REFERENCE = 9 -- vitesse (studs/s) à laquelle l'animation de marche est jouée à 1×
local RUN_REFERENCE = 16 -- idem pour la course

local tracks: { [string]: AnimationTrack } = {}
local current: string? = nil
local jumpUntil = 0

-- Identifiant fourni par le pack de l'avatar (StringValue `walk` > Animation), sinon défaut.
local function animationId(name: string): string
	local holder = script:FindFirstChild(name)
	if holder then
		local animation = holder:FindFirstChildOfClass("Animation")
		if animation and animation.AnimationId ~= "" then
			return animation.AnimationId
		end
	end
	return DEFAULTS[name]
end

local function loadTracks()
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(tracks)
	current = nil
	for name in DEFAULTS do
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId(name)
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = LOOPED[name] == true
			track.Priority = Enum.AnimationPriority.Core
			tracks[name] = track
		end
	end
end

local function play(name: string, speed: number)
	local track = tracks[name]
	if not track then
		return
	end
	if current ~= name then
		local previous = if current then tracks[current] else nil
		if previous then
			previous:Stop(FADE)
		end
		track:Play(FADE)
		current = name
	end
	track:AdjustSpeed(speed)
end

local function stopAll()
	for _, track in tracks do
		track:Stop(FADE)
	end
	current = nil
end

loadTracks()
-- Le pack d'animations de l'avatar peut arriver après le démarrage du script : Roblox
-- ajoute des valeurs (`walk` > Animation) ou modifie l'AnimationId d'animations existantes.
-- Les deux cas rechargent les pistes (regroupés en un seul rechargement).
local reloadQueued = false
local function queueReload()
	if reloadQueued then
		return
	end
	reloadQueued = true
	task.defer(function()
		reloadQueued = false
		loadTracks()
	end)
end
local function watch(instance: Instance)
	if instance:IsA("Animation") then
		instance:GetPropertyChangedSignal("AnimationId"):Connect(queueReload)
	end
end
for _, descendant in script:GetDescendants() do
	watch(descendant)
end
script.DescendantAdded:Connect(function(descendant: Instance)
	watch(descendant)
	queueReload()
end)

humanoid.StateChanged:Connect(function(_, new: Enum.HumanoidStateType)
	if new == Enum.HumanoidStateType.Jumping then
		jumpUntil = os.clock() + 0.3
		local jump = tracks.jump
		if jump then
			if current and current ~= "jump" and tracks[current] then
				tracks[current]:Stop(0.1)
			end
			jump:Play(0.1)
			current = "jump"
		end
	end
end)

local connection: RBXScriptConnection
connection = RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 or character.Parent == nil then
		stopAll()
		connection:Disconnect()
		return
	end
	local state = humanoid:GetState()
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if state == Enum.HumanoidStateType.Jumping or os.clock() < jumpUntil then
		return -- l'animation de saut joue jusqu'au bout de son élan
	elseif state == Enum.HumanoidStateType.Freefall then
		play("fall", 1)
	elseif state == Enum.HumanoidStateType.Climbing then
		play("climb", math.clamp(math.abs(velocity.Y) / 12, 0.2, 1.5))
	elseif state == Enum.HumanoidStateType.Swimming then
		if speed > 1 then
			play("swim", math.clamp(speed / 12, 0.5, 1.5))
		else
			play("swimidle", 1)
		end
	elseif state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.PlatformStanding then
		stopAll()
	elseif speed < 0.75 then
		play("idle", 1)
	elseif speed < (Movement.walkSpeed + Movement.runSpeed) / 2 then
		play("walk", math.clamp(speed / WALK_REFERENCE, 0.4, 1.6))
	else
		play("run", math.clamp(speed / RUN_REFERENCE, 0.6, 1.6))
	end
end)
