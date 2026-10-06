--!strict
--[[
	SwingAnimator — animation PROCÉDURALE de frappe pour tous les personnages (aucun asset).

	Chaque client anime tous les joueurs : la pose « garde » dès qu'une arme est équipée
	(attribut `Weapon` posé par le serveur), puis une frappe selon le style de l'arme (`Swing`).
	On joue sur les `C0` des joints (épaule droite, taille, racine) : l'Animator de Roblox écrit
	dans `Transform`, il n'y a donc aucun conflit avec les animations de marche.
	La boucle Heartbeat n'existe que pendant qu'au moins une frappe est en cours.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local SwingPose = require(Shared.Rules.SwingPose)

local SwingAnimator = {}

type Rig = {
	Character: Model,
	Shoulder: Motor6D,
	Waist: Motor6D?,
	Root: Motor6D?,
	BaseShoulder: CFrame,
	BaseWaist: CFrame,
	BaseRoot: CFrame,
	Armed: boolean,
	Active: boolean,
	T: number,
	Duration: number,
	Style: string,
	ImpactDone: boolean,
	OnImpact: (() -> ())?,
	Trail: Trail?,
}

local rigs: { [Model]: Rig } = {}
local loop: RBXScriptConnection? = nil
local activeCount = 0

local function applyPose(rig: Rig, pose: SwingPose.Pose)
	rig.Shoulder.C0 = rig.BaseShoulder * CFrame.Angles(0, pose.Yaw, 0) * CFrame.Angles(pose.Shoulder, 0, 0)
	local waist = rig.Waist
	if waist then
		waist.C0 = rig.BaseWaist * CFrame.Angles(0, pose.Torso, 0)
	end
	local root = rig.Root
	if root then
		root.C0 = rig.BaseRoot * CFrame.new(0, 0, -pose.Lunge)
	end
end

local function restore(rig: Rig)
	rig.Shoulder.C0 = rig.BaseShoulder
	if rig.Waist then
		rig.Waist.C0 = rig.BaseWaist
	end
	if rig.Root then
		rig.Root.C0 = rig.BaseRoot
	end
end

local function setTrail(rig: Rig, enabled: boolean)
	local model = rig.Character:FindFirstChild("WeaponModel")
	local handle = model and model:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = enabled
	end
end

local function stopLoopIfIdle()
	if activeCount <= 0 and loop then
		loop:Disconnect()
		loop = nil
		activeCount = 0
	end
end

local function step(dt: number)
	for character, rig in rigs do
		if not character.Parent then
			rigs[character] = nil
			if rig.Active then
				activeCount -= 1
			end
		elseif rig.Active then
			rig.T += dt / rig.Duration
			if rig.T >= SwingPose.ImpactTime and not rig.ImpactDone then
				rig.ImpactDone = true
				local callback = rig.OnImpact
				if callback then
					callback()
				end
			end
			if rig.T >= 0.12 and rig.T < 0.62 then
				setTrail(rig, true)
			end
			if rig.T >= 1 then
				rig.Active = false
				activeCount -= 1
				setTrail(rig, false)
				applyPose(rig, SwingPose.ready())
			else
				applyPose(rig, SwingPose.sample(rig.Style, rig.T))
			end
		end
	end
	stopLoopIfIdle()
end

local function ensureLoop()
	if not loop then
		loop = RunService.Heartbeat:Connect(step)
	end
end

local function buildRig(character: Model): Rig?
	local upperArm = character:WaitForChild("RightUpperArm", 10)
	if not upperArm then
		return nil
	end
	local shoulder = upperArm:FindFirstChild("RightShoulder")
	if not shoulder or not shoulder:IsA("Motor6D") then
		return nil -- R6 : pas d'animation de bras
	end
	local upperTorso = character:FindFirstChild("UpperTorso")
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	local root = lowerTorso and lowerTorso:FindFirstChild("Root")
	local rig: Rig = {
		Character = character,
		Shoulder = shoulder,
		Waist = if waist and waist:IsA("Motor6D") then waist else nil,
		Root = if root and root:IsA("Motor6D") then root else nil,
		BaseShoulder = shoulder.C0,
		BaseWaist = if waist and waist:IsA("Motor6D") then waist.C0 else CFrame.identity,
		BaseRoot = if root and root:IsA("Motor6D") then root.C0 else CFrame.identity,
		Armed = false,
		Active = false,
		T = 0,
		Duration = 0.35,
		Style = "Overhead",
		ImpactDone = false,
		OnImpact = nil,
		Trail = nil,
	}
	return rig
end

local function refreshArmed(rig: Rig)
	local armed = rig.Character:GetAttribute("Weapon") ~= nil
	if armed ~= rig.Armed then
		rig.Armed = armed
		if armed then
			applyPose(rig, SwingPose.ready())
		else
			restore(rig)
		end
	end
	local style = rig.Character:GetAttribute("Swing")
	if type(style) == "string" then
		rig.Style = style
	end
end

local function track(character: Model)
	task.spawn(function()
		local rig = buildRig(character)
		if not rig then
			return
		end
		rigs[character] = rig
		refreshArmed(rig)
		character:GetAttributeChangedSignal("Weapon"):Connect(function()
			refreshArmed(rig)
		end)
		character:GetAttributeChangedSignal("Swing"):Connect(function()
			refreshArmed(rig)
		end)
	end)
end

function SwingAnimator.start()
	local function watch(player: Player)
		if player.Character then
			track(player.Character)
		end
		player.CharacterAdded:Connect(track)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

-- Durée visuelle d'une frappe pour un intervalle de cadence donné.
function SwingAnimator.duration(interval: number): number
	return math.clamp(interval * 0.9, 0.26, 0.55)
end

-- Lance une frappe. `onImpact` est appelé à l'instant du contact (pour caler VFX/sons).
function SwingAnimator.play(character: Model, duration: number, onImpact: (() -> ())?)
	local rig = rigs[character]
	if not rig or not rig.Armed then
		if onImpact then
			task.delay(duration * SwingPose.ImpactTime, onImpact)
		end
		return
	end
	if not rig.Active then
		activeCount += 1
	end
	rig.Active = true
	rig.T = 0
	rig.Duration = duration
	rig.ImpactDone = false
	rig.OnImpact = onImpact
	ensureLoop()
end

return SwingAnimator
