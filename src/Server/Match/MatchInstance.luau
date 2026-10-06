--!strict
--[[
	MatchInstance — un match : machine à états des manches + objectif Uplink.

	Waiting ─► Intro ─► Prep ─► Live ─┬─► RoundEnd ─┬─► (SideSwap) ─► Prep …
	                              └─► Planted ─┘    └─► MatchEnd ─► Closed

	* Waiting  : attente des joueurs attendus (serveur réservé) ; timeout -> forfait.
	* Intro    : survol cinématique de la carte côté client (aucun personnage).
	* Prep     : apparition, loadout, barrières de spawn actives, combat fermé.
	* Live     : combat ouvert ; MatchRules.evaluateRound décide de la fin de manche.
	* Planted  : charge Aether posée ; détonation ou désamorçage.
	* RoundEnd : bannière + stats ; match terminé ? côté à échanger ?
	* MatchEnd : écran de victoire, MVP, récompenses (ProgressionService).
	Toutes les décisions de règles sont déléguées à Shared/Rules/MatchRules (testé).
	L'état est répliqué aux participants via le replica "MatchState".
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Weapons = require(Shared.Config.Weapons)
local MatchRules = require(Shared.Rules.MatchRules)
local Janitor = require(Shared.Util.Janitor)
local Logger = require(Shared.Util.Logger)
local Net = require(Shared.Net.Net)
local Ballistics = require(Shared.Combat.Ballistics)
local GameEvents = require(script.Parent.Parent.GameEvents)
local MapBuilder = require(script.Parent.Parent.Maps.MapBuilder)
local ReplicaService = require(script.Parent.Parent.Services.ReplicaService)
local ArenaService = require(script.Parent.Parent.Services.ArenaService)
local CharacterService = require(script.Parent.Parent.Services.CharacterService)
local CombatService = require(script.Parent.Parent.Services.CombatService)
local DataService = require(script.Parent.Parent.Services.DataService)
local MapService = require(script.Parent.Parent.Services.MapService)

local log = Logger.new("Match")

type TeamId = Types.TeamId
type ModeDef = GameModes.ModeDef

export type PlayerResult = {
	player: Player,
	team: TeamId,
	stats: Types.MatchPlayerData,
}

export type MatchResult = {
	matchId: string,
	modeId: string,
	mapId: string,
	ranked: boolean,
	custom: boolean,
	winner: TeamId?,
	draw: boolean,
	forfeit: boolean,
	scores: { A: number, B: number },
	rounds: number,
	players: { PlayerResult },
	mvp: Player?,
}

export type Hooks = {
	onFinished: (match: MatchInstance, result: MatchResult) -> (),
	onClosed: (match: MatchInstance, players: { Player }) -> (),
}

type Entry = {
	player: Player,
	team: TeamId,
	connected: boolean,
	roundKills: number,
}

export type MatchInstance = {
	id: string,
	spec: Types.MatchSpec,
	mode: ModeDef,
	arena: MapBuilder.MapInstance,
	replica: ReplicaService.Replica,
	state: Types.MatchStateData,
	hooks: Hooks,
	entries: { [Player]: Entry },
	expected: { [number]: TeamId },
	janitor: Janitor.Janitor,
	firstBloodDone: boolean,
	clutchCandidates: { [string]: Player },
	swapPending: boolean,
	plantStart: Vector3?,
	defuseStart: Vector3?,
	defuseStartedAt: number,
	core: BasePart?,
	closed: boolean,
	-- méthodes
	addPlayer: (self: MatchInstance, player: Player) -> boolean,
	removePlayer: (self: MatchInstance, player: Player) -> (),
	update: (self: MatchInstance, now: number) -> (),
	isCombatLive: (self: MatchInstance) -> boolean,
	isFirstBlood: (self: MatchInstance) -> boolean,
	interact: (self: MatchInstance, player: Player, action: Types.InteractAction) -> (),
	selectLoadout: (self: MatchInstance, player: Player, slot: Types.WeaponSlot, weaponId: string) -> (),
	players: (self: MatchInstance) -> { Player },
	close: (self: MatchInstance) -> (),
}

local TEAMS: { TeamId } = { "A", "B" }
local DETONATION_RADIUS = 28
local PICKUP_RADIUS = 3.5
local DEFUSE_RADIUS = 4.5
local MOVE_CANCEL = 2.5

local MatchInstance = {}
MatchInstance.__index = MatchInstance

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function key(player: Player): string
	return tostring(player.UserId)
end

local function event(self: MatchInstance, packet: Types.MatchEventPacket)
	local remote = Net.event("MatchEvent")
	for player, entry in self.entries do
		if entry.connected and player.Parent then
			remote:FireClient(player, packet)
		end
	end
end

local function setPhase(self: MatchInstance, phase: Types.MatchPhase, duration: number)
	self.state.phase = phase
	self.state.phaseEndsAt = now() + duration
	self.replica:SetValues({}, { phase = phase, phaseEndsAt = self.state.phaseEndsAt })
end

local function sideOf(self: MatchInstance, team: TeamId): Types.Side
	return self.state.sides[team]
end

local function teamOfSide(self: MatchInstance, side: Types.Side): TeamId
	return if self.state.sides.A == side then "A" else "B"
end

local function playerData(self: MatchInstance, player: Player): Types.MatchPlayerData?
	return self.state.players[key(player)]
end

local function bump(self: MatchInstance, player: Player, field: string, delta: number)
	local data = playerData(self, player)
	if data then
		local value = ((data :: any)[field] or 0) + delta
		self.replica:Set({ "players", key(player), field }, value)
	end
end

local function setAlive(self: MatchInstance, player: Player, alive: boolean)
	local data = playerData(self, player)
	if data and data.alive ~= alive then
		self.replica:Set({ "players", key(player), "alive" }, alive)
	end
end

local function aliveIn(self: MatchInstance, team: TeamId): { Player }
	local list = {}
	for player, entry in self.entries do
		if entry.team == team and entry.connected and CharacterService.isAlive(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function teamSnapshot(self: MatchInstance, team: TeamId): MatchRules.TeamSnapshot
	local alive = aliveIn(self, team)
	local health = 0
	for _, player in alive do
		local hp, armor = CharacterService.health(player)
		health += hp + armor
	end
	return { alive = #alive, health = health }
end

local function connectedCount(self: MatchInstance, team: TeamId): number
	local count = 0
	for _, entry in self.entries do
		if entry.team == team and entry.connected then
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------------------------------------
-- Objectif Uplink
---------------------------------------------------------------------------------------------

local function setObjective(self: MatchInstance, values: { [string]: any })
	self.replica:SetValues({ "objective" }, values)
end

local function destroyCore(self: MatchInstance)
	if self.core then
		self.core:Destroy()
		self.core = nil
	end
end

local function spawnCore(self: MatchInstance, position: Vector3, planted: boolean)
	destroyCore(self)
	local core = Instance.new("Part")
	core.Name = "UplinkCore"
	core.Size = Vector3.new(1.4, 1.4, 1.4)
	core.CFrame = CFrame.new(position + Vector3.new(0, 0.9, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 190, 70)
	core:SetAttribute("Planted", planted)
	core:SetAttribute("MatchId", self.id)
	core:AddTag("UplinkCore")
	local light = Instance.new("PointLight")
	light.Color = core.Color
	light.Brightness = 3
	light.Range = 14
	light.Parent = core
	core.Parent = self.arena.model
	self.core = core
end

local function clearCarrier(self: MatchInstance)
	for player in self.entries do
		local character = player.Character
		if character then
			character:SetAttribute("HasCore", nil)
		end
	end
end

local function assignCarrier(self: MatchInstance)
	clearCarrier(self)
	if self.mode.objective ~= "Uplink" then
		return
	end
	local attackers = aliveIn(self, teamOfSide(self, "Attack"))
	if #attackers == 0 then
		return
	end
	local carrier = attackers[math.random(1, #attackers)]
	local character = carrier.Character
	if character then
		character:SetAttribute("HasCore", true)
	end
	setObjective(self, { carrier = carrier.UserId, dropped = false })
end

local function dropCore(self: MatchInstance, position: Vector3)
	clearCarrier(self)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { self.arena.model }
	local ground = Workspace:Raycast(position, Vector3.new(0, -40, 0), params)
	local spot = if ground then ground.Position else position
	setObjective(self, { carrier = 0, dropped = true, position = spot })
	spawnCore(self, spot, false)
	event(self, { kind = "CoreDropped" })
end

local function siteAt(self: MatchInstance, position: Vector3): string?
	for id, zone in self.arena.sites do
		if MapBuilder.contains(zone, position) then
			return id
		end
	end
	return nil
end

local function setBusy(player: Player, busy: boolean)
	local character = player.Character
	if character then
		character:SetAttribute("Busy", if busy then true else nil)
	end
end

local function cancelPlant(self: MatchInstance)
	local planter = Players:GetPlayerByUserId(self.state.objective.planter)
	if planter then
		setBusy(planter, false)
	end
	self.plantStart = nil
	setObjective(self, { planter = 0, plantEndsAt = 0 })
end

local function cancelDefuse(self: MatchInstance)
	local objective = self.state.objective
	local defuser = Players:GetPlayerByUserId(objective.defuser)
	if defuser then
		setBusy(defuser, false)
	end
	local progress = now() - self.defuseStartedAt
	local checkpoint = objective.halfDefused or progress >= self.mode.defuseTime / 2
	self.defuseStart = nil
	setObjective(self, { defuser = 0, defuseEndsAt = 0, halfDefused = checkpoint })
end

local function completePlant(self: MatchInstance, planter: Player)
	local _, _, root = CharacterService.getCharacter(planter)
	local position = if root then root.Position - Vector3.new(0, 3, 0) else Vector3.zero
	local site = siteAt(self, if root then root.Position else position) or "?"
	setBusy(planter, false)
	clearCarrier(self)
	self.plantStart = nil
	local fuseEndsAt = now() + self.mode.fuseTime
	setObjective(self, {
		planted = true,
		site = site,
		position = position,
		fuseEndsAt = fuseEndsAt,
		planter = 0,
		plantEndsAt = 0,
		carrier = 0,
		dropped = false,
	})
	spawnCore(self, position, true)
	self.state.phase = "Planted"
	self.state.phaseEndsAt = fuseEndsAt
	self.replica:SetValues({}, { phase = "Planted", phaseEndsAt = fuseEndsAt })
	bump(self, planter, "plants", 1)
	bump(self, planter, "score", 100)
	GameEvents.Objective:Fire({ player = planter, action = "Plant", matchId = self.id })
	event(self, { kind = "Planted", reason = site, player = planter.UserId })
end

local function detonate(self: MatchInstance)
	local corePosition = self.state.objective.position
	if corePosition then
		for player in self.entries do
			local _, _, root = CharacterService.getCharacter(player)
			if
				root
				and CharacterService.isAlive(player)
				and (root.Position - corePosition).Magnitude <= DETONATION_RADIUS
			then
				CharacterService.kill(player, {
					attacker = nil,
					weaponId = "uplink",
					zone = "Body",
					wallbang = false,
					distance = 0,
					backstab = false,
					fall = false,
				})
			end
		end
	end
	destroyCore(self)
	event(self, { kind = "Detonated" })
end

local function tickObjective(self: MatchInstance, t: number): (boolean, boolean, boolean)
	local objective = self.state.objective
	local planted, defused, detonated = objective.planted, false, false
	if self.mode.objective ~= "Uplink" then
		return false, false, false
	end
	-- Ramassage de la charge au sol par un attaquant vivant.
	if objective.dropped and objective.position then
		for _, player in aliveIn(self, teamOfSide(self, "Attack")) do
			local _, _, root = CharacterService.getCharacter(player)
			if root and (root.Position - (objective.position :: Vector3)).Magnitude <= PICKUP_RADIUS + 3 then
				destroyCore(self)
				local character = player.Character
				if character then
					character:SetAttribute("HasCore", true)
				end
				setObjective(self, { carrier = player.UserId, dropped = false })
				event(self, { kind = "CorePicked", player = player.UserId })
				break
			end
		end
	end
	-- Pose en cours
	if objective.planter ~= 0 then
		local planter = Players:GetPlayerByUserId(objective.planter)
		local root: BasePart? = nil
		if planter then
			local _, _, found = CharacterService.getCharacter(planter)
			root = found
		end
		if
			not (planter and root and CharacterService.isAlive(planter))
			or not siteAt(self, root.Position)
			or (self.plantStart and (root.Position - (self.plantStart :: Vector3)).Magnitude > MOVE_CANCEL)
		then
			cancelPlant(self)
		elseif t >= objective.plantEndsAt then
			completePlant(self, planter)
			planted = true
		end
	end
	-- Désamorçage en cours
	if objective.defuser ~= 0 then
		local defuser = Players:GetPlayerByUserId(objective.defuser)
		local root: BasePart? = nil
		if defuser then
			local _, _, found = CharacterService.getCharacter(defuser)
			root = found
		end
		local corePosition = objective.position
		if
			not (defuser and root and corePosition and CharacterService.isAlive(defuser))
			or (root.Position - corePosition).Magnitude > DEFUSE_RADIUS + 2
			or (self.defuseStart and (root.Position - (self.defuseStart :: Vector3)).Magnitude > MOVE_CANCEL)
		then
			cancelDefuse(self)
		elseif t >= objective.defuseEndsAt then
			setBusy(defuser, false)
			setObjective(self, { defuser = 0, defuseEndsAt = 0 })
			destroyCore(self)
			bump(self, defuser, "defuses", 1)
			bump(self, defuser, "score", 120)
			GameEvents.Objective:Fire({ player = defuser, action = "Defuse", matchId = self.id })
			event(self, { kind = "Defused", player = defuser.UserId })
			defused = true
		end
	end
	if planted and not defused and t >= objective.fuseEndsAt then
		detonate(self)
		detonated = true
	end
	return planted, defused, detonated
end

---------------------------------------------------------------------------------------------
-- Manches
---------------------------------------------------------------------------------------------

local function loadoutFor(player: Player, pistol: boolean): CombatService.Loadout
	local data = DataService.getData(player)
	local loadout = if data then data.Loadout else Weapons.DEFAULT_LOADOUT
	return {
		Primary = if pistol then nil else loadout.Primary,
		Secondary = loadout.Secondary,
		Melee = loadout.Melee,
	}
end

local function shuffled<T>(list: { T }): { T }
	local copy = table.clone(list)
	for index = #copy, 2, -1 do
		local swap = math.random(1, index)
		copy[index], copy[swap] = copy[swap], copy[index]
	end
	return copy
end

local function spawnTeam(self: MatchInstance, team: TeamId, pistol: boolean)
	local side = sideOf(self, team)
	local spawns: { CFrame } = shuffled(self.arena.spawns[side] or {})
	local shields = if pistol then 0 else self.mode.shields
	local index = 0
	for player, entry in self.entries do
		if entry.team ~= team or not entry.connected or player.Parent == nil then
			continue
		end
		index += 1
		local spawnCFrame = spawns[((index - 1) % math.max(#spawns, 1)) + 1] or self.arena.origin
		entry.roundKills = 0
		task.spawn(function()
			local character = CharacterService.spawn(player, spawnCFrame, {
				arenaKind = "Match",
				arenaId = self.id,
				team = team,
				side = side,
				shields = shields,
			})
			if character and not self.closed then
				CombatService.arm(player, loadoutFor(player, pistol))
				setAlive(self, player, true)
				if self.mode.objective == "Uplink" and self.state.objective.carrier == player.UserId then
					character:SetAttribute("HasCore", true)
				end
			end
		end)
	end
end

local function startRound(self: MatchInstance)
	if self.swapPending then
		self.swapPending = false
		local sides = self.state.sides
		self.replica:Set({ "sides" }, { A = sides.B, B = sides.A })
		event(self, { kind = "SideSwap" })
	end
	local round = self.state.round + 1
	self.replica:Set({ "round" }, round)
	local overtime = MatchRules.isOvertime(self.mode, self.state.scores.A, self.state.scores.B)
	self.replica:Set({ "overtime" }, overtime)
	local pistol = not overtime and GameModes.isPistolRound(self.mode, round)
	self.firstBloodDone = false
	self.clutchCandidates = {}
	destroyCore(self)
	self.plantStart = nil
	self.defuseStart = nil
	self.replica:Set({ "objective" }, {
		carrier = 0,
		dropped = false,
		position = nil,
		planted = false,
		site = "",
		fuseEndsAt = 0,
		defuser = 0,
		defuseEndsAt = 0,
		halfDefused = false,
		planter = 0,
		plantEndsAt = 0,
	})
	MapBuilder.setBarriers(self.arena, true)
	spawnTeam(self, "A", pistol)
	spawnTeam(self, "B", pistol)
	setPhase(self, "Prep", self.mode.prepTime)
	task.delay(math.min(2, self.mode.prepTime * 0.4), function()
		if not self.closed and self.state.phase == "Prep" and self.state.round == round then
			assignCarrier(self)
		end
	end)
	local matchPointTeam: string? = nil
	if MatchRules.isMatchPoint(self.mode, self.state.scores.A, self.state.scores.B, "A") then
		matchPointTeam = "A"
	elseif MatchRules.isMatchPoint(self.mode, self.state.scores.A, self.state.scores.B, "B") then
		matchPointTeam = "B"
	end
	event(self, {
		kind = "RoundStart",
		round = round,
		text = if pistol then "PISTOL" elseif overtime then "OVERTIME" else nil,
		team = matchPointTeam,
	})
end

local function goLive(self: MatchInstance)
	MapBuilder.setBarriers(self.arena, false)
	setPhase(self, "Live", self.mode.roundTime)
	event(self, { kind = "Live", round = self.state.round })
end

local function endRound(self: MatchInstance, winner: TeamId?, reason: string)
	if winner then
		self.replica:Set({ "scores", winner }, self.state.scores[winner] + 1)
	end
	self.replica:ArrayInsert({ "history" }, { winner = winner or "", reason = reason })
	self.replica:SetValues({}, { lastRoundWinner = winner or "", lastRoundReason = reason })

	local winners, losers = {}, {}
	local clutch: Player? = nil
	local ace: Player? = nil
	for player, entry in self.entries do
		if not entry.connected then
			continue
		end
		if winner and entry.team == winner then
			table.insert(winners, player)
			local enemyCount = connectedCount(self, MatchRules.other(entry.team))
			if enemyCount >= 2 and entry.roundKills >= enemyCount then
				ace = player
			end
		else
			table.insert(losers, player)
		end
	end
	if winner and self.clutchCandidates[winner] then
		clutch = self.clutchCandidates[winner]
	end
	if clutch then
		bump(self, clutch, "score", 150)
		event(self, { kind = "Clutch", player = clutch.UserId })
	end
	if ace then
		bump(self, ace, "score", 200)
		event(self, { kind = "Ace", player = ace.UserId })
	end
	GameEvents.RoundEnd:Fire({
		matchId = self.id,
		round = self.state.round,
		winners = winners,
		losers = losers,
		reason = reason,
		clutch = clutch,
		ace = ace,
		firstBlood = nil,
	})
	event(self, { kind = "RoundEnd", team = winner, reason = reason, round = self.state.round })

	-- Fin des actions en cours
	if self.state.objective.planter ~= 0 then
		cancelPlant(self)
	end
	if self.state.objective.defuser ~= 0 then
		cancelDefuse(self)
	end
	self.swapPending = MatchRules.sideSwapDue(self.mode, self.state.round, self.state.scores.A, self.state.scores.B)
	setPhase(self, "RoundEnd", self.mode.roundEndTime)
end

local function computeMvp(self: MatchInstance): Player?
	local best: Player? = nil
	local bestScore = -1
	for player, entry in self.entries do
		local data = playerData(self, player)
		if entry.connected and data then
			local value = data.score + data.kills * 0.01
			if value > bestScore then
				bestScore = value
				best = player
			end
		end
	end
	return best
end

local function finishMatch(self: MatchInstance, winner: TeamId?, forfeit: boolean)
	if self.state.phase == "MatchEnd" or self.state.phase == "Closed" then
		return
	end
	local mvp = computeMvp(self)
	self.replica:SetValues({}, { winner = winner or "", mvp = if mvp then mvp.UserId else 0 })
	setPhase(self, "MatchEnd", self.mode.matchEndTime)
	event(self, {
		kind = "MatchEnd",
		team = winner,
		reason = if forfeit then "Forfeit" else nil,
		player = if mvp then mvp.UserId else nil,
	})
	for player in self.entries do
		CombatService.disarm(player)
	end
	local results: { PlayerResult } = {}
	for player, entry in self.entries do
		local data = playerData(self, player)
		if data and entry.connected and player.Parent then
			table.insert(results, { player = player, team = entry.team, stats = table.clone(data) })
		end
	end
	local result: MatchResult = {
		matchId = self.id,
		modeId = self.mode.id,
		mapId = self.spec.map,
		ranked = self.spec.ranked,
		custom = self.spec.custom,
		winner = winner,
		draw = winner == nil,
		forfeit = forfeit,
		scores = { A = self.state.scores.A, B = self.state.scores.B },
		rounds = self.state.round,
		players = results,
		mvp = mvp,
	}
	GameEvents.MatchEnd:Fire({
		matchId = self.id,
		modeId = self.mode.id,
		ranked = self.spec.ranked,
		winners = (function()
			local list = {}
			for _, item in results do
				if winner and item.team == winner then
					table.insert(list, item.player)
				end
			end
			return list
		end)(),
		losers = (function()
			local list = {}
			for _, item in results do
				if not winner or item.team ~= winner then
					table.insert(list, item.player)
				end
			end
			return list
		end)(),
		draw = winner == nil,
	})
	self.hooks.onFinished(self, result)
	log:info("match", self.id, "terminé", winner or "nul", ("%d-%d"):format(result.scores.A, result.scores.B))
end

---------------------------------------------------------------------------------------------
-- Événements de combat
---------------------------------------------------------------------------------------------

local function onKill(self: MatchInstance, info: GameEvents.KillInfo)
	local killer, victim = info.killer, info.victim
	if killer and self.entries[killer] then
		bump(self, killer, "kills", 1)
		bump(self, killer, "score", 150 + (if info.headshot then 25 else 0))
		if info.headshot then
			bump(self, killer, "headshots", 1)
		end
		self.entries[killer].roundKills += 1
		if not self.firstBloodDone then
			self.firstBloodDone = true
			bump(self, killer, "firstBloods", 1)
			bump(self, killer, "score", 50)
			event(self, { kind = "FirstBlood", player = killer.UserId })
		end
	end
	for _, assister in info.assisters do
		if self.entries[assister] then
			bump(self, assister, "assists", 1)
			bump(self, assister, "score", 50)
		end
	end
	if victim then
		bump(self, victim, "deaths", 1)
	end
end

local function onDeath(self: MatchInstance, player: Player)
	local entry = self.entries[player]
	if not entry then
		return
	end
	setAlive(self, player, false)
	if self.state.objective.carrier == player.UserId then
		local _, _, root = CharacterService.getCharacter(player)
		if root then
			dropCore(self, root.Position)
		end
	end
	-- Situation de clutch : un survivant seul face à 2+ adversaires.
	for _, team: TeamId in TEAMS do
		local alive = aliveIn(self, team)
		local enemies = aliveIn(self, MatchRules.other(team))
		if #alive == 1 and #enemies >= 2 and not self.clutchCandidates[team] then
			self.clutchCandidates[team] = alive[1]
		end
	end
end

---------------------------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------------------------

function MatchInstance.addPlayer(self: MatchInstance, player: Player): boolean
	local team: TeamId? = self.expected[player.UserId]
	if not team or self.closed then
		return false
	end
	local existing = self.entries[player]
	if existing then
		existing.connected = true
	else
		self.entries[player] = { player = player, team = team, connected = true, roundKills = 0 }
	end
	ArenaService.set(player, "Match", self.id)
	MapService.addArenaPlayer(self.arena, player)
	self.replica:AddPlayer(player)
	local data = DataService.getData(player)
	if not self.state.players[key(player)] then
		local record: Types.MatchPlayerData = {
			userId = player.UserId,
			name = player.DisplayName,
			team = team,
			alive = false,
			connected = true,
			kills = 0,
			deaths = 0,
			assists = 0,
			damage = 0,
			score = 0,
			headshots = 0,
			plants = 0,
			defuses = 0,
			firstBloods = 0,
			rankIndex = if data then data.Rank.RankIndex else 0,
			level = if data then data.Level else 1,
			loadout = if data
				then { Primary = data.Loadout.Primary, Secondary = data.Loadout.Secondary, Melee = data.Loadout.Melee }
				else {},
		}
		self.replica:Set({ "players", key(player) }, record)
	else
		self.replica:Set({ "players", key(player), "connected" }, true)
	end
	-- Retire le personnage du hub : le joueur verra l'intro puis apparaîtra en Prep.
	CombatService.disarm(player)
	CharacterService.despawn(player)
	return true
end

function MatchInstance.removePlayer(self: MatchInstance, player: Player)
	local entry = self.entries[player]
	if not entry then
		return
	end
	entry.connected = false
	if self.state.players[key(player)] then
		self.replica:Set({ "players", key(player), "connected" }, false)
		setAlive(self, player, false)
	end
	if self.state.objective.carrier == player.UserId then
		local _, _, root = CharacterService.getCharacter(player)
		dropCore(self, if root then root.Position else self.arena.origin.Position)
	end
	self.replica:RemovePlayer(player)
	-- Équipe vide : forfait
	local phase = self.state.phase
	if phase ~= "Waiting" and phase ~= "MatchEnd" and phase ~= "Closed" then
		if connectedCount(self, entry.team) == 0 then
			finishMatch(self, MatchRules.other(entry.team), true)
		end
	end
end

function MatchInstance.players(self: MatchInstance): { Player }
	local list = {}
	for player, entry in self.entries do
		if entry.connected and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function MatchInstance.isCombatLive(self: MatchInstance): boolean
	local phase = self.state.phase
	return phase == "Live" or phase == "Planted"
end

function MatchInstance.isFirstBlood(self: MatchInstance): boolean
	return not self.firstBloodDone and self:isCombatLive()
end

function MatchInstance.interact(self: MatchInstance, player: Player, action: Types.InteractAction)
	if self.mode.objective ~= "Uplink" or not self:isCombatLive() then
		return
	end
	local entry = self.entries[player]
	local _, humanoid, root = CharacterService.getCharacter(player)
	if not (entry and humanoid and root and CharacterService.isAlive(player)) then
		return
	end
	local objective = self.state.objective
	local side = sideOf(self, entry.team)
	local t = now()
	if action == "PlantStart" then
		if side ~= "Attack" or objective.planted or objective.carrier ~= player.UserId or objective.planter ~= 0 then
			return
		end
		if humanoid.FloorMaterial == Enum.Material.Air or not siteAt(self, root.Position) then
			return
		end
		self.plantStart = root.Position
		setBusy(player, true)
		setObjective(self, { planter = player.UserId, plantEndsAt = t + self.mode.plantTime })
		event(self, { kind = "PlantStart", player = player.UserId })
	elseif action == "PlantCancel" then
		if objective.planter == player.UserId then
			cancelPlant(self)
		end
	elseif action == "DefuseStart" then
		local corePosition = objective.position
		if side ~= "Defense" or not objective.planted or objective.defuser ~= 0 or not corePosition then
			return
		end
		if
			(root.Position - corePosition).Magnitude > DEFUSE_RADIUS + 1
			or humanoid.FloorMaterial == Enum.Material.Air
		then
			return
		end
		local duration = if objective.halfDefused then self.mode.defuseTime / 2 else self.mode.defuseTime
		self.defuseStart = root.Position
		self.defuseStartedAt = if objective.halfDefused then t - self.mode.defuseTime / 2 else t
		setBusy(player, true)
		setObjective(self, { defuser = player.UserId, defuseEndsAt = t + duration })
		event(self, { kind = "DefuseStart", player = player.UserId })
	elseif action == "DefuseCancel" then
		if objective.defuser == player.UserId then
			cancelDefuse(self)
		end
	end
end

function MatchInstance.selectLoadout(self: MatchInstance, player: Player, slot: Types.WeaponSlot, weaponId: string)
	if not Weapons.isValidForSlot(weaponId, slot) then
		return
	end
	local data = DataService.getData(player)
	if data then
		(data.Loadout :: any)[slot] = weaponId
	end
	-- Réarmement immédiat pendant la préparation uniquement.
	if self.state.phase == "Prep" and CharacterService.isAlive(player) then
		local pistol = not self.state.overtime and GameModes.isPistolRound(self.mode, self.state.round)
		CombatService.arm(player, loadoutFor(player, pistol))
	end
	local record = playerData(self, player)
	if record then
		self.replica:Set({ "players", key(player), "loadout", slot }, weaponId)
	end
end

function MatchInstance.update(self: MatchInstance, t: number)
	if self.closed then
		return
	end
	local state = self.state
	local phase = state.phase
	if phase == "Waiting" then
		local ready = connectedCount(self, "A") >= 1 and connectedCount(self, "B") >= 1
		local everyone = true
		for userId in self.expected do
			local player = Players:GetPlayerByUserId(userId)
			if not (player and self.entries[player] and self.entries[player].connected) then
				everyone = false
			end
		end
		if everyone or (t >= state.phaseEndsAt and ready) then
			setPhase(self, "Intro", self.mode.introTime)
			event(self, { kind = "Intro", text = self.spec.map })
		elseif t >= state.phaseEndsAt then
			finishMatch(
				self,
				if connectedCount(self, "A") > 0 then "A" elseif connectedCount(self, "B") > 0 then "B" else nil,
				true
			)
		end
	elseif phase == "Intro" then
		if t >= state.phaseEndsAt then
			startRound(self)
		end
	elseif phase == "Prep" then
		if t >= state.phaseEndsAt then
			goLive(self)
		end
	elseif phase == "Live" or phase == "Planted" then
		local planted, defused, detonated = tickObjective(self, t)
		local aliveA, aliveB = #aliveIn(self, "A"), #aliveIn(self, "B")
		local winner: TeamId?, reason: string? = MatchRules.evaluateRound({
			objective = self.mode.objective,
			sides = state.sides,
			aliveA = aliveA,
			aliveB = aliveB,
			planted = planted,
			defused = defused,
			detonated = detonated,
			timeUp = phase == "Live" and t >= state.phaseEndsAt,
			snapshotA = teamSnapshot(self, "A"),
			snapshotB = teamSnapshot(self, "B"),
		})
		if reason then
			endRound(self, winner, reason)
		end
	elseif phase == "RoundEnd" then
		if t >= state.phaseEndsAt then
			local winner: TeamId? = MatchRules.matchWinner(self.mode, state.scores.A, state.scores.B)
			if winner then
				finishMatch(self, winner, false)
			elseif self.swapPending then
				setPhase(self, "SideSwap", 3)
				event(self, { kind = "SideSwapBanner" })
			else
				startRound(self)
			end
		end
	elseif phase == "SideSwap" then
		if t >= state.phaseEndsAt then
			startRound(self)
		end
	elseif phase == "MatchEnd" then
		if t >= state.phaseEndsAt then
			self:close()
		end
	end
end

function MatchInstance.close(self: MatchInstance)
	if self.closed then
		return
	end
	self.closed = true
	self.state.phase = "Closed"
	destroyCore(self)
	local players = self:players()
	for _, player in players do
		CombatService.disarm(player)
	end
	self.janitor:Cleanup()
	self.replica:Destroy()
	self.hooks.onClosed(self, players)
end

function MatchInstance.new(spec: Types.MatchSpec, arena: MapBuilder.MapInstance, hooks: Hooks): MatchInstance
	local mode = GameModes.get(spec.mode)
	assert(mode, "unknown mode " .. spec.mode)
	local expected: { [number]: TeamId } = {}
	for _, userId in spec.teams.A do
		expected[userId] = "A"
	end
	for _, userId in spec.teams.B do
		expected[userId] = "B"
	end
	local state: Types.MatchStateData = {
		id = spec.matchId,
		mode = spec.mode,
		map = spec.map,
		ranked = spec.ranked,
		custom = spec.custom,
		phase = "Waiting",
		phaseEndsAt = now() + 45,
		round = 0,
		scores = { A = 0, B = 0 },
		sides = { A = "Attack", B = "Defense" },
		overtime = false,
		players = {},
		objective = {
			carrier = 0,
			dropped = false,
			position = nil,
			planted = false,
			site = "",
			fuseEndsAt = 0,
			defuser = 0,
			defuseEndsAt = 0,
			halfDefused = false,
			planter = 0,
			plantEndsAt = 0,
		},
		history = {},
		lastRoundWinner = "",
		lastRoundReason = "",
		winner = "",
		mvp = 0,
	}
	local replica = ReplicaService.new({
		token = "MatchState",
		data = state,
		tags = { MatchId = spec.matchId },
		replicateTo = {},
	})
	local self = setmetatable({
		id = spec.matchId,
		spec = spec,
		mode = mode,
		arena = arena,
		replica = replica,
		state = state,
		hooks = hooks,
		entries = {},
		expected = expected,
		janitor = Janitor.new(),
		firstBloodDone = false,
		clutchCandidates = {},
		swapPending = false,
		plantStart = nil,
		defuseStart = nil,
		defuseStartedAt = 0,
		core = nil,
		closed = false,
	}, MatchInstance)
	local match = (self :: any) :: MatchInstance
	-- Le client retrouve son arène (intro, sites, contours) par cet attribut.
	arena.model:SetAttribute("MatchId", spec.matchId)

	match.janitor:Add(GameEvents.Kill:Connect(function(info: GameEvents.KillInfo)
		if info.arena == match.id then
			onKill(match, info)
		end
	end))
	match.janitor:Add(GameEvents.Damage:Connect(function(info: GameEvents.DamageInfo)
		if info.arena == match.id and info.attacker and match.entries[info.attacker] then
			local amount = math.floor(info.amount + 0.5)
			bump(match, info.attacker, "damage", amount)
			bump(match, info.attacker, "score", amount)
		end
	end))
	match.janitor:Add(CharacterService.Died:Connect(function(player: Player)
		if match.entries[player] then
			onDeath(match, player)
		end
	end))
	return match
end

-- Bouclier par défaut (référencé pour la doc / l'UI de préparation)
MatchInstance.DEFAULT_SHIELDS = Ballistics.MAX_ARMOR

return MatchInstance
