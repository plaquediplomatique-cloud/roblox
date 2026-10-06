--!strict
--[[
	CharacterService — personnages, santé, posture, visée répliquée.

	* Spawn avec l'AVATAR ROBLOX du joueur (son apparence, ses vêtements, ses accessoires),
	  à échelles fixes : les hitboxes (Shared/Combat/Hitbox) sont indépendantes de
	  l'avatar, la silhouette reste donc dans leur enveloppe. En match, les gros accessoires
	  (dos, taille, épaules, devant, objets surdimensionnés) sont retirés : rien ne dépasse
	  d'un couvert ni ne trompe la visée. Tenue d'opérateur (cosmétique) : équipement
	  procédural par-dessus l'avatar ; avatar indisponible : silhouette aux couleurs de la tenue.
	* PV et bouclier AUTORITAIRES : seul le serveur les modifie (Humanoid.Health et
	  attribut "Armor"), via Ballistics.apply. Journal de dégâts -> assists.
	* Mort : ragdoll serveur, désenregistrement des hitboxes, signal Died.
	* Posture (Stance/Lean/ADS) : reçue du client, validée, publiée en attributs
	  (hitboxes serveur + pose 3e personne chez les autres clients).
	* Visée : yaw/pitch reçus en binaire (LookCodec, ~30 Hz), stockés pour l'anti-cheat
	  et la killcam, rediffusés en un paquet binaire unique par arène à 20 Hz.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Logger = require(Shared.Util.Logger)
local Guard = require(Shared.Util.Guard)
local Net = require(Shared.Net.Net)
local LookCodec = require(Shared.Net.LookCodec)
local Ballistics = require(Shared.Combat.Ballistics)
local Stances = require(Shared.Combat.Stances)
local Movement = require(Shared.Config.Movement)
local Cosmetics = require(Shared.Config.Cosmetics)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local OperatorGear = require(script.Parent.Parent.Character.OperatorGear)
local AvatarRules = require(Shared.Rules.AvatarRules)
local Ragdoll = require(script.Parent.Parent.Character.Ragdoll)
local DataService = require(script.Parent.DataService)
local ArenaService = require(script.Parent.ArenaService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local LagCompensationService = require(script.Parent.LagCompensationService)

local log = Logger.new("Character")

export type SpawnOptions = {
	arenaKind: Types.ArenaKind,
	arenaId: string,
	team: string?,
	side: string?,
	shields: number,
}

export type DeathInfo = {
	attacker: Player?,
	weaponId: string,
	zone: Types.HitZone,
	wallbang: boolean,
	distance: number,
	backstab: boolean,
	fall: boolean,
}

type DamageEntry = { attacker: Player, amount: number, t: number }
type LookState =
	{ yaw: number, pitch: number, t: number, previousYaw: number, previousPitch: number, previousT: number }

local CharacterService = {
	Spawned = Signal.new() :: Signal.Signal<Player, Model>,
	Died = Signal.new() :: Signal.Signal<Player, Model, DeathInfo>,
}

local damageLogs: { [Player]: { DamageEntry } } = {}
local looks: { [Player]: LookState } = {}
local lookHistories: { [Player]: { { t: number, yaw: number, pitch: number } } } = {}
local slots: { [number]: Player? } = {}
local spawning: { [Player]: boolean } = {}

local ASSIST_WINDOW = 8
local ASSIST_MIN_DAMAGE = 25
local KILL_Y = -60

---------------------------------------------------------------------------------------------
-- Accès
---------------------------------------------------------------------------------------------

function CharacterService.getCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return character, nil, nil
end

function CharacterService.isAlive(player: Player): boolean
	local character, humanoid = CharacterService.getCharacter(player)
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0 and character:GetAttribute("Alive") == true
end

function CharacterService.stanceOf(character: Model): Types.Stance
	local stance = character:GetAttribute("Stance")
	if stance == "Crouch" or stance == "Slide" then
		return stance
	end
	return "Stand"
end

function CharacterService.leanOf(character: Model): number
	local lean = character:GetAttribute("Lean")
	return if type(lean) == "number" then math.clamp(lean, -1, 1) else 0
end

--[[ Position serveur de l'oeil (validation de l'origine des tirs). ]]
function CharacterService.eyePosition(player: Player): Vector3?
	local character, _, root = CharacterService.getCharacter(player)
	if not (character and root) then
		return nil
	end
	return Stances.eyePosition(root.CFrame, CharacterService.stanceOf(character), CharacterService.leanOf(character))
end

function CharacterService.getLook(player: Player): LookState?
	return looks[player]
end

--[[ Historique de visée [from, to] (killcam). Échantillonné à la réception (~30 Hz). ]]
function CharacterService.lookHistory(
	player: Player,
	from: number,
	to: number
): { { t: number, yaw: number, pitch: number } }
	local list = {}
	local source: { { t: number, yaw: number, pitch: number } } = lookHistories[player] or {}
	for _, sample in source do
		if sample.t >= from and sample.t <= to then
			table.insert(list, sample)
		end
	end
	return list
end

function CharacterService.health(player: Player): (number, number)
	local character, humanoid = CharacterService.getCharacter(player)
	if not (character and humanoid) then
		return 0, 0
	end
	local armor = character:GetAttribute("Armor")
	return humanoid.Health, if type(armor) == "number" then armor else 0
end

---------------------------------------------------------------------------------------------
-- Spawn
---------------------------------------------------------------------------------------------

local avatarCache: { [number]: HumanoidDescription } = {}

--[[
	Apparence Roblox du joueur, récupérée une fois par session. Échec (service
	indisponible, comptes de test Studio à identifiant négatif) : nil.
]]
local function avatarDescription(player: Player): HumanoidDescription?
	local cached = avatarCache[player.UserId]
	if cached then
		return cached:Clone()
	end
	if player.UserId <= 0 then
		return nil
	end
	local ok, result = pcall(function(): HumanoidDescription
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)
	if not ok then
		log:warn("avatar indisponible", player.Name, result)
		return nil
	end
	avatarCache[player.UserId] = result
	return result:Clone()
end

local function buildDescription(
	player: Player,
	arenaKind: Types.ArenaKind
): (HumanoidDescription, Types.ItemDef?, boolean)
	local data = DataService.getData(player)
	local operator = Cosmetics.get(if data then data.Cosmetics.Operator else "op_standard")
		or Cosmetics.get("op_standard")
	local avatar = avatarDescription(player)
	local description: HumanoidDescription
	if avatar then
		description = avatar
		if arenaKind ~= "Hub" then
			for _, field in AvatarRules.MATCH_REMOVED_SLOTS do
				(description :: any)[field] = ""
			end
		end
	else
		description = Instance.new("HumanoidDescription")
		if operator and operator.palette then
			OperatorGear.bodyColors(description, operator.palette)
		end
	end
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	return description, operator, avatar ~= nil
end

--[[ Accessoires : jamais de collision ni de requête ; en combat, les surdimensionnés partent. ]]
local function sanitizeAccessories(character: Model, combat: boolean, removeHeadwear: boolean)
	for _, child in character:GetChildren() do
		if not child:IsA("Accessory") then
			continue
		end
		local handle = child:FindFirstChild("Handle")
		local size = if handle and handle:IsA("BasePart") then handle.Size else Vector3.zero
		local headwear = child.AccessoryType == Enum.AccessoryType.Hat or child.AccessoryType == Enum.AccessoryType.Hair
		if (combat and AvatarRules.oversized(size)) or (removeHeadwear and headwear) then
			child:Destroy()
			continue
		end
		for _, descendant in child:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Massless = true
			end
		end
	end
end

local function setCollisionGroup(character: Model, group: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function registerTarget(player: Player, character: Model, root: BasePart, humanoid: Humanoid, arenaId: string)
	LagCompensationService.register({
		id = player.UserId,
		kind = "Player",
		player = player,
		model = character,
		root = root,
		arena = arenaId,
		team = function(): string
			local team = character:GetAttribute("Team")
			return if type(team) == "string" then team else ""
		end,
		alive = function(): boolean
			return humanoid.Health > 0 and character:GetAttribute("Alive") == true
		end,
		stance = function(): Types.Stance
			return CharacterService.stanceOf(character)
		end,
		lean = function(): number
			return CharacterService.leanOf(character)
		end,
		receive = function(
			amount: number,
			info: LagCompensationService.DamageInfo
		): LagCompensationService.DamageResult
			return CharacterService.applyDamage(player, amount, info)
		end,
	})
end

--[[ Fait (ré)apparaître un joueur. Bloquant (chargement du personnage). ]]
function CharacterService.spawn(player: Player, cframe: CFrame, options: SpawnOptions): Model?
	if spawning[player] then
		return nil
	end
	spawning[player] = true
	local description, operator, ownAvatar = buildDescription(player, options.arenaKind)
	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescriptionAsync(description)
	end)
	spawning[player] = nil
	if not ok then
		log:warn("spawn failed", player.Name, err)
		return nil
	end
	local character, humanoid, root = CharacterService.getCharacter(player)
	if not (character and humanoid and root) then
		return nil
	end

	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = Ballistics.MAX_HEALTH
	humanoid.Health = Ballistics.MAX_HEALTH
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Movement.jumpHeight
	humanoid.WalkSpeed = Movement.runSpeed
	humanoid.RequiresNeck = false

	character:SetAttribute("Armor", options.shields)
	character:SetAttribute("MaxArmor", Ballistics.MAX_ARMOR)
	character:SetAttribute("Stance", "Stand")
	character:SetAttribute("Lean", 0)
	character:SetAttribute("Ads", false)
	character:SetAttribute("Walking", false)
	character:SetAttribute("Sprinting", false)
	character:SetAttribute("Alive", true)
	character:SetAttribute("Team", options.team or "")
	character:SetAttribute("Side", options.side or "")
	character:SetAttribute("StandHipHeight", humanoid.HipHeight)
	character:SetAttribute("ArenaKind", options.arenaKind)
	character:AddTag("Combatant")

	-- Tenue d'opérateur : par-dessus l'avatar seulement si le joueur en a équipé une (le
	-- casque remplace alors chapeaux et cheveux) ; sans avatar, elle habille la silhouette.
	local wearsGear = operator ~= nil and (not ownAvatar or operator.id ~= AvatarRules.DEFAULT_OPERATOR)
	sanitizeAccessories(character, options.arenaKind ~= "Hub", wearsGear)
	if wearsGear then
		OperatorGear.attach(character, operator)
	end
	setCollisionGroup(character, "Players")
	AntiCheatService.allowTeleport(player, 3)
	character:PivotTo(cframe)
	damageLogs[player] = {}
	registerTarget(player, character, root, humanoid, options.arenaId)

	humanoid.Died:Connect(function()
		character:SetAttribute("Alive", false)
	end)

	CharacterService.Spawned:Fire(player, character)
	return character
end

---------------------------------------------------------------------------------------------
-- Dégâts / mort
---------------------------------------------------------------------------------------------

function CharacterService.applyDamage(
	player: Player,
	amount: number,
	info: LagCompensationService.DamageInfo
): LagCompensationService.DamageResult
	local character, humanoid = CharacterService.getCharacter(player)
	if not (character and humanoid) or not CharacterService.isAlive(player) then
		return { killed = false, health = 0, armor = 0, healthLoss = 0, armorLoss = 0 }
	end
	local health, armor = CharacterService.health(player)
	local newHealth, newArmor, healthLoss, armorLoss = Ballistics.apply(health, armor, amount)
	character:SetAttribute("Armor", newArmor)
	character:SetAttribute("TaggedUntil", Workspace:GetServerTimeNow() + Movement.tagging.duration)
	if info.attacker and info.attacker ~= player then
		local log_ = damageLogs[player] or {}
		table.insert(log_, { attacker = info.attacker, amount = healthLoss + armorLoss, t = os.clock() })
		damageLogs[player] = log_
	end
	if newHealth <= 0.5 then
		humanoid.Health = 0
		CharacterService.kill(player, {
			attacker = info.attacker,
			weaponId = info.weaponId,
			zone = info.zone,
			wallbang = info.wallbang,
			distance = info.distance,
			backstab = info.backstab == true,
			fall = false,
		})
		return { killed = true, health = 0, armor = newArmor, healthLoss = healthLoss, armorLoss = armorLoss }
	end
	humanoid.Health = newHealth
	return { killed = false, health = newHealth, armor = newArmor, healthLoss = healthLoss, armorLoss = armorLoss }
end

--[[ Joueurs ayant infligé ≥ 25 dégâts dans les 8 dernières secondes (hors tueur). ]]
function CharacterService.assisters(victim: Player, killer: Player?): { Player }
	local totals: { [Player]: number } = {}
	local now = os.clock()
	local entries: { DamageEntry } = damageLogs[victim] or {}
	for _, entry in entries do
		if now - entry.t <= ASSIST_WINDOW and entry.attacker ~= killer and entry.attacker.Parent then
			totals[entry.attacker] = (totals[entry.attacker] or 0) + entry.amount
		end
	end
	local list = {}
	for attacker, total in totals do
		if total >= ASSIST_MIN_DAMAGE then
			table.insert(list, attacker)
		end
	end
	return list
end

function CharacterService.kill(player: Player, info: DeathInfo)
	local character, humanoid = CharacterService.getCharacter(player)
	if not (character and humanoid) or character:GetAttribute("Alive") ~= true then
		return
	end
	character:SetAttribute("Alive", false)
	humanoid.Health = 0
	Ragdoll.apply(character)
	CharacterService.Died:Fire(player, character, info)
end

--[[ Retire le personnage (fin de manche, retour au hub). ]]
function CharacterService.despawn(player: Player)
	local character = player.Character
	if character then
		LagCompensationService.unregister(player.UserId)
		character:Destroy()
	end
	player.Character = nil
end

---------------------------------------------------------------------------------------------
-- Réseau : posture et visée
---------------------------------------------------------------------------------------------

local isStance = Guard.shape({
	stance = Guard.oneOf({ "Stand", "Crouch", "Slide" }),
	lean = Guard.integer(-1, 1),
	ads = Guard.boolean,
	walking = Guard.boolean,
	sprinting = Guard.boolean,
})

local function parseStance(packet: any): Types.StancePacket?
	return if isStance(packet) then packet :: Types.StancePacket else nil
end

local function assignSlot(player: Player)
	for slot = 1, 255 do
		if slots[slot] == nil then
			slots[slot] = player
			player:SetAttribute("NetSlot", slot)
			return
		end
	end
end

local function releaseSlot(player: Player)
	local slot = player:GetAttribute("NetSlot")
	if type(slot) == "number" and slots[slot] == player then
		slots[slot] = nil
	end
end

local function broadcastLooks()
	local byArena: { [string]: { LookCodec.Entry } } = {}
	local members: { [string]: { Player } } = {}
	for player, look in looks do
		if player.Parent == nil then
			continue
		end
		local arena = ArenaService.idOf(player)
		local list = members[arena] or {}
		table.insert(list, player)
		members[arena] = list
		local slot = player:GetAttribute("NetSlot")
		if type(slot) == "number" and CharacterService.isAlive(player) then
			local entries = byArena[arena] or {}
			table.insert(entries, { slot = slot, yaw = look.yaw, pitch = look.pitch })
			byArena[arena] = entries
		end
	end
	local remote = Net.unreliable("LookBatch")
	for arena, entries in byArena do
		local payload = LookCodec.encodeBatch(entries)
		local recipients: { Player } = members[arena] or {}
		for _, player in recipients do
			remote:FireClient(player, payload)
		end
	end
end

function CharacterService.Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Players")
		PhysicsService:RegisterCollisionGroup("Ragdoll")
		PhysicsService:RegisterCollisionGroup("Effects")
		PhysicsService:CollisionGroupSetCollidable("Ragdoll", "Players", false)
		PhysicsService:CollisionGroupSetCollidable("Ragdoll", "Ragdoll", false)
		PhysicsService:CollisionGroupSetCollidable("Effects", "Players", false)
		PhysicsService:CollisionGroupSetCollidable("Effects", "Ragdoll", false)
		PhysicsService:CollisionGroupSetCollidable("Effects", "Effects", false)
	end)
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(assignSlot)
	for _, player in Players:GetPlayers() do
		assignSlot(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		releaseSlot(player)
		looks[player] = nil
		lookHistories[player] = nil
		avatarCache[player.UserId] = nil
		damageLogs[player] = nil
		spawning[player] = nil
		LagCompensationService.unregister(player.UserId)
	end)

	ServerNet.onEvent(
		"Stance",
		{ capacity = 24, refill = 16 },
		parseStance,
		function(player: Player, packet: Types.StancePacket)
			local character = player.Character
			if not character or character:GetAttribute("Alive") ~= true then
				return
			end
			local lean = if packet.stance == "Slide" then 0 else packet.lean
			character:SetAttribute("Stance", packet.stance)
			character:SetAttribute("Lean", lean)
			character:SetAttribute("Ads", packet.ads)
			character:SetAttribute("Walking", packet.walking)
			-- Pose 3e personne uniquement (arme baissée) : la vitesse reste bornée par l'anti-triche.
			character:SetAttribute("Sprinting", packet.sprinting and packet.stance == "Stand" and not packet.ads)
		end
	)

	ServerNet.onUnreliable(
		"LookUpdate",
		{ capacity = 40, refill = 34 },
		function(value: any): { yaw: number, pitch: number }?
			local yaw, pitch = LookCodec.decodeLocal(value)
			if yaw == nil or pitch == nil then
				return nil
			end
			return { yaw = yaw, pitch = pitch }
		end,
		function(player: Player, look: { yaw: number, pitch: number })
			local now = Workspace:GetServerTimeNow()
			local previous = looks[player]
			local history = lookHistories[player] or {}
			if #history >= 120 then
				table.remove(history, 1)
			end
			table.insert(history, { t = now, yaw = look.yaw, pitch = look.pitch })
			lookHistories[player] = history
			looks[player] = {
				yaw = look.yaw,
				pitch = look.pitch,
				t = now,
				previousYaw = if previous then previous.yaw else look.yaw,
				previousPitch = if previous then previous.pitch else look.pitch,
				previousT = if previous then previous.t else now,
			}
		end
	)

	ServerNet.onEvent("Emote", { capacity = 3, refill = 0.5 }, function(slot: any): number?
		return if Guard.integer(1, 4)(slot) then slot :: number else nil
	end, function(player: Player, slot: number)
		local character = player.Character
		local data = DataService.getData(player)
		if not (character and data) or ArenaService.get(player) ~= "Hub" or not CharacterService.isAlive(player) then
			return
		end
		local emoteId = data.Cosmetics.Emotes[slot]
		if type(emoteId) ~= "string" or emoteId == "" or not data.Inventory[emoteId] then
			return
		end
		character:SetAttribute("Emote", emoteId .. "|" .. tostring(Workspace:GetServerTimeNow()))
	end)

	ArenaService.Changed:Connect(function(player: Player, _kind: Types.ArenaKind, id: string)
		local target = LagCompensationService.get(player.UserId)
		if target then
			target.arena = id
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.05 then
			accumulator = 0
			broadcastLooks()
		end
		-- Chute hors carte
		for _, player in Players:GetPlayers() do
			local _, _, root = CharacterService.getCharacter(player)
			if root and root.Position.Y < KILL_Y and CharacterService.isAlive(player) then
				CharacterService.kill(player, {
					attacker = nil,
					weaponId = "fall",
					zone = "Body",
					wallbang = false,
					distance = 0,
					backstab = false,
					fall = true,
				})
			end
		end
	end)
end

return CharacterService
