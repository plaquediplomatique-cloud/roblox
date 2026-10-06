--!strict
--[[
	TrainingRangeService — stand de tir vivant du hub.

	* Entrer dans la zone TrainingZone : contexte "Training", arme équipée (loadout du
	  profil, réserve infinie), caméra 1re personne côté client. En sortir : désarmé.
	* Bots STATIQUES par couloir (15 / 30 / 45 studs) : réglage du one-tap, lecture des
	  chutes de dégâts.
	* Bots MOBILES dans l'arène de tracking : patrouille par PathfindingService entre points
	  aléatoires + rafales de strafe gauche/droite + accroupissements aléatoires (ils
	  reproduisent les "jiggle peeks" d'un vrai joueur).
	* Les bots utilisent EXACTEMENT les mêmes hitboxes et la même compensation de latence
	  que les joueurs : ce qu'on apprend ici est transférable en match.
	* Statistiques de session répliquées (précision, headshots, dégâts, kills).
]]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Ballistics = require(Shared.Combat.Ballistics)
local Weapons = require(Shared.Config.Weapons)
local Logger = require(Shared.Util.Logger)
local Guard = require(Shared.Util.Guard)
local ServerRole = require(script.Parent.Parent.ServerRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local GameEvents = require(script.Parent.Parent.GameEvents)
local MapBuilder = require(script.Parent.Parent.Maps.MapBuilder)
local DataService = require(script.Parent.DataService)
local ArenaService = require(script.Parent.ArenaService)
local ReplicaService = require(script.Parent.ReplicaService)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local LagCompensationService = require(script.Parent.LagCompensationService)

local log = Logger.new("Training")

type Bot = {
	id: number,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	home: CFrame,
	pickHome: () -> CFrame, -- point de réapparition aléatoire (couloir ou zone de patrouille)
	kind: "Static" | "Strafe",
	zone: MapBuilder.Zone?,
	health: number,
	armor: number,
	alive: boolean,
	standHip: number,
}

local TrainingRangeService = {}

local RESPAWN_DELAY = 0.6 -- s entre la mort d'un bot et sa réapparition ailleurs
local STATIC_DEPTH_JITTER = 5 -- ± studs autour du palier de distance
local STATIC_LATERAL = 3.5 -- ± studs de décalage latéral dans le couloir

local bots: { [number]: Bot } = {}
local botFolder: Folder
local trainingZone: BasePart? = nil
local nextBotId = -1
local armorEnabled = true
local stats: { [Player]: ReplicaService.Replica } = {}

local function inZone(part: BasePart, position: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y + 6
		and math.abs(localPoint.Z) <= half.Z
end

---------------------------------------------------------------------------------------------
-- Bots
---------------------------------------------------------------------------------------------

local function styleBot(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = Color3.fromRGB(70, 28, 34)
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.CollisionGroup = "Players"
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local visor = Instance.new("Part")
		visor.Name = "Gear_Visor"
		visor.Size = Vector3.new(1.1, 0.22, 0.12)
		visor.Material = Enum.Material.Neon
		visor.Color = Color3.fromRGB(255, 70, 85)
		visor.CanCollide = false
		visor.CanQuery = false
		visor.Massless = true
		visor.CFrame = head.CFrame * CFrame.new(0, 0.08, -0.6)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = visor
		weld.Parent = visor
		visor.Parent = model
	end
end

local function resetBot(bot: Bot)
	bot.health = Ballistics.MAX_HEALTH
	bot.armor = if armorEnabled then Ballistics.MAX_ARMOR else 0
	bot.alive = true
	bot.humanoid.Health = bot.health
	bot.model:SetAttribute("Armor", bot.armor)
	bot.model:SetAttribute("Alive", true)
	bot.model:SetAttribute("Stance", "Stand")
	bot.humanoid.HipHeight = bot.standHip
	bot.home = bot.pickHome()
	bot.model:PivotTo(bot.home)
	for _, descendant in bot.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.Transparency = 0
		end
	end
end

local function damageBot(bot: Bot, amount: number): LagCompensationService.DamageResult
	if not bot.alive then
		return { killed = false, health = 0, armor = 0, healthLoss = 0, armorLoss = 0 }
	end
	local health, armor, healthLoss, armorLoss = Ballistics.apply(bot.health, bot.armor, amount)
	bot.health, bot.armor = health, armor
	bot.humanoid.Health = math.max(health, 0)
	bot.model:SetAttribute("Armor", armor)
	if health <= 0.5 then
		bot.alive = false
		bot.model:SetAttribute("Alive", false)
		-- Disparition immédiate : invisible et sorti du stand dans la même frame (aucun corps
		-- qui traîne), puis réapparition ailleurs, au hasard, juste après.
		for _, descendant in bot.model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 1
			end
		end
		bot.model:PivotTo(bot.home + Vector3.new(0, -200, 0))
		task.delay(RESPAWN_DELAY, function()
			if bots[bot.id] == bot then
				resetBot(bot)
			end
		end)
		return { killed = true, health = 0, armor = armor, healthLoss = healthLoss, armorLoss = armorLoss }
	end
	return { killed = false, health = health, armor = armor, healthLoss = healthLoss, armorLoss = armorLoss }
end

local function createBot(pickHome: () -> CFrame, kind: "Static" | "Strafe", zone: MapBuilder.Zone?)
	local home = pickHome()
	local description = Instance.new("HumanoidDescription")
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		log:warn("bot creation failed", model)
		return
	end
	local botModel = model :: Model
	local humanoid = botModel:FindFirstChildOfClass("Humanoid")
	local root = botModel:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		botModel:Destroy()
		return
	end
	botModel.Name = "TrainingBot"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = Ballistics.MAX_HEALTH
	humanoid.WalkSpeed = 14
	styleBot(botModel)
	root.Anchored = kind == "Static"
	botModel:AddTag("TrainingBot")
	botModel.Parent = botFolder

	local id = nextBotId
	nextBotId -= 1
	local bot: Bot = {
		id = id,
		model = botModel,
		humanoid = humanoid,
		root = root,
		home = home,
		pickHome = pickHome,
		kind = kind,
		zone = zone,
		health = Ballistics.MAX_HEALTH,
		armor = Ballistics.MAX_ARMOR,
		alive = true,
		standHip = humanoid.HipHeight,
	}
	bots[id] = bot
	resetBot(bot)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	LagCompensationService.register({
		id = id,
		kind = "Bot",
		player = nil,
		model = botModel,
		root = root,
		arena = "Training",
		team = function(): string
			return "Bots"
		end,
		alive = function(): boolean
			return bot.alive
		end,
		stance = function(): Types.Stance
			local stance = botModel:GetAttribute("Stance")
			return if stance == "Crouch" then "Crouch" else "Stand"
		end,
		lean = function(): number
			return 0
		end,
		receive = function(
			amount: number,
			_info: LagCompensationService.DamageInfo
		): LagCompensationService.DamageResult
			return damageBot(bot, amount)
		end,
	})

	if kind == "Strafe" and zone then
		task.spawn(function()
			local rng = Random.new()
			while bots[id] == bot do
				if bot.alive then
					-- Patrouille : chemin calculé vers un point aléatoire de la zone.
					local half = zone.size * 0.5
					local goal = zone.cframe
						* Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))
					local path =
						PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false })
					local computed = pcall(function()
						path:ComputeAsync(root.Position, goal)
					end)
					if computed and path.Status == Enum.PathStatus.Success then
						for _, waypoint in path:GetWaypoints() do
							if not bot.alive or bots[id] ~= bot then
								break
							end
							humanoid:MoveTo(waypoint.Position)
							-- Rafales de strafe pendant le déplacement
							local deadline = os.clock() + 1.2
							while os.clock() < deadline and (root.Position - waypoint.Position).Magnitude > 2.5 do
								if rng:NextNumber() < 0.25 then
									local side = root.CFrame.RightVector * (if rng:NextNumber() < 0.5 then -1 else 1)
									humanoid:Move(side, false)
								end
								if rng:NextNumber() < 0.06 then
									botModel:SetAttribute("Stance", "Crouch")
									humanoid.HipHeight = bot.standHip - 1.4
									task.wait(0.5)
									botModel:SetAttribute("Stance", "Stand")
									humanoid.HipHeight = bot.standHip
								end
								task.wait(rng:NextNumber(0.15, 0.4))
							end
						end
					end
					task.wait(rng:NextNumber(0.2, 0.8))
				else
					task.wait(0.5)
				end
			end
		end)
	end
end

local function spawnBots()
	local rng = Random.new()
	for _, anchor in CollectionService:GetTagged("BotAnchor") do
		if not (anchor:IsA("BasePart") and anchor:IsDescendantOf(Workspace:FindFirstChild("Hub") :: Instance)) then
			continue
		end
		local kind = anchor:GetAttribute("Kind")
		if kind == "Static" then
			-- Cibles fixes : une par palier de distance, chacune réapparaît dans sa tranche
			-- (proche / moyenne / loin) à une profondeur et une position latérale aléatoires.
			local distances = tostring(anchor:GetAttribute("Distances") or "15,30,45")
			local tiers: { number } = {}
			for token in string.gmatch(distances, "%d+") do
				table.insert(tiers, tonumber(token) or 15)
			end
			for _, distance in tiers do
				local function pickHome(): CFrame
					local depth = distance + rng:NextNumber(-STATIC_DEPTH_JITTER, STATIC_DEPTH_JITTER)
					local lateral = rng:NextNumber(-STATIC_LATERAL, STATIC_LATERAL)
					local position = Vector3.new(-49 - depth, 3, anchor.Position.Z + lateral)
					return CFrame.lookAt(position, position + Vector3.new(1, 0, 0))
				end
				task.spawn(function()
					createBot(pickHome, "Static", nil)
				end)
			end
		elseif kind == "Strafe" then
			local zone: MapBuilder.Zone = { name = "Strafe", cframe = anchor.CFrame, size = anchor.Size }
			local function pickHome(): CFrame
				local half = zone.size * 0.5 - Vector3.new(2, 0, 2)
				local point = zone.cframe
					* Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))
				local position = Vector3.new(point.X, anchor.Position.Y + 3, point.Z)
				return CFrame.lookAt(position, position + Vector3.new(1, 0, 0))
			end
			for _ = 1, 3 do
				task.spawn(function()
					createBot(pickHome, "Strafe", zone)
				end)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Zone et statistiques
---------------------------------------------------------------------------------------------

local function statsReplica(player: Player): ReplicaService.Replica
	local replica = stats[player]
	if not replica then
		replica = ReplicaService.new({
			token = "TrainingStats",
			data = { shots = 0, hits = 0, headshots = 0, kills = 0, damage = 0, armor = armorEnabled },
			replicateTo = { player },
		})
		stats[player] = replica
	end
	return replica
end

local function enterTraining(player: Player)
	ArenaService.set(player, "Training")
	local data = DataService.getData(player)
	local loadout = if data then data.Loadout else Weapons.DEFAULT_LOADOUT
	CombatService.arm(player, { Primary = loadout.Primary, Secondary = loadout.Secondary, Melee = loadout.Melee }, true)
	statsReplica(player)
end

local function leaveTraining(player: Player)
	ArenaService.set(player, "Hub")
	CombatService.disarm(player)
end

function TrainingRangeService.Init() end

function TrainingRangeService.Start()
	if not ServerRole.isLobby() then
		return
	end
	botFolder = Instance.new("Folder")
	botFolder.Name = "Bots"
	botFolder.Parent = Workspace:WaitForChild("Hub")
	for _, part in CollectionService:GetTagged("TrainingZone") do
		if part:IsA("BasePart") then
			trainingZone = part
		end
	end
	task.spawn(spawnBots)

	-- Détection d'entrée / sortie de zone (4 Hz)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0
		local zone = trainingZone
		if not zone then
			return
		end
		for _, player in Players:GetPlayers() do
			local kind = ArenaService.get(player)
			if kind ~= "Hub" and kind ~= "Training" then
				continue
			end
			local _, _, root = CharacterService.getCharacter(player)
			if not root or not CharacterService.isAlive(player) then
				continue
			end
			local inside = inZone(zone, root.Position)
			if inside and kind == "Hub" then
				enterTraining(player)
			elseif not inside and kind == "Training" then
				leaveTraining(player)
			end
		end
	end)

	GameEvents.ShotFired:Connect(function(player: Player, _weapon: string, _count: number)
		if ArenaService.get(player) == "Training" then
			statsReplica(player):Increment({ "shots" }, 1)
		end
	end)
	GameEvents.TrainingHit:Connect(function(info: GameEvents.TrainingHitInfo)
		local replica = statsReplica(info.player)
		replica:Increment({ "hits" }, 1)
		if info.headshot then
			replica:Increment({ "headshots" }, 1)
		end
		if info.killed then
			replica:Increment({ "kills" }, 1)
		end
	end)
	GameEvents.Damage:Connect(function(info: GameEvents.DamageInfo)
		if info.victimBotId and info.attacker then
			statsReplica(info.attacker):Increment({ "damage" }, math.floor(info.amount + 0.5))
		end
	end)

	ServerNet.onInvoke("TrainingAction", { capacity = 6, refill = 2 }, function(payload: any): { action: string }?
		local valid = Guard.shape({ action = Guard.oneOf({ "ResetStats", "ToggleArmor", "Refill" }) })
		return if valid(payload) then payload :: { action: string } else nil
	end, function(player: Player, payload: { action: string }): ServerNet.Response
		if payload.action == "ResetStats" then
			local replica = statsReplica(player)
			replica:SetValues({}, { shots = 0, hits = 0, headshots = 0, kills = 0, damage = 0 })
		elseif payload.action == "ToggleArmor" then
			armorEnabled = not armorEnabled
			for _, bot in bots do
				if bot.alive then
					resetBot(bot)
				end
			end
			for _, replica in stats do
				replica:Set({ "armor" }, armorEnabled)
			end
		elseif payload.action == "Refill" then
			if ArenaService.get(player) == "Training" then
				enterTraining(player)
			end
		end
		return ServerNet.success()
	end)

	Players.PlayerRemoving:Connect(function(player)
		local replica = stats[player]
		if replica then
			replica:Destroy()
			stats[player] = nil
		end
	end)
end

return TrainingRangeService
