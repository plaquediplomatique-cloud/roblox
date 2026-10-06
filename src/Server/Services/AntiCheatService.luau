--!strict
--[[
	AntiCheatService — défense en profondeur côté serveur.

	Principe : le client possède la physique de son personnage (indispensable pour un
	mouvement réactif), donc le serveur VÉRIFIE au lieu de faire confiance.

	1. Mouvement (10 Hz par joueur, historique de 3 s) :
	   * burst     : déplacement horizontal sur 1 s ≤ vitesse max absolue (glissade) + marge
	   * soutenu   : moyenne sur 3 s ≤ vitesse de course max (bhop compris) + marge
	                 -> attrape les speedhacks "discrets" (×1.3–1.5) qu'un seuil instantané rate
	   * téléport  : saut de position impossible entre deux échantillons
	   * noclip    : rayon entre la dernière position valide et l'actuelle qui traverse
	                 une géométrie solide de la map
	   * fly       : >3 s sans sol sous les pieds sans chuter
	   Réponse : RUBBER-BAND immédiat vers la dernière position valide + signalement.
	2. Réseau : spam et paquets invalides remontés par ServerNet.
	3. Combat : origine de tir, cadence, spread, snaps de visée (remontés par CombatService).
	4. Pot de miel : le remote Admin/AdminCommand n'est appelé par aucun client légitime.

	Score de suspicion pondéré, décroissant dans le temps (pas de kick sur un lag isolé) :
	  ≥ 25 -> journal + analytics ;  ≥ 60 -> expulsion + drapeau persistant au profil.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Util.Logger)
local Movement = require(Shared.Config.Movement)
local Net = require(Shared.Net.Net)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)

local log = Logger.new("AntiCheat")

local SAMPLE_INTERVAL = 0.1
local HISTORY_SECONDS = 3
local BURST_MAX_SPEED = Movement.slide.speedCap * 1.15
-- Allure soutenue la plus rapide : sprint au sol ou course + élan aérien plafonné.
local SUSTAINED_MAX_SPEED = math.max(Movement.sprintSpeed, Movement.runSpeed * Movement.maxAirSpeedRatio) * 1.08 * 1.15
local TELEPORT_DISTANCE = 18
local MAX_UPWARD_SPEED = 55
local FLY_TIME = 3
local WARN_SCORE = 25
local KICK_SCORE = 60
local DECAY_PER_SECOND = 1 / 15

type Sample = { t: number, position: Vector3 }

type State = {
	samples: { Sample },
	lastValid: Vector3?,
	graceUntil: number,
	airSince: number?,
	score: number,
	lastDecay: number,
	warned: boolean,
	accumulator: number,
}

local AntiCheatService = {}

local states: { [Player]: State } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = {
			samples = {},
			lastValid = nil,
			graceUntil = os.clock() + 3,
			airSince = nil,
			score = 0,
			lastDecay = os.clock(),
			warned = false,
			accumulator = 0,
		}
		states[player] = state
	end
	return state
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

--[[ Signale une violation. `weight` : 0.5 (spam) … 100 (pot de miel). ]]
function AntiCheatService.flag(player: Player, reason: string, weight: number)
	if player.Parent ~= Players then
		return
	end
	local state = getState(player)
	state.score += weight
	log:debug(player.Name, "flag", reason, ("+%.1f -> %.1f"):format(weight, state.score))

	if state.score >= WARN_SCORE and not state.warned then
		state.warned = true
		log:warn("suspicion élevée", player.Name, player.UserId, reason, state.score)
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "AntiCheatWarning", state.score, { reason = reason })
		end)
	end

	if state.score >= KICK_SCORE then
		local data = DataService.getData(player)
		if data then
			data.Moderation.Suspicion += 1
			data.Moderation.Flags[reason] = (data.Moderation.Flags[reason] or 0) + 1
		end
		log:warn("expulsion", player.Name, player.UserId, reason)
		player:Kick("AETHER STRIKE — Activité anormale détectée (" .. reason .. ").")
	end
end

--[[ Les téléportations légitimes (spawn, changement d'arène) ouvrent une fenêtre de grâce. ]]
function AntiCheatService.allowTeleport(player: Player, duration: number?)
	local state = getState(player)
	state.graceUntil = os.clock() + (duration or 1.5)
	state.samples = {}
	state.lastValid = nil
	state.airSince = nil
end

function AntiCheatService.getScore(player: Player): number
	local state = states[player]
	return if state then state.score else 0
end

local function rubberBand(root: BasePart, target: Vector3)
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(target) * root.CFrame.Rotation
end

local function checkPlayer(player: Player, state: State, now: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		state.samples = {}
		state.lastValid = nil
		return
	end
	local position = root.Position
	if now < state.graceUntil then
		state.samples = { { t = now, position = position } }
		state.lastValid = position
		return
	end

	local samples = state.samples
	local previous = samples[#samples]
	table.insert(samples, { t = now, position = position })
	while #samples > 0 and now - samples[1].t > HISTORY_SECONDS do
		table.remove(samples, 1)
	end

	local violation: string? = nil
	local weight = 0

	if previous then
		local step = position - previous.position
		local flatStep = Vector3.new(step.X, 0, step.Z).Magnitude
		local dt = math.max(now - previous.t, 1 / 60)
		if flatStep > TELEPORT_DISTANCE + BURST_MAX_SPEED * dt then
			violation, weight = "Teleport", 8
		elseif step.Y / dt > MAX_UPWARD_SPEED then
			violation, weight = "VerticalSpeed", 5
		elseif flatStep > 2 and state.lastValid then
			-- Noclip : la ligne entre la dernière position valide et l'actuelle traverse-t-elle un mur ?
			rayParams.FilterDescendantsInstances = geometryRoots()
			local origin = state.lastValid + Vector3.new(0, 1, 0)
			local result = Workspace:Raycast(origin, (position + Vector3.new(0, 1, 0)) - origin, rayParams)
			if result and result.Instance.CanCollide and result.Instance.Transparency < 1 then
				violation, weight = "Noclip", 8
			end
		end
	end

	if not violation then
		-- Fenêtre burst (1 s) et fenêtre soutenue (3 s)
		local burstStart: Sample? = nil
		for _, sample in samples do
			if now - sample.t <= 1.05 then
				burstStart = sample
				break
			end
		end
		if burstStart and now - burstStart.t >= 0.5 then
			local d = position - burstStart.position
			local speed = Vector3.new(d.X, 0, d.Z).Magnitude / (now - burstStart.t)
			if speed > BURST_MAX_SPEED then
				violation, weight = "SpeedBurst", 4
			end
		end
		local oldest = samples[1]
		if not violation and oldest and now - oldest.t >= HISTORY_SECONDS - 0.2 then
			local d = position - oldest.position
			local speed = Vector3.new(d.X, 0, d.Z).Magnitude / (now - oldest.t)
			if speed > SUSTAINED_MAX_SPEED then
				violation, weight = "SpeedSustained", 5
			end
		end
	end

	-- Fly : pas de sol pendant longtemps sans tomber.
	if humanoid.FloorMaterial == Enum.Material.Air then
		state.airSince = state.airSince or now
		if now - (state.airSince :: number) > FLY_TIME and root.AssemblyLinearVelocity.Y > -4 then
			violation, weight = "Fly", 6
			state.airSince = now
		end
	else
		state.airSince = nil
	end

	if violation then
		if state.lastValid then
			rubberBand(root, state.lastValid)
		end
		state.samples = {}
		AntiCheatService.flag(player, violation, weight)
	else
		state.lastValid = position
	end
end

function AntiCheatService.Init()
	ServerNet.setViolationReporter(function(player: Player, reason: string, weight: number)
		AntiCheatService.flag(player, reason, weight)
	end)
end

function AntiCheatService.Start()
	-- Pot de miel : un client légitime n'appelle JAMAIS ce remote.
	Net.event("AdminCommand").OnServerEvent:Connect(function(player: Player)
		AntiCheatService.flag(player, "Honeypot", 100)
	end)

	Players.PlayerAdded:Connect(function(player)
		getState(player)
		player.CharacterAdded:Connect(function()
			AntiCheatService.allowTeleport(player, 3)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, state in states do
			-- Décroissance du score
			local elapsed = now - state.lastDecay
			state.lastDecay = now
			state.score = math.max(0, state.score - elapsed * DECAY_PER_SECOND)
			if state.score < WARN_SCORE * 0.5 then
				state.warned = false
			end
			state.accumulator += dt
			if state.accumulator >= SAMPLE_INTERVAL then
				state.accumulator = 0
				checkPlayer(player, state, now)
			end
		end
	end)
end

return AntiCheatService
