--!strict
--[[
	MissionService — missions quotidiennes / défis hebdomadaires.

	* Tirage déterministe (UserId + jour/semaine) au chargement du profil et au
	  changement de jour : identique sur tous les serveurs, non "farmable".
	* Progression par écoute du bus GameEvents (aucun couplage avec le combat).
	* Récupération explicite des récompenses (bouton CLAIM : moment de satisfaction).
	* 1 reroll quotidien.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Missions = require(Shared.Config.Missions)
local Weapons = require(Shared.Config.Weapons)
local Guard = require(Shared.Util.Guard)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local GameEvents = require(script.Parent.Parent.GameEvents)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local InventoryService = require(script.Parent.InventoryService)

local MissionService = {}

local function makeProgress(defs: { Missions.MissionDef }): { Types.MissionProgress }
	local list = {}
	for _, def in defs do
		table.insert(list, { id = def.id, progress = 0, target = def.target, claimed = false })
	end
	return list
end

local function ensureMissions(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local now = os.time()
	local day = Missions.dayIndex(now)
	local week = Missions.weekIndex(now)
	if data.Missions.Day ~= day then
		local picked = Missions.roll(Missions.daily, Missions.DAILY_COUNT, player.UserId * 31 + day)
		PlayerService.set(player, { "Missions", "Daily" }, makeProgress(picked))
		PlayerService.set(player, { "Missions", "Day" }, day)
		PlayerService.set(player, { "Missions", "Rerolls" }, Missions.DAILY_REROLLS)
	end
	if data.Missions.Week ~= week then
		local picked = Missions.roll(Missions.weekly, Missions.WEEKLY_COUNT, player.UserId * 17 + week * 7)
		PlayerService.set(player, { "Missions", "Weekly" }, makeProgress(picked))
		PlayerService.set(player, { "Missions", "Week" }, week)
	end
end

local function advance(player: Player, eventName: string, amount: number, predicate: (Missions.MissionFilter) -> boolean)
	local data = DataService.getData(player)
	if not data then
		return
	end
	for _, listName in { "Daily", "Weekly" } do
		local list = (data.Missions :: any)[listName] :: { Types.MissionProgress }
		for index, progress in list do
			local def = Missions.byId[progress.id]
			if def and def.event == eventName and not progress.claimed and progress.progress < progress.target and predicate(def.filter) then
				local value = math.min(progress.target, progress.progress + amount)
				PlayerService.set(player, { "Missions", listName, index, "progress" }, value)
				if value >= progress.target then
					PlayerService.notify(player, "MissionComplete", Missions.format(def), { mission = def.id })
				end
			end
		end
	end
end

local function always(_filter: Missions.MissionFilter): boolean
	return true
end

type MissionAction = { action: string, id: string?, index: number? }

local isAction = Guard.shape({
	action = Guard.oneOf({ "Claim", "Reroll" }),
	id = Guard.optional(Guard.string(24)),
	index = Guard.optional(Guard.integer(1, 3)),
})

local function handle(player: Player, request: MissionAction): ServerNet.Response
	local data = DataService.getData(player)
	if not data then
		return ServerNet.failure("Profil non chargé")
	end
	if request.action == "Claim" then
		for _, listName in { "Daily", "Weekly" } do
			local list = (data.Missions :: any)[listName] :: { Types.MissionProgress }
			for index, progress in list do
				if progress.id == request.id then
					if progress.claimed or progress.progress < progress.target then
						return ServerNet.failure("Mission non terminée")
					end
					local def = Missions.byId[progress.id]
					PlayerService.set(player, { "Missions", listName, index, "claimed" }, true)
					if def then
						ProgressionService.awardXP(player, def.xp)
						InventoryService.addFlux(player, def.flux)
					end
					return ServerNet.success({ xp = if def then def.xp else 0 })
				end
			end
		end
		return ServerNet.failure("Mission introuvable")
	elseif request.action == "Reroll" then
		local index = request.index
		if not index or data.Missions.Rerolls <= 0 then
			return ServerNet.failure("Aucun reroll disponible")
		end
		local current = data.Missions.Daily[index]
		if not current or current.claimed then
			return ServerNet.failure("Mission non remplaçable")
		end
		local exclude: { [string]: boolean } = {}
		for _, progress in data.Missions.Daily do
			exclude[progress.id] = true
		end
		local rolled = Missions.roll(Missions.daily, 1, player.UserId * 977 + data.Missions.Day * 13 + index, exclude)[1]
		if not rolled then
			return ServerNet.failure("Aucune mission disponible")
		end
		PlayerService.set(player, { "Missions", "Daily", index }, { id = rolled.id, progress = 0, target = rolled.target, claimed = false })
		PlayerService.increment(player, { "Missions", "Rerolls" }, -1)
		return ServerNet.success()
	end
	return ServerNet.failure("Action inconnue")
end

function MissionService.Init() end

function MissionService.Start()
	PlayerService.Ready:Connect(function(player: Player)
		ensureMissions(player)
	end)
	-- Changement de jour pendant une session longue.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				ensureMissions(player)
			end
		end
	end)

	GameEvents.Kill:Connect(function(info: GameEvents.KillInfo)
		local killer = info.killer
		if not killer then
			return
		end
		local weapon = Weapons.get(info.weaponId)
		if info.firstBlood then
			advance(killer, "FirstBlood", 1, always)
		end
		advance(killer, "Kill", 1, function(filter: Missions.MissionFilter): boolean
			if filter.headshot and not info.headshot then
				return false
			end
			if filter.wallbang and not info.wallbang then
				return false
			end
			if filter.slide and not info.slide then
				return false
			end
			if filter.category and not (weapon and Missions.categoryMatches(filter.category, weapon.category, weapon.slot)) then
				return false
			end
			return true
		end)
	end)
	GameEvents.Damage:Connect(function(info: GameEvents.DamageInfo)
		if info.attacker and info.victim then
			advance(info.attacker, "Damage", math.floor(info.amount + 0.5), always)
		end
	end)
	GameEvents.RoundEnd:Connect(function(info: GameEvents.RoundInfo)
		for _, player in info.winners do
			advance(player, "RoundWin", 1, always)
		end
		if info.clutch then
			advance(info.clutch, "Clutch", 1, always)
		end
	end)
	GameEvents.MatchEnd:Connect(function(info: GameEvents.MatchEndInfo)
		local everyone = table.clone(info.winners)
		for _, player in info.losers do
			table.insert(everyone, player)
		end
		for _, player in everyone do
			advance(player, "MatchPlayed", 1, always)
		end
		for _, player in info.winners do
			advance(player, "MatchWin", 1, function(filter: Missions.MissionFilter): boolean
				return not filter.ranked or info.ranked
			end)
		end
	end)
	GameEvents.Objective:Connect(function(info: GameEvents.ObjectiveInfo)
		advance(info.player, "Objective", 1, always)
	end)
	GameEvents.TrainingHit:Connect(function(info: GameEvents.TrainingHitInfo)
		advance(info.player, "TrainingHit", 1, always)
	end)

	ServerNet.onInvoke("MissionAction", { capacity = 6, refill = 2 }, function(payload: any): MissionAction?
		return if isAction(payload) then payload :: MissionAction else nil
	end, handle)
end

return MissionService
